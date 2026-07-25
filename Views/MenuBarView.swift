import AppKit
import SwiftUI

struct MenuBarView: View {
    let store: ClipboardStore
    let clipboard: ClipboardService
    let onShowPanel: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        Button(L10n.showPanel) { onShowPanel() }
        Divider()
        if !store.items.isEmpty {
            ForEach(store.items.prefix(7)) { item in
                Button(String(item.displayTitle.prefix(30))) { clipboard.paste(item) }
            }
            Divider()
        }

        // Sparkle 检查更新菜单项
        Button(L10n.checkUpdates) {
            SparkleBridge.shared.checkForUpdates()
        }

        // 直接走 AppServices.openSettingsWindow()（自己托管的 NSWindow），
        // 不再依赖 SwiftUI Settings 场景 / showSettingsWindow:（macOS 14+ 已移除）。
        Button(L10n.settings) { onOpenSettings() }
        Button(L10n.aboutEasyPaste) { AboutPresenter.show() }
        Divider()
        Button(L10n.exitEasyPaste) { NSApp.terminate(nil) }
    }
}

enum AboutPresenter {
    @MainActor static func show() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L10n.aboutTitle
        alert.informativeText = L10n.aboutDescription
        alert.addButton(withTitle: L10n.aboutButton)
        alert.runModal()
    }
}
