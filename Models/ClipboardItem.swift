import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum ClipboardKind: String, Codable, CaseIterable, Identifiable {
    case text, link, image, file
    var id: String { rawValue }
    var title: String {
        switch self {
        case .text: "文本"; case .link: "链接"; case .image: "图片"; case .file: "文件"
        }
    }
    var symbol: String { switch self { case .text: "text.alignleft"; case .link: "link"; case .image: "photo"; case .file: "doc" } }
}

struct ClipboardItem: Codable, Identifiable, Hashable {
    let id: UUID
    let kind: ClipboardKind
    let createdAt: Date
    var text: String?
    var url: URL?
    var fileURLs: [URL]?
    var imageData: Data?
    var boardID: UUID?
    var isFavorite: Bool
    var sourceApplication: String?
    var customTitle: String?

    init(kind: ClipboardKind, text: String? = nil, url: URL? = nil, fileURLs: [URL]? = nil, imageData: Data? = nil) {
        self.id = UUID(); self.kind = kind; self.createdAt = .now
        self.text = text; self.url = url; self.fileURLs = fileURLs; self.imageData = imageData
        self.boardID = nil; self.isFavorite = false
        self.sourceApplication = nil; self.customTitle = nil
    }

    var displayTitle: String {
        if let customTitle, !customTitle.isEmpty { return customTitle }
        switch kind {
        case .text: return text?.split(separator: "\n").first.map(String.init) ?? "文本"
        case .link: return url?.host ?? url?.absoluteString ?? "链接"
        case .image: return "图片"
        case .file: return fileURLs?.first?.lastPathComponent ?? "文件"
        }
    }
    var detail: String {
        switch kind {
        case .text: return text?.replacingOccurrences(of: "\n", with: " ") ?? ""
        case .link: return url?.absoluteString ?? ""
        case .image: return imageData.flatMap(NSImage.init(data:))?.size.debugDescription ?? "图片"
        case .file: return "\(fileURLs?.count ?? 0) 个文件"
        }
    }
}

struct AutomationRule: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var keyword: String
    var sourceApplication: String
    var targetBoardID: UUID?
    var enabled: Bool

    init(name: String, keyword: String = "", sourceApplication: String = "", targetBoardID: UUID? = nil, enabled: Bool = true) {
        id = UUID(); self.name = name; self.keyword = keyword; self.sourceApplication = sourceApplication
        self.targetBoardID = targetBoardID; self.enabled = enabled
    }

    func matches(_ item: ClipboardItem) -> Bool {
        guard enabled else { return false }
        let content = "\(item.displayTitle) \(item.detail)".lowercased()
        let keywordMatches = keyword.isEmpty || content.contains(keyword.lowercased())
        let appMatches = sourceApplication.isEmpty || item.sourceApplication?.localizedCaseInsensitiveContains(sourceApplication) == true
        return keywordMatches && appMatches
    }
}

struct Pasteboard: Codable, Identifiable, Hashable {
    let id: UUID
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
