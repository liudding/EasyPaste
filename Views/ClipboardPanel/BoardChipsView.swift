import SwiftUI
import UniformTypeIdentifiers

/// 看板芯片行：包含全部/各看板芯片、拖拽重排、新增看板控件。
struct BoardChipsView: View {
    @Bindable var store: ClipboardStore
    @Bindable var panelState: PanelState
    @FocusState.Binding var boardFieldFocused: Bool

    @State private var draggingBoardID: UUID?
    @State private var dragTranslation: CGFloat = 0
    @State private var dragStartMinX: CGFloat = 0
    @State private var frozenChipWidths: [UUID: CGFloat] = [:]
    @State private var dragBaseMinX: CGFloat = 0
    @State private var chipFrames: [UUID: CGRect] = [:]
    private let chipSpacing: CGFloat = 8

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: chipSpacing) {
                BoardChipView(title: L10n.allBoards, color: .secondary, selected: store.selectedBoardID == nil, draggable: false, isDragging: false, onReorderDragChanged: { _ in }, onReorderDragEnded: {}) {
                    store.selectedBoardID = nil
                } onDrop: { clipID in
                    store.move(clipID, to: nil)
                }
                ForEach(store.boards) { board in
                    if panelState.editingBoardID == board.id {
                        editBoardControl(for: board)
                    } else {
                        BoardChipView(title: board.name, color: board.swiftUIColor, selected: store.selectedBoardID == board.id, draggable: true, isDragging: draggingBoardID == board.id, onReorderDragChanged: { boardDragChanged(board.id, translation: $0) }, onReorderDragEnded: boardDragEnded) {
                            store.selectedBoardID = board.id
                        } onDrop: { clipID in
                            store.move(clipID, to: board.id)
                        }
                        .overlay(BoardContextMenuOverlay(
                            board: board,
                            onEdit: {
                                panelState.editingBoardID = board.id
                                panelState.editingBoardName = board.name
                                boardFieldFocused = true
                            },
                            onDelete: {
                                if store.clipCount(for: board.id) == 0 {
                                    store.deleteBoard(board.id)
                                } else {
                                    confirmDeleteBoard(board)
                                }
                            },
                            onColorChange: { colorName in
                                store.updateBoardColor(board.id, color: colorName)
                            }
                        ))
                        .background(
                            GeometryReader { g in
                                Color.clear.preference(key: BoardFrameKey.self, value: [board.id: g.frame(in: .named("boardSpace"))])
                            }
                        )
                    }
                }
                addBoardControl
            }
            .padding(.horizontal, 2)
            .coordinateSpace(name: "boardSpace")
            .onPreferenceChange(BoardFrameKey.self) { if draggingBoardID == nil { chipFrames = $0 } }
            .overlay(alignment: .topLeading) {
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

    // MARK: Delete Board Confirmation

    /// 弹出 AppKit NSAlert 确认删除看板（NSPanel 内 SwiftUI .alert 会导致面板无法弹出）。
    private func confirmDeleteBoard(_ board: Pasteboard) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(format: L10n.deleteBoardTitle, board.name)
        alert.informativeText = L10n.deleteBoardMessage
        alert.addButton(withTitle: L10n.cancel)
        alert.addButton(withTitle: L10n.deleteBoardOnly)
        alert.addButton(withTitle: L10n.deleteBoardAll)

        // 按钮顺序：Cancel(0), Board Only(1), Delete All(2)
        alert.buttons[1].keyEquivalent = ""
        alert.buttons[2].keyEquivalent = ""
        alert.buttons[2].hasDestructiveAction = true

        let response = alert.runModal()
        switch response {
        case .alertSecondButtonReturn: // Delete Board Only
            store.deleteBoard(board.id)
        case .alertThirdButtonReturn: // Delete All
            store.deleteBoardAndClips(board.id)
        default: // Cancel
            break
        }
    }

    // MARK: Edit Board

    @ViewBuilder private func editBoardControl(for board: Pasteboard) -> some View {
        HStack(spacing: 6) {
            TextField(L10n.newBoardPlaceholder, text: $panelState.editingBoardName)
                .textFieldStyle(.plain).font(.system(size: 12))
                .frame(width: 90).focused($boardFieldFocused)
                .onSubmit(commitEditBoard)
            ForEach(Pasteboard.palette, id: \.self) { name in
                Button { store.updateBoardColor(board.id, color: name) } label: {
                    Circle().fill(Pasteboard(name: "", color: name).swiftUIColor).frame(width: 12, height: 12)
                        .overlay(Circle().stroke(.white, lineWidth: board.color == name ? 1.5 : 0))
                }.buttonStyle(.plain)
            }
            Button(action: commitEditBoard) {
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
    }

    private func commitEditBoard() {
        if let boardID = panelState.editingBoardID {
            let name = panelState.editingBoardName.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty {
                store.renameBoard(boardID, to: name)
            }
        }
        panelState.editingBoardName = ""
        panelState.editingBoardID = nil
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
}

// MARK: - Private Helpers

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
    let draggable: Bool
    let isDragging: Bool
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
                    if isDragging {
                        Capsule()
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .foregroundStyle(.primary.opacity(0.35))
                    }
                }
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

// MARK: - Board Context Menu (AppKit)

/// 看板芯片右键菜单：用 AppKit NSMenu 实现横向颜色选择区。
/// overlay 视图仅捕获 rightMouseDown，其他事件透传给下层 SwiftUI。
private struct BoardContextMenuOverlay: NSViewRepresentable {
    let board: Pasteboard
    var onEdit: () -> Void
    var onDelete: () -> Void
    var onColorChange: (String) -> Void

    func makeNSView(context: Context) -> RightClickCaptureView {
        let view = RightClickCaptureView()
        view.configure(board: board, onEdit: onEdit, onDelete: onDelete, onColorChange: onColorChange)
        return view
    }

    func updateNSView(_ nsView: RightClickCaptureView, context: Context) {
        nsView.configure(board: board, onEdit: onEdit, onDelete: onDelete, onColorChange: onColorChange)
    }

    final class RightClickCaptureView: NSView {
        var board: Pasteboard?
        var onEdit: (() -> Void)?
        var onDelete: (() -> Void)?
        var onColorChange: ((String) -> Void)?
        /// 当前正在显示的菜单引用（用于色板点击后关闭菜单）。
        weak var currentMenu: NSMenu?

        func configure(board: Pasteboard, onEdit: @escaping () -> Void, onDelete: @escaping () -> Void, onColorChange: @escaping (String) -> Void) {
            self.board = board
            self.onEdit = onEdit
            self.onDelete = onDelete
            self.onColorChange = onColorChange
        }

        /// 仅在右键按下时捕获事件，其余事件透传给下层 SwiftUI。
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard NSApp.currentEvent?.type == .rightMouseDown else { return nil }
            return super.hitTest(point)
        }

        override func rightMouseDown(with event: NSEvent) {
            guard let board = board else { return }
            let menu = buildMenu(for: board)
            // 弹出后阻塞，直到用户选择或点击外部。色板点击需手动关闭菜单。
            currentMenu = menu
            NSMenu.popUpContextMenu(menu, with: event, for: self)
            currentMenu = nil
        }

        private func buildMenu(for board: Pasteboard) -> NSMenu {
            let menu = NSMenu()

            // Edit
            let editItem = NSMenuItem(title: L10n.rename, action: #selector(editAction), keyEquivalent: "")
            editItem.target = self
            menu.addItem(editItem)

            menu.addItem(.separator())

            // Color label (section header)
            let labelItem = NSMenuItem(title: L10n.boardColor, action: nil, keyEquivalent: "")
            labelItem.isEnabled = false
            menu.addItem(labelItem)

            // Horizontal color swatches
            let swatchItem = NSMenuItem()
            swatchItem.view = makeColorSwatches(for: board)
            menu.addItem(swatchItem)

            menu.addItem(.separator())

            // Delete (red)
            let deleteItem = NSMenuItem(title: L10n.delete, action: #selector(deleteAction), keyEquivalent: "")
            deleteItem.target = self
            let attrs: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.systemRed]
            deleteItem.attributedTitle = NSAttributedString(string: L10n.delete, attributes: attrs)
            menu.addItem(deleteItem)

            return menu
        }

        /// 横向排列的彩色圆点：点击切换颜色，当前选中色显示白色描边。样式与新增时一致。
        private func makeColorSwatches(for board: Pasteboard) -> NSView {
            let row = ColorSwatchRowView(frame: NSRect(x: 0, y: 0, width: 220, height: 22))
            row.selectedColor = board.color
            row.onSelect = { [weak self] colorName in
                self?.onColorChange?(colorName)
                self?.currentMenu?.cancelTracking()
            }
            return row
        }

        @objc func editAction() { onEdit?() }
        @objc func deleteAction() { onDelete?() }
    }
}

/// 横向彩色圆点行：在单个 NSView 内 draw 8 个色块 + 选中态描边，命中测试在 mouseDown 中处理。
/// 使用单一视图而非 NSStackView，避免 NSMenuItem 上下文里 Auto Layout 尺寸为 0 导致不可见的问题。
final class ColorSwatchRowView: NSView {
    var selectedColor: String = "" {
        didSet { needsDisplay = true }
    }
    var onSelect: ((String) -> Void)?

    private let swatchSize: CGFloat = 14
    private let spacing: CGFloat = 8
    private let leftInset: CGFloat = 18
    private let swatches = Pasteboard.palette
    private var hitRects: [(String, NSRect)] = []

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        hitRects.removeAll()
        var x: CGFloat = leftInset
        let y: CGFloat = (bounds.height - swatchSize) / 2
        for colorName in swatches {
            let rect = NSRect(x: x, y: y, width: swatchSize, height: swatchSize)
            hitRects.append((colorName, rect))

            let color = nsColor(for: colorName)
            color.setFill()
            NSBezierPath(ovalIn: rect).fill()

            if selectedColor == colorName {
                NSColor.white.setStroke()
                let ring = NSBezierPath(ovalIn: rect.insetBy(dx: -1.5, dy: -1.5))
                ring.lineWidth = 1.5
                ring.stroke()
            }
            x += swatchSize + spacing
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        for (colorName, rect) in hitRects where rect.contains(p) {
            onSelect?(colorName)
            return
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // 扩展命中区到整个视图，让色块之间的间隙也能点击（不会穿透到菜单关闭）
        for (_, rect) in hitRects where rect.insetBy(dx: -spacing / 2, dy: -2).contains(point) {
            return self
        }
        return nil
    }

    private func nsColor(for name: String) -> NSColor {
        switch name {
        case "blue": return .systemBlue
        case "purple": return .systemPurple
        case "green": return .systemGreen
        case "red": return .systemRed
        case "yellow": return .systemYellow
        case "pink": return .systemPink
        case "teal": return .systemTeal
        default: return .systemOrange
        }
    }
}
