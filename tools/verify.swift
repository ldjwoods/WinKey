import ApplicationServices
import CoreGraphics
import Foundation

// 独立验证工具：观测键盘事件流里 C/V/X/A/Z/S/F 的真实 flags。
// 用 tailAppendEventTap 放在事件链末尾，看到的正是应用最终收到的内容，
// 因此可以直接证明 WinKey 的改写是否真的生效。
//
// 用法: verify <秒数>

let seconds = CommandLine.arguments.count > 1 ? Double(CommandLine.arguments[1]) ?? 8 : 8

let targets: [CGKeyCode: String] = [
    0x08: "C(复制)", 0x09: "V(粘贴)", 0x07: "X(剪切)",
    0x00: "A(全选)", 0x06: "Z(撤销)", 0x01: "S(保存)", 0x03: "F(查找)",
]

let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)

let tap = CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .tailAppendEventTap,
    options: .listenOnly,
    eventsOfInterest: mask,
    callback: { _, _, event, _ in
        let kc = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        guard let label = targets[kc] else { return Unmanaged.passUnretained(event) }
        let f = event.flags
        let ctrl = f.contains(.maskControl)
        let cmd = f.contains(.maskCommand)
        let shift = f.contains(.maskShift)

        // 只报告带修饰键的按下，纯字母输入不刷屏
        guard ctrl || cmd else { return Unmanaged.passUnretained(event) }

        let verdict: String
        if cmd && !ctrl {
            verdict = "✅ 已改写为 Cmd+\(label)"
        } else if ctrl && !cmd {
            verdict = "⬜ 仍是 Ctrl+\(label)（未被拦截）"
        } else {
            verdict = "⚠️ 同时带 Ctrl 和 Cmd"
        }
        let shiftNote = shift ? " [Shift]" : ""
        FileHandle.standardError.write("\(verdict)\(shiftNote)\n".data(using: .utf8)!)
        return Unmanaged.passUnretained(event)
    },
    userInfo: nil
)

guard let tap else {
    print("❌ 无法创建观测 tap —— 需要辅助功能权限")
    exit(1)
}

let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)

print("🎧 观测中（\(Int(seconds)) 秒）… 现在依次按下 Ctrl+C / Ctrl+V / Ctrl+X / Ctrl+A / Ctrl+Z")
RunLoop.current.run(until: Date().addingTimeInterval(seconds))
print("观测结束")
