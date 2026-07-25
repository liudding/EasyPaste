import AppKit
import SwiftUI

struct MenuBarView: View {
    let store: ClipboardStore
    let clipboard: ClipboardService
    let onShowPanel: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        Button("显示面板") { onShowPanel() }
        Divider()
        if !store.items.isEmpty {
            ForEach(store.items.prefix(7)) { item in
                Button(String(item.displayTitle.prefix(30))) { clipboard.paste(item) }
            }
            Divider()
        }

        // Sparkle 检查更新菜单项
        Button("检查更新…") {
            SparkleBridge.shared.checkForUpdates()
        }

        // 直接走 AppServices.openSettingsWindow()（自己托管的 NSWindow），
        // 不再依赖 SwiftUI Settings 场景 / showSettingsWindow:（macOS 14+ 已移除）。
        Button("设置…") { onOpenSettings() }
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
