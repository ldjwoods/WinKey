import AppKit

// 纯代码启动，不使用 SwiftUI 的 App 生命周期，避免 SPM 构建时的资源打包问题。
let app = NSApplication.shared
let controller = MenuBarController()
app.delegate = controller
app.run()
