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
    /// 创建时计算并持久化的来源 app icon 主色调（已编码为 sRGB 分量）。
    /// 旧数据无此字段时回退到 AppIconCache 计算。
    var sourceAppColor: CodableColor? = nil
    var title: String?

    init(kind: ClipKind, text: String? = nil, url: URL? = nil, fileURLs: [URL]? = nil, imageData: Data? = nil) {
        self.id = UUID(); self.kind = kind; self.createdAt = .now
        self.text = text; self.url = url; self.fileURLs = fileURLs; self.imageData = imageData
        self.boardID = nil; self.isFavorite = false
        self.sourceApplication = nil; self.sourceApplicationBundleID = nil; self.title = nil
    }
    

    var displayTitle: String {
        if let title, !title.isEmpty { return title }
        switch kind {
            case .text: return text?.split(separator: "\n").first.map(String.init) ?? "文本"
            case .link: return url?.host ?? url?.absoluteString ?? "链接"
            case .image: return "图片"
            case .file: return fileURLs?.first?.lastPathComponent ?? "文件"
            case .color: return text ?? "颜色"
        }
    }
    var detail: String {
        switch kind {
        case .text: return text ?? ""
        case .link: return url?.absoluteString ?? ""
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
