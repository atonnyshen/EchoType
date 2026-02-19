// bridge.rs — Rust 端 JSON-IPC 與 EchoTypeHelper 溝通模組
//
// 架構:
//   Rust (Tauri) ─stdin→ EchoTypeHelper (Swift) ─stdout→ Rust
//   每次呼叫發送一行 JSON，讀取一行 JSON 回應。

use serde::Deserialize;
use serde_json::{json, Value};
use std::io::{BufRead, BufReader, Write};
use std::process::{Child, ChildStdin, ChildStdout, Command, Stdio};
use std::sync::{Mutex, OnceLock};

// MARK: - Lazy-init singleton helper process

static HELPER: OnceLock<Mutex<Option<HelperProcess>>> = OnceLock::new();

struct HelperProcess {
    stdin: ChildStdin,
    stdout: BufReader<ChildStdout>,
    _child: Child,
}

fn get_helper_path() -> std::path::PathBuf {
    // 在 debug 模式下使用 swift build 的產物
    #[cfg(debug_assertions)]
    {
        let workspace = std::env::current_exe()
            .unwrap_or_default()
            .ancestors()
            .find(|p| p.join("helper").exists())
            .map(|p| p.to_path_buf())
            .unwrap_or_else(|| std::path::PathBuf::from("/Users/atonny/工作區/EchoType"));

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

    let mut child = Command::new(&helper_path)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|e| format!("Failed to spawn EchoTypeHelper: {}", e))?;

    let stdin = child.stdin.take().ok_or("No stdin")?;
    let stdout = child.stdout.take().ok_or("No stdout")?;

    *guard = Some(HelperProcess {
        stdin,
        stdout: BufReader::new(stdout),
        _child: child,
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

    // Send request
    let request = json!({ "cmd": cmd, "args": args });
    let mut line = serde_json::to_string(&request).map_err(|e| e.to_string())?;
    line.push('\n');
    helper.stdin.write_all(line.as_bytes()).map_err(|e| format!("Write error: {}", e))?;
    helper.stdin.flush().map_err(|e| format!("Flush error: {}", e))?;

    // Read response (one line)
    let mut response_line = String::new();
    helper.stdout.read_line(&mut response_line).map_err(|e| format!("Read error: {}", e))?;

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
