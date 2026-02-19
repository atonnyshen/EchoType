// Prevents additional console window on Windows in release, DO NOT REMOVE!!
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

pub mod bridge;
pub mod commands;
pub mod keyboard;
pub mod tray;


#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_notification::init())
        .plugin(tauri_plugin_global_shortcut::Builder::new().build())
        .plugin(tauri_plugin_clipboard_manager::init())
        .plugin(tauri_plugin_autostart::init(
            tauri_plugin_autostart::MacosLauncher::LaunchAgent,
            None,
        ))
        .invoke_handler(tauri::generate_handler![
            commands::get_context,
            commands::start_recording,
            commands::stop_recording,
            commands::inject_text,
            commands::get_history,
            commands::get_settings,
            commands::set_setting,
            commands::get_microphones,
        ])
        .setup(|app| {
            // 設定系統托盤
            tray::setup_tray(app)?;

            // 註冊全域錄音快捷鍵
            let handle = app.handle().clone();
            if let Err(e) = keyboard::register_recording_hotkey(&handle, keyboard::DEFAULT_HOTKEY) {
                eprintln!("Failed to register hotkey: {}", e);
            }

            // 建立浮動錄音條視窗（初始隱藏）
            // Tauri v2: transparent + decorations(false) via WindowBuilder config
            tauri::WebviewWindowBuilder::new(
                app,
                "floating-bar",
                tauri::WebviewUrl::App("index.html#/floating".into()),
            )
            .title("EchoType")
            .decorations(false)
            .always_on_top(true)
            .resizable(false)
            .skip_taskbar(true)
            .inner_size(320.0, 80.0)
            .visible(false)
            .build()?;

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running EchoType");
}
