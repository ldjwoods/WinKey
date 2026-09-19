import Foundation

/// 轻量文件日志。
///
/// 之所以不用 NSLog：bundle 应用经 launchd 启动时日志路由不稳定，
/// 用 `log show --predicate 'process == "WinKey"'` 经常什么都抓不到，
/// 排查权限/启动问题时会误判成「代码没执行」。写文件最可靠。
///
/// 查看: tail -f /tmp/winkey.log
enum Log {
    private static let url = URL(fileURLWithPath: "/tmp/winkey.log")
    private static let queue = DispatchQueue(label: "com.local.winkey.log")

    static func write(_ message: String) {
        // 用串行队列异步写，避免阻塞 CGEventTap 回调所在的键盘线程。
        queue.async {
            let stamp = ISO8601DateFormatter().string(from: Date())
            let line = "[\(stamp)] \(message)\n"
            guard let data = line.data(using: .utf8) else { return }

            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                handle.seekToEndOfFile()
                handle.write(data)
            } else {
                // 文件还不存在，直接创建。
                try? data.write(to: url)
            }
        }
    }
}
