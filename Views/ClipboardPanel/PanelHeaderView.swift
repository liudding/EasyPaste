import SwiftUI

/// 剪贴板面板头部：搜索、标题、看板芯片、快速设置、更多菜单。
struct PanelHeaderView: View {
    @Bindable var store: ClipboardStore
    @Bindable var settings: AppSettings
    @Bindable var panelState: PanelState
    let onOpenSettings: () -> Void
    @FocusState.Binding var searchFocused: Bool
    @FocusState.Binding var boardFieldFocused: Bool

    @State private var l10nStore = L10nStore.shared

    private var isVertical: Bool { settings.panelPosition.isVertical }

    var body: some View {
        let _ = l10nStore.version
        if isVertical {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    searchControlVertical
                    quickSettingsInline
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(1)
                    moreMenu
                        .fixedSize()
                        .layoutPriority(1)
                }
                .frame(height: 30)
                BoardChipsView(store: store, panelState: panelState, boardFieldFocused: $boardFieldFocused)
            }
        } else {
            HStack(spacing: 10) {
                searchControl
                Rectangle().fill(.primary.opacity(0.12)).frame(width: 1, height: 18)
                BoardChipsView(store: store, panelState: panelState, boardFieldFocused: $boardFieldFocused)
                Spacer()
                quickSettingsInline
                moreMenu
            }
            .frame(height: 30)
        }
    }

    // MARK: Search

    @ViewBuilder private var searchControl: some View {
        if panelState.searchExpanded || !store.activeFilters.isEmpty {
            FilterSearchBar(
                store: store,
                panelState: panelState,
                searchFocused: $searchFocused,
                isVertical: false
            )
            .frame(width: 240)
            .transition(.opacity.combined(with: .scale(scale: 0.6, anchor: .leading)))
        } else {
            Button {
                withAnimation(.easeOut(duration: 0.18)) { panelState.searchExpanded = true }
                searchFocused = true
            } label: {
                Image(systemName: "magnifyingglass").font(.system(size: 14, weight: .medium))
                    .frame(width: 28, height: 28).contentShape(.rect)
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .focusEffectDisabled()
        }
    }

    /// 竖直方向专用搜索栏：始终展开、填满可用宽度，无需折叠/展开切换。
    @ViewBuilder private var searchControlVertical: some View {
        FilterSearchBar(
            store: store,
            panelState: panelState,
            searchFocused: $searchFocused,
            isVertical: true
        )
    }

    // MARK: More Menu

    private var moreMenu: some View {
        Menu {
            Button(L10n.aboutEasyPaste) { AboutPresenter.show() }
            Button(L10n.settings) { openSettingsWindow() }
            Divider()
            Button(L10n.exitEasyPaste) { NSApp.terminate(nil) }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 13, weight: .bold))
                .frame(width: 34, height: 34).contentShape(.rect)
        }
        .menuIndicator(.hidden)
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func openSettingsWindow() {
        onOpenSettings()
    }

    // MARK: Quick Settings

    private var quickSettingsInline: some View {
        HStack(spacing: 2) {
            soundToggle
            plainTextToggle
            positionGroup
        }
        .frame(height: 24)
    }

    @ViewBuilder
    private var positionGroup: some View {
        Rectangle().fill(.primary.opacity(0.12)).frame(width: 1, height: 14)
        HStack(spacing: 1) {
            positionButton(.top, icon: "inset.filled.tophalf.rectangle")
            positionButton(.left, icon: "inset.filled.lefthalf.rectangle")
            positionButton(.right, icon: "inset.filled.righthalf.rectangle")
            positionButton(.bottom, icon: "inset.filled.bottomhalf.rectangle")
        }
        .background(.primary.opacity(0.07), in: Capsule())
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private func positionButton(_ position: AppSettings.PanelPosition, icon: String) -> some View {
        let isActive = settings.panelPosition == position
        Button {
            withAnimation(.easeOut(duration: 0.15)) { settings.panelPosition = position }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 9, weight: isActive ? .bold : .regular))
                .frame(width: 18, height: 18)
                .foregroundStyle(isActive ? .white : .secondary)
        }
        .buttonStyle(.plain)
    }

    private var soundToggle: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { settings.soundEnabled.toggle() }
        } label: {
            Image(systemName: settings.soundEnabled ? "speaker.wave.3.fill" : "speaker.slash.fill")
                .font(.system(size: 11, weight: settings.soundEnabled ? .semibold : .regular))
                .frame(width: 20, height: 20)
                .foregroundStyle(settings.soundEnabled ? .primary : .tertiary)
        }
        .buttonStyle(.plain)
        .help(settings.soundEnabled ? L10n.soundOn : L10n.soundOff)
    }

    private var plainTextToggle: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { settings.alwaysPastePlainText.toggle() }
        } label: {
            Image(systemName: settings.alwaysPastePlainText ? "textformat.convert" : "textformat")
                .font(.system(size: 11, weight: settings.alwaysPastePlainText ? .semibold : .regular))
                .frame(width: 20, height: 20)
                .foregroundStyle(settings.alwaysPastePlainText ? .primary : .tertiary)
        }
        .buttonStyle(.plain)
        .help(settings.alwaysPastePlainText ? L10n.plainTextPasteOn : L10n.plainTextPasteOff)
    }
}
