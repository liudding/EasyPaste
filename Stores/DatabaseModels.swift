import Foundation
import GRDB

// MARK: - clips 行适配器

/// `clips` 表的 GRDB 行适配器。
/// `Clip` 内存模型保持原有 `Codable` 结构不变，这里仅负责与数据库列的双向映射，
/// 不污染 `Models/Clip.swift`。
struct ClipRow: FetchableRecord, PersistableRecord, Codable {
    static let databaseTableName = "clips"

    let id: String
    let kind: String
    let createdAt: Double
    let text: String?
    let url: String?
    let fileURLs: String?           // JSON 数组 [String]（absoluteString）
    let boardID: String?
    let isFavorite: Int
    let sourceApplication: String?
    let sourceApplicationBundleID: String?
    let uti: String?
    let sourceAppColorRed: Double?
    let sourceAppColorGreen: Double?
    let sourceAppColorBlue: Double?
    let contentColorRed: Double?
    let contentColorGreen: Double?
    let contentColorBlue: Double?
    let title: String?

    init(_ clip: Clip) {
        id = clip.id.uuidString
        kind = clip.kind.rawValue
        createdAt = clip.createdAt.timeIntervalSince1970
        text = clip.text
        url = clip.url?.absoluteString
        fileURLs = clip.fileURLs.flatMap { urls in
            (try? JSONEncoder().encode(urls.map { $0.absoluteString }))
                .flatMap { String(data: $0, encoding: .utf8) }
        }
        boardID = clip.boardID?.uuidString
        isFavorite = clip.isFavorite ? 1 : 0
        sourceApplication = clip.sourceApplication
        sourceApplicationBundleID = clip.sourceApplicationBundleID
        uti = clip.uti
        sourceAppColorRed = clip.sourceAppColor?.red
        sourceAppColorGreen = clip.sourceAppColor?.green
        sourceAppColorBlue = clip.sourceAppColor?.blue
        contentColorRed = clip.contentColor?.red
        contentColorGreen = clip.contentColor?.green
        contentColorBlue = clip.contentColor?.blue
        title = clip.title
    }

    /// 还原为内存 `Clip`。`blob` 来自 `clip_blobs` 表（同一事务写入）。
    func toClip(blob: ClipBlobRow?) -> Clip {
        let fileURLs = self.fileURLs.flatMap { decodeFileURLs($0) }
        var clip = Clip(
            kind: ClipKind(rawValue: kind) ?? .text,
            text: text,
            url: url.flatMap { URL(string: $0) },
            fileURLs: fileURLs,
            imageData: blob?.imageData,
            uti: uti,
            utiData: blob?.utiData,
            allPasteboardData: blob?.allPasteboardData.flatMap { decodeUTIEntries($0) }
        )
        clip.id = UUID(uuidString: id) ?? UUID()
        clip.createdAt = Date(timeIntervalSince1970: createdAt)
        clip.boardID = boardID.flatMap { UUID(uuidString: $0) }
        clip.isFavorite = isFavorite != 0
        clip.sourceApplication = sourceApplication
        clip.sourceApplicationBundleID = sourceApplicationBundleID
        clip.title = title
        if let r = sourceAppColorRed, let g = sourceAppColorGreen, let b = sourceAppColorBlue {
            clip.sourceAppColor = CodableColor(red: r, green: g, blue: b)
        }
        if let r = contentColorRed, let g = contentColorGreen, let b = contentColorBlue {
            clip.contentColor = CodableColor(red: r, green: g, blue: b)
        }
        return clip
    }
}

// MARK: - clip_blobs 行适配器

/// `clip_blobs` 表的 GRDB 行适配器（1:1 懒加载，列表不 SELECT 此表）。
struct ClipBlobRow: FetchableRecord, PersistableRecord, Codable {
    static let databaseTableName = "clip_blobs"

    let clipID: String
    let imageData: Data?
    let utiData: Data?
    let allPasteboardData: Data?   // [UTIEntry] 编码为 JSON Data

    init(_ clip: Clip) {
        clipID = clip.id.uuidString
        imageData = clip.imageData
        utiData = clip.utiData
        allPasteboardData = encodeUTIEntries(clip.allPasteboardData)
    }
}

// MARK: - pasteboards 行适配器

struct PasteboardRow: FetchableRecord, PersistableRecord, Codable {
    static let databaseTableName = "pasteboards"

    let id: String
    let name: String
    let color: String
    var sortIndex: Int?

    init(_ board: Pasteboard, sortIndex: Int? = nil) {
        id = board.id.uuidString
        name = board.name
        color = board.color
        self.sortIndex = sortIndex
    }

    func toPasteboard() -> Pasteboard {
        var board = Pasteboard(name: name, color: color)
        board.id = UUID(uuidString: id) ?? UUID()
        return board
    }
}

// MARK: - automation_rules 行适配器

struct AutomationRuleRow: FetchableRecord, PersistableRecord, Codable {
    static let databaseTableName = "automation_rules"

    let id: String
    let name: String
    let keyword: String
    let sourceApplication: String
    let targetBoardID: String?
    let enabled: Int

    init(_ rule: AutomationRule) {
        id = rule.id.uuidString
        name = rule.name
        keyword = rule.keyword
        sourceApplication = rule.sourceApplication
        targetBoardID = rule.targetBoardID?.uuidString
        enabled = rule.enabled ? 1 : 0
    }

    func toAutomationRule() -> AutomationRule {
        var rule = AutomationRule(
            name: name,
            keyword: keyword,
            sourceApplication: sourceApplication,
            targetBoardID: targetBoardID.flatMap { UUID(uuidString: $0) },
            enabled: enabled != 0
        )
        rule.id = UUID(uuidString: id) ?? UUID()
        return rule
    }
}

// MARK: - 编码辅助

/// 将 `[UTIEntry]` 编码为 JSON `Data` 存入 `clip_blobs.allPasteboardData`。
private func encodeUTIEntries(_ entries: [UTIEntry]?) -> Data? {
    guard let entries else { return nil }
    return try? JSONEncoder().encode(entries)
}

/// 从 `clip_blobs.allPasteboardData` 的 JSON `Data` 解码回 `[UTIEntry]`。
private func decodeUTIEntries(_ data: Data) -> [UTIEntry]? {
    try? JSONDecoder().decode([UTIEntry].self, from: data)
}

/// 将 `fileURLs` 的 JSON 数组字符串还原为 `[URL]`。
private func decodeFileURLs(_ json: String) -> [URL]? {
    guard let data = json.data(using: .utf8),
          let arr = try? JSONDecoder().decode([String].self, from: data) else { return nil }
    return arr.compactMap { URL(string: $0) }
}
