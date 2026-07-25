import AppKit
import Foundation
import SwiftUI
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
        case .text: "文本"; case .link: "链接"; case .image: "图片"; case .file: "文件"; case .color: "颜色"
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

struct Clip: Codable, Identifiable, Hashable {
    var id: UUID
    var kind: ClipKind
    var createdAt: Date
    var text: String?
    var url: URL?
    var fileURLs: [URL]?
    var imageData: Data?
    var boardID: UUID?
    var isFavorite: Bool
    var sourceApplication: String?
    var sourceApplicationBundleID: String?
    /// 剪贴项在 macOS 剪贴板上的 Uniform Type Identifier（如 public.plain-text、public.html、public.png 等），用于标识原始数据类型。
    var uti: String?
    /// 对应 uti 的原始二进制数据，用于粘贴时保真写回剪贴板。
    var utiData: Data?
    /// 剪贴板上所有可用 UTI 类型及其原始数据，粘贴时全部写回以保真还原来源格式。
    var allPasteboardData: [UTIEntry]?
    /// 创建时计算并持久化的来源 app icon 主色调（已编码为 sRGB 分量）。
    /// 旧数据无此字段时回退到 AppIconCache 计算。
    var sourceAppColor: CodableColor? = nil
    var title: String?

    init(kind: ClipKind, text: String? = nil, url: URL? = nil, fileURLs: [URL]? = nil, imageData: Data? = nil, uti: String? = nil, utiData: Data? = nil, allPasteboardData: [UTIEntry]? = nil) {
        self.id = UUID(); self.kind = kind; self.createdAt = .now
        self.text = text; self.url = url; self.fileURLs = fileURLs; self.imageData = imageData
        self.boardID = nil; self.isFavorite = false
        self.sourceApplication = nil; self.sourceApplicationBundleID = nil; self.uti = uti; self.utiData = utiData; self.allPasteboardData = allPasteboardData; self.title = nil
    }
    

    var displayTitle: String {
        if let title, !title.isEmpty { return title }
        switch kind {
            case .text: return text?.split(separator: "\n").first.map(String.init) ?? previewPlainText ?? "文本"
            case .link: return url?.host ?? url?.absoluteString ?? previewPlainText ?? "链接"
            case .image: return "图片"
            case .file: return fileURLs?.first?.lastPathComponent ?? "文件"
            case .color: return text ?? "颜色"
        }
    }
    var detail: String {
        switch kind {
        case .text: return text ?? previewPlainText ?? ""
        case .link: return url?.absoluteString ?? previewPlainText ?? ""
        case .image: return ImageSizeCache.shared.sizeDescription(for: self) ?? "图片"
        case .file: return "\(fileURLs?.count ?? 0) 个文件"
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

struct AutomationRule: Codable, Identifiable, Hashable {
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

struct Pasteboard: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var color: String
    init(name: String, color: String) { id = UUID(); self.name = name; self.color = color }
}

/// 拖拽卡片在 Pinboard 之间移动用的内部数据载体。
struct ClipDragPayload: Codable, Transferable {
    let id: UUID
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .easypasteClip)
    }
}

extension UTType {
    static let easypasteClip = UTType(importedAs: "com.easypaste.clip")
    /// 看板（Pinboard）之间拖拽重排用的内部类型，仅在 App 进程内生效。
    static let easypasteBoard = UTType(importedAs: "com.easypaste.board")
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
