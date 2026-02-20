use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use tauri::Emitter;
use tauri_plugin_autostart::ManagerExt;
use crate::bridge::call_helper_async;
use crate::permissions;

// MARK: - Data Types

#[derive(Debug, Serialize, Deserialize)]
pub struct AppContext {
    pub app_name: Option<String>,
    pub bundle_id: Option<String>,
    pub window_title: Option<String>,
    pub web_url: Option<String>,
    pub web_domain: Option<String>,
    pub web_title: Option<String>,
    pub context_before: Option<String>,
    pub context_after: Option<String>,
    pub selected_text: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct HistoryEntry {
    pub id: String,
    pub transcript: String,
    pub polished_text: Option<String>,
    pub app_name: Option<String>,
    pub window_title: Option<String>,
    pub web_url: Option<String>,
    pub web_domain: Option<String>,
    pub web_title: Option<String>,
    pub asr_engine: String,
    pub created_at: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct RecordingResult {
    pub transcript: String,
    pub polished_text: String,
    pub duration_seconds: f64,
    pub asr_engine: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct AudioDevice {
    pub id: String,
    pub name: String,
    pub is_default: bool,
}

// MARK: - Helper: parse Value into typed struct

fn parse<T: for<'de> Deserialize<'de>>(v: Value) -> Result<T, String> {
    serde_json::from_value(v).map_err(|e| format!("Parse error: {}", e))
}

// MARK: - Tauri Commands (connected to EchoTypeHelper via bridge)

/// 取得當前焦點 App 的上下文
#[tauri::command]
pub async fn get_context() -> Result<AppContext, String> {
    let result = call_helper_async("get_context", json!({})).await?;
    parse(result)
}

/// 開始錄音（在 helper 內啟動 AVAudioEngine）
#[tauri::command]
pub async fn start_recording() -> Result<String, String> {
    let result = call_helper_async("start_recording", json!({})).await?;
    Ok(result.as_str().unwrap_or("ok").to_string())
}

/// 停止錄音、ASR 轉錄（whisper.cpp 或 MLX），回傳原始轉錄
#[tauri::command]
pub async fn stop_recording() -> Result<RecordingResult, String> {
    // 1. 停止錄音，取得 transcript
    let asr_result = call_helper_async("stop_recording", json!({})).await?;

    // H2 修復：統一錯誤處理，避免 unwrap_or 吞掉錯誤
    let transcript = asr_result["transcript"]
        .as_str()
        .ok_or("Missing transcript field")?
        .to_string();
    let duration = asr_result["duration"]
        .as_f64()
        .ok_or("Missing duration field")?;
    let engine = asr_result["asr_engine"]
        .as_str()
        .ok_or("Missing asr_engine field")?
        .to_string();

    // 2. 從設定取得潤飾模式
    let settings = call_helper_async("get_settings", json!({})).await?;
    let polisher_mode = settings["polisher_mode"].as_str().unwrap_or("none").to_string();

    // 3. 如果選擇本地或雲端潤飾，目前先 passthrough (模型整合在 helper 端 TODO)
    let polished = if polisher_mode != "none" {
        transcript.clone() // TODO: hook into LocalPolisher in helper
    } else {
        transcript.clone()
    };

    // 4. 取得上下文並儲存歷史記錄（非關鍵操作，失敗僅記錄）
    let ctx = call_helper_async("get_context", json!({})).await.ok();
    if let Err(e) = call_helper_async("save_history", json!({
        "transcript": transcript,
        "polished_text": polished,
        "app_name": ctx.as_ref().and_then(|c| c["app_name"].as_str()),
        "window_title": ctx.as_ref().and_then(|c| c["window_title"].as_str()),
        "web_url": ctx.as_ref().and_then(|c| c["web_url"].as_str()),
        "web_domain": ctx.as_ref().and_then(|c| c["web_domain"].as_str()),
        "web_title": ctx.as_ref().and_then(|c| c["web_title"].as_str()),
        "asr_engine": engine,
        "duration": duration
    })).await {
        eprintln!("[commands] Failed to save history: {}", e);
    }

    Ok(RecordingResult {
        transcript: transcript.clone(),
        polished_text: polished,
        duration_seconds: duration,
        asr_engine: engine,
    })
}

/// 注入文字到焦點 App（AX API → 剪貼簿 fallback）
#[tauri::command]
pub async fn inject_text(app: tauri::AppHandle, text: String) -> Result<(), String> {
    match call_helper_async("inject_text", json!({ "text": text.clone() })).await {
        Ok(_) => Ok(()),
        Err(e) => {
            // 注入失敗，emit 事件給前端，讓使用者手動複製
            let _ = app.emit("inject-failed", json!({ "text": text }));
            Err(e)
        }
    }
}

/// 取得歷史記錄（從 SQLite via GRDB）
#[tauri::command]
pub async fn get_history(limit: Option<usize>) -> Result<Vec<HistoryEntry>, String> {
    let result = call_helper_async("get_history", json!({ "limit": limit.unwrap_or(50) })).await?;
    parse(result)
}

/// 取得全部設定
#[tauri::command]
pub async fn get_settings() -> Result<Value, String> {
    call_helper_async("get_settings", json!({})).await
}

/// 儲存單一設定（同步反映到 ASR Manager）
#[tauri::command]
pub async fn set_setting(app: tauri::AppHandle, key: String, value: String) -> Result<(), String> {
    // 特殊處理：launchAtLogin
    if key == "launchAtLogin" {
        let enable = value == "true";
        let autostart = app.autolaunch();
        if enable {
            autostart.enable().map_err(|e: tauri_plugin_autostart::Error| e.to_string())?;
        } else {
            autostart.disable().map_err(|e: tauri_plugin_autostart::Error| e.to_string())?;
        }
    }

    call_helper_async("set_setting", json!({ "key": key, "value": value })).await?;
    Ok(())
}

/// 取得麥克風列表
#[tauri::command]
pub async fn get_microphones() -> Result<Vec<AudioDevice>, String> {
    let result = call_helper_async("get_microphones", json!({})).await?;
    parse(result)
}

// MARK: - v0.3.0 Permission Commands

#[derive(Debug, Clone, Serialize)]
pub struct PermissionStatusResponse {
    pub microphone: String,
    pub accessibility: bool,
    pub input_monitoring: bool,
}

/// 一次性查詢所有權限狀態
/// microphone 狀態透過 Swift helper 取得（AVFoundation TCC 需在帶有 UI 的進程中讀取）
#[tauri::command]
pub async fn check_permissions() -> Result<PermissionStatusResponse, String> {
    // H2 修復：麥克風權限查詢失敗應返回錯誤而非默認值
    let mic_status = call_helper_async("check_microphone_permission", json!({}))
        .await
        .map(|v| v.as_str().unwrap_or("unknown").to_string())
        .unwrap_or_else(|e| {
            eprintln!("[commands] Failed to check microphone permission: {}", e);
            "error".to_string()
        });

    // Accessibility 和 Input Monitoring：在 Rust 端直接查詢
    let accessibility = permissions::check_accessibility();
    let input_monitoring = permissions::check_input_monitoring();

    Ok(PermissionStatusResponse {
        microphone: mic_status,
        accessibility,
        input_monitoring,
    })
}

/// 開啟系統設定對應的權限頁面
#[tauri::command]
pub fn open_system_preferences(pane: String) -> Result<(), String> {
    permissions::open_system_preferences(&pane)
}

/// 請求麥克風權限（觸發系統對話框）
/// 若用戶已決定（authorized/denied），此呼叫不會再次彈窗
#[tauri::command]
pub async fn request_microphone() -> Result<String, String> {
    call_helper_async("request_microphone", json!({}))
        .await
        .map(|v| v.as_str().unwrap_or("denied").to_string())
}

/// 取得個人詞典
#[tauri::command]
pub async fn get_dictionary() -> Result<Vec<String>, String> {
    let result = call_helper_async("get_dictionary", json!({})).await?;
    parse(result)
}

/// 設定個人詞典
#[tauri::command]
pub async fn set_dictionary(words: Vec<String>) -> Result<(), String> {
    call_helper_async("set_dictionary", json!({ "words": words })).await?;
    Ok(())
}
