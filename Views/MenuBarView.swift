import AppKit
import SwiftUI

struct MenuBarView: View {
    let store: ClipboardStore
    let clipboard: ClipboardService
    let onShowPanel: () -> Void

    var body: some View {
        Button("显示面板") { onShowPanel() }
        Divider()
        if !store.items.isEmpty {
            ForEach(store.items.prefix(7)) { item in
                Button(String(item.displayTitle.prefix(30))) { clipboard.paste(item) }
            }
            Divider()
        }
        // SettingsLink 是 macOS 14+ 官方方式打开 Settings 场景；
        // sendAction(showSettingsWindow:) 在 Sonoma+ 已被移除。
        SettingsLink { Text("设置…") }
        Button("关于 EasyPaste") { AboutPresenter.show() }
        Divider()
        Button("退出 EasyPaste") { NSApp.terminate(nil) }
    }
}

enum AboutPresenter {
    @MainActor static func show() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "EasyPaste"
        alert.informativeText = "版本 1.0\n\n⌘⇧V 唤起剪贴板面板，双击或回车粘贴到之前的应用。"
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}
