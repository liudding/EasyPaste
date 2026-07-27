import AppKit
import SwiftUI

// MARK: - General Settings

struct SettingsGeneralView: View {
    @Bindable var settings: AppSettings
    let store: ClipboardStore

    @State private var showClearConfirm = false
    @State private var selectedLocale: L10n.Locale = L10nStore.shared.locale

    var body: some View {
        Form {
            Section {
                Picker(L10n.panelPosition, selection: $settings.panelPosition) {
                    ForEach(AppSettings.PanelPosition.allCases) { Text($0.title).tag($0) }
                }

                Picker(L10n.themeAppearance, selection: themeBinding) {
                    ForEach(ThemeAppearance.allCases) { theme in
                        Label(theme.displayName, systemImage: theme.icon).tag(theme)
                    }
                }
                .pickerStyle(.menu)

                Picker(L10n.languageSection, selection: $selectedLocale) {
                    ForEach(L10n.Locale.allCases) { locale in
                        Text(locale.name).tag(locale)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedLocale) { _, newValue in
                    L10nStore.shared.locale = newValue
                }
            } header: {
                Text(L10n.sectionPanel)
            } footer: {
                Text(L10n.themeDescription).font(.caption)
            }
            Section(L10n.sectionGeneral) {
                Toggle(L10n.openAtLogin, isOn: $settings.openAtLogin)
                Toggle(L10n.icloudSync, isOn: $settings.iCloudSync)
                Toggle(L10n.showInMenuBar, isOn: $settings.showInMenuBar)
                    .help(L10n.menuBarHelp)
                Toggle(L10n.hideDockIconSetting, isOn: $settings.hideDockIcon)
                    .disabled(!settings.showInMenuBar)
                    .help(L10n.hideDockIconHelp)
                    .onChange(of: settings.showInMenuBar) { _, newValue in
                        if !newValue { settings.hideDockIcon = false }
                    }
                Picker(L10n.pasteSound, selection: $settings.soundName) {
                    Text(L10n.soundNone).tag("")
                    ForEach(AppSettings.soundNames, id: \.self) { Text($0).tag($0) }
                }
                .onChange(of: settings.soundName) { _, _ in
                    guard !settings.soundName.isEmpty else { return }
                    NSSound(named: NSSound.Name(settings.soundName))?.play()
                }
                Picker(L10n.copySound, selection: $settings.copySoundName) {
                    Text(L10n.soundNone).tag("")
                    ForEach(AppSettings.soundNames, id: \.self) { Text($0).tag($0) }
                }
                .onChange(of: settings.copySoundName) { _, _ in
                    guard !settings.copySoundName.isEmpty else { return }
                    NSSound(named: NSSound.Name(settings.copySoundName))?.play()
                }
                Toggle(L10n.alwaysPastePlainText, isOn: $settings.alwaysPastePlainText)
            }
            Section(L10n.sectionHistory) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack { Text(L10n.retentionPeriod); Spacer(); Text(settings.historyLimitLabel).foregroundStyle(.secondary) }
                    Slider(value: historyIndexBinding, in: 0...1, step: 1.0 / Double(AppSettings.historyStepsRaw.count - 1))
                }
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    HStack { Text(L10n.maxRetentionCount); Spacer(); Text(settings.maxItemsLabel).foregroundStyle(.secondary) }
                    Picker(L10n.maxRetentionCount, selection: $settings.maxItemsMode) {
                        ForEach(AppSettings.MaxItemsMode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if settings.maxItemsMode == .limited {
                        Stepper(value: $settings.maxItemsCount, in: 100...10000, step: 100) {
                            Text("\(settings.maxItemsCount) \(L10n.characters)")
                        }
                    }
                }
                Button(L10n.clearAllHistory, role: .destructive) { showClearConfirm = true }
                    .alert(L10n.clearConfirmTitle, isPresented: $showClearConfirm) {
                        Button(L10n.clearConfirmAction, role: .destructive) { store.clearAll() }
                        Button(L10n.clearConfirmCancel, role: .cancel) {}
                    } message: { Text(L10n.clearConfirmMessage) }
            }
        }
        .formStyle(.grouped)
    }

    private var historyIndexBinding: Binding<Double> {
        let stepsCount = Double(AppSettings.historyStepsRaw.count)
        return Binding<Double>(
            get: { Double(settings.historyStepIndex) / (stepsCount - 1) },
            set: { settings.historyStepIndex = Int(round($0 * (stepsCount - 1))) }
        )
    }

    private var themeBinding: Binding<ThemeAppearance> {
        Binding(
            get: { ThemeStore.shared.appearance },
            set: { ThemeStore.shared.appearance = $0 }
        )
    }
}
