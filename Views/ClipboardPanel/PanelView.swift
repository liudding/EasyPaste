import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 从屏幕边缘弹出的剪贴板面板内容：头部（搜索/标题/Pinboard/添加/更多）+ 横向滚动卡片 + 预览浮层。
struct PanelView: View {
    @Bindable var store: ClipboardStore
    let clipboard: ClipboardService
    @Bindable var settings: AppSettings
    @Bindable var panelState: PanelState
    let onOpenSettings: () -> Void
    @FocusState private var searchFocused: Bool
    @FocusState private var boardFieldFocused: Bool

    /// 滚动视口内各卡片的实时位置（非观察存储：滚动中逐帧更新，但不触发重渲染）。
    @State private var frameStore = ClipFrameStore()
    /// 视口在滚动轴向上的尺寸。
    @State private var viewportExtent: CGFloat = 0
    /// 当前正在被拖拽重排的看板 id（nil 表示没有）。
    @State private var draggingBoardID: UUID?
    /// 各看板芯片在 `boardSpace` 坐标系下的实时框（id -> rect），用于计算拖拽落点插入位置。
    @State private var chipFrames: [UUID: CGRect] = [:]
    /// 卡片滚入视口后额外露出的相邻卡片宽度（pt）。
    private let neighborPeek: CGFloat = 36

    private var isVertical: Bool { settings.panelPosition.isVertical }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 14).padding(.top, 14)
                clipStrip
                    .padding(.top, 10)
                    .padding(.bottom, 14)
            }
            .background(.ultraThinMaterial)
            .background(Color(red: 0.07, green: 0.075, blue: 0.09).opacity(0.82))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.10), lineWidth: 1))
            .shadow(color: .black.opacity(0.45), radius: 24, y: 10)

            if let item = panelState.previewItem { previewOverlay(item) }
        }
        .padding(8)
        .preferredColorScheme(.dark)
        .onAppear {
            panelState.focusSearch = { searchFocused = true }
            // 后台预热来源 app 图标/主色调，避免首张卡片渲染时主线程解码
            AppIconCache.shared.warm(bundleIDs: store.filteredItems.compactMap(\.sourceApplicationBundleID))
        }
        .onChange(of: searchFocused) { _, value in panelState.searchFocused = value }
        .onChange(of: panelState.searchExpanded) { _, value in if !value { searchFocused = false } }
        .onChange(of: store.query) { _, _ in validateSelection() }
        .onChange(of: store.selectedBoardID) { _, _ in validateSelection() }
        .onChange(of: store.selectedKind) { _, _ in validateSelection() }
    }

    /// 检查当前选中项是否仍在过滤结果中，不在则选第一个。
    private func validateSelection() {
        let items = store.filteredItems
        if panelState.selectedID == nil || !items.contains(where: { $0.id == panelState.selectedID }) {
            panelState.selectedID = items.first?.id
        }
    }

    // MARK: Header

    private var headerTitle: String {
        store.selectedBoardID.flatMap { id in store.boards.first { $0.id == id }?.name } ?? "剪切板"
    }

    private var header: some View {
        HStack(spacing: 10) {
            searchControl
            Text(headerTitle).font(.system(size: 15, weight: .bold)).lineLimit(1).fixedSize()
            Rectangle().fill(.white.opacity(0.12)).frame(width: 1, height: 18)
            boardChips
            Spacer()
            quickSettingsInline
            moreMenu
        }
        .frame(height: 30)
    }

    @ViewBuilder private var searchControl: some View {
        if panelState.searchExpanded {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(.secondary)
                TextField("搜索剪贴板", text: $store.query)
                    .textFieldStyle(.plain).font(.system(size: 13))
                    .focused($searchFocused).frame(width: 170)
                if !store.query.isEmpty {
                    Button { store.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.white.opacity(0.09), in: Capsule())
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
        }
    }

    private var boardChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                BoardChipView(title: "全部", color: .secondary, selected: store.selectedBoardID == nil, store: store, boardID: nil, draggingID: draggingBoardID, onDragStart: { _ in }) {
                    store.selectedBoardID = nil
                } onDrop: { clipID in
                    store.move(clipID, to: nil)
                }
                ForEach(store.boards) { board in
                    BoardChipView(title: board.name, color: board.swiftUIColor, selected: store.selectedBoardID == board.id, store: store, boardID: board.id, draggingID: draggingBoardID, onDragStart: { draggingBoardID = $0 }) {
                        store.selectedBoardID = board.id
                    } onDrop: { clipID in
                        store.move(clipID, to: board.id)
                    }
                    .background(
                        GeometryReader { g in
                            Color.clear.preference(key: BoardFrameKey.self, value: [board.id: g.frame(in: .named("boardSpace"))])
                        }
                    )
                }
                addBoardControl
            }
            .padding(.horizontal, 2)
            .coordinateSpace(name: "boardSpace")
            .onDrop(of: [UTType.easypasteBoard.identifier], delegate: BoardReorderDelegate(store: store, frames: $chipFrames, draggingID: $draggingBoardID))
            .onPreferenceChange(BoardFrameKey.self) { chipFrames = $0 }
        }
        .scrollClipDisabled()
        .scrollIndicators(.hidden)
    }

    private struct BoardChipView: View {
        let title: String
        let color: Color
        let selected: Bool
        let store: ClipboardStore
        /// 看板 id；nil 表示不可重排的元芯片（如“全部”）。
        let boardID: UUID?
        /// 当前正在拖拽的看板 id（用于把源芯片半透明化）。
        let draggingID: UUID?
        /// 拖拽开始回调，用于把源 id 写入父视图的 `draggingBoardID`。
        let onDragStart: (UUID) -> Void
        let action: () -> Void
        let onDrop: (UUID) -> Void

        @State private var isTargeted = false
        @State private var dropBounce = false

        var body: some View {
            let chip = HStack(spacing: 5) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(selected ? color.opacity(0.28) : (isTargeted ? color.opacity(0.18) : .white.opacity(0.07)))
            )
            .overlay(Capsule().stroke(selected ? color.opacity(0.8) : (isTargeted ? color.opacity(0.5) : .clear), lineWidth: 1))
            .foregroundStyle(selected ? .white : (isTargeted ? .primary : .secondary))
            .contentShape(Capsule())
            .onTapGesture { action() }
            .scaleEffect(isTargeted ? 1.05 : (dropBounce ? 1.15 : 1.0))
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isTargeted)
            .animation(.spring(response: 0.3, dampingFraction: 0.5), value: dropBounce)
            .opacity(boardID != nil && boardID == draggingID ? 0.4 : 1.0)
            .background(
                BoardChipDropZone(onTargeted: { targeted in
                    isTargeted = targeted
                }, onDrop: { clipID in
                    dropBounce = true
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.5).delay(0.1)) {
                        dropBounce = false
                    }
                    onDrop(clipID)
                })
            )

            if let boardID {
                chip
                    .onDrag {
                        onDragStart(boardID)
                        let provider = NSItemProvider()
                        provider.registerDataRepresentation(forTypeIdentifier: UTType.easypasteBoard.identifier, visibility: .ownProcess) { completion in
                            completion(boardID.uuidString.data(using: .utf8), nil)
                            return nil
                        }
                        return provider
                    }
            } else {
                chip
            }
        }
    }

    /// 看板芯片拖拽重排的落点框收集（id -> 在 `boardSpace` 坐标系下的 rect）。
    private struct BoardFrameKey: PreferenceKey {
        static var defaultValue: [UUID: CGRect] { [:] }
        static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
            value.merge(nextValue()) { _, new in new }
        }
    }

    /// 看板拖拽重排的容器级拖放代理：根据拖拽落点相对各芯片中点的位置，实时把被拖看板插到对应槽位，
    /// 让其它芯片“让位”（带动画），并在每次实际换位时落库。
    private struct BoardReorderDelegate: DropDelegate {
        let store: ClipboardStore
        @Binding var frames: [UUID: CGRect]
        @Binding var draggingID: UUID?

        func validateDrop(info: DropInfo) -> Bool {
            info.hasItemsConforming(to: [UTType.easypasteBoard.identifier])
        }

        func dropUpdated(info: DropInfo) -> DropProposal {
            guard let drag = draggingID, let idx = insertionIndex(info: info) else {
                return DropProposal(operation: .move)
            }
            if store.reorderBoardLive(drag, to: idx) {
                store.persistBoardOrder()
            }
            return DropProposal(operation: .move)
        }

        func performDrop(info: DropInfo) -> Bool {
            draggingID = nil
            return true
        }

        func dropExited(info: DropInfo) {
            draggingID = nil
        }

        /// 落点 x 小于某个芯片中点时，插入到该芯片之前；否则追加到末尾。
        private func insertionIndex(info: DropInfo) -> Int? {
            let x = info.location.x
            let sorted = frames.sorted { $0.value.midX < $1.value.midX }
            for (i, (_, rect)) in sorted.enumerated() {
                if x < rect.midX { return i }
            }
            return sorted.count
        }
    }

    private struct BoardChipDropZone: NSViewRepresentable {
        var onTargeted: (Bool) -> Void
        var onDrop: (UUID) -> Void 

        func makeNSView(context: Context) -> DroppableView {
            let view = DroppableView()
            view.onTargeted = onTargeted
            view.onDrop = onDrop
            return view
        }
        
        func updateNSView(_ nsView: DroppableView, context: Context) {}

        class DroppableView: NSView {
            var onTargeted: (Bool) -> Void = { _ in }
            var onDrop: (UUID) -> Void = { _ in }
            var originalFrames: [Int: NSRect] = [:]

            override init(frame: NSRect) {
                super.init(frame: frame)
                registerForDraggedTypes([NSPasteboard.PasteboardType(UTType.easypasteClip.identifier)])
            }
            required init?(coder: NSCoder) { fatalError() }

            override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
                onTargeted(true)
                originalFrames.removeAll()
                
                sender.enumerateDraggingItems(options: [], for: nil, classes: [NSPasteboardItem.self], searchOptions: [:]) { draggingItem, idx, stop in
                    let currentFrame = draggingItem.draggingFrame
                    self.originalFrames[idx] = currentFrame
                    
                    let scale: CGFloat = 0.5
                    let newWidth = currentFrame.width * scale
                    let newHeight = currentFrame.height * scale
                    let offsetX = (currentFrame.width - newWidth) / 2
                    let offsetY = (currentFrame.height - newHeight) / 2
                    let newFrame = NSRect(x: currentFrame.origin.x + offsetX, y: currentFrame.origin.y + offsetY, width: newWidth, height: newHeight)
                    
                    if let firstComp = draggingItem.imageComponents?.first {
                        draggingItem.setDraggingFrame(newFrame, contents: firstComp.contents)
                    }
                }
                return .copy
            }
            
            override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
                return .copy 
            }
            
            override func draggingExited(_ sender: NSDraggingInfo?) {
                onTargeted(false)
                guard let sender = sender else { return }
                
                sender.enumerateDraggingItems(options: [], for: nil, classes: [NSPasteboardItem.self], searchOptions: [:]) { draggingItem, idx, stop in
                    if let origFrame = self.originalFrames[idx] {
                        draggingItem.setDraggingFrame(origFrame, contents: draggingItem.imageComponents?.first?.contents)
                    }
                }
                originalFrames.removeAll()
            }
            
            override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
                onTargeted(false)
                guard let item = sender.draggingPasteboard.pasteboardItems?.first else { return false }
                
                if let data = item.data(forType: NSPasteboard.PasteboardType(UTType.easypasteClip.identifier)) {
                    if let payload = try? JSONDecoder().decode(ClipDragPayload.self, from: data) {
                        onDrop(payload.id)
                        sender.animatesToDestination = true
                        return true
                    }
                }
                return false
            }
        }
    }

    @ViewBuilder private var addBoardControl: some View {
        if panelState.addingBoard {
            HStack(spacing: 6) {
                TextField("新 Pinboard", text: $panelState.newBoardName)
                    .textFieldStyle(.plain).font(.system(size: 12))
                    .frame(width: 90).focused($boardFieldFocused)
                    .onSubmit(commitNewBoard)
                ForEach(Pasteboard.palette, id: \.self) { name in
                    Button { panelState.newBoardColor = name } label: {
                        Circle().fill(Pasteboard(name: "", color: name).swiftUIColor).frame(width: 12, height: 12)
                            .overlay(Circle().stroke(.white, lineWidth: panelState.newBoardColor == name ? 1.5 : 0))
                    }.buttonStyle(.plain)
                }
                Button(action: commitNewBoard) {
                    Label("确定", systemImage: "checkmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(.white.opacity(0.16)))
                        .overlay(Capsule().stroke(.white.opacity(0.28), lineWidth: 0.5))
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(.white.opacity(0.09), in: Capsule())
        } else {
            Button {
                panelState.addingBoard = true
                boardFieldFocused = true
            } label: {
                Image(systemName: "plus").font(.system(size: 12, weight: .bold)).frame(width: 24, height: 24).contentShape(.rect)
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
        }
    }

    private func commitNewBoard() {
        let name = panelState.newBoardName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { panelState.addingBoard = false; return }
        store.addBoard(named: name, color: panelState.newBoardColor)
        panelState.newBoardName = ""
        panelState.addingBoard = false
    }

    private var moreMenu: some View {
        Menu {
            Button("关于 EasyPaste") { AboutPresenter.show() }
            Button("设置…") { openSettingsWindow() }
            Divider()
            Button("退出 EasyPaste") { NSApp.terminate(nil) }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 13, weight: .bold))
                .frame(width: 34, height: 34).contentShape(.rect)
        }
        .menuIndicator(.hidden)
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func openSettingsWindow() {
        // 隐藏面板交由 PanelController 处理（forceHidePanel），确保浮动面板不会遮挡设置窗口。
        onOpenSettings()
    }

    // MARK: Quick Settings Inline (in header, left of moreMenu)

    private var quickSettingsInline: some View {
        HStack(spacing: 2) {
            // Sound toggle
            soundToggle
            // Plain text toggle
            plainTextToggle
            // Position group
            positionGroup
        }
        .frame(height: 24)
    }

    @ViewBuilder
    private var positionGroup: some View {
        Rectangle().fill(.white.opacity(0.12)).frame(width: 1, height: 14)
        HStack(spacing: 1) {
            positionButton(.top, icon: "inset.filled.tophalf.rectangle")
            positionButton(.left, icon: "inset.filled.lefthalf.rectangle")
            positionButton(.right, icon: "inset.filled.righthalf.rectangle")
            positionButton(.bottom, icon: "inset.filled.bottomhalf.rectangle")
        }
        .background(.white.opacity(0.07), in: Capsule())
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
        .help(settings.soundEnabled ? "音效已开启" : "音效已关闭")
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
        .help(settings.alwaysPastePlainText ? "纯文本粘贴已开启" : "纯文本粘贴已关闭")
    }

    // MARK: Clip strip

    @ViewBuilder private var clipStrip: some View {
        ScrollViewReader { proxy in
            GeometryReader { geo in
                Group {
                    if store.filteredItems.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "rectangle.on.rectangle").font(.system(size: 26)).foregroundStyle(.tertiary)
                            Text("暂无剪贴内容").font(.system(size: 13)).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if isVertical {
                        ScrollView(.vertical) { LazyVStack(spacing: 10) { cards(availableWidth: geo.size.width) }.padding(.vertical, 2) }
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
            onPreview: { item in withAnimation { panelState.previewItem = item } }
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
                Text("空格 / Esc 关闭").font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(18)
            .frame(maxWidth: 520, maxHeight: 380)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.12)))
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
}
