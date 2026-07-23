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

    private var isVertical: Bool { settings.panelPosition.isVertical }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 14).padding(.top, 14)
                clipStrip
                    .padding(.top, 12).padding(.bottom, 14)
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
        onOpenSettings()
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
                    ScrollView(.horizontal) { LazyHStack(spacing: 10) { cards }.padding(.horizontal, 14) }
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
        case .colorValue:
            ZStack {
                (item.resolvedColorValue ?? item.kind.defaultColor)
                Text(item.text ?? "").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
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

    /// 卡片头部区背景色：优先 pin board 色 → app icon 提取色 → 类型默认色。
    /// 色值类型 header 不使用解析色值本身，依然走 app icon 色 → 默认色逻辑。
    private var headerColor: Color {
        // 1) 有 pin board 则用 board 色
        if let boardID = item.boardID,
           let board = boards.first(where: { $0.id == boardID }) {
            return board.swiftUIColor
        }
        // 2) 有 app icon 提取色
        if let appColor = item.sourceAppDominantColor {
            return appColor
        }
        // 3) 类型默认色兜底
        return item.kind.defaultColor
    }

    /// 来源 app icon（从缓存读取 22×22 缩放版本）。
    private var sourceAppIconImage: NSImage? {
        AppIconCache.shared.icon(forBundleID: item.sourceApplicationBundleID, displaySize: 22)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── 头部区：flat color 背景 + 类型 icon + 标题 + time ago + app icon ──
            cardHeader
            // ── 内容区 + Footer：按类型分化 ──
            VStack(alignment: .leading, spacing: 0) {
                cardBody
                    .padding(.horizontal, item.kind == .colorValue ? 0 : 10)
                    .padding(.top, item.kind == .colorValue ? 0 : 6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: item.kind == .colorValue ? .center : .topLeading)
                if item.kind != .colorValue {
                    cardFooter
                        .padding(.horizontal, 10).padding(.bottom, 7)
                }
            }
            .background(bodyFooterBackground, in: .rect(bottomLeadingRadius: 12, bottomTrailingRadius: 12))
        }
        .frame(width: vertical ? nil : 170, height: vertical ? nil : 160)
        .frame(maxWidth: vertical ? .infinity : nil)
        .frame(minHeight: vertical ? 80 : nil)
        .clipShape(.rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? headerColor : .white.opacity(0.07), lineWidth: selected ? 1.5 : 1))
        .contentShape(.rect)
        .onTapGesture { onSelect() }
        .simultaneousGesture(TapGesture(count: 2).onEnded { onPaste(item) })
        .itemProvider { makeProvider() }
        .contextMenu { contextMenu }
    }

    // MARK: Header

    private var cardHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Image(systemName: item.kind.symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white)
                if renaming {
                    TextField("名称", text: $draftTitle)
                        .textFieldStyle(.plain).font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .focused($renameFocused)
                        .onSubmit { onRenameCommit(item.id, draftTitle) }
                        .onAppear { draftTitle = item.displayTitle; renameFocused = true }
                } else {
                    Text(item.displayTitle).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                }
                Spacer(minLength: 2)
                // 最右侧：来源 app icon
                if let appIcon = sourceAppIconImage {
                    Image(nsImage: appIcon).frame(width: 22, height: 22)
                }
                if item.isFavorite { Image(systemName: "star.fill").font(.system(size: 8)).foregroundStyle(.yellow) }
            }
            Text(timeAgoString(from: item.createdAt)).font(.system(size: 9)).foregroundStyle(.white.opacity(0.65))
        }
        .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 6)
        .background(headerColor.opacity(0.85))
        .clipShape(.rect(topLeadingRadius: 12, topTrailingRadius: 12))
    }

    /// 将 Date 转成 "2分钟前"、"1小时前" 等简短的 time ago 格式。
    private func timeAgoString(from date: Date) -> String {
        let interval = Date.now.timeIntervalSince(date)
        if interval < 60 { return "刚刚" }
        if interval < 3600 { return "\(Int(interval / 60))分钟前" }
        if interval < 86400 { return "\(Int(interval / 3600))小时前" }
        if interval < 604800 { return "\(Int(interval / 86400))天前" }
        if interval < 2592000 { return "\(Int(interval / 604800))周前" }
        let months = Int(interval / 2592000)
        if months < 12 { return "\(months)月前" }
        return "\(Int(interval / 31536000))年前"
    }

    // MARK: Body (content area, varies by type)

    @ViewBuilder private var cardBody: some View {
        switch item.kind {
        case .colorValue:
            // 貌值：body 不需要再填色（卡片背景已是该色值），居中显示色值文本
            Text(item.text ?? "").font(.system(size: 14, weight: .bold))
                .foregroundStyle(isLightColor(item.resolvedColorValue ?? item.kind.defaultColor) ? .black : .white)
        case .image:
            if let image = ImageSizeCache.shared.image(for: item) {
                Image(nsImage: image).resizable().scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity).clipShape(.rect(cornerRadius: 6))
            }
        case .link:
            // 链接：body 展示网页预览（host + 缩略摘要）
            VStack(alignment: .leading, spacing: 3) {
                Text(item.url?.host ?? "").font(.system(size: 11, weight: .bold)).foregroundStyle(headerColor)
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

    // MARK: Footer (varies by type)

    @ViewBuilder private var cardFooter: some View {
        switch item.kind {
        case .text:
            Text("\(item.characterCount) 字符").font(.system(size: 9)).foregroundStyle(.tertiary)
        case .link:
            HStack(spacing: 4) {
                Text(item.linkFooterTitle).lineLimit(1).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                Text(item.linkFooterURL).lineLimit(1).font(.system(size: 8)).foregroundStyle(.tertiary)
            }
        case .image:
            if let sizeDesc = item.imageSizeDescription {
                Text(sizeDesc).font(.system(size: 9)).foregroundStyle(.tertiary)
            }
        case .file:
            Text(item.detail).font(.system(size: 9)).foregroundStyle(.tertiary)
        case .colorValue:
            Text(item.text ?? "").font(.system(size: 9)).foregroundStyle(.tertiary)
        }
    }

    // MARK: Background

    /// body+footer 区域的背景色（底部有圆角）。
    private var bodyFooterBackground: Color {
        if selected { return headerColor.opacity(0.18) }
        // 色值类型 body 底色就是解析的色值颜色
        if item.kind == .colorValue { return item.resolvedColorValue ?? item.kind.defaultColor }
        return Color.white.opacity(0.06)
    }

    /// 判断一个颜色是否为亮色（用于决定文本用黑/白）。
    private func isLightColor(_ color: Color) -> Bool {
        // 粗略判断：取 RGB 亮度 > 0.5 就是亮色
        let nsColor = NSColor(color)
        guard let rgb = nsColor.usingColorSpace(.sRGB) else { return false }
        let luminance = 0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent
        return luminance > 0.5
    }

    // MARK: Context menu & drag provider (unchanged)

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
        case .colorValue:
            provider.registerObject(NSString(string: item.text ?? ""), visibility: .all)
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
