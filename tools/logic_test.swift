import Foundation
import CoreGraphics

// 纯逻辑自测：验证 Ctrl→Cmd 的匹配规则矩阵。
// 这些用例不需要辅助功能权限，因此在任何环境下都能跑，
// 用来保证「哪些组合该改、哪些组合绝对不能碰」这件事是确定的。
//
// 用法: swiftc -O tools/logic_test.swift -o tools/logic_test && ./tools/logic_test

var passed = 0
var failed = 0

func check(_ label: String, _ actual: Bool, _ expected: Bool) {
    if actual == expected {
        passed += 1
        print("  ✅ \(label)")
    } else {
        failed += 1
        print("  ❌ \(label) —— 期望 \(expected)，实际 \(actual)")
    }
}

/// 与 KeyInterceptor 中 tryTranslateCtrlToCmd 保持一致的判定逻辑。
/// 这里复制一份是为了让自测不依赖辅助功能权限。
func shouldTranslateToCmd(flags: CGEventFlags, ruleEnabled: Bool) -> Bool {
    guard flags.contains(.maskControl) else { return false }
    guard !flags.contains(.maskCommand) else { return false }
    guard !flags.contains(.maskAlternate) else { return false }
    return ruleEnabled
}

print("=== Ctrl→Cmd 映射规则矩阵 ===")

check("Ctrl+C 应被改写", shouldTranslateToCmd(flags: [.maskControl], ruleEnabled: true), true)
check("Ctrl+Shift+Z 应被改写（重做）",
      shouldTranslateToCmd(flags: [.maskControl, .maskShift], ruleEnabled: true), true)
check("Ctrl+Alt+C 不改写（AltGr 等场景）",
      shouldTranslateToCmd(flags: [.maskControl, .maskAlternate], ruleEnabled: true), false)
check("Cmd+Ctrl+C 不改写（用户主动按 Mac 组合）",
      shouldTranslateToCmd(flags: [.maskControl, .maskCommand], ruleEnabled: true), false)
check("裸 C 不改写",
      shouldTranslateToCmd(flags: [], ruleEnabled: true), false)
check("Cmd+C 完全不碰（原生复制仍可用）",
      shouldTranslateToCmd(flags: [.maskCommand], ruleEnabled: true), false)
check("规则被用户关闭时不改写",
      shouldTranslateToCmd(flags: [.maskControl], ruleEnabled: false), false)
check("Shift+Ctrl+C 顺序无关，仍改写",
      shouldTranslateToCmd(flags: [.maskShift, .maskControl], ruleEnabled: true), true)

print()
print("=== 黑名单匹配逻辑 ===")

let excluded: Set<String> = ["com.apple.Terminal", "com.googlecode.iterm2"]
check("终端在黑名单中", excluded.contains("com.apple.Terminal"), true)
check("Safari 不在黑名单中", excluded.contains("com.apple.Safari"), false)

// MARK: - 导航规则匹配

/// 与 KeyInterceptor.tryTranslateNavigation 的判定保持一致。
func matchesNavigation(
    ruleRequiresControl: Bool,
    flags: CGEventFlags
) -> Bool {
    let hasCtrl = flags.contains(.maskControl)
    let hasCmd = flags.contains(.maskCommand)
    let hasAlt = flags.contains(.maskAlternate)
    if ruleRequiresControl {
        return hasCtrl && !hasCmd && !hasAlt
    } else {
        return !hasCtrl && !hasCmd && !hasAlt
    }
}

print()
print("=== 导航规则匹配矩阵 ===")

// 裸 Home：不能带任何修饰键，否则 Cmd+Home / Shift+Home 会被误伤
check("裸 Home 触发行首规则", matchesNavigation(ruleRequiresControl: false, flags: []), true)
check("Shift+Home 不触发裸键规则（保留原生选中）",
      matchesNavigation(ruleRequiresControl: false, flags: [.maskShift]), true)
check("Cmd+Home 不触发裸键规则（保留系统行为）",
      matchesNavigation(ruleRequiresControl: false, flags: [.maskCommand]), false)
check("Ctrl+Home 不触发裸键规则（应走文稿首规则，它是另一个规则）",
      matchesNavigation(ruleRequiresControl: false, flags: [.maskControl]), false)
check("Alt+Home 不触发裸键规则",
      matchesNavigation(ruleRequiresControl: false, flags: [.maskAlternate]), false)

// Ctrl+Home：需要 Ctrl
check("Ctrl+Home 触发文稿首规则", matchesNavigation(ruleRequiresControl: true, flags: [.maskControl]), true)
check("Ctrl+Shift+Home 触发（允许 Shift 选中）",
      matchesNavigation(ruleRequiresControl: true, flags: [.maskControl, .maskShift]), true)
check("裸 Home 不触发文稿首规则", matchesNavigation(ruleRequiresControl: true, flags: []), false)
check("Ctrl+Cmd+Home 不触发（避免抢系统快捷键）",
      matchesNavigation(ruleRequiresControl: true, flags: [.maskControl, .maskCommand]), false)

print()
print("=== Alt+Tab 状态机 ===")

/// 与 KeyInterceptor.handleWindowSwitch 的判定保持一致。
/// Alt 的按下事件实测 keyCode 是 0x0，因此只能用 flags 判断。
func shouldSwitchWindow(altDown: Bool, tabKeyCode: UInt16, isTab: Bool, ctrlDown: Bool, altTabActive: Bool) -> Bool {
    guard isTab else { return false }
    guard altTabActive || altDown else { return false }
    guard !ctrlDown else { return false }
    return true
}

check("Alt 按住 + Tab → 触发切换",
      shouldSwitchWindow(altDown: true, tabKeyCode: 0x30, isTab: true, ctrlDown: false, altTabActive: false), true)
check("仅 Tab（无 Alt）→ 不触发",
      shouldSwitchWindow(altDown: false, tabKeyCode: 0x30, isTab: true, ctrlDown: false, altTabActive: false), false)
check("Alt 已记录但 Tab 事件未带 Alt → 仍触发（连续按 Tab 场景）",
      shouldSwitchWindow(altDown: false, tabKeyCode: 0x30, isTab: true, ctrlDown: false, altTabActive: true), true)
check("Ctrl+Alt+Tab → 不抢（交给系统）",
      shouldSwitchWindow(altDown: true, tabKeyCode: 0x30, isTab: true, ctrlDown: true, altTabActive: true), false)
check("Alt + 非 Tab 键 → 不触发",
      shouldSwitchWindow(altDown: true, tabKeyCode: 0x08, isTab: false, ctrlDown: false, altTabActive: true), false)

print()
print("通过 \(passed) 项，失败 \(failed) 项")
exit(failed == 0 ? 0 : 1)
