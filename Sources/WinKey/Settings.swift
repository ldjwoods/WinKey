import Foundation
import CoreGraphics

/// 用户可持久化的偏好设置。用 UserDefaults 存，零依赖。
final class Settings {
    static let shared = Settings()

    private enum Keys {
        static let enabled = "globalEnabled"
        static let enabledKeyCodes = "enabledKeyCodes"
        static let reverseCmdToCtrl = "reverseCmdToCtrl"
        static let enabledNavigation = "enabledNavigationRules"
        static let windowSwitch = "windowSwitchEnabled"
        static let minimizeHotKey = "minimizeHotKeyEnabled"
        static let clickToMinimize = "clickToMinimizeEnabled"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // 首次启动时写入默认值，避免 object(forKey:) 为 nil 时把功能判成关闭。
        if defaults.object(forKey: Keys.enabled) == nil {
            defaults.set(true, forKey: Keys.enabled)
        }
        if defaults.object(forKey: Keys.enabledKeyCodes) == nil {
            defaults.set(KeyMap.defaultEnabledKeyCodes.map(Int.init), forKey: Keys.enabledKeyCodes)
        }
        if defaults.object(forKey: Keys.enabledNavigation) == nil {
            let ids = NavigationMap.rules
                .filter(\.defaultEnabled)
                .map { NavigationMap.ruleID(triggerKeyCode: $0.triggerKeyCode,
                                            requiresControl: $0.requiresControl) }
            defaults.set(ids, forKey: Keys.enabledNavigation)
        }
    }

    /// 总开关。
    var isEnabled: Bool {
        get { defaults.bool(forKey: Keys.enabled) }
        set { defaults.set(newValue, forKey: Keys.enabled) }
    }

    /// 当前启用的单个映射。
    var enabledKeyCodes: Set<CGKeyCode> {
        get {
            guard let raw = defaults.array(forKey: Keys.enabledKeyCodes) as? [Int] else {
                return KeyMap.defaultEnabledKeyCodes
            }
            return Set(raw.map { CGKeyCode($0) })
        }
        set {
            defaults.set(newValue.map(Int.init).sorted(), forKey: Keys.enabledKeyCodes)
        }
    }

    /// 反向映射：把 Cmd+<key> 翻译成 Ctrl+<key>。
    /// 默认关闭——它会让 Mac 原生快捷键失效，只有深度 Windows 用户才需要。
    var isReverseMappingEnabled: Bool {
        get { defaults.bool(forKey: Keys.reverseCmdToCtrl) }
        set { defaults.set(newValue, forKey: Keys.reverseCmdToCtrl) }
    }

    func isRuleEnabled(_ keyCode: CGKeyCode) -> Bool {
        enabledKeyCodes.contains(keyCode)
    }

    func setRule(_ keyCode: CGKeyCode, enabled: Bool) {
        var current = enabledKeyCodes
        if enabled {
            current.insert(keyCode)
        } else {
            current.remove(keyCode)
        }
        enabledKeyCodes = current
    }

    // MARK: - 导航类映射（Home/End、Ctrl+方向键）

    /// 已启用的导航规则 ID 集合。
    var enabledNavigationRuleIDs: Set<String> {
        get {
            guard let raw = defaults.array(forKey: Keys.enabledNavigation) as? [String] else {
                return Set(NavigationMap.rules
                    .filter(\.defaultEnabled)
                    .map { NavigationMap.ruleID(triggerKeyCode: $0.triggerKeyCode,
                                                requiresControl: $0.requiresControl) })
            }
            return Set(raw)
        }
        set {
            defaults.set(Array(newValue).sorted(), forKey: Keys.enabledNavigation)
        }
    }

    func isNavigationRuleEnabled(_ rule: NavigationRule) -> Bool {
        enabledNavigationRuleIDs.contains(
            NavigationMap.ruleID(triggerKeyCode: rule.triggerKeyCode,
                                 requiresControl: rule.requiresControl)
        )
    }

    func setNavigationRule(_ rule: NavigationRule, enabled: Bool) {
        let id = NavigationMap.ruleID(triggerKeyCode: rule.triggerKeyCode,
                                      requiresControl: rule.requiresControl)
        var current = enabledNavigationRuleIDs
        if enabled {
            current.insert(id)
        } else {
            current.remove(id)
        }
        enabledNavigationRuleIDs = current
    }

    // MARK: - 窗口切换

    /// Alt+Tab → Cmd+Tab。默认开启，这是 Windows 用户肌肉记忆最强的一条。
    var isWindowSwitchEnabled: Bool {
        get {
            if defaults.object(forKey: Keys.windowSwitch) == nil { return true }
            return defaults.bool(forKey: Keys.windowSwitch)
        }
        set { defaults.set(newValue, forKey: Keys.windowSwitch) }
    }

    // MARK: - 最小化前台应用

    /// 全局快捷键 Ctrl+M 最小化前台应用。默认开启。
    var isMinimizeHotKeyEnabled: Bool {
        get {
            if defaults.object(forKey: Keys.minimizeHotKey) == nil { return true }
            return defaults.bool(forKey: Keys.minimizeHotKey)
        }
        set { defaults.set(newValue, forKey: Keys.minimizeHotKey) }
    }

    /// 点菜单栏图标时最小化前台应用。
    /// 默认关闭 —— 它改变菜单栏图标的默认行为（原本是弹菜单），应由用户主动开启。
    var isClickToMinimizeEnabled: Bool {
        get { defaults.bool(forKey: Keys.clickToMinimize) }
        set { defaults.set(newValue, forKey: Keys.clickToMinimize) }
    }
}
