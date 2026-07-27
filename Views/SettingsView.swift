import AppKit
import Carbon
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

    /// 内联更新状态（检查中 / 下载进度 / 更新可用 等），由自定义 Sparkle user driver 写入。
    @ObservedObject private var updateState = SparkleBridge.shared.uiState

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
                    detailHeader
                }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 680, minHeight: 460)
        .preferredColorScheme(themeStore.effectiveColorScheme)
        .onAppear { selectedLocale = L10nStore.shared.locale }
        .onReceive(SettingsNavigation.shared.$pendingSection) { section in
            if let section {
                selectedSection = section
                SettingsNavigation.shared.pendingSection = nil
            }
        }
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

    /// 当前选中分区的标题，用于详情区顶部 head 展示。
    private var sectionTitle: String {
        switch selectedSection {
        case .general: L10n.tabGeneral
        case .privacy: L10n.tabPrivacy
        case .shortcuts: L10n.tabShortcuts
        case .updates: L10n.tabUpdates
        }
    }

    /// 详情区顶部 head：高度与侧栏 head（titleBarInset）一致，
    /// 左对齐显示当前分区标题，底部细分割线与内容区分隔。
    private var detailHeader: some View {
        HStack {
            Text(sectionTitle)
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .frame(height: titleBarInset)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) {
            Divider()
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
                    // 在设置中选择某个声音后立即试听一次（选「无」时不播放）。
                    guard !settings.soundName.isEmpty else { return }
                    NSSound(named: NSSound.Name(settings.soundName))?.play()
                }
                Picker(L10n.copySound, selection: $settings.copySoundName) {
                    Text(L10n.soundNone).tag("")
                    ForEach(AppSettings.soundNames, id: \.self) { Text($0).tag($0) }
                }
                .onChange(of: settings.copySoundName) { _, _ in
                    // 在设置中选择某个声音后立即试听一次（选「无」时不播放）。
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
                Toggle(L10n.tabSwitchBoardLabel, isOn: $settings.tabSwitchBoardEnabled)
                    .help(L10n.tabSwitchBoardHelp)
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
    
    /// 获取上下文菜单项的快捷键 Binding。
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
    
    // MARK: Updates
    
    private var updates: some View {
        Form {
            Section(L10n.autoUpdate) {
                HStack {
                    Button(L10n.checkUpdatesButton) {
                        SparkleBridge.shared.checkForUpdates()
                    }
                    Spacer()
                    if updateState.phase == .checking {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text(L10n.checkingForUpdates).foregroundStyle(.secondary)
                        }
                    }
                }

                updateStatusInline

                if let result = updateState.resultMessage {
                    Label(result, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
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
        .alert(L10n.updateError, isPresented: Binding(
            get: { updateState.errorMessage != nil },
            set: { if !$0 { updateState.errorMessage = nil } }
        )) {
            Button(L10n.ok) { updateState.errorMessage = nil }
        } message: {
            Text(updateState.errorMessage ?? "")
        }
    }

    /// 检查 / 下载 / 可用 / 安装中 等瞬态更新状态的内联渲染（替代 Sparkle 原生独立窗口）。
    /// 终态结果（已是最新 / 出错）分别由 resultMessage / errorMessage 承载，不在本开关内。
    @ViewBuilder
    private var updateStatusInline: some View {
        switch updateState.phase {
        case .idle, .checking:
            EmptyView()
        case .updateAvailable(let version):
            VStack(alignment: .leading, spacing: 10) {
                Label(String(format: L10n.updateAvailable, version), systemImage: "arrow.down.circle.fill")
                    .foregroundStyle(.blue)
                HStack(spacing: 8) {
                    Button(L10n.updateNow) { updateState.install?() }
                        .controlSize(.small)
                    Button(L10n.skipThisVersion) { updateState.skip?() }
                        .controlSize(.small)
                    Button(L10n.remindLater) { updateState.dismiss?() }
                        .controlSize(.small)
                }
            }
        case .downloading(let progress):
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.downloadingUpdate).foregroundStyle(.secondary)
                ProgressView(value: progress).progressViewStyle(.linear)
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .installing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(L10n.installingUpdate).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Settings Section

enum SettingsSection: Hashable {
    case general
    case privacy
    case shortcuts
    case updates
}
