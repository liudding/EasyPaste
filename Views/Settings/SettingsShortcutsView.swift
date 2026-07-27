import Carbon
import SwiftUI

// MARK: - Shortcuts Settings

struct SettingsShortcutsView: View {
    @Bindable var settings: AppSettings
    let onInvokeShortcutChanged: (Shortcut) -> Void

    var body: some View {
        Form {
            Section {
                LabeledContent(L10n.invokePanelLabel) { ShortcutRecorderView(shortcut: invokeBinding) }
                LabeledContent(L10n.switchBoardShortcutLabel) { ShortcutRecorderView(shortcut: $settings.boardSwitchShortcut) }
                // Toggle(L10n.tabSwitchBoardLabel, isOn: $settings.tabSwitchBoardEnabled)
                //     .help(L10n.tabSwitchBoardHelp)
            } footer: {
                Text(L10n.shortcutsFooter).font(.caption)
            }

            Section {
                GroupBox(L10n.contextMenuShortcutsUniversal) {
                    VStack(spacing: 12) {
                        LabeledContent(L10n.shortcutPasteToApp) { ShortcutRecorderView(shortcut: contextMenuShortcutBinding(for: "paste")) }
                        LabeledContent(L10n.shortcutPastePlainText) { ShortcutRecorderView(shortcut: contextMenuShortcutBinding(for: "paste_plain")) }
                        LabeledContent(L10n.shortcutCopy) { ShortcutRecorderView(shortcut: contextMenuShortcutBinding(for: "copy")) }
                        LabeledContent(L10n.shortcutRename) { ShortcutRecorderView(shortcut: contextMenuShortcutBinding(for: "rename")) }
                        LabeledContent(L10n.shortcutPreview) { ShortcutRecorderView(shortcut: contextMenuShortcutBinding(for: "preview")) }
                        LabeledContent(L10n.shortcutDelete) { ShortcutRecorderView(shortcut: contextMenuShortcutBinding(for: "delete")) }
                    }
                }

                GroupBox(L10n.contextMenuShortcutsTypeSpecific) {
                    VStack(spacing: 12) {
                        LabeledContent(L10n.shortcutExportTxt) { ShortcutRecorderView(shortcut: contextMenuShortcutBinding(for: "export_txt")) }
                        LabeledContent(L10n.shortcutExportRtf) { ShortcutRecorderView(shortcut: contextMenuShortcutBinding(for: "export_rtf")) }
                        LabeledContent(L10n.shortcutSaveAs) { ShortcutRecorderView(shortcut: contextMenuShortcutBinding(for: "save_as")) }
                        LabeledContent(L10n.shortcutQrCode) { ShortcutRecorderView(shortcut: contextMenuShortcutBinding(for: "qr_code")) }
                        LabeledContent(L10n.shortcutSendEmail) { ShortcutRecorderView(shortcut: contextMenuShortcutBinding(for: "send_email")) }
                        LabeledContent(L10n.shortcutJsonPreview) { ShortcutRecorderView(shortcut: contextMenuShortcutBinding(for: "json_preview")) }
                        LabeledContent(L10n.shortcutOpenLink) { ShortcutRecorderView(shortcut: contextMenuShortcutBinding(for: "open_link")) }
                    }
                }
            } header: {
                Text(L10n.contextMenuShortcutsSection).font(.headline)
            } footer: {
                Text(L10n.shortcutsFooter).font(.caption)
            }
        }
        .formStyle(.grouped)
    }

    private func contextMenuShortcutBinding(for actionID: String) -> Binding<Shortcut> {
        Binding(
            get: { settings.contextMenuShortcuts[actionID]?.shortcut ?? .init(keyCode: UInt16(kVK_ANSI_V), modifierFlags: NSEvent.ModifierFlags([.command, .shift]).rawValue) },
            set: {
                if var config = settings.contextMenuShortcuts[actionID] {
                    config.shortcut = $0
                    settings.contextMenuShortcuts[actionID] = config
                } else {
                    settings.contextMenuShortcuts[actionID] = .init(shortcut: $0)
                }
            }
        )
    }

    private var invokeBinding: Binding<Shortcut> {
        Binding(get: { settings.invokeShortcut }, set: { settings.invokeShortcut = $0; onInvokeShortcutChanged($0) })
    }
}
