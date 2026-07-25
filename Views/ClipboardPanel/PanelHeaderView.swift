import SwiftUI
import UniformTypeIdentifiers

/// 剪贴板面板头部：搜索、标题、看板芯片、快速设置、更多菜单。
struct PanelHeaderView: View {
    @Bindable var store: ClipboardStore
    @Bindable var settings: AppSettings
    @Bindable var panelState: PanelState
    let onOpenSettings: () -> Void
    @FocusState.Binding var searchFocused: Bool
    @FocusState.Binding var boardFieldFocused: Bool

    /// 正在被手势拖拽重排的看板 id（nil 表示没有）。
    @State private var draggingBoardID: UUID?
    /// 拖拽手势的实时水平位移（驱动浮动克隆层）。
    @State private var dragTranslation: CGFloat = 0
    /// 拖拽起始时被拖芯片在 `boardSpace` 下的 minX（克隆层锚点 + 插入位计算基准）。
    @State private var dragStartMinX: CGFloat = 0
    /// 拖拽期间冻结的各芯片宽度。插入位推导只用「当前顺序 + 冻结宽度」——
    /// 让位动画中 GeometryReader 上报的是插值 frame，直接拿来算中点会来回抖动。
    @State private var frozenChipWidths: [UUID: CGFloat] = [:]
    /// 最左芯片槽位的 minX（重排不变量：无论哪个芯片占据该槽位，其起始 x 相同）。
    @State private var dragBaseMinX: CGFloat = 0
    /// 各看板芯片在 `boardSpace` 坐标系下的框（拖拽期间冻结，松手后恢复更新）。
    @State private var chipFrames: [UUID: CGRect] = [:]
    /// 芯片间距（与下方 HStack spacing 同源，供重排布局推导）。
    private let chipSpacing: CGFloat = 8
    @State private var l10nStore = L10nStore.shared

    private var isVertical: Bool { settings.panelPosition.isVertical }

    private var headerTitle: String {
        store.selectedBoardID.flatMap { id in store.boards.first { $0.id == id }?.name } ?? L10n.clipboardTitle
    }

    var body: some View {
        let _ = l10nStore.version
        if isVertical {
            // 竖直方向（左/右停靠）：顶部搜索 + 右侧设置，下方看板芯片
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    searchControlVertical
                    quickSettingsInline
                    moreMenu
                }
                .frame(height: 30)
                boardChips
            }
        } else {
            HStack(spacing: 10) {
                searchControl
                Rectangle().fill(.primary.opacity(0.12)).frame(width: 1, height: 18)
                boardChips
                Spacer()
                quickSettingsInline
                moreMenu
            }
            .frame(height: 30)
        }
    }

    // MARK: Search

    @ViewBuilder private var searchControl: some View {
        if panelState.searchExpanded {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(.secondary)
                TextField(L10n.searchPlaceholder, text: $store.query)
                    .textFieldStyle(.plain).font(.system(size: 13))
                    .focused($searchFocused).frame(width: 170)
                    .focusEffectDisabled()
                if !store.query.isEmpty {
                    Button { store.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.primary.opacity(0.09), in: Capsule())
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
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(.secondary)
            TextField(L10n.searchPlaceholder, text: $store.query)
                .textFieldStyle(.plain).font(.system(size: 13))
                .focused($searchFocused)
                .focusEffectDisabled()
            if !store.query.isEmpty {
                Button { store.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.primary.opacity(0.09), in: Capsule())
    }

    // MARK: Board Chips

    private var boardChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: chipSpacing) {
                BoardChipView(title: L10n.allBoards, color: .secondary, selected: store.selectedBoardID == nil, draggable: false, isDragging: false, onReorderDragChanged: { _ in }, onReorderDragEnded: {}) {
                    store.selectedBoardID = nil
                } onDrop: { clipID in
                    store.move(clipID, to: nil)
                }
                ForEach(store.boards) { board in
                    BoardChipView(title: board.name, color: board.swiftUIColor, selected: store.selectedBoardID == board.id, draggable: true, isDragging: draggingBoardID == board.id, onReorderDragChanged: { boardDragChanged(board.id, translation: $0) }, onReorderDragEnded: boardDragEnded) {
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
            .onPreferenceChange(BoardFrameKey.self) { if draggingBoardID == nil { chipFrames = $0 } }
            .overlay(alignment: .topLeading) {
                // 浮动克隆层：被拖芯片的"本体"跟随手指，列表中只留下虚线间隙占位，
                // 其余芯片实时让位——列表级重排，而非"投进另一个芯片"。
                if let id = draggingBoardID, let board = store.boards.first(where: { $0.id == id }) {
                    BoardChipLabel(title: board.name, color: board.swiftUIColor, selected: store.selectedBoardID == id)
                        .scaleEffect(1.06)
                        .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
                        .offset(x: dragStartMinX + dragTranslation)
                }
            }
        }
        .scrollClipDisabled()
        .scrollIndicators(.hidden)
    }

    /// 看板拖拽重排：克隆层跟随手指平移；插入间隔位（gap）用「当前顺序 + 冻结宽度」推导出的
    /// 静止槽位中点计算，克隆层相关状态显式禁用动画——两者共同消除让位抖动与跟手偏移。
    private func boardDragChanged(_ boardID: UUID, translation: CGFloat) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if draggingBoardID != boardID {
                draggingBoardID = boardID
                dragStartMinX = chipFrames[boardID]?.minX ?? 0
                frozenChipWidths = chipFrames.mapValues(\.width)
                dragBaseMinX = chipFrames.values.map(\.minX).min() ?? 0
            }
            dragTranslation = translation
        }
        let center = dragStartMinX + (frozenChipWidths[boardID] ?? 0) / 2 + translation
        var gap = 0
        var x = dragBaseMinX
        for board in store.boards {
            let width = frozenChipWidths[board.id] ?? 0
            if board.id != boardID, x + width / 2 < center { gap += 1 }
            x += width + chipSpacing
        }
        store.moveBoardToGap(boardID, gap: gap)
    }

    /// 松手提交：顺序已在拖拽过程中实时落定，此处统一写库一次并清理拖拽态。
    private func boardDragEnded() {
        store.persistBoardOrder()
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            draggingBoardID = nil
            dragTranslation = 0
            dragStartMinX = 0
            frozenChipWidths = [:]
            dragBaseMinX = 0
        }
    }

    private struct BoardFrameKey: PreferenceKey {
        static var defaultValue: [UUID: CGRect] { [:] }
        static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
            value.merge(nextValue()) { _, new in new }
        }
    }

    /// 芯片纯视觉（圆点 + 标题的胶囊），供列表芯片与拖拽浮动克隆层共用。
    private struct BoardChipLabel: View {
        let title: String
        let color: Color
        let selected: Bool
        var highlighted: Bool = false

        var body: some View {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(selected ? color.opacity(0.28) : (highlighted ? color.opacity(0.18) : .primary.opacity(0.07)))
            )
            .overlay(Capsule().stroke(selected ? color.opacity(0.8) : (highlighted ? color.opacity(0.5) : .clear), lineWidth: 1))
            .foregroundStyle(selected ? .white : (highlighted ? .primary : .secondary))
        }
    }

    private struct BoardChipView: View {
        let title: String
        let color: Color
        let selected: Bool
        /// 是否可手势拖拽重排（“全部”等元芯片为 false）。
        let draggable: Bool
        /// 是否正被拖拽（列表中显示为半透明占位，本体由父视图的克隆层呈现）。
        let isDragging: Bool
        /// 拖拽手势位移回调（水平分量）。
        let onReorderDragChanged: (CGFloat) -> Void
        let onReorderDragEnded: () -> Void
        let action: () -> Void
        let onDrop: (UUID) -> Void

        @State private var isTargeted = false
        @State private var dropBounce = false

        var body: some View {
            let chip = BoardChipLabel(title: title, color: color, selected: selected, highlighted: isTargeted)
                .contentShape(Capsule())
                .onTapGesture { action() }
                .scaleEffect(isTargeted ? 1.05 : (dropBounce ? 1.15 : 1.0))
                .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isTargeted)
                .animation(.spring(response: 0.3, dampingFraction: 0.5), value: dropBounce)
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

            if draggable {
                chip
                    .opacity(isDragging ? 0 : 1)
                    .background {
                        // 拖拽中原位只留"插入间隙"虚线胶囊，本体由父视图克隆层呈现；
                        // 占位与克隆层不同款，避免"芯片从鼠标位置偏移走"的视觉错觉。
                        if isDragging {
                            Capsule()
                                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                .foregroundStyle(.primary.opacity(0.35))
                        }
                    }
                    // 列表级重排手势：minimumDistance 保证点按选中不受影响；
                    // 位移超过阈值后手势优先于 TapGesture，松手不会误触选中。
                    .gesture(
                        DragGesture(minimumDistance: 4)
                            .onChanged { onReorderDragChanged($0.translation.width) }
                            .onEnded { _ in onReorderDragEnded() }
                    )
            } else {
                chip
            }
        }
    }

    /// 芯片背后的 AppKit 落点视图：承接「clip 拖到看板换板」。
    /// 看板重排不走这里——它由芯片上的 DragGesture 驱动（列表级排序，见 BoardChipView）。
    private struct BoardChipDropZone: NSViewRepresentable {
        var onTargeted: (Bool) -> Void
        var onDrop: (UUID) -> Void

        func makeNSView(context: Context) -> DroppableView {
            let view = DroppableView()
            view.onTargeted = onTargeted
            view.onDrop = onDrop
            return view
        }

        func updateNSView(_ nsView: DroppableView, context: Context) {
            nsView.onTargeted = onTargeted
            nsView.onDrop = onDrop
        }

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

    // MARK: Add Board

    @ViewBuilder private var addBoardControl: some View {
        if panelState.addingBoard {
            HStack(spacing: 6) {
                TextField(L10n.newBoardPlaceholder, text: $panelState.newBoardName)
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
                    Label(L10n.addBoardConfirm, systemImage: "checkmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(.primary.opacity(0.16)))
                        .overlay(Capsule().stroke(.primary.opacity(0.28), lineWidth: 0.5))
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(.primary.opacity(0.09), in: Capsule())
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
