import Foundation
import AppKit
import ApplicationServices

/// 辅助功能（Accessibility）权限的查询与申请。
///
/// macOS 对 CGEventTap 的键盘监听要求进程被授予「辅助功能」权限，
/// 否则 tapCreate 会直接失败或收到空事件。
enum Permission {
    /// 是否已获得辅助功能权限。
    static var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    /// 弹出系统授权引导。带 prompt 的检查会在未授权时自动弹出系统对话框。
    @discardableResult
    static func requestAccessibility() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// 直接打开「系统设置 > 隐私与安全性 > 辅助功能」面板，方便用户手动勾选。
    static func openAccessibilitySettings() {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
