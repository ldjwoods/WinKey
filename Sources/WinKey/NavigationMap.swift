import Foundation
import CoreGraphics

/// 导航类映射：把 Windows 的光标/窗口行为翻译成 macOS 组合键。
///
/// 与 `KeyMap` 的 Ctrl→Cmd 不同，这类映射需要**改变按下的键**，
/// 而不只是换修饰键。因此用「合成新键 + 吞掉原事件」的方式实现。
///
/// 例如：Windows 的 Home 是「行首」，macOS 的 Home 是「文稿开头」，
/// 而 macOS 的「行首」是 Cmd+←。所以 Home 要转成 Cmd+←。
struct NavigationRule {
    /// 触发键的虚拟键码。
    let triggerKeyCode: CGKeyCode
    /// 目标键的虚拟键码。
    let targetKeyCode: CGKeyCode
    /// 目标事件需要带的修饰键。
    let targetFlags: CGEventFlags
    /// 本地化文案的 key。
    let labelKey: String
    /// 触发时是否要求按住 Ctrl（Windows 的 Ctrl+方向键 = 按词移动）。
    let requiresControl: Bool
    /// 是否默认启用。
    let defaultEnabled: Bool
}

enum NavigationMap {
    // macOS 上的方向键与 Home/End 键码
    private static let left: CGKeyCode = 0x7B       // kVK_LeftArrow
    private static let right: CGKeyCode = 0x7C      // kVK_RightArrow
    private static let up: CGKeyCode = 0x7E         // kVK_UpArrow
    private static let down: CGKeyCode = 0x7D       // kVK_DownArrow
    private static let home: CGKeyCode = 0x73       // kVK_Home
    private static let end: CGKeyCode = 0x77        // kVK_End
    private static let pageUp: CGKeyCode = 0x74     // kVK_PageUp
    private static let pageDown: CGKeyCode = 0x79   // kVK_PageDown
    private static let forwardDelete: CGKeyCode = 0x75 // kVK_ForwardDelete

    static let rules: [NavigationRule] = [
        // Home / End：macOS 上是「文稿首尾」，Windows 上是「行首行尾」。
        // 转成 Cmd+← / Cmd+→ 才是 macOS 的「行首行尾」。
        NavigationRule(
            triggerKeyCode: home, targetKeyCode: left, targetFlags: [.maskCommand],
            labelKey: "nav.line_start", requiresControl: false, defaultEnabled: true
        ),
        NavigationRule(
            triggerKeyCode: end, targetKeyCode: right, targetFlags: [.maskCommand],
            labelKey: "nav.line_end", requiresControl: false, defaultEnabled: true
        ),

        // Ctrl+Home / Ctrl+End：Windows 上是「文稿首尾」。
        // macOS 上 Cmd+↑ / Cmd+↓ 正是文稿首尾。
        NavigationRule(
            triggerKeyCode: home, targetKeyCode: up, targetFlags: [.maskCommand],
            labelKey: "nav.doc_start", requiresControl: true, defaultEnabled: true
        ),
        NavigationRule(
            triggerKeyCode: end, targetKeyCode: down, targetFlags: [.maskCommand],
            labelKey: "nav.doc_end", requiresControl: true, defaultEnabled: true
        ),

        // Ctrl+← / Ctrl+→：Windows 上按词移动。
        // macOS 上 Option+← / Option+→ 是按词移动。
        NavigationRule(
            triggerKeyCode: left, targetKeyCode: left, targetFlags: [.maskAlternate],
            labelKey: "nav.word_left", requiresControl: true, defaultEnabled: true
        ),
        NavigationRule(
            triggerKeyCode: right, targetKeyCode: right, targetFlags: [.maskAlternate],
            labelKey: "nav.word_right", requiresControl: true, defaultEnabled: true
        ),
    ]

    /// 组合键的唯一标识：同一个 triggerKeyCode 可能对应多条规则，
    /// 靠 requiresControl 区分（Home 与 Ctrl+Home）。
    static func ruleID(triggerKeyCode: CGKeyCode, requiresControl: Bool) -> String {
        "\(triggerKeyCode)-\(requiresControl ? "ctrl" : "plain")"
    }
}
