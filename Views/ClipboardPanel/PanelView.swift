import AppKit
import SwiftUI

/// 从屏幕边缘弹出的剪贴板面板内容：头部（搜索/标题/Pinboard/添加/更多）+ 横向滚动卡片 + 预览浮层。
struct PanelView: View {
    @Bindable var store: ClipboardStore
    let clipboard: ClipboardService
    let clipAction: ClipActionService
    @Bindable var settings: AppSettings
    @Bindable var panelState: PanelState
    let onOpenSettings: () -> Void
    @FocusState private var searchFocused: Bool
    @FocusState private var boardFieldFocused: Bool

    /// 滚动视口内各卡片的实时位置（非观察存储：滚动中逐帧更新，但不触发重渲染）。
    @State private var frameStore = ClipFrameStore()
    /// 视口在滚动轴向上的尺寸。
    @State private var viewportExtent: CGFloat = 0
    /// 卡片滚入视口后额外露出的相邻卡片宽度（pt）。
    private let neighborPeek: CGFloat = 36
    @State private var l10nStore = L10nStore.shared
    @State private var themeStore = ThemeStore.shared
    @Environment(\.colorScheme) private var colorScheme

    private var isVertical: Bool { settings.panelPosition.isVertical }

    /// 面板背景叠色：深色主题用深蓝黑（原视觉），浅色主题用近白半透明。
    private var panelOverlayColor: Color {
        colorScheme == .dark
            ? Color(red: 0.07, green: 0.075, blue: 0.09).opacity(0.82)
            : Color(red: 0.96, green: 0.96, blue: 0.98).opacity(0.86)
    }

    var body: some View {
        let _ = l10nStore.version
        let _ = themeStore.version
        ZStack {
            VStack(spacing: 0) {
                PanelHeaderView(store: store, settings: settings, panelState: panelState, onOpenSettings: onOpenSettings, searchFocused: $searchFocused, boardFieldFocused: $boardFieldFocused)
                    .padding(.horizontal, 14).padding(.top, 14)
                    .zIndex(1)
                Group {
                    if panelState.filterGridPresented {
                        filterGridContainer
                    } else {
                        clipStrip
                    }
                }
                .padding(.top, 10)
                .padding(.bottom, 14)
            }
            .background(.ultraThinMaterial)
            .background(panelOverlayColor)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.primary.opacity(0.10), lineWidth: 1))
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.45 : 0.18), radius: 24, y: 10)

            if let item = panelState.previewItem { previewOverlay(item) }
            if let qrContent = panelState.qrCodeContent { qrCodeOverlay(qrContent) }
            if let jsonItem = panelState.jsonPreviewItem { jsonPreviewOverlay(jsonItem) }
        }
        .padding(8)
        .preferredColorScheme(themeStore.effectiveColorScheme)
        .onAppear {
            panelState.focusSearch = { searchFocused = true }
            AppIconCache.shared.warm(bundleIDs: store.filteredItems.compactMap(\.sourceApplicationBundleID))
        }
        .onChange(of: searchFocused) { _, value in panelState.searchFocused = value }
        .onChange(of: panelState.searchExpanded) { _, value in if !value { searchFocused = false } }
        .onChange(of: store.query) { _, _ in validateSelection() }
        .onChange(of: store.selectedBoardID) { _, _ in validateSelection() }
        .onChange(of: store.selectedKind) { _, _ in validateSelection() }
        .onChange(of: store.activeFilters) { _, _ in validateSelection() }
    }

    private func validateSelection() {
        let items = store.filteredItems
        if panelState.selectedID == nil || !items.contains(where: { $0.id == panelState.selectedID }) {
            panelState.selectedID = items.first?.id
        }
    }

    // MARK: Filter grid container

    /// `/` 或 filter icon 触发的分组筛选面板，替换 clip strip 区域展示。
    @ViewBuilder private var filterGridContainer: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.2)) {
                        panelState.filterGridPresented = false
                    }
                }
            FilterGridOverlay(
                store: store,
                onToggle: { store.toggleFilter($0) },
                onClear: {
                    store.query = ""
                    store.clearAllFilters()
                }
            )
            .padding(.horizontal, 6)
            .padding(.bottom, 2)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: Clip strip

    @ViewBuilder private var clipStrip: some View {
        ScrollViewReader { proxy in
            GeometryReader { geo in
                Group {
                    if store.filteredItems.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "rectangle.on.rectangle").font(.system(size: 26)).foregroundStyle(.tertiary)
                            Text(L10n.emptyState).font(.system(size: 13)).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if isVertical {
                        ScrollView(.vertical) { LazyVStack(spacing: 10) { cards(availableWidth: geo.size.width - 28) }.padding(.horizontal, 14).padding(.vertical, 2) }
                    } else {
                        ScrollView(.horizontal) { LazyHStack(spacing: 10) { cards(availableWidth: geo.size.width) }.padding(.horizontal, 14) }
                    }
                }
                .scrollIndicators(.hidden)
                .coordinateSpace(name: "clipStrip")
                .onPreferenceChange(ClipFramesKey.self) { frameStore.frames = $0 }
                .onAppear { viewportExtent = axisExtent(of: geo.size) }
                .onChange(of: geo.size) { _, size in viewportExtent = axisExtent(of: size) }
                .onChange(of: panelState.selectedID) { _, _ in scrollSelectedClipIntoView(proxy: proxy) }
            }
        }
    }

    private func axisExtent(of size: CGSize) -> CGFloat { isVertical ? size.height : size.width }

    /// 选中变化时按需滚动：
    /// - 卡片已完全可见 → 不滚动；
    /// - 卡片一侧被裁 → 滚动到刚好完全可见，并额外露出相邻卡片的一部分（neighborPeek）；
    /// - 位置未知（懒加载未布局）→ 最小滚动使其可见。
    private func scrollSelectedClipIntoView(proxy: ScrollViewProxy) {
        guard let id = panelState.selectedID else { return }
        func animated(_ action: @escaping () -> Void) {
            withAnimation(.easeInOut(duration: 0.2), action)
        }
        guard viewportExtent > 0,
              let frame = frameStore.frames[id] else {
            animated { proxy.scrollTo(id) } // anchor 为 nil：最小滚动至可见
            return
        }
        let cardStart = isVertical ? frame.minY : frame.minX
        let cardEnd = isVertical ? frame.maxY : frame.maxX
        let slack = viewportExtent - (cardEnd - cardStart)
        guard slack > 1 else { animated { proxy.scrollTo(id) }; return } // 卡片比视口还大，最小滚动兜底

        // scrollTo 的 anchor 语义：卡片自身 u 分位点与视口 u 分位点对齐。
        // 卡片头边视口坐标 = u * (viewportExtent - cardExtent)。
        let anchor: UnitPoint
        if cardEnd > viewportExtent + 0.5 {
            // 右/下侧被裁：尾边停在距视口尾边 peek 处 → 露出下一个卡片一部分
            let u = (viewportExtent - neighborPeek - (cardEnd - cardStart)) / slack
            anchor = axisPoint(min(max(u, 0), 1))
        } else if cardStart < -0.5 {
            // 左/上侧被裁：头边停在距视口头边 peek 处 → 露出前一个卡片一部分
            anchor = axisPoint(min(max(neighborPeek / slack, 0), 1))
        } else {
            return // 完全可见，不滚动
        }
        animated { proxy.scrollTo(id, anchor: anchor) }
    }

    private func axisPoint(_ u: CGFloat) -> UnitPoint {
        isVertical ? UnitPoint(x: 0.5, y: u) : UnitPoint(x: u, y: 0.5)
    }

    @ViewBuilder private func cards(availableWidth: CGFloat) -> some View {
        ForEach(store.filteredItems) { item in
            clipCard(for: item, availableWidth: availableWidth)
        }
    }

    @ViewBuilder private func clipCard(for item: Clip, availableWidth: CGFloat) -> some View {
        ClipCardView(
            item: item,
            selected: panelState.selectedID == item.id,
            renaming: panelState.renamingID == item.id,
            vertical: isVertical,
            availableWidth: availableWidth,
            targetName: panelState.targetAppName,
            boards: store.boards,
            onSelect: { panelState.selectedID = item.id },
            onPaste: { paste($0, plain: false) },
            onPastePlain: { paste($0, plain: true) },
            onCopy: { clipboard.copy($0) },
            onRename: { panelState.renamingID = $0.id },
            onRenameCommit: { id, title in store.rename(id, title: title); panelState.renamingID = nil },
            onDelete: { store.delete([$0.id]) },
            onPin: { store.move($0.id, to: $1) },
            onPreview: { item in withAnimation { panelState.previewItem = item } },
            onShowQRCode: { content in withAnimation { panelState.qrCodeContent = content } },
            onExportText: { clipAction.exportAsText($0) },
            onExportRTF: { clipAction.exportAsRTF($0) },
            onExportImage: { clipAction.exportAsImage($0) },
            onSendEmail: { clipAction.sendEmail(to: $0) },
            onPasteColorAs: { clip, format in
                clipAction.pasteColorAs(clip, format: format)
                panelState.hidePanel()
            },
            onOpenURL: { clipAction.openURL($0) },
            onPreviewJSON: { clip in withAnimation { panelState.jsonPreviewItem = clip } },
            settings: settings
        )
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: ClipFramesKey.self,
                    value: [item.id: geo.frame(in: .named("clipStrip"))]
                )
            }
        )
    }

    private func paste(_ item: Clip, plain: Bool) {
        clipboard.paste(item, plainText: plain)
        panelState.hidePanel()
    }

    // MARK: Preview overlay

    private func previewOverlay(_ item: Clip) -> some View {
        ZStack {
            Color.black.opacity(0.55).clipShape(RoundedRectangle(cornerRadius: 16))
                .onTapGesture { withAnimation { panelState.previewItem = nil } }
            VStack(spacing: 12) {
                HStack {
                    Text(item.displayTitle).font(.headline).lineLimit(1)
                    Spacer()
                    Button { withAnimation { panelState.previewItem = nil } } label: {
                        Image(systemName: "xmark.circle.fill").font(.title3)
                    }.buttonStyle(.plain).foregroundStyle(.secondary)
                }
                previewContent(item).frame(maxWidth: .infinity)
                Text(L10n.previewCloseHint).font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(18)
            .frame(maxWidth: 520, maxHeight: 380)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.primary.opacity(0.12)))
        }
        .transition(.opacity)
    }

    @ViewBuilder private func previewContent(_ item: Clip) -> some View {
        switch item.kind {
        case .text, .link:
            if let attr = item.attributedText {
                ScrollView {
                    AttributedTextView(attributedString: attr, maxLines: 0)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
            } else {
                ScrollView { Text(item.text ?? "").font(.system(size: 13)).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }
            }
        case .image:
            if let image = ImageSizeCache.shared.image(for: item) {
                Image(nsImage: image).resizable().scaledToFit()
            }
        case .file:
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(item.fileURLs ?? [], id: \.self) { Text($0.path).font(.system(size: 12)).textSelection(.enabled) }
                }
            }
        case .color:
            ZStack {
                (item.resolvedColorValue ?? item.kind.defaultColor)
                Text(item.text ?? "").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
            }
        }
    }

    // MARK: QR code overlay

    private func qrCodeOverlay(_ content: String) -> some View {
        ZStack {
            Color.black.opacity(0.55).clipShape(RoundedRectangle(cornerRadius: 16))
                .onTapGesture { withAnimation { panelState.qrCodeContent = nil } }
            QRCodeView(content: content, onClose: { withAnimation { panelState.qrCodeContent = nil } })
                .onTapGesture {} // 阻止点击浮层内容时关闭
        }
        .transition(.opacity)
    }

    // MARK: JSON preview overlay

    private func jsonPreviewOverlay(_ item: Clip) -> some View {
        ZStack {
            Color.black.opacity(0.55).clipShape(RoundedRectangle(cornerRadius: 16))
                .onTapGesture { withAnimation { panelState.jsonPreviewItem = nil } }
            JSONPreviewView(clip: item, onClose: { withAnimation { panelState.jsonPreviewItem = nil } })
                .onTapGesture {} // 阻止点击浮层内容时关闭
        }
        .transition(.opacity)
    }
}
