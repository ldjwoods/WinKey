import Foundation
import CoreGraphics

/// 窗口切换映射：Windows 的 Alt+Tab → macOS 的 Cmd+Tab。
///
/// 实现要点与普通映射不同：
/// Alt+Tab 是一个「按住 Alt 连续按 Tab」的持续交互。macOS 的 Cmd+Tab
/// 由系统 Dock 处理，它会跟踪 Cmd 的按下与抬起来决定何时提交切换。
/// 因此我们必须在 Alt 按下期间**持续**把它呈现为 Cmd，
/// 包括修饰键自身的事件，否则系统的切换器会在第一次 Tab 后就消失。
enum WindowSwitch {
    static let altKeyCode: CGKeyCode = 0x3A     // kVK_Option (左 Alt)
    static let rightAltKeyCode: CGKeyCode = 0x3D // kVK_RightOption
    static let tabKeyCode: CGKeyCode = 0x30     // kVK_Tab

    /// 是否启用（由 Settings 提供）。
    static var isEnabled: Bool { Settings.shared.isWindowSwitchEnabled }

    /// 判断一个事件是否属于 Alt+Tab 交互。
    static func isAltKey(_ keyCode: CGKeyCode) -> Bool {
        keyCode == altKeyCode || keyCode == rightAltKeyCode
    }
}
