import Foundation
import CoreGraphics
import AppKit

/// 全局键盘拦截与改写引擎。
///
/// 工作方式：在 `.cgSessionEventTap` 上挂一个事件监听，拿到每一个按键事件后
/// 决定「原样放行」还是「改写修饰键后放行」。使用 callback（而非 default）tap，
/// 是因为只有 callback 类型能修改并吞掉事件。
final class KeyInterceptor {
    /// CGEventTap 的回调是 C 函数指针，需要一个全局引用回到 Swift 实例。
    /// 这里用静态存储保证生命周期与 tap 一致。
    private static var shared: KeyInterceptor?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// 记录被改写的 keyCode，用于排查。
    private var rewrittenKeyCodes = Set<CGKeyCode>()

    /// 累计改写次数。用于验证工具与用户确认拦截是否真的在工作。
    private(set) var rewriteCount = 0
    /// 导航类改写次数（Home/End 等）。
    private(set) var navigationRewriteCount = 0
    /// 因命中黑名单而放行的次数。
    private(set) var bypassCount = 0

    /// 状态变化回调，供 UI 刷新。
    var onStateChange: ((Bool) -> Void)?

    private(set) var isRunning = false

    // MARK: - 生命周期

    init() {
        KeyInterceptor.shared = self
    }

    /// 启动拦截。返回是否成功——失败通常意味着缺少辅助功能权限。
    @discardableResult
    func start() -> Bool {
        guard !isRunning else { return true }

        // 同时监听按下与抬起：只改按下会让抬起事件带着旧修饰键，导致
        // 某些应用出现「按键卡住」的错觉。
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        // 用 Unmanaged 传递 self 指针给 C 回调。
        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { proxy, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let interceptor = Unmanaged<KeyInterceptor>.fromOpaque(userInfo).takeUnretainedValue()
                return interceptor.handle(proxy: proxy, type: type, event: event)
            },
            userInfo: userInfo
        ) else {
            Log.write("[WinKey] 无法创建事件监听，请检查辅助功能权限。")
            return false
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        isRunning = true
        Log.write("[WinKey] 键盘拦截已启动。")
        return true
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        isRunning = false
        Log.write("[WinKey] 键盘拦截已停止。")
    }

    /// 权限被撤销或系统休眠后 tap 会被禁用，需要重新启用。
    func reenable() {
        guard let tap = eventTap else {
            _ = start()
            return
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        Log.write("[WinKey] 事件监听已重新启用。")
    }

    // MARK: - 核心改写逻辑

    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // 系统的 tap 可能因为超时被自动禁用，收到这个信号时立刻恢复。
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            reenable()
            return Unmanaged.passUnretained(event)
        }

        guard Settings.shared.isEnabled else {
            return Unmanaged.passUnretained(event)
        }

        // 黑名单应用（终端等）内完全放行，保留 macOS 原生行为。
        if AppFilter.shared.shouldBypassCurrentApp() {
            bypassCount += 1
            // 首次命中时记一条日志，方便确认黑名单真的在生效。
            if bypassCount == 1 {
                Log.write("[WinKey] 当前应用在黑名单中，放行按键: \(AppFilter.shared.frontmostBundleID() ?? "?")")
            }
            return Unmanaged.passUnretained(event)
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        // Alt+Tab → Cmd+Tab。
        // 必须在 flagsChanged 的类型判断【之前】处理：Alt 的按下/抬起本身就是
        // flagsChanged 事件，若先被下面的 guard 挡掉，就跟踪不到 Alt 状态了。
        if Settings.shared.isWindowSwitchEnabled {
            let action = handleWindowSwitch(event: event, type: type, keyCode: keyCode, flags: flags)
            switch action {
            case .rewrote:
                return Unmanaged.passUnretained(event)
            case .observed:
                return Unmanaged.passUnretained(event)
            case .notMine:
                break   // 继续走后面的映射逻辑
            }
        }

        // flagsChanged 事件用于同步修饰键状态，直接放行。
        guard type == .keyDown || type == .keyUp else {
            return Unmanaged.passUnretained(event)
        }

        if tryTranslateCtrlToCmd(event: event, keyCode: keyCode, flags: flags) {
            // 只在按下时计数，否则一次 Ctrl+C 会被记成 2 次（按下+抬起）。
            if type == .keyDown { noteRewrite(keyCode, from: "Ctrl", to: "Cmd") }
            return Unmanaged.passUnretained(event)
        }

        if Settings.shared.isReverseMappingEnabled,
           tryTranslateCmdToCtrl(event: event, keyCode: keyCode, flags: flags) {
            if type == .keyDown { noteRewrite(keyCode, from: "Cmd", to: "Ctrl") }
            return Unmanaged.passUnretained(event)
        }

        // 导航类映射（Home/End、Ctrl+方向键）
        if tryTranslateNavigation(event: event, type: type, keyCode: keyCode, flags: flags) {
            return Unmanaged.passUnretained(event)
        }

        return Unmanaged.passUnretained(event)
    }

    /// 导航键改写。
    ///
    /// 与修饰键改写不同，这里要**换掉按下的键本身**（Home → Cmd+←），
    /// 做法是就地修改 keyCode 字段与 flags，而不是合成新事件 ——
    /// 就地改写能保留原事件的时间戳与来源，兼容性更好，也不会产生事件顺序问题。
    private func tryTranslateNavigation(
        event: CGEvent,
        type: CGEventType,
        keyCode: CGKeyCode,
        flags: CGEventFlags
    ) -> Bool {
        let hasCtrl = flags.contains(.maskControl)
        let hasCmd = flags.contains(.maskCommand)
        let hasAlt = flags.contains(.maskAlternate)

        for rule in NavigationMap.rules {
            guard rule.triggerKeyCode == keyCode else { continue }
            guard Settings.shared.isNavigationRuleEnabled(rule) else { continue }

            if rule.requiresControl {
                // 需要 Ctrl 参与的规则：必须按着 Ctrl，且不能同时按 Cmd/Alt 以免抢系统快捷键。
                guard hasCtrl, !hasCmd, !hasAlt else { continue }
            } else {
                // 裸键规则（Home/End 单独按）：不能带任何修饰键，
                // 否则 Cmd+Home、Shift+Home 等其他组合会被误伤。
                guard !hasCtrl, !hasCmd, !hasAlt else { continue }
            }

            // 组装目标修饰键：保留 Shift（让 Shift+Home 能选中到行首），
            // 保留 Ctrl 之外的原始状态。
            var newFlags = flags
            newFlags.remove(.maskControl)
            newFlags.remove(.maskAlternate)
            newFlags.remove(.maskCommand)
            newFlags.formUnion(rule.targetFlags)

            event.flags = newFlags
            event.setIntegerValueField(.keyboardEventKeycode, value: Int64(rule.targetKeyCode))

            if type == .keyDown {
                navigationRewriteCount += 1
                if navigationRewriteCount <= 15 {
                    let fromName = "0x\(String(keyCode, radix: 16))"
                    let toName = "0x\(String(rule.targetKeyCode, radix: 16))"
                    Log.write("[WinKey] 导航改写 #\(navigationRewriteCount): \(fromName) → \(toName) flags=\(newFlags.rawValue)")
                }
            }
            return true
        }
        return false
    }

    /// Alt+Tab 处理的结果，决定事件后续怎么走。
    enum WindowSwitchAction {
        /// 已改写成 Cmd+Tab，直接放行。
        case rewrote
        /// 只是观察到了 Alt 状态变化，放行并跳过后续映射。
        case observed
        /// 与 Alt+Tab 无关，交给后面的映射逻辑继续处理。
        case notMine
    }

    /// Alt+Tab → Cmd+Tab。
    ///
    /// 为什么不能只改 Tab 事件的 flags：
    /// macOS 的 Cmd+Tab 由 Dock 的切换器实现，它跟踪的是**修饰键状态**。
    /// 若只把 Tab 改成带 Cmd，切换器会收到一个「凭空的 Cmd」，通常表现为
    /// 切换器闪一下就消失。
    ///
    /// 实测要点（用探针抓过真实事件序列）：
    /// 按下 Alt 时系统发出的是 `flagsChanged`，而它的 **keyCode 是 0x0**，
    /// 不是 kVK_Option(0x3A)。所以不能靠 keyCode 判断 Alt，
    /// 必须看 `flags.contains(.maskAlternate)`。
    ///
    /// 实测序列: FLAGS(alt=true, kc=0x0) → KEYDN(kc=0x30 Tab, alt=true) → FLAGS(alt=false)
    private func handleWindowSwitch(
        event: CGEvent,
        type: CGEventType,
        keyCode: CGKeyCode,
        flags: CGEventFlags
    ) -> WindowSwitchAction {
        let altDown = flags.contains(.maskAlternate)
        let cmdDown = flags.contains(.maskCommand)
        let ctrlDown = flags.contains(.maskControl)
        let isTab = (keyCode == WindowSwitch.tabKeyCode)

        // Alt 单独按下（尚未与 Tab 组合）：记住状态。
        // 不在这里把 Alt 转成 Cmd —— Option 在 macOS 上用途很多
        // （输入特殊字符、Option+拖拽），改了会破坏它们。
        if altDown && !cmdDown && !isTab {
            altTabActive = true
            // 纯修饰键变化不参与后续映射，直接放行。
            return type == .flagsChanged ? .observed : .notMine
        }

        // Alt 抬起：复位。
        if !altDown && altTabActive && !isTab {
            altTabActive = false
            return type == .flagsChanged ? .observed : .notMine
        }

        // 真正的 Alt+Tab：Tab 事件带 Alt，或此前已记录 Alt 按下。
        guard isTab, altTabActive || altDown else { return .notMine }
        // Ctrl 也按着时不动，别抢 Ctrl+Alt+Tab 之类的组合。
        guard !ctrlDown else { return .notMine }

        var newFlags = flags
        newFlags.remove(.maskAlternate)
        newFlags.insert(.maskCommand)
        event.flags = newFlags

        if type == .keyDown {
            navigationRewriteCount += 1
            Log.write("[WinKey] Alt+Tab → Cmd+Tab（累计 \(navigationRewriteCount) 次）")
        }
        return .rewrote
    }

    /// Alt 是否处于按下状态（用于 Alt+Tab 交互跟踪）。
    private var altTabActive = false

    /// 记录改写并打印确认日志。前若干次逐条打，避免日志被刷爆。
    private func noteRewrite(_ keyCode: CGKeyCode, from: String, to: String) {
        rewriteCount += 1
        guard rewriteCount <= 20 else { return }
        let name = KeyMap.rulesByKeyCode[keyCode]?.name ?? "0x\(String(keyCode, radix: 16))"
        Log.write("[WinKey] 改写 #\(rewriteCount): \(from)+\(name) → \(to)+\(name)  [累计 \(rewriteCount) 次]")
    }

    /// Ctrl+<key> -> Cmd+<key>
    ///
    /// 匹配条件：必须是 Ctrl 按下，且没有 Cmd / Alt 同时按下（排除 Fn 相关位）。
    /// Shift 允许参与，这样 Ctrl+Shift+Z（重做）也能被正确翻译。
    private func tryTranslateCtrlToCmd(
        event: CGEvent,
        keyCode: CGKeyCode,
        flags: CGEventFlags
    ) -> Bool {
        guard flags.contains(.maskControl) else { return false }

        // 已经带 Cmd 或 Alt 的组合交给系统处理，例如用户本来就按了 Cmd+Ctrl+Q。
        guard !flags.contains(.maskCommand) else { return false }
        guard !flags.contains(.maskAlternate) else { return false }

        guard Settings.shared.isRuleEnabled(keyCode) else { return false }

        var newFlags = flags
        newFlags.remove(.maskControl)
        newFlags.insert(.maskCommand)
        event.flags = newFlags

        rewrittenKeyCodes.insert(keyCode)
        return true
    }

    /// Cmd+<key> -> Ctrl+<key>（可选的反向映射）
    private func tryTranslateCmdToCtrl(
        event: CGEvent,
        keyCode: CGKeyCode,
        flags: CGEventFlags
    ) -> Bool {
        guard flags.contains(.maskCommand) else { return false }
        guard !flags.contains(.maskControl) else { return false }
        guard !flags.contains(.maskAlternate) else { return false }
        guard Settings.shared.isRuleEnabled(keyCode) else { return false }

        var newFlags = flags
        newFlags.remove(.maskCommand)
        newFlags.insert(.maskControl)
        event.flags = newFlags

        rewrittenKeyCodes.insert(keyCode)
        return true
    }
}
