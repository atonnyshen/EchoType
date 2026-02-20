// Prevents additional console window on Windows in release, DO NOT REMOVE!
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

pub mod bridge;
pub mod commands;
pub mod keyboard;
pub mod logger;  // L3: 日誌模組
pub mod permissions; // v0.3.0 新增
pub mod tray;


#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    // L3: 初始化日誌系統
    logger::init_logger();

    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_notification::init())
        // v0.3.0: 移除 tauri_plugin_global_shortcut，改用 CGEventTap 直接監聽 fn 鍵
        .plugin(tauri_plugin_clipboard_manager::init())
        .plugin(tauri_plugin_updater::Builder::new().build())
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
            // v0.3.0 新增
            commands::check_permissions,
            commands::open_system_preferences,
            commands::request_microphone,
            commands::get_dictionary,
            commands::set_dictionary,
        ])
        .setup(|app| {
            // 設定系統托盤
            tray::setup_tray(app)?;

            // v0.3.0: 啟動 CGEventTap fn 鍵監聽（取代 global-shortcut）
            keyboard::start_fn_key_listener(app.handle().clone());

            // 建立浮動錄音條視窗（初始隱藏，錄音時由前端控制顯示/隱藏）
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
            .inner_size(360.0, 72.0)
            .visible(false)
            .build()?;

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running EchoType");
}
