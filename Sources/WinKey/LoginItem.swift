import Foundation
import ServiceManagement

/// 开机自启管理。macOS 13+ 用 SMAppService，是官方推荐做法。
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// 切换开机自启，返回操作后是否处于启用状态。
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            Log.write("[WinKey] 设置开机自启失败: \(error.localizedDescription)")
        }
        return isEnabled
    }
}
