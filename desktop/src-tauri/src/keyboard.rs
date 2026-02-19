// keyboard.rs — 全域快捷鍵管理
use tauri::{AppHandle, Emitter};
use tauri_plugin_global_shortcut::{GlobalShortcutExt, ShortcutState};

pub const DEFAULT_HOTKEY: &str = "F13";

pub fn register_recording_hotkey(app: &AppHandle, hotkey: &str) -> Result<(), String> {
    app.global_shortcut()
        .on_shortcut(hotkey, move |app_handle, shortcut, event| {
            if event.state == ShortcutState::Pressed {
                let _ = app_handle.emit("hotkey-pressed", shortcut.to_string());
            } else {
                let _ = app_handle.emit("hotkey-released", shortcut.to_string());
            }
        })
        .map_err(|e| e.to_string())
}
