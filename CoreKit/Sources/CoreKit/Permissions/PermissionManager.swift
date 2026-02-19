// CoreKit/Sources/CoreKit/Permissions/PermissionManager.swift
// 統一封裝 macOS 三大權限的 Swift Actor (v0.3.0)

import AVFoundation
import AppKit

public actor PermissionManager {

    public static let shared = PermissionManager()

    private init() {}

    // MARK: - 麥克風

    /// 查詢麥克風授權狀態（不觸發系統對話框）
    public func checkMicrophoneStatus() -> String {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .notDetermined: return "not_determined"
        case .authorized:    return "authorized"
        case .denied:        return "denied"
        case .restricted:    return "restricted"
        @unknown default:    return "unknown"
        }
    }

    /// 請求麥克風授權（觸發系統對話框）
    /// 返回 "authorized" 或 "denied"
    public func requestMicrophone() async -> String {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        return granted ? "authorized" : "denied"
    }

    // MARK: - Accessibility (AXIsProcessTrusted)

    /// 查詢 Accessibility 授權狀態（不觸發對話框）
    public func checkAccessibility() -> Bool {
        AXIsProcessTrusted()
    }

    // MARK: - 系統設定 Deep Links

    /// 開啟系統設定對應權限面板
    public func openSystemPreferences(pane: String) {
        let urlMap: [String: String] = [
            "microphone":
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone",
            "accessibility":
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "input_monitoring":
                "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent",
        ]

        guard let urlStr = urlMap[pane],
              let url = URL(string: urlStr) else {
            return
        }

        NSWorkspace.shared.open(url)
    }
}
