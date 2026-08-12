import AppKit
import Foundation
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// 可编码的 sRGB 颜色分量，用于把来源 app icon 主色调随剪贴项一起持久化，
/// 避免每次渲染都重新从 AppIconCache 计算。
struct CodableColor: Codable, Hashable {
    let red: Double
    let green: Double
    let blue: Double

    var color: Color {
        Color(red: red, green: green, blue: blue)
    }

    init(red: Double, green: Double, blue: Double) {
        self.red = red; self.green = green; self.blue = blue
    }
}

/// 一个 UTI 类型及其原始数据的键值对，用于保存多格式剪贴板数据。
struct UTIEntry: Codable, Hashable, Equatable {
    let uti: String
    let data: Data
}

enum ClipKind: String, Codable, CaseIterable, Identifiable {
    case text, link, image, file, color
    var id: String { rawValue }
    var title: String {
        switch self {
        case .text: L10n.tr("clip.kind.text")
        case .link: L10n.tr("clip.kind.link")
        case .image: L10n.tr("clip.kind.image")
        case .file: L10n.tr("clip.kind.file")
        case .color: L10n.tr("clip.kind.color")
        }
    }
    var symbol: String { switch self { case .text: "text.alignleft"; case .link: "link"; case .image: "photo"; case .file: "doc"; case .color: "paintpalette.fill" } }
    /// 该类型在没有 pin board 色 / app 色时的默认纯色。
    var defaultColor: Color {
        switch self {
        case .text: Color(red: 0.28, green: 0.54, blue: 0.90)  // blue
        case .link: Color(red: 0.96, green: 0.62, blue: 0.24)  // orange
        case .image: Color(red: 0.35, green: 0.78, blue: 0.56)  // green
        case .file: Color(red: 0.55, green: 0.33, blue: 0.76)  // purple
        case .color: Color(red: 0.92, green: 0.38, blue: 0.42)  // red-pink
        }
    }
}

/// text 类型的子类型，用于 Context Menu 分化。
/// nil 表示普通纯文本。
enum ClipSubkind: String, Codable {
    case richText     // 富文本（含 RTF/RTFD/HTML 原始格式数据）
    case email        // 邮箱地址
    case json         // JSON 格式文本
}

// MARK: - SwiftData Models

/// 剪贴板历史条目（SwiftData @Model）。
///
/// 大 blob（imageData / utiData / allPasteboardDataRaw）使用 `@Attribute(.externalStorage)`
/// 存储在辅助文件中，列表查询不会加载这些字段，等价于原 GRDB 的 `clip_blobs` 分离设计。
@Model
final class Clip {
    var id: UUID
    var kind: ClipKind
    var createdAt: Date
    var text: String?
    var url: URL?
    var fileURLs: [URL]?

    @Attribute(.externalStorage)
    var imageData: Data?

    var boardID: UUID?
    var isFavorite: Bool
    var title: String?
    var sourceApplication: String?
    var sourceApplicationBundleID: String?
    var uti: String?
    var sourceAppColor: CodableColor?
    var contentColor: CodableColor?

    @Attribute(.externalStorage)
    var utiData: Data?

    /// `[UTIEntry]` 编码为 JSON `Data` 存储，使用 externalStorage 避免列表查询加载大 blob。
    @Attribute(.externalStorage)
    var allPasteboardDataRaw: Data?

    var contentHash: String?
    var subkind: ClipSubkind?

    /// 搜索索引：text/url/文件名/title 归一化（小写）后的全文副本。
    /// 列表过滤热路径只做 `contains`，避免每次按键逐条拼装 detail/previewPlainText。
    /// 新条目在 init 构建；rename 时重建；存量数据由 Store.backfillSearchIndexIfNeeded 懒回填。
    var searchText: String?

    func buildSearchText() {
        var parts: [String] = []
        if let text, !text.isEmpty { parts.append(text) }
        if let url { parts.append(url.absoluteString) }
        if let fileURLs { parts.append(contentsOf: fileURLs.map(\.lastPathComponent)) }
        if let linkTitle, !linkTitle.isEmpty { parts.append(linkTitle) }
        if let title, !title.isEmpty { parts.append(title) }
        parts.append(kind.title)
        // 富文本（text 为空，全文在 HTML 里）：解析出全量可见文本进索引，
        // 保证 previewPlainText 200 字符截断之外的词仍可检索。
        if text?.isEmpty ?? true,
           let htmlData = allPasteboardData?.first(where: { $0.uti == "public.html" })?.data,
           let parsed = try? NSAttributedString(data: htmlData, options: [.documentType: NSAttributedString.DocumentType.html], documentAttributes: nil),
           !parsed.string.isEmpty {
            parts.append(parsed.string)
        }
        searchText = parts.joined(separator: " ").lowercased()
    }

    /// 从 link 所对应的网页中提取的 title / description（运行时填充，不持久化）。
    @Transient
    var linkTitle: String? = nil
    @Transient
    var linkDescription: String? = nil

    /// 剪贴板上所有可用 UTI 类型及其原始数据，粘贴时全部写回以保真还原来源格式。
    /// 计算属性：在 `[UTIEntry]` 与 JSON `Data` 之间双向转换。
    var allPasteboardData: [UTIEntry]? {
        get { allPasteboardDataRaw.flatMap { try? JSONDecoder().decode([UTIEntry].self, from: $0) } }
        set { allPasteboardDataRaw = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    init(kind: ClipKind, text: String? = nil, url: URL? = nil, fileURLs: [URL]? = nil, imageData: Data? = nil, uti: String? = nil, utiData: Data? = nil, allPasteboardData: [UTIEntry]? = nil, contentColor: CodableColor? = nil) {
        self.id = UUID(); self.kind = kind; self.createdAt = .now
        self.text = text; self.url = url; self.fileURLs = fileURLs; self.imageData = imageData
        self.boardID = nil; self.isFavorite = false
        self.sourceApplication = nil; self.sourceApplicationBundleID = nil
        self.uti = uti; self.utiData = utiData
        self.allPasteboardDataRaw = allPasteboardData.flatMap { try? JSONEncoder().encode($0) }
        self.title = nil; self.contentColor = contentColor
        self.contentHash = nil; self.subkind = nil
        buildSearchText()
    }

    /// 默认是 kind 的名称
    var displayTitle: String {
        if let title: String, !title.isEmpty { return title }
        switch kind {
        case .text:
            return L10n.tr("clip.default_text")
        case .link:
            return L10n.tr("clip.default_link")
        case .image:
            return L10n.tr("clip.default_image")
        case .file:
            return L10n.tr("clip.default_file")
        case .color:
            return L10n.tr("clip.default_color")
        }
    }
    var detail: String {
        switch kind {
        case .text: return text ?? previewPlainText ?? ""
        case .link: return url?.absoluteString ?? previewPlainText ?? ""
        case .image: return ImageSizeCache.shared.sizeDescription(for: self) ?? L10n.tr("clip.default_image")
        case .file: return String(format: L10n.tr("clip.files_count"), fileURLs?.count ?? 0)
        case .color: return text ?? ""
        }
    }

    /// 判断文本是否是色值（#RGB / #RRGGBB / #RRGGBBAA / rgb() / hsl()）。
    var isColorValue: Bool {
        guard kind == .text, let t = text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return false }
        // Hex patterns
        if t.hasPrefix("#") && [4, 7, 9].contains(t.count) { return true }
        // rgb()/hsl()/rgba()/hsla() patterns
        if t.lowercased().hasPrefix("rgb") || t.lowercased().hasPrefix("hsl") { return true }
        return false
    }

    /// 从文本色值解析出 SwiftUI Color（支持 #RGB, #RRGGBB,；其余返回 nil）。
    var resolvedColorValue: Color? {
        guard let t = text?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        // Hex
        if t.hasPrefix("#") {
            var hexStr = String(t.dropFirst())
            if hexStr.count == 3 {
                let chars = Array(hexStr)
                hexStr = "\(chars[0])\(chars[0])\(chars[1])\(chars[1])\(chars[2])\(chars[2])"
            }
            guard hexStr.count == 6, let v = UInt64(hexStr, radix: 16) else { return nil }
            let r = Double((v >> 16) & 0xFF) / 255
            let g = Double((v >> 8) & 0xFF) / 255
            let b = Double(v & 0xFF) / 255
            return Color(red: r, green: g, blue: b)
        }
        return nil
    }

    /// 文本类型的字符数（用于卡片 footer 显示）。
    var characterCount: Int { text?.count ?? 0 }

    /// 图片尺寸描述（用于 footer 显示，从缓存读取）。
    var imageSizeDescription: String? {
        guard kind == .image else { return nil }
        return ImageSizeCache.shared.sizeDescription(for: self)
    }

    /// 链接的网页 title（优先 url host）和 URL 文本（用于 footer 显示）。
    var linkFooterTitle: String { url?.host ?? displayTitle }
    var linkFooterURL: String { url?.absoluteString ?? text ?? "" }

    // MARK: - 原始格式渲染

    /// 从 allPasteboardData 中按优先级提取 RTF / HTML 数据，解析为 NSAttributedString。
    /// 用于卡片 body 和预览浮层中展示原始富文本格式。
    var attributedText: NSAttributedString? {
        guard kind == .text || kind == .link else { return nil }
        guard let entries = allPasteboardData, !entries.isEmpty else { return nil }
        
        // 优先尝试 RTF → RTFD → HTML → plain-text
        let rtfKeys = ["public.rtf", "com.apple.flat-rtfd", "public.html"]
        for key in rtfKeys {
            if let entry = entries.first(where: { $0.uti == key }) {
                let data = entry.data
                if let attr = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) {
                    return attr
                }
                // HTML 用 html 文档类型
                if let attr = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.html], documentAttributes: nil) {
                    return attr
                }
            }
        }
        // fallback: 纯文本
        if let text = text, !text.isEmpty {
            return NSAttributedString(string: text)
        }
        return nil
    }

    /// 从 allPasteboardData 中提取一个纯文本摘要用于卡片预览。
    /// 优先级：plain-text > RTF 纯文本 > HTML 中的可见文本 > 第一个非空数据字符串化。
    var previewPlainText: String? {
        guard let entries = allPasteboardData, !entries.isEmpty else { return text }
        
        // 1. 优先用已有的 text 字段
        if let text = text, !text.isEmpty { return text }
        
        // 2. 尝试 public.plain-text / public.utf8-plain-text / NSStringPboardType
        let stringKeys = ["public.plain-text", "public.utf8-plain-text", "NSStringPboardType"]
        for key in stringKeys {
            if let entry = entries.first(where: { $0.uti == key }),
               let s = String(data: entry.data, encoding: .utf8), !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return s.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        // 3. 尝试从 HTML 中提取纯文本（去掉标签）
        if let htmlEntry = entries.first(where: { $0.uti == "public.html" || $0.uti == "Apple HTML pasteboard type" }),
           let html = String(data: htmlEntry.data, encoding: .utf8) {
            // 使用 NSAttributedString 解析 HTML 获取纯文本
            if let attr = try? NSAttributedString(data: htmlEntry.data, options: [.documentType: NSAttributedString.DocumentType.html], documentAttributes: nil) {
                let text = attr.string
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200).description
                }
            }
            // fallback: 正则去除 < > 标签
            let cleaned = html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed.prefix(200).description }
        }
        
        // 4. 最后一个兜底：取第一个有数据的 entry 的字符串化
        if let first = entries.first, let s = String(data: first.data, encoding: .utf8), !s.isEmpty {
            return s.prefix(200).description
        }
        
        return nil
    }
}

// MARK: - App icon & dominant color extraction (cached via AppIconCache)

extension Clip {
    /// 根据 sourceApplicationBundleID 获取 app 的 NSImage icon（从缓存读取）。
    var sourceAppIcon: NSImage? {
        AppIconCache.shared.icon(forBundleID: sourceApplicationBundleID)
    }

    /// 来源 app icon 主色调：优先返回创建时已持久化的颜色，
    /// 旧数据（未存字段）回退到 AppIconCache 计算。
    var sourceAppDominantColor: Color? {
        if let c = sourceAppColor { return c.color }
        return AppIconCache.shared.dominantColor(forBundleID: sourceApplicationBundleID)
    }
}

// MARK: - AutomationRule Model

@Model
final class AutomationRule {
    var id: UUID
    var name: String
    var keyword: String
    var sourceApplication: String
    var targetBoardID: UUID?
    var enabled: Bool

    init(name: String, keyword: String = "", sourceApplication: String = "", targetBoardID: UUID? = nil, enabled: Bool = true) {
        id = UUID(); self.name = name; self.keyword = keyword; self.sourceApplication = sourceApplication
        self.targetBoardID = targetBoardID; self.enabled = enabled
    }

    func matches(_ item: Clip) -> Bool {
        guard enabled else { return false }
        let content = "\(item.displayTitle) \(item.detail)".lowercased()
        let keywordMatches = keyword.isEmpty || content.contains(keyword.lowercased())
        let appMatches = sourceApplication.isEmpty || item.sourceApplication?.localizedCaseInsensitiveContains(sourceApplication) == true
        return keywordMatches && appMatches
    }
}

// MARK: - Pasteboard Model

@Model
final class Pasteboard {
    var id: UUID
    var name: String
    var color: String
    var sortIndex: Int?

    init(name: String, color: String, sortIndex: Int? = nil) {
        id = UUID(); self.name = name; self.color = color; self.sortIndex = sortIndex
    }
}

// MARK: - Drag payload & UTType

/// 拖拽卡片在 Pinboard 之间移动用的内部数据载体。
struct ClipDragPayload: Codable, Transferable {
    let id: UUID
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .easypasteClip)
    }
}

extension UTType {
    static let easypasteClip = UTType(importedAs: "com.easypaste.clip")
}

extension Pasteboard {
    var swiftUIColor: Color {
        switch color {
        case "blue": .blue; case "purple": .purple; case "green": .green
        case "red": .red; case "yellow": .yellow; case "pink": .pink; case "teal": .teal
        default: .orange
        }
    }
    static let palette = ["orange", "blue", "purple", "green", "red", "yellow", "pink", "teal"]
}
