import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Bindable var settings: AppSettings
    let store: ClipboardStore
    let onInvokeShortcutChanged: (Shortcut) -> Void
    @State private var showClearConfirm = false
    @State private var selectedLocale: L10n.Locale = L10nStore.shared.locale
    @State private var l10nStore = L10nStore.shared
    @State private var themeStore = ThemeStore.shared
    @State private var selectedSection: SettingsSection = .general

    /// 标题栏区域高度（标准 macOS titled 窗口无 toolbar 时为 28pt）。
    /// 侧栏顶部用此高度让出悬浮的交通灯按钮空间；detail 同高度顶部内边距保持对齐。
    private let titleBarInset: CGFloat = 28

    var body: some View {
        let _ = l10nStore.version
        let _ = themeStore.version
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
                .safeAreaInset(edge: .top, spacing: 0) {
                    Color.clear.frame(height: titleBarInset)
                }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 680, minHeight: 460)
        .preferredColorScheme(themeStore.effectiveColorScheme)
        .onAppear { selectedLocale = L10nStore.shared.locale }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selectedSection) {
            Label(L10n.tabGeneral, systemImage: "gear")
                .tag(SettingsSection.general)
            Label(L10n.tabPrivacy, systemImage: "hand.raised.fill")
                .tag(SettingsSection.privacy)
            Label(L10n.tabShortcuts, systemImage: "keyboard")
                .tag(SettingsSection.shortcuts)
            Label(L10n.tabUpdates, systemImage: "arrow.down.circle")
                .tag(SettingsSection.updates)
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        .safeAreaInset(edge: .top, spacing: 0) {
            Color.clear.frame(height: titleBarInset)
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailView: some View {
        switch selectedSection {
        case .general: general
        case .privacy: privacy
        case .shortcuts: shortcuts
        case .updates: updates
        }
    }

    // MARK: General

    private var general: some View {
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
                Picker(L10n.pasteSound, selection: $settings.soundName) {
                    Text(L10n.soundNone).tag("")
                    ForEach(AppSettings.soundNames, id: \.self) { Text($0).tag($0) }
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
            get: { themeStore.appearance },
            set: { themeStore.appearance = $0 }
        )
    }

    // MARK: Privacy

    private var privacy: some View {
        Form {
            Section {
                if settings.ignoredApps.isEmpty {
                    Text(L10n.noIgnoredApps).foregroundStyle(.secondary)
                }
                ForEach(settings.ignoredApps) { app in
                    HStack(spacing: 8) {
                        Image(nsImage: icon(for: app.bundleID)).resizable().frame(width: 20, height: 20)
                        VStack(alignment: .leading) {
                            Text(app.name)
                            Text(app.bundleID).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { settings.ignoredApps.removeAll { $0.id == app.id } } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                        }.buttonStyle(.plain)
                    }
                }
                Button(L10n.addApp) { addIgnoredApp() }
            } header: {
                Text(L10n.ignoredAppsHeader)
            } footer: {
                Text(L10n.ignoredAppsFooter).font(.caption)
            }
        }
        .formStyle(.grouped)
    }

    private func icon(for bundleID: String) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
    }

    private func addIgnoredApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = L10n.selectAppDialogTitle
        if panel.runModal() == .OK, let url = panel.url, let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier {
            let name = bundle.infoDictionary?["CFBundleName"] as? String ?? url.deletingPathExtension().lastPathComponent
            if !settings.ignoredApps.contains(where: { $0.bundleID == bundleID }) {
                settings.ignoredApps.append(AppSettings.IgnoredApp(bundleID: bundleID, name: name))
            }
        }
    }

    // MARK: Shortcuts

    private var shortcuts: some View {
        Form {
            Section {
                LabeledContent(L10n.invokePanelLabel) { ShortcutRecorderView(shortcut: invokeBinding) }
                LabeledContent(L10n.switchBoardShortcutLabel) { ShortcutRecorderView(shortcut: $settings.boardSwitchShortcut) }
            } footer: {
                Text(L10n.shortcutsFooter).font(.caption)
            }
        }
        .formStyle(.grouped)
    }

    private var invokeBinding: Binding<Shortcut> {
        Binding(get: { settings.invokeShortcut }, set: { settings.invokeShortcut = $0; onInvokeShortcutChanged($0) })
    }
    
    // MARK: Updates
    
    private var updates: some View {
        Form {
            Section(L10n.autoUpdate) {
                Button(L10n.checkUpdatesButton) {
                    SparkleBridge.shared.checkForUpdates()
                }
                
                let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? L10n.unknownVersion
                let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? L10n.unknownVersion
                
                LabeledContent(L10n.currentVersion) { Text("\(version) (\(build))") }
                
                #if canImport(Sparkle)
                LabeledContent(L10n.updateEngine) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(L10n.updateEngineEnabled)
                }
                #else
                LabeledContent(L10n.updateEngine) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(L10n.updateEngineDevMode)
                }
                #endif
            }
            
            Section(L10n.releaseNotesSection) {
                Text(L10n.releaseNotesPlaceholder)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Section(L10n.updateConfigSection) {
                Text(L10n.updateConfigText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Settings Section

enum SettingsSection: Hashable {
    case general
    case privacy
    case shortcuts
    case updates
}
