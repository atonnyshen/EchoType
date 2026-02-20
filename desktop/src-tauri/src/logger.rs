// logger.rs — 統一日誌模組，支援環境變量配置日誌級別
//
// 使用方式：
//   export ECHOTYPE_LOG=debug  # 啟用 debug 日誌
//   export ECHOTYPE_LOG=info   # 僅顯示 info 及以上
//   export ECHOTYPE_LOG=error  # 僅顯示錯誤

use std::sync::OnceLock;

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum LogLevel {
    Debug = 0,
    Info = 1,
    Warn = 2,
    Error = 3,
}

static LOG_LEVEL: OnceLock<LogLevel> = OnceLock::new();

pub fn init_logger() {
    let level = std::env::var("ECHOTYPE_LOG")
        .ok()
        .and_then(|s| match s.to_lowercase().as_str() {
            "debug" => Some(LogLevel::Debug),
            "info" => Some(LogLevel::Info),
            "warn" | "warning" => Some(LogLevel::Warn),
            "error" => Some(LogLevel::Error),
            _ => None,
        })
        .unwrap_or(LogLevel::Info);

    LOG_LEVEL.set(level).ok();
    eprintln!("[logger] Log level set to: {:?}", level);
}

pub fn should_log(level: LogLevel) -> bool {
    let current = LOG_LEVEL.get().copied().unwrap_or(LogLevel::Info);
    level >= current
}

#[macro_export]
macro_rules! log_debug {
    ($($arg:tt)*) => {
        if $crate::logger::should_log($crate::logger::LogLevel::Debug) {
            eprintln!("[DEBUG] {}", format!($($arg)*));
        }
    };
}

#[macro_export]
macro_rules! log_info {
    ($($arg:tt)*) => {
        if $crate::logger::should_log($crate::logger::LogLevel::Info) {
            eprintln!("[INFO] {}", format!($($arg)*));
        }
    };
}

#[macro_export]
macro_rules! log_warn {
    ($($arg:tt)*) => {
        if $crate::logger::should_log($crate::logger::LogLevel::Warn) {
            eprintln!("[WARN] {}", format!($($arg)*));
        }
    };
}

#[macro_export]
macro_rules! log_error {
    ($($arg:tt)*) => {
        if $crate::logger::should_log($crate::logger::LogLevel::Error) {
            eprintln!("[ERROR] {}", format!($($arg)*));
        }
    };
}

