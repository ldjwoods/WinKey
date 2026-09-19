import AppKit
import Carbon.HIToolbox

/// 菜单栏控制器：负责状态栏图标、下拉菜单与权限引导。
final class MenuBarController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let interceptor = KeyInterceptor()
    private var permissionTimer: Timer?
    private var minimizeHotKey: GlobalHotKey?

    // MARK: - 应用生命周期

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)  // 不出现在 Dock 里
        setupStatusItem()
        startInterceptorIfPossible()
        startPermissionWatch()
        observeAppSwitches()
        setupMinimizeHotKey()
    }

    /// 注册 Ctrl+M 全局快捷键。
    private func setupMinimizeHotKey() {
        let hotKey = GlobalHotKey { [weak self] in
            self?.minimizeFrontmostApp()
        }
        minimizeHotKey = hotKey
        applyHotKeyRegistration()
    }

    /// 根据设置决定是否注册热键。设置变化时调用即可生效。
    private func applyHotKeyRegistration() {
        guard let minimizeHotKey else { return }
        if Settings.shared.isMinimizeHotKeyEnabled {
            // kVK_ANSI_M = 0x2E, controlKey = Carbon 的 Control 修饰
            minimizeHotKey.register(keyCode: UInt32(kVK_ANSI_M), modifiers: UInt32(controlKey))
        } else {
            minimizeHotKey.unregister()
        }
    }

    /// 最小化当前前台应用。
    @objc func minimizeFrontmostApp() {
        WindowMinimizer.minimizeFrontmost()
    }

    /// 前台应用切换时让 AppFilter 的缓存立即失效，
    /// 否则切换应用后的头几百毫秒内可能用到过期的黑名单判断。
    private func observeAppSwitches() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { _ in
            AppFilter.shared.invalidateCache()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        interceptor.stop()
        permissionTimer?.invalidate()
    }

    // MARK: - 状态栏

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // 自己接管点击事件：默认是「点一下弹菜单」，
        // 开启最小化后要能区分左键单击与右键/带修饰键点击。
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        updateStatusIcon()
        rebuildMenu()
    }

    /// 状态栏图标被点击。
    ///
    /// 行为设计：
    ///   · 默认（未开启「点击最小化」）：点一下弹菜单，和普通菜单栏应用一致。
    ///   · 开启「点击最小化」后：**左键单击**最小化前台应用，
    ///     **右键 / Cmd+点击**仍然弹菜单 —— 否则用户就再也打不开设置了。
    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let isRightClick = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true
        let wantsMenu = event?.modifierFlags.contains(.command) == true

        if Settings.shared.isClickToMinimizeEnabled && !isRightClick && !wantsMenu {
            minimizeFrontmostApp()
            // 给一点视觉反馈，让用户知道点到了
            flashStatusIcon()
            return
        }

        // 弹菜单前必须先重建，保证显示的是「当前设置」而不是上一次构建的结果。
        //
        // 为什么必须在这里重建（这是修复一个真实 bug）：
        // 之前依赖 menuNeedsUpdate 去重建，但时序是
        //   挂上 currentMenu(旧) → 弹出 → menuNeedsUpdate 才新建菜单
        // 屏幕上显示的始终是挂上去的那个旧菜单对象，于是开关状态滞后一次
        // （关掉后重开显示为开，再开一次才对）。
        // 在这里同步重建并直接挂新菜单，就消除了这个时序差。
        rebuildMenu()
        statusItem.menu = currentMenu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    /// 点击后让图标闪一下，作为「已触发」的即时反馈。
    private func flashStatusIcon() {
        guard let button = statusItem.button else { return }
        button.alphaValue = 0.35
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            button.alphaValue = 1.0
        }
    }

    private func updateStatusIcon() {
        guard let button = statusItem.button else { return }
        let enabled = Settings.shared.isEnabled && interceptor.isRunning

        // 用应用自己的图标（Resources/MenuBarIcon.png），而不是系统键盘符号 ——
        // 这样菜单栏与 Dock 是同一个视觉标识，用户一眼能认出是 WinKey。
        // 模板图 + isTemplate=true：系统按菜单栏明暗自动着色。
        if let image = loadMenuBarIcon() {
            image.isTemplate = true
            button.image = image
            // 暂停态降低不透明度，保留「开着还是关着」的一眼可辨
            button.alphaValue = enabled ? 1.0 : 0.45
        } else {
            // 兜底：拿不到资源时退回系统符号，避免图标空白
            let symbol = enabled ? "keyboard.fill" : "keyboard"
            let fallback = NSImage(systemSymbolName: symbol, accessibilityDescription: "WinKey")
            fallback?.isTemplate = true
            button.image = fallback
            button.alphaValue = 1.0
        }

        button.toolTip = enabled ? L("tip.enabled") : L("tip.paused")
    }

    /// 加载菜单栏用的模板图标。
    /// 优先 @2x（Retina 下更锐利），拿不到再退回 @1x。
    ///
    /// 尺寸处理：图标是文字型的（"WK" 缩写，宽高比约 2.1:1），
    /// 不能强制成正方形，否则会被拉变形。按菜单栏高度 15pt 等比换算宽度。
    private func loadMenuBarIcon() -> NSImage? {
        for name in ["MenuBarIcon@2x", "MenuBarIcon"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
                  let image = NSImage(contentsOf: url) else { continue }

            let targetHeight: CGFloat = 12
            let aspect = image.size.width / max(1, image.size.height)
            image.size = NSSize(width: targetHeight * aspect, height: targetHeight)
            return image
        }
        Log.write("[WinKey] 警告：找不到菜单栏图标资源，回退到系统符号")
        return nil
    }

    // MARK: - 权限

    /// 尝试启动拦截；没有权限时给出引导。
    private func startInterceptorIfPossible() {
        Log.write("[WinKey] startInterceptorIfPossible: 权限=\(Permission.isAccessibilityGranted) 已运行=\(interceptor.isRunning)")
        guard Permission.isAccessibilityGranted else {
            Log.write("[WinKey] 尚未获得辅助功能权限，等待用户授权。")
            return
        }
        let ok = interceptor.start()
        Log.write("[WinKey] interceptor.start() 返回 \(ok)")
        updateStatusIcon()
    }

    /// 轮询权限状态：用户在系统设置里勾选后，应用无需重启即可自动生效。
    private func startPermissionWatch() {
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let granted = Permission.isAccessibilityGranted
            Log.write("[WinKey] 权限轮询: 已授权=\(granted) 拦截运行中=\(self.interceptor.isRunning)")
            if granted && !self.interceptor.isRunning {
                self.startInterceptorIfPossible()
                self.rebuildMenu()
            }
        }
        // 必须显式加入 .common —— 只加 .default 时，菜单弹出等模态循环会暂停它。
        RunLoop.main.add(timer, forMode: .common)
        permissionTimer = timer
    }

    // MARK: - 菜单

    /// 当前菜单的引用。因为我们要自己控制「点击图标」的行为，
    /// 菜单不再常驻挂在 statusItem 上，弹出时才临时挂载。
    private var currentMenu: NSMenu?

    func menuNeedsUpdate(_ menu: NSMenu) {
        // 这里不再重建菜单。
        //
        // 原因：menuNeedsUpdate 是在菜单**已经弹出**时回调的，此时重建会新建
        // 一个 NSMenu 对象，而屏幕上显示的仍是旧对象，导致开关状态滞后一次。
        // 菜单现在统一在 statusItemClicked 里、弹之前同步重建。
        //
        // 保留这个 delegate 方法是为了满足 NSMenuDelegate 协议，并让
        // 菜单内各勾选项在与 Settings 不一致时能兜底刷新状态。
        syncMenuStates(menu)
    }

    /// 把菜单里各勾选项的状态同步成 Settings 的当前值。
    /// 只更新 state，不替换菜单对象，因此不会造成显示滞后。
    private func syncMenuStates(_ menu: NSMenu) {
        for item in menu.items {
            if let raw = item.representedObject as? Int {
                let keyCode = CGKeyCode(raw)
                item.state = Settings.shared.isRuleEnabled(keyCode) ? .on : .off
            } else if let ruleID = item.representedObject as? String {
                if let rule = NavigationMap.rules.first(where: {
                    NavigationMap.ruleID(triggerKeyCode: $0.triggerKeyCode,
                                         requiresControl: $0.requiresControl) == ruleID
                }) {
                    item.state = Settings.shared.isNavigationRuleEnabled(rule) ? .on : .off
                } else if ruleID == "minimize-hotkey" {
                    item.state = Settings.shared.isMinimizeHotKeyEnabled ? .on : .off
                } else if ruleID == "click-to-minimize" {
                    item.state = Settings.shared.isClickToMinimizeEnabled ? .on : .off
                } else if ruleID == "window-switch" {
                    item.state = Settings.shared.isWindowSwitchEnabled ? .on : .off
                } else if ruleID == "reverse" {
                    item.state = Settings.shared.isReverseMappingEnabled ? .on : .off
                }
            }
        }
    }

    /// 构造一行「标题 + 右侧滑动开关」的菜单项，模仿系统 Wi-Fi 开关的观感。
    ///
    /// 用自绘的 `ToggleSwitch` 而不是 `NSSwitch`：
    /// `NSSwitch` 没有公开的颜色接口（实测连 KVC 设 tintColor 都会抛异常），
    /// 开关填充色只能由系统 accent color 决定，无法指定成想要的蓝色。
    /// 自绘后颜色完全可控，见 ToggleSwitch.swift 的说明。
    private func makeToggleRow(title: String, isOn: Bool, controller: ToggleSwitch) -> NSMenuItem {
        let rowHeight: CGFloat = 30
        let width: CGFloat = 250

        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: rowHeight))

        let label = NSTextField(labelWithString: title)
        label.font = .menuFont(ofSize: 0)
        label.sizeToFit()
        label.frame.origin = NSPoint(x: 14, y: (rowHeight - label.frame.height) / 2)
        container.addSubview(label)

        // 自绘控件尺寸由 intrinsicContentSize 给出，不需要 sizeToFit 兜底。
        controller.setState(isOn)
        controller.frame = NSRect(origin: .zero, size: controller.intrinsicContentSize)
        controller.frame.origin = NSPoint(
            x: width - controller.frame.width - 14,
            y: (rowHeight - controller.frame.height) / 2
        )
        container.addSubview(controller)

        let item = NSMenuItem()
        item.view = container
        return item
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.delegate = self
        Log.write("[WinKey] 重建菜单（总开关=\(Settings.shared.isEnabled ? "开" : "关")）")

        // 权限提示区
        if !Permission.isAccessibilityGranted {
            let warn = NSMenuItem(
                title: L("menu.needs_permission"),
                action: #selector(grantPermission),
                keyEquivalent: ""
            )
            warn.target = self
            menu.addItem(warn)
            menu.addItem(.separator())
        }

        // 总开关：自绘滑动开关，开启时是系统蓝（对齐 macOS 默认强调色）
        let powerSwitch = ToggleSwitch()
        // 可访问性标识：让辅助功能与自动化测试能识别并操作这个开关
        powerSwitch.setAccessibilityLabel(L("menu.power"))
        powerSwitch.setAccessibilityRole(.checkBox)
        powerSwitch.onChange = { [weak self] isOn in
            Settings.shared.isEnabled = isOn
            Log.write("[WinKey] 总开关切换 → \(isOn ? "启用" : "暂停")")
            self?.updateStatusIcon()
        }
        menu.addItem(makeToggleRow(
            title: L("menu.power"),
            isOn: Settings.shared.isEnabled,
            controller: powerSwitch
        ))

        menu.addItem(.separator())

        // 功能开关列表
        let header = NSMenuItem(title: L("menu.section.shortcuts"), action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        for rule in KeyMap.rules {
            let item = NSMenuItem(
                title: "Ctrl+\(rule.name)  →  \(L(rule.behaviorKey))",
                action: #selector(toggleRule(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = Int(rule.keyCode)
            item.state = Settings.shared.isRuleEnabled(rule.keyCode) ? .on : .off
            item.indentationLevel = 1
            menu.addItem(item)
        }

        menu.addItem(.separator())

        // 导航类映射（Home/End、Ctrl+方向键、Alt+Tab）
        let navHeader = NSMenuItem(title: L("menu.section.navigation"), action: nil, keyEquivalent: "")
        navHeader.isEnabled = false
        menu.addItem(navHeader)

        let wsItem = NSMenuItem(
            title: L("nav.window_switch"),
            action: #selector(toggleWindowSwitch),
            keyEquivalent: ""
        )
        wsItem.target = self
        wsItem.representedObject = "window-switch"
        wsItem.state = Settings.shared.isWindowSwitchEnabled ? .on : .off
        wsItem.indentationLevel = 1
        menu.addItem(wsItem)

        for rule in NavigationMap.rules {
            let item = NSMenuItem(
                title: L(rule.labelKey),
                action: #selector(toggleNavigationRule(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = NavigationMap.ruleID(
                triggerKeyCode: rule.triggerKeyCode,
                requiresControl: rule.requiresControl
            )
            item.state = Settings.shared.isNavigationRuleEnabled(rule) ? .on : .off
            item.indentationLevel = 1
            menu.addItem(item)
        }

        menu.addItem(.separator())

        // 最小化前台应用
        let minHeader = NSMenuItem(title: L("menu.section.minimize"), action: nil, keyEquivalent: "")
        minHeader.isEnabled = false
        menu.addItem(minHeader)

        let minHotKey = NSMenuItem(
            title: L("min.hotkey"),
            action: #selector(toggleMinimizeHotKey),
            keyEquivalent: ""
        )
        minHotKey.target = self
        minHotKey.representedObject = "minimize-hotkey"
        minHotKey.state = Settings.shared.isMinimizeHotKeyEnabled ? .on : .off
        minHotKey.indentationLevel = 1
        menu.addItem(minHotKey)

        let minClick = NSMenuItem(
            title: L("min.click_menubar"),
            action: #selector(toggleClickToMinimize),
            keyEquivalent: ""
        )
        minClick.target = self
        minClick.representedObject = "click-to-minimize"
        minClick.state = Settings.shared.isClickToMinimizeEnabled ? .on : .off
        minClick.indentationLevel = 1
        menu.addItem(minClick)

        menu.addItem(.separator())

        // 反向映射
        let reverse = NSMenuItem(
            title: L("menu.reverse"),
            action: #selector(toggleReverse),
            keyEquivalent: ""
        )
        reverse.target = self
        reverse.representedObject = "reverse"
        reverse.state = Settings.shared.isReverseMappingEnabled ? .on : .off
        menu.addItem(reverse)

        // 开机自启
        let login = NSMenuItem(
            title: L("menu.login_item"),
            action: #selector(toggleLoginItem),
            keyEquivalent: ""
        )
        login.target = self
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())

        // 排除应用（终端类）子菜单
        let excludeItem = NSMenuItem(title: L("menu.section.exclude"), action: nil, keyEquivalent: "")
        let excludeMenu = NSMenu()
        for terminal in AppFilter.knownTerminals {
            let sub = NSMenuItem(
                title: terminal.name,
                action: #selector(toggleExcludedApp(_:)),
                keyEquivalent: ""
            )
            sub.target = self
            sub.representedObject = terminal.bundleID
            sub.state = AppFilter.shared.isExcluded(terminal.bundleID) ? .on : .off
            excludeMenu.addItem(sub)
        }
        excludeItem.submenu = excludeMenu
        menu.addItem(excludeItem)

        menu.addItem(.separator())

        let about = NSMenuItem(title: L("menu.about"), action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        let quit = NSMenuItem(title: L("menu.quit"), action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        // 菜单不常驻挂在 statusItem 上：点击行为由 statusItemClicked 决定，
        // 需要弹菜单时才临时挂载（见 statusItemClicked）。
        currentMenu = menu
        updateStatusIcon()
    }

    // MARK: - 动作

    @objc private func grantPermission() {
        Permission.requestAccessibility()
        Permission.openAccessibilitySettings()
    }

    /// 总开关（滑动开关）状态变化。
    @objc private func toggleMinimizeHotKey() {
        Settings.shared.isMinimizeHotKeyEnabled.toggle()
        applyHotKeyRegistration()
        rebuildMenu()
    }

    @objc private func toggleClickToMinimize() {
        Settings.shared.isClickToMinimizeEnabled.toggle()
        rebuildMenu()
    }

    @objc private func toggleRule(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? Int else { return }
        let keyCode = CGKeyCode(raw)
        Settings.shared.setRule(keyCode, enabled: !Settings.shared.isRuleEnabled(keyCode))
        rebuildMenu()
    }

    @objc private func toggleReverse() {
        Settings.shared.isReverseMappingEnabled.toggle()
        rebuildMenu()
    }

    @objc private func toggleLoginItem() {
        LoginItem.setEnabled(!LoginItem.isEnabled)
        rebuildMenu()
    }

    @objc private func toggleExcludedApp(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String else { return }
        AppFilter.shared.setExcluded(bundleID, excluded: !AppFilter.shared.isExcluded(bundleID))
        rebuildMenu()
    }

    @objc private func toggleWindowSwitch() {
        Settings.shared.isWindowSwitchEnabled.toggle()
        rebuildMenu()
    }

    @objc private func toggleNavigationRule(_ sender: NSMenuItem) {
        guard let ruleID = sender.representedObject as? String else { return }
        guard let rule = NavigationMap.rules.first(where: {
            NavigationMap.ruleID(triggerKeyCode: $0.triggerKeyCode,
                                 requiresControl: $0.requiresControl) == ruleID
        }) else { return }
        Settings.shared.setNavigationRule(rule, enabled: !Settings.shared.isNavigationRuleEnabled(rule))
        rebuildMenu()
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L("about.title")
        alert.informativeText = L("about.body")
        alert.addButton(withTitle: L("about.ok"))
        alert.runModal()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
