import Carbon.HIToolbox
import Foundation

/// A narrow AppKit/Carbon bridge: the app owns presentation; Carbon only delivers Cmd–Shift–V globally.
final class GlobalShortcutService {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var action: (() -> Void)?

    func registerDefaultShortcut(action: @escaping () -> Void) {
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
        RegisterEventHotKey(UInt32(kVK_ANSI_V), UInt32(cmdKey | shiftKey), id, GetEventDispatcherTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil; handlerRef = nil
    }

    deinit { unregister() }
}
