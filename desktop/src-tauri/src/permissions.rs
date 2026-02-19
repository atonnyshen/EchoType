// permissions.rs — macOS 權限管理模組 (v0.3.0)
// 職責：集中管理 Accessibility、Input Monitoring 的 Rust 端檢測與系統設定 Deep Links

use serde::Serialize;
use std::ffi::c_void;
use std::process::Command;

// MARK: - Permission Status

#[derive(Debug, Clone, Serialize)]
pub struct PermissionStatus {
    pub microphone: String,      // "not_determined" | "authorized" | "denied" | "restricted"
    pub accessibility: bool,     // AXIsProcessTrusted()
    pub input_monitoring: bool,  // 嘗試建立 CGEventTap 探針
}

// MARK: - Accessibility (AXIsProcessTrusted)

extern "C" {
    fn AXIsProcessTrusted() -> bool;
}

pub fn check_accessibility() -> bool {
    unsafe { AXIsProcessTrusted() }
}

// MARK: - Input Monitoring（間接偵測）
// 嘗試建立 ListenOnly CGEventTap，成功 = 有 Input Monitoring 權限
// 成功後立即銷毀，This is a probe-only tap

extern "C" {
    #[allow(dead_code)]
    fn CGEventTapCreate(
        tap: u32,
        place: u32,
        options: u32,
        events_of_interest: u64,
        callback: extern "C" fn(*mut c_void, u32, *mut c_void, *mut c_void) -> *mut c_void,
        user_info: *mut c_void,
    ) -> *mut c_void;

    fn CFRelease(cf: *const c_void);
}

// 探針 callback（不做任何事）
extern "C" fn probe_callback(
    _proxy: *mut c_void,
    _event_type: u32,
    event: *mut c_void,
    _user_info: *mut c_void,
) -> *mut c_void {
    event
}

pub fn check_input_monitoring() -> bool {
    const K_CG_SESSION_EVENT_TAP: u32 = 1;
    const K_CG_HEAD_INSERT_EVENT_TAP: u32 = 0;
    const K_CG_EVENT_TAP_OPTION_LISTEN_ONLY: u32 = 1;
    const K_CG_EVENT_FLAGS_CHANGED: u64 = 1 << 12;

    unsafe {
        let tap = CGEventTapCreate(
            K_CG_SESSION_EVENT_TAP,
            K_CG_HEAD_INSERT_EVENT_TAP,
            K_CG_EVENT_TAP_OPTION_LISTEN_ONLY,
            K_CG_EVENT_FLAGS_CHANGED,
            probe_callback,
            std::ptr::null_mut(),
        );

        if tap.is_null() {
            return false;
        }

        CFRelease(tap as *const c_void);
        true
    }
}

// MARK: - System Preferences Deep Links

pub fn open_system_preferences(pane: &str) -> Result<(), String> {
    let url = match pane {
        "microphone" =>
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone",
        "accessibility" =>
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
        "input_monitoring" =>
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent",
        _ => return Err(format!("Unknown pane: {pane}")),
    };

    Command::new("open")
        .arg(url)
        .spawn()
        .map_err(|e| e.to_string())?;

    Ok(())
}
