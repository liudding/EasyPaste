import AppKit
import SwiftUI

/// 快捷键录入控件：点击进入录制态，捕获下一个带修饰键的按键；Esc 取消。
struct ShortcutRecorderView: View {
    @Binding var shortcut: Shortcut
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            recording ? stop() : start()
        } label: {
            Text(recording ? "按下快捷键…" : shortcut.displayString)
                .frame(minWidth: 110)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(recording ? .orange.opacity(0.3) : .white.opacity(0.08), in: .rect(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .font(.system(size: 12, weight: .medium, design: .monospaced))
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stop(); return nil }
            let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
            guard !flags.isEmpty else { NSSound.beep(); return nil }
            shortcut = Shortcut(keyCode: event.keyCode, modifierFlags: flags.rawValue)
            stop()
            return nil
        }
    }

    private func stop() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        recording = false
    }
}
