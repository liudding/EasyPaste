import Carbon.HIToolbox
import Foundation

/// Carbon 桥：注册一个可配置的全局热键，触发时回调 app。面板/设置负责决定回调动作。
final class GlobalShortcutService {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var action: (() -> Void)?

    func register(shortcut: Shortcut, action: @escaping () -> Void) {
        unregister()
        self.action = action
        let eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, userData in
            guard let userData else { return noErr }
            let service = Unmanaged<GlobalShortcutService>.fromOpaque(userData).takeUnretainedValue()
            service.action?()
            return noErr
        }, 1, [eventType], pointer, &handlerRef)
        let id = EventHotKeyID(signature: OSType(0x4550_4153), id: 1) // EPAS
        RegisterEventHotKey(UInt32(shortcut.keyCode), shortcut.carbonModifiers, id, GetEventDispatcherTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil; handlerRef = nil
    }

    deinit { unregister() }
}
