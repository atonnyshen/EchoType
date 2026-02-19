import Foundation

#if os(macOS)
import AppKit
import ApplicationServices

// MARK: - macOS Context Reader
/// 使用 macOS Accessibility API (AXUIElement) 讀取焦點 App 的上下文。
/// 這是 Typeless 的核心機制的精確仿製 + 改良版本。
public final class MacOSContextReader: ContextReaderProtocol {
    public init() {}

    public func getFocusedContext() async -> AppContext? {
        return await Task.detached(priority: .userInitiated) {
            self.readFocusedContext()
        }.value
    }

    public func getSurroundingText(beforeChars: Int = 200, afterChars: Int = 100) async -> SurroundingText? {
        return await Task.detached(priority: .userInitiated) {
            self.readSurroundingText(beforeChars: beforeChars, afterChars: afterChars)
        }.value
    }

    // MARK: - Private Implementation

    private func readFocusedContext() -> AppContext? {
        // 1. 取得焦點 App
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        let appName = frontApp.localizedName
        let bundleId = frontApp.bundleIdentifier
        let pid = frontApp.processIdentifier

        // 2. 取得 AX 根元素
        let appRef = AXUIElementCreateApplication(pid)

        // 3. 取得視窗標題
        let windowTitle = getWindowTitle(appRef: appRef)

        // 4. 判斷是否為瀏覽器，取得 URL
        var webUrl: String? = nil
        var webDomain: String? = nil
        var webTitle: String? = nil
        if isBrowser(bundleId: bundleId) {
            (webUrl, webTitle) = getBrowserInfo(appRef: appRef)
            webDomain = extractDomain(from: webUrl)
        }

        // 5. 取得游標前後文字
        let surrounding = readSurroundingText(beforeChars: 200, afterChars: 100)
        let selectedText = getSelectedText(appRef: appRef)

        return AppContext(
            appName: appName,
            bundleId: bundleId,
            windowTitle: windowTitle,
            webUrl: webUrl,
            webDomain: webDomain,
            webTitle: webTitle,
            contextBefore: surrounding?.before,
            contextAfter: surrounding?.after,
            selectedText: selectedText
        )
    }

    private func readSurroundingText(beforeChars: Int, afterChars: Int) -> SurroundingText? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        let appRef = AXUIElementCreateApplication(frontApp.processIdentifier)

        // 取得焦點元素
        var focusedElement: AnyObject?
        let result = AXUIElementCopyAttributeValue(appRef, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        guard result == .success, let element = focusedElement else { return nil }

        let axEl = element as! AXUIElement

        // 取得游標前文字
        let before = getTextBefore(element: axEl, maxChars: beforeChars) ?? ""
        let after  = getTextAfter(element: axEl, maxChars: afterChars) ?? ""
        let selected = getSelectedTextFromElement(element: axEl) ?? ""

        return SurroundingText(before: before, after: after, selected: selected)
    }

    // MARK: - AX Helpers

    private func getWindowTitle(appRef: AXUIElement) -> String? {
        var windowList: AnyObject?
        guard AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowList) == .success,
              let windows = windowList as? [AXUIElement],
              let firstWindow = windows.first else { return nil }
        var title: AnyObject?
        guard AXUIElementCopyAttributeValue(firstWindow, kAXTitleAttribute as CFString, &title) == .success else { return nil }
        return title as? String
    }

    private func getTextBefore(element: AXUIElement, maxChars: Int) -> String? {
        // 利用 AXSelectedTextRange 取得游標位置
        var rangeValue: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success else { return nil }
        guard let cfRange = rangeValue, CFGetTypeID(cfRange as CFTypeRef) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        AXValueGetValue(cfRange as! AXValue, .cfRange, &range)

        let startIndex = max(0, range.location - maxChars)
        let length = range.location - startIndex
        guard length > 0 else { return nil }

        // 使用 AXStringForRange 取得文字
        var paramValue: AnyObject?
        var paramRange = CFRange(location: startIndex, length: length)
        let axRange = AXValueCreate(.cfRange, &paramRange)!
        let result = AXUIElementCopyParameterizedAttributeValue(
            element, kAXStringForRangeParameterizedAttribute as CFString, axRange, &paramValue
        )
        guard result == .success else { return nil }
        return paramValue as? String
    }

    private func getTextAfter(element: AXUIElement, maxChars: Int) -> String? {
        var rangeValue: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success else { return nil }
        guard let cfRange = rangeValue, CFGetTypeID(cfRange as CFTypeRef) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        AXValueGetValue(cfRange as! AXValue, .cfRange, &range)

        let startIndex = range.location + range.length
        let length = maxChars

        var paramValue: AnyObject?
        var paramRange = CFRange(location: startIndex, length: length)
        let axRange = AXValueCreate(.cfRange, &paramRange)!
        let result = AXUIElementCopyParameterizedAttributeValue(
            element, kAXStringForRangeParameterizedAttribute as CFString, axRange, &paramValue
        )
        guard result == .success else { return nil }
        return paramValue as? String
    }

    private func getSelectedText(appRef: AXUIElement) -> String? {
        var focusedElement: AnyObject?
        guard AXUIElementCopyAttributeValue(appRef, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success,
              let element = focusedElement else { return nil }
        return getSelectedTextFromElement(element: element as! AXUIElement)
    }

    private func getSelectedTextFromElement(element: AXUIElement) -> String? {
        var selectedText: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedText) == .success else { return nil }
        return selectedText as? String
    }

    // MARK: - Browser Detection

    private let browserBundleIds: Set<String> = [
        "com.apple.Safari",
        "com.google.Chrome",
        "org.mozilla.firefox",
        "com.microsoft.edgemac",
        "com.operasoftware.Opera",
        "com.google.Chrome.beta",
        "com.brave.Browser"
    ]

    private func isBrowser(bundleId: String?) -> Bool {
        guard let bundleId else { return false }
        return browserBundleIds.contains(bundleId)
    }

    private func getBrowserInfo(appRef: AXUIElement) -> (url: String?, title: String?) {
        // 嘗試讀取 URL 欄位 (Safari / Chrome 都有)
        var windowList: AnyObject?
        guard AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowList) == .success,
              let windows = windowList as? [AXUIElement],
              let firstWindow = windows.first else { return (nil, nil) }

        // 搜尋 URL 欄位（通常在 toolbar 的 text field 中）
        let url = findURLField(in: firstWindow)
        var title: AnyObject?
        AXUIElementCopyAttributeValue(firstWindow, kAXTitleAttribute as CFString, &title)
        return (url, title as? String)
    }

    private func findURLField(in element: AXUIElement, depth: Int = 0) -> String? {
        guard depth < 8 else { return nil }
        var roleValue: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        let role = roleValue as? String

        if role == "AXTextField" {
            var value: AnyObject?
            AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
            if let urlString = value as? String, urlString.hasPrefix("http") {
                return urlString
            }
        }

        var childrenValue: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let children = childrenValue as? [AXUIElement] else { return nil }

        for child in children {
            if let url = findURLField(in: child, depth: depth + 1) { return url }
        }
        return nil
    }

    private func extractDomain(from urlString: String?) -> String? {
        guard let urlString, let url = URL(string: urlString) else { return nil }
        return url.host
    }
}

#endif
