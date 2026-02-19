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

    let _tray = TrayIconBuilder::new()
        .icon(app.default_window_icon().unwrap().clone())
        .menu(&menu)
        .tooltip("EchoType — 語音輸入助手")
        .on_tray_icon_event(|tray, event| match event {
            TrayIconEvent::Click {
                button: MouseButton::Left,
                button_state: MouseButtonState::Up,
                ..
            } => {
                let app = tray.app_handle();
                if let Some(win) = app.get_webview_window("main") {
                    let _ = win.show();
                    let _ = win.set_focus();
                }
            }
            _ => {}
        })
        .on_menu_event(|app, event| match event.id.as_ref() {
            "quit" => app.exit(0),
            "show" => {
                if let Some(win) = app.get_webview_window("main") {
                    let _ = win.show();
                    let _ = win.set_focus();
                }
            }
            "settings" => {
                if let Some(win) = app.get_webview_window("main") {
                    let _ = win.show();
                    let _ = win.set_focus();
                    let _ = win.emit("navigate", "/settings");
                }
            }
            _ => {}
        })
        .build(app)?;

    Ok(())
}
