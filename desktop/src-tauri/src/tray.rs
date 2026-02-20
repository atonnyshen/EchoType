use tauri::{
    menu::{Menu, MenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    App, Emitter, Manager,
};

pub fn setup_tray(app: &mut App) -> tauri::Result<()> {
    let quit = MenuItem::with_id(app, "quit", "結束 EchoType", true, None::<&str>)?;
    let show = MenuItem::with_id(app, "show", "開啟控制台", true, None::<&str>)?;
    let settings = MenuItem::with_id(app, "settings", "設定", true, None::<&str>)?;

    let menu = Menu::with_items(app, &[&show, &settings, &quit])?;

    let tray_builder = TrayIconBuilder::new().menu(&menu);

    // 嘗試使用 default icon，如果失敗則使用內建 icon
    let tray_builder = if let Some(icon) = app.default_window_icon() {
        tray_builder.icon(icon.clone())
    } else {
        tray_builder
    };

    let _tray = tray_builder
        .tooltip("EchoType — 語音輸入助手")
        .on_tray_icon_event(|tray, event| match event {
            TrayIconEvent::Click {
                button: MouseButton::Left,
                button_state: MouseButtonState::Up,
                ..
            } => {
                let app = tray.app_handle();
                if let Some(win) = app.get_webview_window("main") {
                    // H3 修復：添加錯誤處理和日誌
                    if let Err(e) = win.show() {
                        eprintln!("[tray] Failed to show window: {}", e);
                    }
                    if let Err(e) = win.set_focus() {
                        eprintln!("[tray] Failed to focus window: {}", e);
                    }
                } else {
                    eprintln!("[tray] Main window not found");
                }
            }
            _ => {}
        })
        .on_menu_event(|app, event| match event.id.as_ref() {
            "quit" => app.exit(0),
            "show" => {
                if let Some(win) = app.get_webview_window("main") {
                    // H3 修復：添加錯誤處理和日誌
                    if let Err(e) = win.show() {
                        eprintln!("[tray] Failed to show window: {}", e);
                    }
                    if let Err(e) = win.set_focus() {
                        eprintln!("[tray] Failed to focus window: {}", e);
                    }
                } else {
                    eprintln!("[tray] Main window not found");
                }
            }
            "settings" => {
                if let Some(win) = app.get_webview_window("main") {
                    // H3 修復：添加錯誤處理和日誌
                    if let Err(e) = win.show() {
                        eprintln!("[tray] Failed to show window: {}", e);
                    }
                    if let Err(e) = win.set_focus() {
                        eprintln!("[tray] Failed to focus window: {}", e);
                    }
                    if let Err(e) = win.emit("navigate", "/settings") {
                        eprintln!("[tray] Failed to emit navigate event: {}", e);
                    }
                } else {
                    eprintln!("[tray] Main window not found");
                }
            }
            _ => {}
        })
        .build(app)?;

    Ok(())
}
