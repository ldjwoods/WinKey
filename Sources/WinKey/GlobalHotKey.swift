import AppKit
import Carbon.HIToolbox

/// 全局快捷键注册。
///
/// 用 Carbon 的 `RegisterEventHotKey`：它是 macOS 上注册系统级热键的正规做法，
/// 不需要额外的 Input Monitoring 权限（辅助功能权限已覆盖），
/// 也不会像 CGEventTap 那样需要自己处理按键匹配。
final class GlobalHotKey {
    /// 热键触发时的回调。
    private let handler: () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    /// Carbon 用四字符码标识事件处理器，这里用 'WnK1'。
    private static let signature: OSType = 0x576E_4B31

    init(handler: @escaping () -> Void) {
        self.handler = handler
    }

    deinit {
        unregister()
    }

    /// 注册快捷键。
    /// - Parameters:
    ///   - keyCode: 虚拟键码（如 kVK_ANSI_M = 0x2E）
    ///   - modifiers: Carbon 修饰键掩码（如 controlKey）
    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32) -> Bool {
        unregister()

        // 安装事件处理器：Carbon 通过 EventTarget 回调，用 refcon 传回 self。
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                let manager = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()

                // 核对触发的确实是我们的热键，避免误吞别人的事件。
                var hotKeyID = EventHotKeyID()
                let err = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard err == noErr, hotKeyID.signature == GlobalHotKey.signature else {
                    return OSStatus(eventNotHandledErr)
                }
                manager.handler()
                return noErr
            },
            1,
            &eventType,
            selfPtr,
            &eventHandlerRef
        )

        guard installStatus == noErr else {
            Log.write("[WinKey] 安装热键事件处理器失败: \(installStatus)")
            return false
        }

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard registerStatus == noErr else {
            Log.write("[WinKey] 注册热键失败 (keyCode=\(keyCode) mods=\(modifiers)): \(registerStatus)")
            return false
        }

        Log.write("[WinKey] 全局快捷键已注册 (keyCode=\(keyCode) mods=\(modifiers))")
        return true
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }
}
