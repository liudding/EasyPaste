import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 卡片内容区固定高度（pt）
private let clipCardBodyHeight: CGFloat = 110

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
    // 类型专属操作回调
    let onShowQRCode: (String) -> Void
    let onExportText: (Clip) -> Void
    let onExportRTF: (Clip) -> Void
    let onExportImage: (Clip) -> Void
    let onSendEmail: (String) -> Void
    let onPasteColorAs: (Clip, ColorPasteFormat) -> Void
    let onOpenURL: (URL) -> Void
    let onPreviewJSON: (Clip) -> Void
    let settings: AppSettings

    @State private var draftTitle = ""
    @FocusState private var renameFocused: Bool
    @State private var l10nStore = L10nStore.shared
    @Environment(\.colorScheme) private var colorScheme

    /// 卡片头部区背景色：优先 pin board 色 → app icon 提取色 → 类型默认色。
    /// 色值类型 header 不使用解析色值本身，依然走 app icon 色 → 默认色逻辑。
    /// 统一在浅色外观下解析为固定 sRGB（系统语义色如 .yellow 会随主题变暗，固定后两种主题一致），
    /// 并压暗过亮颜色，确保浅色主题下与近白背景可区分、header 白字可读。
    private var headerColor: Color {
        let raw: Color
        // 1) 有 pin board 则用 board 色
        if let boardID = item.boardID,
           let board = boards.first(where: { $0.id == boardID }) {
            raw = board.swiftUIColor
        // 2) 有 app icon 提取色
        } else if let appColor = item.sourceAppDominantColor {
            raw = appColor
        // 3) 类型默认色兜底
        } else {
            raw = item.kind.defaultColor
        }
        return readableHeaderColor(raw)
    }

    /// 将 header 颜色解析为固定 sRGB 分量，并压暗过亮值（亮度 > 阈值时按比例降至阈值）。
    private func readableHeaderColor(_ color: Color) -> Color {
        let (r, g, b) = fixedRGB(color)
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b
        // 阈值 0.6：浅色主题背景近白(0.98)，超过此亮度的颜色（如系统 .yellow、浅色 app icon 主色）
        // 会与背景混为一体且白字不可读，需压暗。
        let maxLuminance: Double = 0.6
        if luminance <= maxLuminance {
            return Color(red: r, green: g, blue: b)
        }
        let factor = maxLuminance / luminance
        return Color(red: r * factor, green: g * factor, blue: b * factor)
    }

    /// 在浅色(aqua)外观下解析 Color 为固定 sRGB 分量。
    /// 系统语义色（.yellow/.green 等）会随当前外观变化；强制 aqua 解析可保证两种主题下 header 颜色一致。
    private func fixedRGB(_ color: Color) -> (r: Double, g: Double, b: Double) {
        let nsColor = NSColor(color)
        guard let aqua = NSAppearance(named: .aqua) else {
            return (0, 0, 0)
        }
        var r: Double = 0, g: Double = 0, b: Double = 0
        aqua.performAsCurrentDrawingAppearance {
            if let rgb = nsColor.usingColorSpace(.sRGB) {
                r = Double(rgb.redComponent)
                g = Double(rgb.greenComponent)
                b = Double(rgb.blueComponent)
            }
        }
        return (r, g, b)
    }

    /// 来源 app icon（从缓存读取 22×22 缩放版本）。
    private var sourceAppIconImage: NSImage? {
        AppIconCache.shared.icon(forBundleID: item.sourceApplicationBundleID, displaySize: 22)
    }

    /// 内容区：footer 已移除，原 footer 信息合并进 body，body 占满整块高度。
    @ViewBuilder private var cardBodyRegion: some View {
        ZStack(alignment: .center) {
            // 底层 Color.clear 保证固定尺寸，上层 cardBody 叠加内容。
            Color.clear
            cardBody
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .padding(.horizontal, item.kind == .color ? 0 : 10)
        .padding(.vertical, item.kind == .color ? 0 : 6)
        .frame(maxWidth: .infinity)
        .frame(height: clipCardBodyHeight)
        .clipped()
        // body 背景不透明，按主题设定颜色（底部圆角）。
        .background(bodyBackground, in: .rect(bottomLeadingRadius: 12, bottomTrailingRadius: 12))
        // 选中态：在不透明底色上叠加 headerColor 薄膜，保持整体不透明。
        .overlay {
            if selected {
                headerColor.opacity(0.18)
            }
        }
        .textSelection(.disabled)
    }

    var body: some View {
        let _ = l10nStore.version
        VStack(alignment: .leading, spacing: 0) {
            // ── 头部区：flat color 背景 + 类型 icon + 标题 + time ago + app icon ──
            cardHeader
            // ── 内容区：按类型分化（原 footer 信息已合并进 body）──
            cardBodyRegion
        }
        .frame(width: vertical ? availableWidth : 170)
        .clipShape(.rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? headerColor : .primary.opacity(0.07), lineWidth: selected ? 1.5 : 1))
        .contentShape(.rect)
        .onTapGesture { onSelect() }
        .simultaneousGesture(TapGesture(count: 2).onEnded { onPaste(item) })
        .onDrag { makeProvider() }
        // 右键选中：捕获层仅在 rightMouseDown 时拦截事件触发一次选中，随后转发 responder chain
        // 让外层 SwiftUI `.contextMenu` 的 NSMenu 正常弹出。左键/拖拽透传不受影响。
        // 不能在 contextMenu 的 @ViewBuilder 闭包内调 onSelect——该闭包在 body 更新时对所有可见卡片
        // 急切求值，每张卡都写 selectedID → 互相覆盖 → 无限重渲染 → 主线程阻塞(ANR)。
        .overlay(RightClickSelector(onSelect: onSelect))
        .contextMenu { contextMenu }
    }

    // MARK: Header

    private var cardHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Image(systemName: item.kind.symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white)
                if renaming {
                    TextField(L10n.rename, text: $draftTitle)
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
        .background(headerColor)
        .clipShape(.rect(topLeadingRadius: 12, topTrailingRadius: 12))
    }

    /// 将 Date 转成 "2分钟前"、"1小时前" 等简短的 time ago 格式。
    private func timeAgoString(from date: Date) -> String {
        let interval = Date.now.timeIntervalSince(date)
        if interval < 60 { return L10n.justNow }
        if interval < 3600 { return "\(Int(interval / 60))\(L10n.minutesAgo)" }
        if interval < 86400 { return "\(Int(interval / 3600))\(L10n.hoursAgo)" }
        if interval < 604800 { return "\(Int(interval / 86400))\(L10n.daysAgo)" }
        if interval < 2592000 { return "\(Int(interval / 604800))\(L10n.weeksAgo)" }
        let months = Int(interval / 2592000)
        if months < 12 { return "\(months)\(L10n.monthsAgo)" }
        return "\(Int(interval / 31536000))\(L10n.yearsAgo)"
    }

    // MARK: Body (content area, varies by type)
    // 原 footer 展示的信息已合并进各类型的 body：内容置顶，附加信息经 Spacer 推到底部。

    @ViewBuilder private var cardBody: some View {
        switch item.kind {
        case .color:
            ColorCardBody(item: item)
        case .image:
            ImageCardBody(item: item)
        case .link:
            LinkCardBody(item: item, headerColor: headerColor)
        case .file:
            FileCardBody(item: item)
        case .text:
            TextCardBody(item: item)
        }
    }

    // MARK: Background

    /// body 区域背景色（不透明，按主题设定颜色，底部有圆角）。
    /// - 色值类型：底色即为解析的色值颜色。
    /// - 其余类型：深色主题用深灰、浅色主题用近白，均为不透明实色，面板材质不再透出。
    private var bodyBackground: Color {
        // 色值类型 body 底色就是解析的色值颜色
        if item.kind == .color { return item.resolvedColorValue ?? item.kind.defaultColor }
        // 按主题不透明底色：深色稍亮于面板、浅色近白，确保与面板材质有层次。
        return colorScheme == .dark
            ? Color(white: 0.16)
            : Color(white: 0.98)
    }

    // MARK: Context menu & drag provider

    @ViewBuilder private var contextMenu: some View {
        // ── Leading type-specific items (email, JSON, open link, color Paste as) ──
        leadingTypeSpecificMenu
        if hasLeadingTypeSpecificMenu { Divider() }
        // ── Universal items ──
        Button { onPaste(item) } label: { menuRow(String(format: L10n.pasteToApp, targetName ?? ""), hint: shortcutHint(for: "paste")) }
        Button { onPastePlain(item) } label: { menuRow(L10n.pastePlainText, hint: shortcutHint(for: "paste_plain")) }
        Button { onCopy(item) } label: { menuRow(L10n.copyAction, hint: shortcutHint(for: "copy")) }
        Button(L10n.rename) { onRename(item) }.keyboardShortcut(.return, modifiers: .command)
        Divider()
        Menu(L10n.pinTo) {
            ForEach(boards) { board in
                Button { onPin(item, board.id) } label: {
                    if item.boardID == board.id { Label(board.name, systemImage: "checkmark") } else { Text(board.name) }
                }
            }
            if !boards.isEmpty { Divider() }
            Button(L10n.unpin) { onPin(item, nil) }
        }
        Divider()
        Button { onPreview(item) } label: { menuRow(L10n.preview, hint: shortcutHint(for: "preview")) }
        // ── Trailing type-specific items (QR, export, save as) ──
        if hasTrailingTypeSpecificMenu { Divider() }
        trailingTypeSpecificMenu
        Divider()
        Button(L10n.delete, role: .destructive) { onDelete(item) }.keyboardShortcut(.delete, modifiers: [])
    }

    /// Whether the leading type-specific menu has items (used to decide divider visibility).
    private var hasLeadingTypeSpecificMenu: Bool {
        switch item.kind {
        case .text:
            switch item.subkind {
            case .email: return true
            case .json: return true
            default: return false
            }
        case .color: return true
        case .link: return true  // Open Link is leading
        default: return false
        }
    }

    /// Whether the trailing type-specific menu has items (used to decide divider visibility).
    private var hasTrailingTypeSpecificMenu: Bool {
        switch item.kind {
        case .text:
            let hasContent = !(item.text?.isEmpty ?? true)
            switch item.subkind {
            case .richText: return hasContent
            case nil: return hasContent
            default: return false
            }
        case .image: return BlobStore.shared.exists(id: item.id, kind: .image)
        case .link: return !(item.url?.absoluteString.isEmpty ?? true)  // QR Code is trailing
        default: return false
        }
    }

    /// Leading type-specific items: stay at the TOP of the menu (before universal items).
    /// - text/email: Send Email
    /// - text/json: JSON Preview
    /// - link: Open Link
    /// - color: "Paste as" submenu (hex / rgb / hsl)
    @ViewBuilder private var leadingTypeSpecificMenu: some View {
        switch item.kind {
        case .text:
            switch item.subkind {
            case .email:
                Button(L10n.menuSendEmail) { onSendEmail(item.text ?? "") }.keyboardShortcut(.return, modifiers: .command)
            case .json:
                if !(item.text?.isEmpty ?? true) {
                    Button(L10n.menuJSONPreview) { onPreviewJSON(item) }
                }
            default:
                EmptyView()
            }
        case .color:
            Menu(L10n.menuPasteAs) {
                Button(L10n.menuHex) { onPasteColorAs(item, .hex) }
                Button(L10n.menuRGB) { onPasteColorAs(item, .rgb) }
                Button(L10n.menuHSL) { onPasteColorAs(item, .hsl) }
            }
        case .link:
            if let url = item.url {
                Button(L10n.menuOpenLink) { onOpenURL(url) }
            }
        default:
            EmptyView()
        }
    }

    /// Trailing type-specific items: move to the BOTTOM (after Preview, before Delete).
    /// - text/richText: Export TXT, Export RTF, QR Code
    /// - text/nil: Export TXT, QR Code
    /// - image: Save As…
    /// - link: QR Code
    @ViewBuilder private var trailingTypeSpecificMenu: some View {
        switch item.kind {
        case .text:
            let hasContent = !(item.text?.isEmpty ?? true)
            switch item.subkind {
            case .richText:
                if hasContent {
                    Button(L10n.menuExportTxt) { onExportText(item) }.keyboardShortcut("e", modifiers: .command)
                    Button(L10n.menuExportRtf) { onExportRTF(item) }.keyboardShortcut("e", modifiers: [.command, .shift])
                    Button(L10n.menuQRCode) { onShowQRCode(item.text ?? "") }.keyboardShortcut("q", modifiers: .command)
                }
            case nil:
                if hasContent {
                    Button(L10n.menuExportTxt) { onExportText(item) }.keyboardShortcut("e", modifiers: .command)
                    Button(L10n.menuQRCode) { onShowQRCode(item.text ?? "") }.keyboardShortcut("q", modifiers: .command)
                }
            default:
                EmptyView()
            }
        case .image:
            if BlobStore.shared.exists(id: item.id, kind: .image) {
                Button(L10n.menuSaveAs) { onExportImage(item) }.keyboardShortcut("s", modifiers: .command)
            }
        case .link:
            if !(item.url?.absoluteString.isEmpty ?? true) {
                Button(L10n.menuQRCode) { onShowQRCode(item.url?.absoluteString ?? item.text ?? "") }.keyboardShortcut("q", modifiers: .command)
            }
        default:
            EmptyView()
        }
    }

    /// 获取指定动作的快捷键提示字符串。
    private func shortcutHint(for actionID: String) -> String {
        guard let config = settings.contextMenuShortcuts[actionID],
              config.enabled,
              let shortcut = config.shortcut else {
            return ""
        }
        return shortcut.displayString
    }
    
    private func menuRow(_ title: String, hint: String) -> some View {
        HStack { Text(title); Spacer(); if !hint.isEmpty { Text(hint).foregroundStyle(.secondary) } }
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

// MARK: - Right-click selection capture

/// 右键选中捕获层：仅在 rightMouseDown 时拦截事件以触发一次选中，随后转发给 responder chain
/// 让外层 SwiftUI `.contextMenu` 设置的 NSMenu 正常弹出。其余事件（左键、拖拽）透传给下层 SwiftUI。
///
/// 与 `BoardContextMenuOverlay` 同一 hitTest 模式：`hitTest` 仅在 `NSApp.currentEvent?.type == .rightMouseDown`
/// 时返回自身，否则返回 nil（透明）。`rightMouseDown` 调 `onSelect()` 后调 `super.rightMouseDown(with:)`，
/// NSView 默认实现沿 nextResponder(=superview) 向上查找 `menu(for:)`，最终命中 `.contextMenu` 的 NSMenu。
private struct RightClickSelector: NSViewRepresentable {
    let onSelect: () -> Void

    func makeNSView(context: Context) -> RightClickSelectorView {
        let view = RightClickSelectorView()
        view.onSelect = onSelect
        return view
    }

    func updateNSView(_ nsView: RightClickSelectorView, context: Context) {
        nsView.onSelect = onSelect
    }

    final class RightClickSelectorView: NSView {
        var onSelect: (() -> Void)?

        /// 仅在右键按下时捕获事件，其余事件透传给下层 SwiftUI（左键、拖拽等）。
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard NSApp.currentEvent?.type == .rightMouseDown else { return nil }
            return super.hitTest(point)
        }

        override func rightMouseDown(with event: NSEvent) {
            onSelect?()
            // 转发 responder chain：NSView 默认实现会沿 nextResponder 向上查找 menu(for:)，
            // 最终命中外层 SwiftUI `.contextMenu` 设置的 NSMenu 并弹出。不消耗事件。
            super.rightMouseDown(with: event)
        }
    }
}
