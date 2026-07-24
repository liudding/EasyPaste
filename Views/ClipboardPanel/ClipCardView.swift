import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 卡片内容区固定高度（pt）：无论剪贴项有无可预览内容，body 都占满这个高度。
private let clipCardBodyHeight: CGFloat = 90
/// 卡片 footer 固定占位高度（pt）：即使内容为空也保留此高度，避免 body 因 footer 塌陷而变高。
private let clipCardFooterHeight: CGFloat = 20

struct ClipCardView: View {
    let item: Clip
    let selected: Bool
    let renaming: Bool
    let vertical: Bool
    /// 卡片可用宽度：竖向（贴边）面板下卡片本应撑满面板宽度，但卡片若用 content-sized（width:nil），
    /// 会把「无限宽」下发给子视图，导致 body 内 scaledToFill 的图片被放大到无限宽、整卡撑爆面板、头部被裁掉。
    /// 因此竖向模式必须传入确定的可用宽度（= clipStrip 几何宽度），强制卡片定宽。
    let availableWidth: CGFloat
    let targetName: String?
    let boards: [Pasteboard]
    let onSelect: () -> Void
    let onPaste: (Clip) -> Void
    let onPastePlain: (Clip) -> Void
    let onCopy: (Clip) -> Void
    let onRename: (Clip) -> Void
    let onRenameCommit: (UUID, String) -> Void
    let onDelete: (Clip) -> Void
    let onPin: (Clip, UUID?) -> Void
    let onPreview: (Clip) -> Void

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

    /// 内容区固定高度：色值卡片无 footer，需额外吃下 footer 高度使整卡与其余类型等高。
    private var clipCardBodyRenderHeight: CGFloat {
        item.kind == .color ? clipCardBodyHeight + clipCardFooterHeight : clipCardBodyHeight
    }

    /// 内容区 + Footer：body 高度固定，footer 占位固定，整块高度与剪贴内容无关。
    @ViewBuilder private var cardBodyRegion: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ZStack：底层 Color.clear 保证固定尺寸，上层 cardBody 叠加内容。
            ZStack(alignment: item.kind == .color ? .center : .topLeading) {
                Color.clear
                cardBody
                    .padding(.horizontal, item.kind == .color ? 0 : 10)
                    .padding(.top, item.kind == .color ? 0 : 6)
            }
            .frame(maxWidth: .infinity)
            .frame(height: clipCardBodyRenderHeight)
            .clipped()
            if item.kind != .color {
                cardFooter
                    .padding(.horizontal, 10).padding(.bottom, 7)
                    .frame(maxWidth: .infinity, minHeight: clipCardFooterHeight, alignment: .top)
            }
        }
        .background(bodyFooterBackground, in: .rect(bottomLeadingRadius: 12, bottomTrailingRadius: 12))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── 头部区：flat color 背景 + 类型 icon + 标题 + time ago + app icon ──
            cardHeader
            // ── 内容区 + Footer：按类型分化 ──
            cardBodyRegion
        }
        .frame(width: vertical ? availableWidth : 170)
        .clipShape(.rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? headerColor : .white.opacity(0.07), lineWidth: selected ? 1.5 : 1))
        .contentShape(.rect)
        .onTapGesture { onSelect() }
        .simultaneousGesture(TapGesture(count: 2).onEnded { onPaste(item) })
        .onDrag { makeProvider() }
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
                    Text(item.displayTitle.isEmpty ? " " : item.displayTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
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
        case .color:
            // 貌值：body 不需要再填色（卡片背景已是该色值），居中显示色值文本
            Text(item.text ?? "").font(.system(size: 14, weight: .bold))
                .foregroundStyle(isLightColor(item.resolvedColorValue ?? item.kind.defaultColor) ? .black : .white)
        case .image:
            if let image = ImageSizeCache.shared.thumbnail(for: item) {
                // Color.clear 占据父级提议的尺寸，overlay 在其上绘制 scaledToFill 图片；
                // 这样图片的布局尺寸 = Color.clear 的尺寸 = 父级提议尺寸，不会因宽图而撑爆卡片。
                Color.clear.overlay(
                    Image(nsImage: image).resizable().scaledToFill()
                )
                .clipShape(.rect(cornerRadius: 6))
            } else {
                // 图片数据为空时用 Color.clear 撑满区域，overlay 居中显示占位图标。
                Color.clear.overlay(
                    Image(systemName: "photo")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                )
            }
        case .link:
            // 链接：优先展示原始富文本格式，无则 fallback 到 URL 摘要或纯文本预览
            if let attr = item.attributedText {
                AttributedTextView(attributedString: attr, maxLines: 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let url = item.url {
                VStack(alignment: .leading, spacing: 3) {
                    Text(url.host ?? "").font(.system(size: 11, weight: .bold)).foregroundStyle(headerColor)
                    if let preview = item.previewPlainText, preview != url.absoluteString {
                        Text(preview).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(2)
                    } else {
                        Text(url.absoluteString).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(3)
                    }
                }
            } else if let preview = item.previewPlainText {
                Text(preview).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(4).multilineTextAlignment(.leading)
            } else {
                Text("无法预览").font(.system(size: 9)).foregroundStyle(.tertiary)
            }
        case .file:
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: "doc.fill").font(.title3).foregroundStyle(.secondary)
                Text(item.detail).font(.system(size: 9)).foregroundStyle(.secondary)
            }
        case .text:
            // 优先展示原始富文本格式，无则 fallback 到纯文本预览
            if let attr = item.attributedText {
                AttributedTextView(attributedString: attr, maxLines: 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let preview = item.previewPlainText {
                Text(preview).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(4).multilineTextAlignment(.leading)
            } else {
                Text("无法预览").font(.system(size: 9)).foregroundStyle(.tertiary)
            }
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
            } else {
                // 如果没有图片尺寸信息，也提供一个占位文本高度的视图，以确保 footer 高度绝对一致
                Text(" ").font(.system(size: 9)).opacity(0)
            }
        case .file:
            Text(item.detail).font(.system(size: 9)).foregroundStyle(.tertiary)
        case .color:
            Text(item.text ?? "").font(.system(size: 9)).foregroundStyle(.tertiary)
        }
    }

    // MARK: Background

    /// body+footer 区域的背景色（底部有圆角）。
    private var bodyFooterBackground: Color {
        if selected { return headerColor.opacity(0.18) }
        // 色值类型 body 底色就是解析的色值颜色
        if item.kind == .color { return item.resolvedColorValue ?? item.kind.defaultColor }
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
        
        // 1. 保真还原：注册所有原始剪贴板数据
        if let allData = item.allPasteboardData {
            for entry in allData {
                provider.registerDataRepresentation(forTypeIdentifier: entry.uti, visibility: .all) { completion in
                    completion(entry.data, nil)
                    return nil
                }
            }
        }
        
        // 2. 标准类型兼容：注册系统类型对象，补充可能遗漏的基础格式，并处理无原始数据的情况
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
        case .color:
            provider.registerObject(NSString(string: item.text ?? ""), visibility: .all)
        }
        
        // 3. 内部拖拽：提供专属 Payload 给 board chip 解析
        if let payload = try? JSONEncoder().encode(ClipDragPayload(id: item.id)) {
            provider.registerDataRepresentation(forTypeIdentifier: UTType.easypasteClip.identifier, visibility: .all) { completion in
                completion(payload, nil)
                return nil
            }
        }
        return provider
    }
}
