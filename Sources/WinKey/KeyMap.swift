import Foundation
import CoreGraphics

/// 一条映射规则：把 Windows 风格的 Ctrl+<key> 翻译成 macOS 的 Cmd+<key>。
///
/// 只允许 Ctrl + 单个「无修饰」字母键参与匹配，这样 Ctrl+Shift+C 之类的
/// 组合不会被误伤（例如终端里的 Ctrl+C 中断信号需要保留）。
struct KeyMapRule {
    /// 触发键的虚拟键码（ANSI 键盘布局下的物理位置）。
    let keyCode: CGKeyCode
    /// 人类可读的名字，仅用于日志和菜单展示。
    let name: String
    /// 该规则对应行为的本地化 key（见 Resources/*.lproj/Localizable.strings）。
    let behaviorKey: String
    /// 是否默认启用。
    let defaultEnabled: Bool
}

enum KeyMap {
    // 使用 kVK_ANSI_* 常量而非魔数，避免键盘布局差异带来的困惑。
    static let rules: [KeyMapRule] = [
        KeyMapRule(keyCode: 0x08, name: "C", behaviorKey: "beh.copy", defaultEnabled: true),   // kVK_ANSI_C
        KeyMapRule(keyCode: 0x09, name: "V", behaviorKey: "beh.paste", defaultEnabled: true),   // kVK_ANSI_V
        KeyMapRule(keyCode: 0x07, name: "X", behaviorKey: "beh.cut", defaultEnabled: true),   // kVK_ANSI_X
        KeyMapRule(keyCode: 0x00, name: "A", behaviorKey: "beh.select_all", defaultEnabled: true),   // kVK_ANSI_A
        KeyMapRule(keyCode: 0x06, name: "Z", behaviorKey: "beh.undo", defaultEnabled: true),   // kVK_ANSI_Z
        KeyMapRule(keyCode: 0x01, name: "S", behaviorKey: "beh.save", defaultEnabled: true),   // kVK_ANSI_S
        KeyMapRule(keyCode: 0x03, name: "F", behaviorKey: "beh.find", defaultEnabled: true),   // kVK_ANSI_F
        KeyMapRule(keyCode: 0x0C, name: "Q", behaviorKey: "beh.quit_app", defaultEnabled: false), // kVK_ANSI_Q
        KeyMapRule(keyCode: 0x0D, name: "W", behaviorKey: "beh.close", defaultEnabled: false), // kVK_ANSI_W
        KeyMapRule(keyCode: 0x0E, name: "E", behaviorKey: "beh.search", defaultEnabled: false), // kVK_ANSI_E
        KeyMapRule(keyCode: 0x05, name: "G", behaviorKey: "beh.find_next", defaultEnabled: false), // kVK_ANSI_G
        KeyMapRule(keyCode: 0x1F, name: "O", behaviorKey: "beh.open", defaultEnabled: false),   // kVK_ANSI_O
        KeyMapRule(keyCode: 0x11, name: "T", behaviorKey: "beh.new_tab", defaultEnabled: false), // kVK_ANSI_T
        KeyMapRule(keyCode: 0x20, name: "U", behaviorKey: "beh.underline", defaultEnabled: false),  // kVK_ANSI_U
        KeyMapRule(keyCode: 0x23, name: "P", behaviorKey: "beh.print", defaultEnabled: false),   // kVK_ANSI_P
        KeyMapRule(keyCode: 0x0B, name: "B", behaviorKey: "beh.bold", defaultEnabled: false),   // kVK_ANSI_B
        KeyMapRule(keyCode: 0x0F, name: "R", behaviorKey: "beh.refresh", defaultEnabled: false),   // kVK_ANSI_R
        KeyMapRule(keyCode: 0x25, name: "L", behaviorKey: "beh.address_bar", defaultEnabled: false), // kVK_ANSI_L
    ]

    /// keyCode -> 规则的快速查找表。
    static let rulesByKeyCode: [CGKeyCode: KeyMapRule] = {
        Dictionary(uniqueKeysWithValues: rules.map { ($0.keyCode, $0) })
    }()

    /// 默认启用的 keyCode 集合，交给 Settings 做初始状态。
    static var defaultEnabledKeyCodes: Set<CGKeyCode> {
        Set(rules.filter(\.defaultEnabled).map(\.keyCode))
    }
}
