import AppKit
import SwiftUI

// MARK: - Recording state notifications

extension Notification.Name {
    /// 快捷键录制开始 — 接收方可借此挂起全局热键，防止 Carbon 层面提前触发。
    static let shortcutRecorderDidStart = Notification.Name("shortcutRecorderDidStart")
    /// 快捷键录制结束 — 接收方可借此恢复全局热键。
    static let shortcutRecorderDidStop = Notification.Name("shortcutRecorderDidStop")
}

/// 快捷键录入控件：点击进入录制态，捕获下一个按键（允许无修饰键的单键，如 Tab/回车/字母/F 键等）；Esc 取消。
/// 录制期间会通过 local monitor 拦截所有 keyDown 事件并消费（返回 nil），
/// 同时禁用窗口 Tab 键盘导航并挂起全局热键，确保快捷键不会触发其他 app 功能。
struct ShortcutRecorderView: View {
    @Binding var shortcut: Shortcut
    @State private var recording = false
    @State private var monitor: Any?
    @State private var previousResponder: NSResponder?
    @State private var l10nStore = L10nStore.shared

    /// 纯修饰键的键码：单独按下它们时不作为快捷键录入（真正的组合键会跟随字符键的 keyDown 到达）。
    private static let modifierKeyCodes: Set<UInt16> = [
        54, 55, // Command (右/左)
        56, 60, // Shift (右/左)
        58, 61, // Option (右/左)
        59, 62, // Control (右/左)
        57,      // Caps Lock
        63       // Fn
    ]

    var body: some View {
        let _ = l10nStore.version
        Button {
            recording ? stop() : start()
        } label: {
            Text(recording ? L10n.shortcutRecording : shortcut.displayString)
                .frame(minWidth: 110)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(recording ? .orange.opacity(0.3) : .primary.opacity(0.08), in: .rect(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .font(.system(size: 12, weight: .medium, design: .monospaced))
        .onDisappear { stop() }
    }

    private func start() {
        recording = true

        // 清除窗口第一响应者，防止 Tab 键被键盘导航截获而无法到达 keyDown monitor。
        previousResponder = NSApp.keyWindow?.firstResponder
        NSApp.keyWindow?.makeFirstResponder(nil)

        // 通知持有者挂起全局热键（如 invokeShortcut），防止 Carbon 层面提前触发。
        NotificationCenter.default.post(name: .shortcutRecorderDidStart, object: nil)

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Esc 取消录制
            if event.keyCode == 53 { stop(); return nil }

            // 仅修饰键本身不作为快捷键录入，避免「只按了 Command/Shift 等」被误录。
            // 真正的组合键（如 ⌘F）会由字符键的 keyDown 携带修饰标志到达，从而被正确记录。
            guard !Self.modifierKeyCodes.contains(event.keyCode) else { return nil }

            // 允许无修饰键的单键（Tab/回车/字母/F 键等）；modifierFlags 为 0 时即为单键快捷键。
            let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
            shortcut = Shortcut(keyCode: event.keyCode, modifierFlags: flags.rawValue)
            stop()
            return nil
        }
    }

    private func stop() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil

        // 恢复窗口第一响应者
        if let window = NSApp.keyWindow, let resp = previousResponder {
            window.makeFirstResponder(resp)
        }
        previousResponder = nil

        // 通知持有者恢复全局热键
        NotificationCenter.default.post(name: .shortcutRecorderDidStop, object: nil)

        recording = false
    }
}
