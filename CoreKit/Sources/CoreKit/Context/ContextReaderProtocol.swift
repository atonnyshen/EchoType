import Foundation

// MARK: - Context Reader Protocol
/// 讀取焦點 App 的上下文資訊（游標文字、App 資訊、視窗標題等）。
/// macOS 使用 AX API，iOS 使用 textDocumentProxy。
public protocol ContextReaderProtocol: Sendable {
    /// 取得當前焦點 App 的完整上下文（非同步）
    func getFocusedContext() async -> AppContext?

    /// 取得游標前後的文字（最小 token 版本）
    func getSurroundingText(beforeChars: Int, afterChars: Int) async -> SurroundingText?
}

// MARK: - App Context (送到 AI 的上下文結構)
public struct AppContext: Sendable, Codable {
    public let appName: String?
    public let bundleId: String?
    public let windowTitle: String?
    public let webUrl: String?
    public let webDomain: String?
    public let webTitle: String?
    public let contextBefore: String?   // 游標前 ~200 字元
    public let contextAfter: String?    // 游標後 ~100 字元
    public let selectedText: String?    // 選取的文字（替換模式用）

    public init(
        appName: String? = nil,
        bundleId: String? = nil,
        windowTitle: String? = nil,
        webUrl: String? = nil,
        webDomain: String? = nil,
        webTitle: String? = nil,
        contextBefore: String? = nil,
        contextAfter: String? = nil,
        selectedText: String? = nil
    ) {
        self.appName = appName
        self.bundleId = bundleId
        self.windowTitle = windowTitle
        self.webUrl = webUrl
        self.webDomain = webDomain
        self.webTitle = webTitle
        self.contextBefore = contextBefore
        self.contextAfter = contextAfter
        self.selectedText = selectedText
    }

    /// Token 最小化：生成簡潔的上下文字串供 AI 使用
    /// 目標: ~300-500 token
    public func toMinimalPromptContext() -> String {
        var parts: [String] = []
        if let app = appName { parts.append("App: \(app)") }
        if let domain = webDomain { parts.append("網站: \(domain)") }
        if let title = windowTitle ?? webTitle { parts.append("標題: \(title)") }
        if let before = contextBefore, !before.isEmpty {
            let trimmed = String(before.suffix(200)) // 最多 200 字元
            parts.append("游標前文字: \"\(trimmed)\"")
        }
        if let after = contextAfter, !after.isEmpty {
            let trimmed = String(after.prefix(100)) // 最多 100 字元
            parts.append("游標後文字: \"\(trimmed)\"")
        }
        if let selected = selectedText, !selected.isEmpty {
            parts.append("選取文字: \"\(selected)\"")
        }
        return parts.joined(separator: "\n")
    }
}

// MARK: - Surrounding Text
public struct SurroundingText: Sendable {
    public let before: String
    public let after: String
    public let selected: String

    public init(before: String = "", after: String = "", selected: String = "") {
        self.before = before
        self.after = after
        self.selected = selected
    }
}
