import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 从屏幕边缘弹出的剪贴板面板内容：头部（搜索/标题/Pinboard/添加/更多）+ 横向滚动卡片 + 预览浮层。
struct PanelView: View {
    @Bindable var store: ClipboardStore
    let clipboard: ClipboardService
    @Bindable var settings: AppSettings
    @Bindable var panelState: PanelState
    @FocusState private var searchFocused: Bool
    @FocusState private var boardFieldFocused: Bool

    private var isVertical: Bool { settings.panelPosition.isVertical }

    var body: some View {
        ZStack {
            VStack(spacing: 12) {
                header
                clipStrip
            }
            .padding(14)
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
        }
        .onChange(of: searchFocused) { _, value in panelState.searchFocused = value }
        .onChange(of: panelState.searchExpanded) { _, value in if !value { searchFocused = false } }
        .onChange(of: store.filteredItems.map(\.id)) { _, ids in
            if panelState.selectedID == nil || !ids.contains(panelState.selectedID!) { panelState.selectedID = ids.first }
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
                boardChip(title: "全部", color: .secondary, selected: store.selectedBoardID == nil) { store.selectedBoardID = nil }
                    .dropDestination(for: ClipDragPayload.self) { payloads, _ in
                        if let p = payloads.first { store.move(p.id, to: nil) }
                        return true
                    }
                ForEach(store.boards) { board in
                    boardChip(title: board.name, color: board.swiftUIColor, selected: store.selectedBoardID == board.id) {
                        store.selectedBoardID = board.id
                    }
                    .dropDestination(for: ClipDragPayload.self) { payloads, _ in
                        if let p = payloads.first { store.move(p.id, to: board.id) }
                        return true
                    }
                }
                addBoardControl
            }
            .padding(.horizontal, 2)
        }
        .scrollIndicators(.hidden)
    }

    private func boardChip(title: String, color: Color, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(selected ? color.opacity(0.28) : .white.opacity(0.07), in: Capsule())
            .overlay(Capsule().stroke(selected ? color.opacity(0.8) : .clear, lineWidth: 1))
            .foregroundStyle(selected ? .white : .secondary)
        }
        .buttonStyle(.plain)
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
                Button(action: commitNewBoard) { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }.buttonStyle(.plain)
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
                .frame(width: 28, height: 28).contentShape(.rect)
        }
        .menuIndicator(.hidden)
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func openSettingsWindow() {
        panelState.hidePanel()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            if !NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
                NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
            }
        }
    }

    // MARK: Clip strip

    @ViewBuilder private var clipStrip: some View {
        ScrollViewReader { proxy in
            Group {
                if store.filteredItems.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "rectangle.on.rectangle").font(.system(size: 26)).foregroundStyle(.tertiary)
                        Text("暂无剪贴内容").font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if isVertical {
                    ScrollView(.vertical) { LazyVStack(spacing: 10) { cards }.padding(.vertical, 2) }
                } else {
                    ScrollView(.horizontal) { LazyHStack(spacing: 10) { cards }.padding(.vertical, 2) }
                }
            }
            .scrollIndicators(.hidden)
            .onChange(of: panelState.selectedID) { _, id in
                if let id { withAnimation { proxy.scrollTo(id, anchor: .center) } }
            }
        }
    }

    @ViewBuilder private var cards: some View {
        ForEach(store.filteredItems) { item in
            clipCard(for: item)
        }
    }

    @ViewBuilder private func clipCard(for item: ClipboardItem) -> some View {
        ClipCardView(
            item: item,
            selected: panelState.selectedID == item.id,
            renaming: panelState.renamingID == item.id,
            vertical: isVertical,
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
    }

    private func paste(_ item: ClipboardItem, plain: Bool) {
        clipboard.paste(item, plainText: plain)
        panelState.hidePanel()
    }

    // MARK: Preview overlay

    private func previewOverlay(_ item: ClipboardItem) -> some View {
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

    @ViewBuilder private func previewContent(_ item: ClipboardItem) -> some View {
        switch item.kind {
        case .text:
            ScrollView { Text(item.text ?? "").font(.system(size: 13)).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }
        case .link:
            VStack(spacing: 10) {
                Text(item.url?.absoluteString ?? "").font(.system(size: 13)).textSelection(.enabled)
                Button("在浏览器中打开") { if let url = item.url { NSWorkspace.shared.open(url) } }
            }
        case .image:
            if let data = item.imageData, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFit()
            }
        case .file:
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(item.fileURLs ?? [], id: \.self) { Text($0.path).font(.system(size: 12)).textSelection(.enabled) }
                }
            }
        }
    }
}

// MARK: - Clip card

private struct ClipCardView: View {
    let item: ClipboardItem
    let selected: Bool
    let renaming: Bool
    let vertical: Bool
    let targetName: String?
    let boards: [Pasteboard]
    let onSelect: () -> Void
    let onPaste: (ClipboardItem) -> Void
    let onPastePlain: (ClipboardItem) -> Void
    let onCopy: (ClipboardItem) -> Void
    let onRename: (ClipboardItem) -> Void
    let onRenameCommit: (UUID, String) -> Void
    let onDelete: (ClipboardItem) -> Void
    let onPin: (ClipboardItem, UUID?) -> Void
    let onPreview: (ClipboardItem) -> Void

    @State private var draftTitle = ""
    @FocusState private var renameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: item.kind.symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(.orange)
                Text(item.kind.title).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                if item.isFavorite { Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(.yellow) }
            }
            preview.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if renaming {
                TextField("名称", text: $draftTitle)
                    .textFieldStyle(.plain).font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(.white.opacity(0.12), in: .rect(cornerRadius: 6))
                    .focused($renameFocused)
                    .onSubmit { onRenameCommit(item.id, draftTitle) }
                    .onAppear { draftTitle = item.displayTitle; renameFocused = true }
            } else {
                Text(item.displayTitle).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            }
            HStack { Text(item.sourceApplication ?? "剪贴板").lineLimit(1); Spacer(); Text(item.createdAt, style: .relative) }
                .font(.system(size: 9)).foregroundStyle(.tertiary)
        }
        .padding(10)
        .frame(width: vertical ? nil : 150, height: vertical ? 120 : 150)
        .frame(maxWidth: vertical ? .infinity : nil)
        .background(selected ? Color.orange.opacity(0.22) : Color.white.opacity(0.06), in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? .orange : .white.opacity(0.07), lineWidth: selected ? 1.5 : 1))
        .contentShape(.rect)
        .onTapGesture(count: 2) { onPaste(item) }
        .onTapGesture(count: 1) { onSelect() }
        .itemProvider { makeProvider() }
        .contextMenu { contextMenu }
    }

    @ViewBuilder private var preview: some View {
        switch item.kind {
        case .image:
            if let data = item.imageData, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity).clipShape(.rect(cornerRadius: 6))
            }
        case .link:
            VStack(alignment: .leading, spacing: 3) {
                Text(item.url?.host ?? "").font(.system(size: 10, weight: .bold)).foregroundStyle(.orange)
                Text(item.url?.absoluteString ?? "").font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(3)
            }
        case .file:
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: "doc.fill").font(.title3).foregroundStyle(.secondary)
                Text(item.detail).font(.system(size: 9)).foregroundStyle(.secondary)
            }
        case .text:
            Text(item.detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(4).multilineTextAlignment(.leading)
        }
    }

    @ViewBuilder private var contextMenu: some View {
        Button { onPaste(item) } label: { menuRow("粘贴到 \(targetName ?? "当前应用")", hint: "↩") }
        Button { onPastePlain(item) } label: { menuRow("以纯文本粘贴", hint: "⇧↩") }
        Button { onCopy(item) } label: { menuRow("拷贝", hint: "⌘C") }
        Button("重命名…") { onRename(item) }
        Divider()
        Menu("固定到") {
            ForEach(boards) { board in
                Button { onPin(item, board.id) } label: {
                    if item.boardID == board.id { Label(board.name, systemImage: "checkmark") } else { Text(board.name) }
                }
            }
            if !boards.isEmpty { Divider() }
            Button("取消固定") { onPin(item, nil) }
        }
        Divider()
        Button { onPreview(item) } label: { menuRow("预览", hint: "空格") }
        Divider()
        Button("删除", role: .destructive) { onDelete(item) }
    }

    private func menuRow(_ title: String, hint: String) -> some View {
        HStack { Text(title); Spacer(); Text(hint).foregroundStyle(.secondary) }
    }

    private func makeProvider() -> NSItemProvider {
        let provider = NSItemProvider()
        provider.suggestedName = item.displayTitle
        switch item.kind {
        case .text:
            provider.registerObject(NSString(string: item.text ?? ""), visibility: .all)
        case .link:
            if let url = item.url { provider.registerObject(url as NSURL, visibility: .all) }
            provider.registerObject(NSString(string: item.url?.absoluteString ?? item.text ?? ""), visibility: .all)
        case .image:
            if let data = item.imageData, let image = NSImage(data: data) { provider.registerObject(image, visibility: .all) }
        case .file:
            for url in item.fileURLs ?? [] { provider.registerObject(url as NSURL, visibility: .all) }
        }
        if let payload = try? JSONEncoder().encode(ClipDragPayload(id: item.id)) {
            provider.registerDataRepresentation(forTypeIdentifier: UTType.easypasteClip.identifier, visibility: .all) { completion in
                completion(payload, nil)
                return nil
            }
        }
        return provider
    }
}
