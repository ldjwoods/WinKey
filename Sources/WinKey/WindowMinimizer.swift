import AppKit
import ApplicationServices

/// 最小化当前前台应用的窗口。
///
/// 为什么不用 `NSRunningApplication.hide()`：
/// 那是 macOS 的「隐藏应用」(Cmd+H)，会让整个应用消失且不进入 Dock 右侧的
/// 最小化区域。Windows 的「最小化」对应的是窗口级操作，在 macOS 上应该走
/// Accessibility 的窗口最小化 —— 窗口会缩进 Dock，行为才对得上。
///
/// 实现方式的取舍（实测得出）：
/// 直觉做法是取 `AXMinimizeButton` 然后对它执行 `AXPress`，但在 macOS 26 上
/// 这个属性经常取不到 —— 属性名列在 `AXMinimizeButton`，读取却返回
/// `kAXErrorAttributeUnsupported(-25212)`，且窗口的 action 列表里只有 `AXRaise`。
/// 因此改为**直接写 `AXMinimized` 属性**，这是 AX 规定的标准可写属性，
/// 实测可稳定生效。
enum WindowMinimizer {

    /// 最小化前台应用当前聚焦的窗口。
    /// - Returns: 成功返回 true。
    @discardableResult
    static func minimizeFrontmost() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            Log.write("[WinKey] 最小化失败：拿不到前台应用")
            return false
        }

        // 不处理自己：WinKey 是菜单栏应用，没有可最小化的窗口。
        if app.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            return false
        }

        return minimize(pid: app.processIdentifier, appName: app.localizedName ?? "?")
    }

    /// 最小化指定进程的聚焦窗口；若拿不到聚焦窗口，就退而最小化它的任一可见窗口。
    @discardableResult
    static func minimize(pid: pid_t, appName: String) -> Bool {
        let appElement = AXUIElementCreateApplication(pid)

        // 优先取 focusedWindow；某些应用（如 Finder 无窗口时）会拿不到。
        var candidates: [AXUIElement] = []
        if let focused = copyElementAttribute(appElement, kAXFocusedWindowAttribute) {
            candidates.append(focused)
        }
        if let windows = copyArrayAttribute(appElement, kAXWindowsAttribute) {
            for w in windows where !candidates.contains(where: { CFEqual($0, w) }) {
                candidates.append(w)
            }
        }

        guard !candidates.isEmpty else {
            Log.write("[WinKey] 最小化失败：\(appName) 没有窗口")
            return false
        }

        // 已经全部最小化时，目标状态其实已达成，不算失败。
        let visible = candidates.filter { !isMinimized($0) }
        if visible.isEmpty {
            Log.write("[WinKey] \(appName) 的窗口已经是最小化状态")
            return true
        }

        for window in visible where setMinimized(window) {
            Log.write("[WinKey] 已最小化 \(appName) 的窗口")
            return true
        }

        Log.write("[WinKey] 最小化失败：\(appName) 的窗口都不接受最小化")
        return false
    }

    /// 直接设置 AXMinimized 属性（true = 最小化）。
    private static func setMinimized(_ window: AXUIElement) -> Bool {
        let result = AXUIElementSetAttributeValue(
            window,
            kAXMinimizedAttribute as CFString,
            kCFBooleanTrue
        )
        return result == .success
    }

    private static func isMinimized(_ window: AXUIElement) -> Bool {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            window, kAXMinimizedAttribute as CFString, &value
        )
        guard result == .success, let flag = value as? Bool else { return false }
        return flag
    }

    // MARK: - AX 取值辅助

    private static func copyElementAttribute(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success, let v = value else { return nil }
        guard CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    private static func copyArrayAttribute(_ element: AXUIElement, _ attribute: String) -> [AXUIElement]? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success, let array = value as? [AXUIElement] else { return nil }
        return array
    }
}
