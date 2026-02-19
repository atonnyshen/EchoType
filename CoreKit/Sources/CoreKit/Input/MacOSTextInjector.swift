import Foundation

// MARK: - Text Injector Protocol
public protocol TextInjectorProtocol: Sendable {
    /// 在游標位置插入文字
    func insertText(_ text: String) async throws

    /// 替換目前選取的文字
    func replaceSelectedText(with text: String) async throws

    /// 刪除游標前的字元
    func deleteBackward(count: Int) async throws
}

// MARK: - Injector Errors
public enum InjectorError: LocalizedError {
    case accessibilityPermissionDenied
    case noFocusedElement
    case insertionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .accessibilityPermissionDenied: return "需要無障礙功能權限"
        case .noFocusedElement:              return "找不到焦點輸入欄位"
        case .insertionFailed(let msg):      return "文字注入失敗: \(msg)"
        }
    }
}

#if os(macOS)
import AppKit
import ApplicationServices

// MARK: - macOS Text Injector
/// 仿 Typeless libInputHelper.dylib 的文字注入邏輯。
/// 策略: 優先用 AX API 直接插入; 失敗時用剪貼簿備份→模擬 Cmd+V→還原剪貼簿。
public final class MacOSTextInjector: TextInjectorProtocol {
    public init() {}

    public func insertText(_ text: String) async throws {
        let success = await tryAXInsertion(text: text)
        if !success {
            try await clipboardInsertion(text: text)
        }
    }

    public func replaceSelectedText(with text: String) async throws {
        // 先用 AX 選取文字刪除，再插入新文字
        let success = await tryAXReplacement(text: text)
        if !success {
            try await clipboardInsertion(text: text)
        }
    }

    public func deleteBackward(count: Int) async throws {
        await Task.detached(priority: .userInitiated) {
            self.simulateBackspace(count: count)
        }.value
    }

    // MARK: - AX Direct Insertion

    private func tryAXInsertion(text: String) async -> Bool {
        return await Task.detached(priority: .userInitiated) {
            guard let frontApp = NSWorkspace.shared.frontmostApplication else { return false }
            let appRef = AXUIElementCreateApplication(frontApp.processIdentifier)
            var focusedElement: AnyObject?
            guard AXUIElementCopyAttributeValue(
                appRef, kAXFocusedUIElementAttribute as CFString, &focusedElement
            ) == .success else { return false }

            let axEl = focusedElement as! AXUIElement
            let result = AXUIElementSetAttributeValue(
                axEl, kAXSelectedTextAttribute as CFString, text as CFString
            )
            return result == .success
        }.value
    }

    private func tryAXReplacement(text: String) async -> Bool {
        return await tryAXInsertion(text: text)
    }

    // MARK: - Clipboard Insertion (fallback)
    /// Typeless 的 savePasteboard → simulatePaste → restorePasteboard 精確仿製。

    /// 使用 actor 序列化剪貼簿操作，避免快速連續注入時的競態
    private static let clipboardSerializer = ClipboardSerializer()

    private actor ClipboardSerializer {
        func run(_ block: @Sendable () async throws -> Void) async rethrows {
            try await block()
        }
    }

    private func clipboardInsertion(text: String) async throws {
        try await Self.clipboardSerializer.run { [self] in
            let savedItems = self.savePasteboard()

            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)

            await self.simulatePaste()

            // 等待貼上完成後還原剪貼簿
            try? await Task.sleep(nanoseconds: 200_000_000)  // 等 0.2s
            self.restorePasteboard(savedItems)
        }
    }

    private func savePasteboard() -> [(type: NSPasteboard.PasteboardType, data: Data)] {
        var saved: [(type: NSPasteboard.PasteboardType, data: Data)] = []
        for item in NSPasteboard.general.pasteboardItems ?? [] {
            for type in item.types {
                if let data = item.data(forType: type) {
                    saved.append((type: type, data: data))
                }
            }
        }
        return saved
    }

    private func restorePasteboard(_ items: [(type: NSPasteboard.PasteboardType, data: Data)]) {
        NSPasteboard.general.clearContents()
        let pbItem = NSPasteboardItem()
        for item in items {
            pbItem.setData(item.data, forType: item.type)
        }
        NSPasteboard.general.writeObjects([pbItem])
    }

    private func simulatePaste() async {
        await Task.detached(priority: .userInitiated) {
            let src = CGEventSource(stateID: .hidSystemState)
            // Cmd+V keydown
            let vDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
            vDown?.flags = .maskCommand
            vDown?.post(tap: .cgAnnotatedSessionEventTap)
            // Cmd+V keyup
            let vUp = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
            vUp?.flags = .maskCommand
            vUp?.post(tap: .cgAnnotatedSessionEventTap)
        }.value
        try? await Task.sleep(nanoseconds: 100_000_000)  // 等 0.1s
    }

    private func simulateBackspace(count: Int) {
        let src = CGEventSource(stateID: .hidSystemState)
        for _ in 0..<count {
            let bsDown = CGEvent(keyboardEventSource: src, virtualKey: 0x33, keyDown: true)
            bsDown?.post(tap: .cgAnnotatedSessionEventTap)
            let bsUp = CGEvent(keyboardEventSource: src, virtualKey: 0x33, keyDown: false)
            bsUp?.post(tap: .cgAnnotatedSessionEventTap)
        }
    }
}

#endif
