// bridge.rs — Rust 端 JSON-IPC 與 EchoTypeHelper 溝通模組
//
// 架構:
//   Rust (Tauri) ─stdin→ EchoTypeHelper (Swift) ─stdout→ Rust
//   每次呼叫發送一行 JSON，讀取一行 JSON 回應。

#[cfg(debug_assertions)]
use crate::log_warn;
use serde::Deserialize;
use serde_json::{json, Value};
use std::io::{BufRead, BufReader, ErrorKind, Write};
use std::process::{Child, ChildStdin, ChildStdout, Command, Stdio};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::{Duration, Instant};

#[cfg(unix)]
use libc;

// MARK: - Lazy-init singleton helper process

static HELPER: OnceLock<Mutex<Option<HelperProcess>>> = OnceLock::new();

const HELPER_TIMEOUT_SECS: u64 = 10;  // Helper 回應超時時間

struct HelperProcess {
    stdin: ChildStdin,
    stdout: BufReader<ChildStdout>,
    child: Child,
    last_response: Arc<Mutex<Instant>>,  // 最後一次成功回應時間
}

fn get_helper_path() -> std::path::PathBuf {
    // 在 debug 模式下使用 swift build 的產物
    #[cfg(debug_assertions)]
    {
        // L5 修復：優先使用環境變量，避免硬編碼路徑
        if let Ok(helper_path) = std::env::var("ECHOTYPE_HELPER_PATH") {
            return std::path::PathBuf::from(helper_path);
        }

        let workspace = std::env::current_exe()
            .unwrap_or_default()
            .ancestors()
            .find(|p| p.join("helper").exists())
            .map(|p| p.to_path_buf())
            .or_else(|| {
                // 嘗試從當前目錄向上查找
                std::env::current_dir().ok().and_then(|cwd| {
                    cwd.ancestors()
                        .find(|p| p.join("helper").exists())
                        .map(|p| p.to_path_buf())
                })
            })
            .unwrap_or_else(|| {
                log_warn!("Could not find helper directory, using current directory");
                std::env::current_dir().unwrap_or_default()
            });

        workspace
            .join("helper")
            .join(".build/arm64-apple-macosx/debug/EchoTypeHelper")
    }
    // 在 Release 模式下，helper 打包在 app bundle 內
    #[cfg(not(debug_assertions))]
    {
        let exe = std::env::current_exe().unwrap_or_default();
        exe.parent()
            .unwrap_or(&exe)
            .join("EchoTypeHelper")
    }
}

fn acquire_helper() -> Result<(), String> {
    let mutex = HELPER.get_or_init(|| Mutex::new(None));
    let mut guard = mutex.lock().map_err(|e| e.to_string())?;

    if guard.is_some() {
        return Ok(());  // Already running
    }

    let helper_path = get_helper_path();
    if !helper_path.exists() {
        return Err(format!(
            "EchoTypeHelper not found at {}. Run: cd EchoType/helper && swift build",
            helper_path.display()
        ));
    }

    // M1 修復：將 stderr 重定向到日誌文件而非 /dev/null
    let log_dir = std::env::temp_dir().join("echotype");
    std::fs::create_dir_all(&log_dir).ok();
    let stderr_log = log_dir.join("helper_stderr.log");
    let stderr_file = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&stderr_log)
        .map_err(|e| format!("Failed to open stderr log: {}", e))?;

    let mut child = Command::new(&helper_path)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(stderr_file)
        .spawn()
        .map_err(|e| format!("Failed to spawn EchoTypeHelper: {}", e))?;

    eprintln!("[bridge] Helper stderr logging to: {}", stderr_log.display());

    let stdin = child.stdin.take().ok_or("No stdin")?;
    let stdout = child.stdout.take().ok_or("No stdout")?;

    *guard = Some(HelperProcess {
        stdin,
        stdout: BufReader::new(stdout),
        child,
        last_response: Arc::new(Mutex::new(Instant::now())),
    });

    Ok(())
}

// MARK: - Core call function

#[derive(Deserialize)]
struct HelperResponse {
    ok: bool,
    result: Option<Value>,
    error: Option<String>,
}

pub fn call_helper(cmd: &str, args: Value) -> Result<Value, String> {
    acquire_helper()?;

    let mutex = HELPER.get().ok_or("Helper not initialized")?;
    let mut guard = mutex.lock().map_err(|e| e.to_string())?;
    let helper = guard.as_mut().ok_or("Helper process not running")?;

    // 健康檢查：如果 helper 進程已死亡，重啟
    match helper.child.try_wait() {
        Ok(Some(status)) => {
            eprintln!("[bridge] Helper process exited with status: {}", status);
            drop(guard);  // 釋放鎖
            // 清空舊的 helper 並重新啟動
            let mutex = HELPER.get().ok_or("Helper not initialized")?;
            *mutex.lock().map_err(|e| e.to_string())? = None;
            acquire_helper()?;
            // 重新獲取鎖
            guard = mutex.lock().map_err(|e| e.to_string())?;
        }
        Ok(None) => {}, // 進程仍在運行
        Err(e) => {
            eprintln!("[bridge] Failed to check helper status: {}", e);
        }
    }

    let helper = guard.as_mut().ok_or("Helper process not running after restart")?;

    // Send request
    let request = json!({ "cmd": cmd, "args": args });
    let mut line = serde_json::to_string(&request).map_err(|e| e.to_string())?;
    line.push('\n');
    helper.stdin.write_all(line.as_bytes()).map_err(|e| format!("Write error: {}", e))?;
    helper.stdin.flush().map_err(|e| format!("Flush error: {}", e))?;

    // Read response with timeout using polling
    let start = Instant::now();
    let mut response_line = String::new();

    // 設置 stdout 為非阻塞模式
    #[cfg(unix)]
    let original_flags = {
        use std::os::unix::io::AsRawFd;
        let fd = helper.stdout.get_ref().as_raw_fd();
        unsafe {
            let flags = libc::fcntl(fd, libc::F_GETFL, 0);
            libc::fcntl(fd, libc::F_SETFL, flags | libc::O_NONBLOCK);
            flags
        }
    };

    // 輪詢讀取，直到成功或超時
    let read_result = loop {
        match helper.stdout.read_line(&mut response_line) {
            Ok(0) => {
                // EOF - helper 進程已關閉
                break Err("Helper process closed unexpectedly".to_string());
            }
            Ok(_) => {
                // 成功讀取
                *helper.last_response.lock().unwrap() = Instant::now();
                break Ok(());
            }
            Err(e) if e.kind() == ErrorKind::WouldBlock => {
                // 非阻塞模式：數據尚未就緒
                if start.elapsed() > Duration::from_secs(HELPER_TIMEOUT_SECS) {
                    break Err(format!(
                        "Helper timeout after {}s (cmd: {}). Process killed.",
                        HELPER_TIMEOUT_SECS, cmd
                    ));
                }
                // 短暫休眠後重試
                std::thread::sleep(Duration::from_millis(10));
            }
            Err(e) => {
                break Err(format!("Read error: {}", e));
            }
        }
    };

    // 恢復 stdout 為阻塞模式
    #[cfg(unix)]
    {
        use std::os::unix::io::AsRawFd;
        let fd = helper.stdout.get_ref().as_raw_fd();
        unsafe {
            libc::fcntl(fd, libc::F_SETFL, original_flags);
        }
    }

    // 處理讀取結果
    if let Err(e) = read_result {
        let _ = helper.child.kill();
        drop(guard);
        let mutex = HELPER.get().ok_or("Helper not initialized")?;
        *mutex.lock().map_err(|e| e.to_string())? = None;
        return Err(e);
    }

    let resp: HelperResponse = serde_json::from_str(&response_line)
        .map_err(|e| format!("JSON parse error: {} (raw: {})", e, response_line.trim()))?;

    if resp.ok {
        Ok(resp.result.unwrap_or(Value::Null))
    } else {
        Err(resp.error.unwrap_or_else(|| "Unknown helper error".into()))
    }
}

/// 便捷函式：在非同步 Tauri 命令中用 spawn_blocking 呼叫同步的 call_helper
pub async fn call_helper_async(cmd: &'static str, args: Value) -> Result<Value, String> {
    tokio::task::spawn_blocking(move || call_helper(cmd, args))
        .await
        .map_err(|e| e.to_string())?
}
