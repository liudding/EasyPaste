import AppKit
import Foundation

enum ClipboardKind: String, Codable, CaseIterable, Identifiable {
    case text, link, image, file
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
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

    init(kind: ClipboardKind, text: String? = nil, url: URL? = nil, fileURLs: [URL]? = nil, imageData: Data? = nil) {
        self.id = UUID(); self.kind = kind; self.createdAt = .now
        self.text = text; self.url = url; self.fileURLs = fileURLs; self.imageData = imageData
        self.boardID = nil; self.isFavorite = false
        self.sourceApplication = nil
    }

    var displayTitle: String {
        switch kind {
        case .text: return text?.split(separator: "\n").first.map(String.init) ?? "Text"
        case .link: return url?.host ?? url?.absoluteString ?? "Link"
        case .image: return "Image"
        case .file: return fileURLs?.first?.lastPathComponent ?? "File"
        }
    }
    var detail: String {
        switch kind {
        case .text: return text?.replacingOccurrences(of: "\n", with: " ") ?? ""
        case .link: return url?.absoluteString ?? ""
        case .image: return imageData.flatMap(NSImage.init(data:))?.size.debugDescription ?? "Image"
        case .file: return "\(fileURLs?.count ?? 0) file\(fileURLs?.count == 1 ? "" : "s")"
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
