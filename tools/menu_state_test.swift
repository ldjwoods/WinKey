import Foundation

// 用状态机模拟菜单构建与显示的时序，对比修复前后的行为。
// 这是确定性的：不依赖 GUI 操作，能直接证明 bug 的成因与修复。

final class Settings { var enabled = true }
final class Menu {
    let snapshotEnabled: Bool       // 菜单构建时快照的开关状态
    init(_ e: Bool) { snapshotEnabled = e }
    var displayedSwitchIsOn: Bool { snapshotEnabled }
}

print("=== 修复前：menuNeedsUpdate 里重建 ===")
do {
    let settings = Settings()
    var currentMenu = Menu(settings.enabled)   // 启动时构建
    var visible: Menu? = nil

    func openMenu() {
        // 旧逻辑：挂上旧菜单 → 弹出 → menuNeedsUpdate 才重建
        visible = currentMenu                  // 挂上"上一次"构建的菜单
        currentMenu = Menu(settings.enabled)   // menuNeedsUpdate 新建（但屏幕上是 visible）
    }

    print("初始 settings.enabled = \(settings.enabled)")
    openMenu()
    print("第1次打开菜单，开关显示 = \(visible!.displayedSwitchIsOn)")
    settings.enabled = false                  // 用户点了开关
    print("用户切换后 settings.enabled = \(settings.enabled)")

    openMenu()
    print("第2次打开菜单，开关显示 = \(visible!.displayedSwitchIsOn)  ← 应为 false")
    let bug = visible!.displayedSwitchIsOn != settings.enabled
    print(bug ? "❌ 复现 bug：显示滞后一次" : "✅ 正确")

    openMenu()
    print("第3次打开菜单，开关显示 = \(visible!.displayedSwitchIsOn)  ← 这次才对")
}

print("\n=== 修复后：弹之前同步重建 ===")
do {
    let settings = Settings()
    var currentMenu = Menu(settings.enabled)
    var visible: Menu? = nil

    func openMenu() {
        currentMenu = Menu(settings.enabled)   // 先重建
        visible = currentMenu                  // 再挂上并显示
    }

    print("初始 settings.enabled = \(settings.enabled)")
    openMenu()
    print("第1次打开菜单，开关显示 = \(visible!.displayedSwitchIsOn)")
    settings.enabled = false
    print("用户切换后 settings.enabled = \(settings.enabled)")

    openMenu()
    print("第2次打开菜单，开关显示 = \(visible!.displayedSwitchIsOn)  ← 应为 false")
    let ok = visible!.displayedSwitchIsOn == settings.enabled
    print(ok ? "✅ 修复有效：无滞后" : "❌ 仍有 bug")
}
