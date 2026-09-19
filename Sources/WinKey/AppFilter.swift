import AppKit
import Foundation

/// 应用黑名单：命中的前台应用里，WinKey 不介入，保留 macOS 原生行为。
///
/// 典型场景是终端类应用——在终端里 Ctrl+C 是发送 SIGINT 中断信号，
/// 如果被翻译成 Cmd+C，终端就没法正常中断进程了。
final class AppFilter {
    static let shared = AppFilter()

    /// 已知的终端类应用 bundle ID。用 bundle ID 而非应用名，避免改名失效。
    static let knownTerminals: [(bundleID: String, name: String)] = [
        ("com.apple.Terminal", "终端"),
        ("com.googlecode.iterm2", "iTerm2"),
        ("dev.warp.Warp-Stable", "Warp"),
        ("com.microsoft.VSCode", "VS Code"),
        ("com.microsoft.VSCodeInsiders", "VS Code Insiders"),
        ("com.vscodium", "VSCodium"),
        ("co.zeit.hyper", "Hyper"),
        ("com.github.wez.wezterm", "WezTerm"),
        ("net.kovidgoyal.kitty", "kitty"),
        ("org.alacritty", "Alacritty"),
        ("com.jetbrains.intellij", "IntelliJ IDEA"),
        ("com.jetbrains.pycharm", "PyCharm"),
        ("com.jetbrains.goland", "GoLand"),
        ("com.jetbrains.WebStorm", "WebStorm"),
        ("com.apple.dt.Xcode", "Xcode"),
        ("com.termius.mac", "Termius"),
        ("com.panic.Transmit", "Transmit"),
        ("com.eltima.ForkLift", "ForkLift"),
        ("ru.keepcoder.Telegram", "Telegram"),
        ("com.tinyspeck.slackmacgap", "Slack"),
        ("com.hnc.Discord", "Discord"),
        ("com.tencent.xinWeChat", "微信"),
        ("com.tencent.qq", "QQ"),
    ]

    private enum Keys {
        static let excludedIDs = "excludedBundleIDs"
        static let filterEnabled = "appFilterEnabled"
    }

    private let defaults = UserDefaults.standard

    /// 前台应用的缓存。CGEventTap 回调在每次按键时触发，
    /// 每次都查 NSWorkspace 会明显增加延迟，因此缓存并在应用切换时刷新。
    private var cachedBundleID: String?
    private var cachedAt: Date = .distantPast
    private let cacheTTL: TimeInterval = 0.3
    private let lock = NSLock()

    private init() {
        if defaults.object(forKey: Keys.filterEnabled) == nil {
            defaults.set(true, forKey: Keys.filterEnabled)
        }
        if defaults.object(forKey: Keys.excludedIDs) == nil {
            // 默认排除已知终端，避免开箱就破坏终端使用
            defaults.set(Self.knownTerminals.map(\.bundleID), forKey: Keys.excludedIDs)
        }
    }

    var isFilterEnabled: Bool {
        get { defaults.bool(forKey: Keys.filterEnabled) }
        set { defaults.set(newValue, forKey: Keys.filterEnabled) }
    }

    var excludedBundleIDs: Set<String> {
        get {
            guard let raw = defaults.array(forKey: Keys.excludedIDs) as? [String] else {
                return Set(Self.knownTerminals.map(\.bundleID))
            }
            return Set(raw)
        }
        set {
            defaults.set(Array(newValue).sorted(), forKey: Keys.excludedIDs)
        }
    }

    func isExcluded(_ bundleID: String) -> Bool {
        excludedBundleIDs.contains(bundleID)
    }

    func setExcluded(_ bundleID: String, excluded: Bool) {
        var current = excludedBundleIDs
        if excluded {
            current.insert(bundleID)
        } else {
            current.remove(bundleID)
        }
        excludedBundleIDs = current
    }

    /// 当前前台应用的 bundle ID（带短时缓存）。
    func frontmostBundleID() -> String? {
        lock.lock()
        defer { lock.unlock() }

        let now = Date()
        if now.timeIntervalSince(cachedAt) < cacheTTL {
            return cachedBundleID
        }

        // frontmostApplication 需要在主线程之外也安全读取，
        // NSWorkspace 的这个属性本身是线程安全的。
        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        cachedBundleID = bundleID
        cachedAt = now
        return bundleID
    }

    /// 判断当前是否应当让按键透传给系统（即被排除）。
    func shouldBypassCurrentApp() -> Bool {
        guard isFilterEnabled else { return false }
        guard let bundleID = frontmostBundleID() else { return false }
        return isExcluded(bundleID)
    }

    /// 强制刷新缓存——应用切换通知到达时调用。
    func invalidateCache() {
        lock.lock()
        cachedAt = .distantPast
        lock.unlock()
    }
}
