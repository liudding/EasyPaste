import Carbon
import SwiftUI

// MARK: - Shortcuts Settings

struct SettingsShortcutsView: View {
    @Bindable var settings: AppSettings
    let onInvokeShortcutChanged: (Shortcut) -> Void

    @State private var showResetConfirm = false

    var body: some View {
        Form {
            Section {
                LabeledContent(L10n.invokePanelLabel) { ShortcutRecorderView(shortcut: invokeBinding) }
                LabeledContent(L10n.switchBoardNextLabel) { ShortcutRecorderView(shortcut: $settings.boardSwitchNextShortcut) }
                LabeledContent(L10n.switchBoardPrevLabel) { ShortcutRecorderView(shortcut: $settings.boardSwitchPrevShortcut) }
            } footer: {
                Text(L10n.shortcutsFooter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button(L10n.resetShortcuts, role: .destructive) {
                    showResetConfirm = true
                }
                .alert(L10n.resetShortcuts, isPresented: $showResetConfirm) {
                    Button(L10n.resetShortcuts, role: .destructive) { resetToDefaults() }
                    Button(L10n.clearConfirmCancel, role: .cancel) {}
                } message: {
                    Text("Reset all shortcuts to their default values?")
                }
            }
        }
        .formStyle(.grouped)
    }

    private var invokeBinding: Binding<Shortcut> {
        Binding(get: { settings.invokeShortcut }, set: { settings.invokeShortcut = $0; onInvokeShortcutChanged($0) })
    }

    private func resetToDefaults() {
        settings.invokeShortcut = .invokeDefault
        onInvokeShortcutChanged(.invokeDefault)
        settings.boardSwitchNextShortcut = .boardSwitchNextDefault
        settings.boardSwitchPrevShortcut = .boardSwitchPrevDefault
    }
}
