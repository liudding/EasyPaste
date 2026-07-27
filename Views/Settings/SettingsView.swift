import SwiftUI

// MARK: - Settings

struct SettingsView: View {
    @Bindable var settings: AppSettings
    let store: ClipboardStore
    let onInvokeShortcutChanged: (Shortcut) -> Void

    @State private var selectedSection: SettingsSection = .general

    /// 标题栏区域高度（标准 macOS titled 窗口无 toolbar 时为 28pt）。
    /// 侧栏顶部用此高度让出悬浮的交通灯按钮空间；detail 同高度顶部内边距保持对齐。
    private let titleBarInset: CGFloat = 28

    @State private var themeStore = ThemeStore.shared

    var body: some View {
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
        case .general:
            SettingsGeneralView(settings: settings, store: store)
        case .privacy:
            SettingsPrivacyView(settings: settings)
        case .shortcuts:
            SettingsShortcutsView(settings: settings, onInvokeShortcutChanged: onInvokeShortcutChanged)
        case .updates:
            SettingsUpdatesView()
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
}
