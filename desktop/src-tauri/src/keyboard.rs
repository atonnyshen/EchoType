// keyboard.rs — fn 鍵 CGEventTap 狀態機 (v0.3.0)
//
// 架構：移除 tauri-plugin-global-shortcut，改用 Rust 直接 FFI 呼叫 CGEventTap
// 支援兩種錄音模式：
//   - push_to_talk: 長按 fn > 300ms → 開始錄音 → 放開 → 停止
//   - toggle:       短按 fn < 300ms → toggle 錄音開/關（hotkey-tap 事件，由前端處理）
//
// 防誤觸策略：
//   1. 50ms debounce（忽略 flagsChanged 事件抖動）
//   2. 300ms 長按閾值（HOLD_THRESHOLD_MS）
//   3. 500ms 最短有效錄音時長（MIN_RECORDING_MS）
//   4. CGEventTap 被系統停用時自動 re-enable

use std::ffi::c_void;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use tauri::{AppHandle, Emitter};

// MARK: - FFI Types

type CGEventRef = *mut c_void;
type CGEventTapProxy = *mut c_void;
type CFMachPortRef = *mut c_void;
type CFRunLoopSourceRef = *mut c_void;
type CFRunLoopRef = *mut c_void;

// MARK: - CGEventTap 常數

const K_CG_SESSION_EVENT_TAP: u32 = 1;
const K_CG_HEAD_INSERT_EVENT_TAP: u32 = 0;
const K_CG_EVENT_TAP_OPTION_LISTEN_ONLY: u32 = 1;
const K_CG_EVENT_FLAGS_CHANGED: u32 = 12;
const K_CG_EVENT_KEY_DOWN: u32 = 10;
const K_CG_EVENT_TAP_DISABLED_BY_TIMEOUT: u32 = 0xFFFFFFFE;

const FN_FLAG_MASK: u64 = 0x800000; // kCGEventFlagMaskSecondaryFn
const SHIFT_FLAG: u64   = 0x020000; // kCGEventFlagMaskShift
const CTRL_FLAG: u64    = 0x040000; // kCGEventFlagMaskControl
const ALT_FLAG: u64     = 0x080000; // kCGEventFlagMaskAlternate
const CMD_FLAG: u64     = 0x100000; // kCGEventFlagMaskCommand
const COMBO_MASK: u64   = SHIFT_FLAG | CTRL_FLAG | ALT_FLAG | CMD_FLAG;

const HOLD_THRESHOLD_MS: u64 = 300;  // 長按判定閾值
const MIN_RECORDING_MS: u64 = 500;   // 最短有效錄音時長
const DEBOUNCE_MS: u64 = 50;         // flagsChanged 去抖動

// MARK: - FFI 宣告

extern "C" {
    fn CGEventTapCreate(
        tap: u32,
        place: u32,
        options: u32,
        events_of_interest: u64,
        callback: extern "C" fn(CGEventTapProxy, u32, CGEventRef, *mut c_void) -> CGEventRef,
        user_info: *mut c_void,
    ) -> CFMachPortRef;

    fn CGEventGetFlags(event: CGEventRef) -> u64;
    fn CGEventGetIntegerValueField(event: CGEventRef, field: u32) -> i64;
    fn CGEventTapEnable(tap: CFMachPortRef, enable: bool);
    #[allow(dead_code)]
    fn CGEventTapIsEnabled(tap: CFMachPortRef) -> bool;

    fn CFMachPortCreateRunLoopSource(
        allocator: *const c_void,
        port: CFMachPortRef,
        order: i64,
    ) -> CFRunLoopSourceRef;

    fn CFRunLoopGetCurrent() -> CFRunLoopRef;
    fn CFRunLoopAddSource(rl: CFRunLoopRef, source: CFRunLoopSourceRef, mode: *const c_void);
    fn CFRunLoopRun();
    fn CFRelease(cf: *const c_void);
}

extern "C" {
    static kCFRunLoopCommonModes: *const c_void;
}

// MARK: - 狀態機

#[derive(Debug, Clone, Copy, PartialEq)]
enum FnKeyState {
    Idle,      // 閒置，等待 fn 按下
    Pending,   // fn 已按下，等待 300ms 判定長按或點按
    Holding,   // 確認長按（> 300ms），正在錄音
}

// MARK: - Context（CGEventTap callback 全域狀態）

struct FnKeyContext {
    state: Mutex<FnKeyState>,
    press_instant: Mutex<Instant>,
    last_event_ms: AtomicU64,
    app_handle: AppHandle,
    tap_ref: Mutex<Option<CFMachPortRef>>,
    timer_cancelled: AtomicBool,  // 取消標記：防止計時器在 fn 放開後仍觸發
}

// SAFETY: Manual Send/Sync implementation for FnKeyContext
//
// This is safe because:
// 1. CFMachPortRef is an opaque pointer to a Core Foundation object that is thread-safe
//    when accessed through proper synchronization (which we do via Mutex<Option<CFMachPortRef>>)
// 2. The tap_ref is only accessed under Mutex protection, ensuring exclusive access
// 3. The CGEventTap callback runs on a dedicated CFRunLoop thread that we spawn and control
// 4. AppHandle is already Send+Sync (Tauri guarantees this)
// 5. Mutex<FnKeyState> and Mutex<Instant> are Send+Sync by definition
// 6. AtomicU64 is Send+Sync by definition
//
// The CFMachPortRef itself is never directly accessed across threads without synchronization.
// All mutations happen either:
// - In the CFRunLoop thread (via event_tap_callback)
// - In timer threads (via the 300ms hold detection thread)
// Both of which properly synchronize through the Mutex-protected state.
unsafe impl Send for FnKeyContext {}
unsafe impl Sync for FnKeyContext {}

// 全域 context 指標（CGEventTap C callback 需要，只在 start_fn_key_listener 中設定一次）
static GLOBAL_CTX: std::sync::OnceLock<Arc<FnKeyContext>> = std::sync::OnceLock::new();

// MARK: - CGEventTap Callback

extern "C" fn event_tap_callback(
    _proxy: CGEventTapProxy,
    event_type: u32,
    event: CGEventRef,
    _user_info: *mut c_void,
) -> CGEventRef {
    // CGEventTap 被系統停用時（通常因 callback 執行太慢）自動重啟
    if event_type == K_CG_EVENT_TAP_DISABLED_BY_TIMEOUT {
        if let Some(ctx) = GLOBAL_CTX.get() {
            if let Ok(guard) = ctx.tap_ref.lock() {
                if let Some(tap) = *guard {
                    unsafe { CGEventTapEnable(tap, true); }
                    eprintln!("[keyboard] CGEventTap 被停用，已自動重啟");
                }
            }
        }
        return event;
    }

    // 處理 keyDown 事件
    if event_type == K_CG_EVENT_KEY_DOWN {
        if let Some(ctx) = GLOBAL_CTX.get() {
            let flags = unsafe { CGEventGetFlags(event) };
            let keycode = unsafe { CGEventGetIntegerValueField(event, 9) }; // kCGKeyboardEventKeycode = 9

            // 偵測 Ctrl+Cmd+V (keycode 0x09 = V key)
            const V_KEYCODE: i64 = 0x09;
            let has_cmd = (flags & CMD_FLAG) != 0;
            let has_ctrl = (flags & CTRL_FLAG) != 0;

            if keycode == V_KEYCODE && has_cmd && has_ctrl {
                let _ = ctx.app_handle.emit("paste-last-transcript", "ctrl-cmd-v");
                return event;
            }

            // 如果在 Pending/Holding 狀態收到任何按鍵，取消錄音
            let mut state = ctx.state.lock().unwrap();
            if *state == FnKeyState::Pending || *state == FnKeyState::Holding {
                // H1 修復：Pending 狀態也需要設置取消標記
                if *state == FnKeyState::Pending {
                    ctx.timer_cancelled.store(true, Ordering::Release);
                }
                if *state == FnKeyState::Holding {
                    let _ = ctx.app_handle.emit("hotkey-cancelled", "combo-key");
                }
                *state = FnKeyState::Idle;
            }
        }
        return event;
    }

    if event_type != K_CG_EVENT_FLAGS_CHANGED {
        return event;
    }

    let flags = unsafe { CGEventGetFlags(event) };
    let fn_down = (flags & FN_FLAG_MASK) != 0;

    if let Some(ctx) = GLOBAL_CTX.get() {
        process_fn_event(ctx, fn_down, flags);
    }

    event
}

fn process_fn_event(ctx: &Arc<FnKeyContext>, fn_down: bool, flags: u64) {
    // 如果 fn 與其他 modifier 同時按下（Shift/Ctrl/Alt/Cmd），忽略此事件
    if fn_down && (flags & COMBO_MASK) != 0 {
        let mut state = ctx.state.lock().unwrap();
        // H1 修復：Pending 狀態也需要設置取消標記
        if *state == FnKeyState::Pending {
            ctx.timer_cancelled.store(true, Ordering::Release);
        }
        if *state == FnKeyState::Holding {
            let _ = ctx.app_handle.emit("hotkey-cancelled", "combo-key");
        }
        *state = FnKeyState::Idle;
        return;
    }

    // Debounce：忽略 50ms 內的重複事件（flagsChanged 事件常有抖動）
    let now_ms = {
        let epoch = ctx.press_instant.lock().unwrap();
        epoch.elapsed().as_millis() as u64
    };
    let last = ctx.last_event_ms.load(Ordering::Relaxed);
    if now_ms.saturating_sub(last) < DEBOUNCE_MS {
        return;
    }
    ctx.last_event_ms.store(now_ms, Ordering::Relaxed);

    let mut state = ctx.state.lock().unwrap();

    match (*state, fn_down) {
        // IDLE + fn 按下 → PENDING 並啟動 300ms 計時器
        (FnKeyState::Idle, true) => {
            *ctx.press_instant.lock().unwrap() = Instant::now();
            *state = FnKeyState::Pending;

            // 重置取消標記
            ctx.timer_cancelled.store(false, Ordering::Release);

            let ctx_clone = Arc::clone(ctx);
            std::thread::spawn(move || {
                std::thread::sleep(Duration::from_millis(HOLD_THRESHOLD_MS));

                // 檢查取消標記：如果已取消，直接返回
                if ctx_clone.timer_cancelled.load(Ordering::Acquire) {
                    return;
                }

                let mut s = ctx_clone.state.lock().unwrap();
                if *s == FnKeyState::Pending {
                    *s = FnKeyState::Holding;
                    // 通知前端：長按確認，開始錄音
                    let _ = ctx_clone.app_handle.emit("hotkey-pressed", "fn-hold");
                }
            });
        }

        // PENDING + fn 放開（< 300ms）→ 點按模式，通知前端 toggle
        (FnKeyState::Pending, false) => {
            // 設置取消標記，防止計時器線程繼續執行
            ctx.timer_cancelled.store(true, Ordering::Release);
            *state = FnKeyState::Idle;
            let _ = ctx.app_handle.emit("hotkey-tap", "fn-tap");
        }

        // HOLDING + fn 放開 → 長按模式，判斷錄音時長是否達到最短門檻
        (FnKeyState::Holding, false) => {
            let elapsed = ctx.press_instant.lock().unwrap().elapsed();
            *state = FnKeyState::Idle;

            if elapsed.as_millis() >= MIN_RECORDING_MS as u128 {
                // 有效錄音，通知前端停止
                let _ = ctx.app_handle.emit("hotkey-released", "fn-hold");
            } else {
                // 錄音太短（通常是 300ms-500ms 之間），丟棄
                let _ = ctx.app_handle.emit("hotkey-cancelled", "too-short");
            }
        }

        _ => {}
    }
}

// MARK: - Public API

/// 啟動 fn 鍵全域監聽（在獨立執行緒的 CFRunLoop 中運行）
/// 必須在應用啟動時呼叫，只能呼叫一次
pub fn start_fn_key_listener(app: AppHandle) {
    std::thread::spawn(move || {
        let ctx = Arc::new(FnKeyContext {
            state: Mutex::new(FnKeyState::Idle),
            press_instant: Mutex::new(Instant::now()),
            last_event_ms: AtomicU64::new(0),
            app_handle: app,
            tap_ref: Mutex::new(None),
            timer_cancelled: AtomicBool::new(false),
        });

        // 設定全域 context（OnceLock 只設定一次）
        let _ = GLOBAL_CTX.set(Arc::clone(&ctx));

        // 監聽 kCGEventFlagsChanged (type 12) 和 kCGEventKeyDown (type 10)
        let mask: u64 = (1u64 << K_CG_EVENT_FLAGS_CHANGED) | (1u64 << K_CG_EVENT_KEY_DOWN);

        let tap = unsafe {
            CGEventTapCreate(
                K_CG_SESSION_EVENT_TAP,
                K_CG_HEAD_INSERT_EVENT_TAP,
                K_CG_EVENT_TAP_OPTION_LISTEN_ONLY,
                mask,
                event_tap_callback,
                std::ptr::null_mut(),
            )
        };

        if tap.is_null() {
            eprintln!(
                "[keyboard] CGEventTap 建立失敗 — 請確認已授予「輸入監控 (Input Monitoring)」權限"
            );
            return;
        }

        // 儲存 tap 指標以供自動重啟使用
        *ctx.tap_ref.lock().unwrap() = Some(tap);

        unsafe {
            let source = CFMachPortCreateRunLoopSource(std::ptr::null(), tap, 0);
            let run_loop = CFRunLoopGetCurrent();
            CFRunLoopAddSource(run_loop, source, kCFRunLoopCommonModes);
            CGEventTapEnable(tap, true);

            // Release the source after adding to run loop (follows Create Rule)
            // The run loop retains it, so we must release our ownership
            CFRelease(source as *const c_void);

            eprintln!("[keyboard] CGEventTap 已啟動，監聽 fn 鍵事件");

            // 阻塞此執行緒，直到 CFRunLoop 結束（正常情況永不結束）
            CFRunLoopRun();
        }
    });
}
