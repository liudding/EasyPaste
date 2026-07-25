import AppKit
import Carbon
import Foundation

/// 一个可配置的全局/面板内快捷键：键码 + 修饰键（仅 command/shift/option/control）。
struct Shortcut: Codable, Equatable {
    var keyCode: UInt16
    var modifierFlags: UInt

    static let invokeDefault = Shortcut(keyCode: UInt16(kVK_ANSI_V),
                                        modifierFlags: NSEvent.ModifierFlags([.command, .shift]).rawValue)
    static let boardSwitchDefault = Shortcut(keyCode: UInt16(kVK_ANSI_RightBracket),
                                             modifierFlags: NSEvent.ModifierFlags.command.rawValue)

    var modifiers: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifierFlags) }

    /// Carbon RegisterEventHotKey 需要的修饰键位掩码。
    var carbonModifiers: UInt32 {
        var carbon: UInt32 = 0
        let flags = modifiers
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        return carbon
    }

    var displayString: String {
        var result = ""
        let flags = modifiers
        if flags.contains(.control) { result += "⌃" }
        if flags.contains(.option) { result += "⌥" }
        if flags.contains(.shift) { result += "⇧" }
        if flags.contains(.command) { result += "⌘" }
        result += Self.keyName(for: keyCode)
        return result
    }

    static func keyName(for keyCode: UInt16) -> String {
        let specials: [UInt16: String] = [
            36: "↩", 76: "↩", 48: "⇥", 49: L10n.spaceKey, 51: "⌫", 53: "⎋",
            117: "⌦", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
            123: "←", 124: "→", 125: "↓", 126: "↑"
        ]
        if let special = specials[keyCode] { return special }

        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return "?"
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(layoutPointer).takeUnretainedValue()
        let keyboardLayout = unsafeBitCast(CFDataGetBytePtr(layoutData), to: UnsafePointer<UCKeyboardLayout>.self)
        var deadKeys: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = UCKeyTranslate(keyboardLayout, keyCode, UInt16(kUCKeyActionDisplay), 0,
                                    UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysMask),
                                    &deadKeys, chars.count, &length, &chars)
        guard status == noErr, length > 0 else { return "?" }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
}
