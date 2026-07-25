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

    @State private var draggingBoardID: UUID?
    @State private var chipFrames: [UUID: CGRect] = [:]

    private var headerTitle: String {
        store.selectedBoardID.flatMap { id in store.boards.first { $0.id == id }?.name } ?? "剪切板"
    }

    var body: some View {
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

    // MARK: Search

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

    // MARK: Board Chips

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
        let boardID: UUID?
        let draggingID: UUID?
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

    private struct BoardFrameKey: PreferenceKey {
        static var defaultValue: [UUID: CGRect] { [:] }
        static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
            value.merge(nextValue()) { _, new in new }
        }
    }

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

    // MARK: Add Board

    @ViewBuilder private var addBoardControl: some View {
        if panelState.addingBoard {
            HStack(spacing: 6) {
                TextField("新 Board", text: $panelState.newBoardName)
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

    // MARK: More Menu

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
}
