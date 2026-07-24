import Foundation
import Observation

@Observable @MainActor
final class ClipboardStore {
    private(set) var items: [Clip] = []
    private(set) var boards: [Pasteboard] = [Pasteboard(name: "灵感", color: "orange"), Pasteboard(name: "工作", color: "blue")]
    private(set) var rules: [AutomationRule] = []
    var selectedBoardID: UUID?
    var selectedKind: ClipKind?
    var query = ""
    var isFavoritesOnly = false
    /// 历史保留天数（0 = 无限）。由 AppServices 从设置同步。
    var historyLimitDays = 0
    private var fileURL: URL

    init(iCloud: Bool = false) {
        fileURL = Self.historyFileURL(iCloud: iCloud)
        selectedBoardID = nil
        load()
    }

    /// 过滤结果：每次访问都直接基于 items 与过滤条件计算。
    /// 必须始终读取 items（而非返回缓存），否则 SwiftUI 的 Observation 不会在本次渲染中登记对
    /// items 的依赖，导致增删剪贴项后列表不刷新（需点击其他 item 才刷新的 bug）。
    var filteredItems: [Clip] {
        items.filter { item in
            (selectedBoardID == nil || item.boardID == selectedBoardID) &&
            (selectedKind == nil || item.kind == selectedKind) &&
            (query.isEmpty || item.displayTitle.localizedCaseInsensitiveContains(query) || item.detail.localizedCaseInsensitiveContains(query))
        }
    }
    func add(_ item: Clip) {
        // 用 allPasteboardData 的哈希去重：相同原始数据的剪贴板只保留一条
        if let data = item.allPasteboardData, !data.isEmpty {
            let hash = clipHash(item)
            if items.contains(where: { $0.id != item.id && $0.kind == item.kind && clipHash($0) == hash }) { return }
        } else {
            // 无 allPasteboardData 的旧数据仍按 displayTitle + detail 去重
            guard !items.contains(where: { $0.kind == item.kind && $0.displayTitle == item.displayTitle && $0.detail == item.detail }) else { return }
        }
        var classified = item
        if let match = rules.first(where: { $0.matches(item) }) { classified.boardID = match.targetBoardID }
        items.insert(classified, at: 0)
        if items.count > 600 { items.removeLast(items.count - 600) }
        pruneExpired()
        save()
    }
    func toggleFavorite(_ id: UUID) { update(id) { $0.isFavorite.toggle() } }
    func move(_ id: UUID, to board: UUID?) { update(id) { $0.boardID = board } }
    func rename(_ id: UUID, title: String?) { update(id) { $0.title = (title?.isEmpty == true) ? nil : title } }
    func delete(_ ids: Set<UUID>) { items.removeAll { ids.contains($0.id) }; save() }
    func clearAll() { items.removeAll(); save() }
    func addBoard(named name: String, color: String = "purple") { boards.append(Pasteboard(name: name, color: color)); save() }
    func addRule(_ rule: AutomationRule) { rules.append(rule); save() }
    func deleteRules(_ ids: Set<UUID>) { rules.removeAll { ids.contains($0.id) }; save() }
    func toggleRule(_ id: UUID) { guard let index = rules.firstIndex(where: { $0.id == id }) else { return }; rules[index].enabled.toggle(); save() }

    /// 删除超过保留时长的历史；days <= 0 表示不限制。
    func pruneExpired(limitDays: Int? = nil) {
        let days = limitDays ?? historyLimitDays
        guard days > 0 else { return }
        let cutoff = Date().addingTimeInterval(-TimeInterval(days) * 86_400)
        let before = items.count
        items.removeAll { $0.createdAt < cutoff }
        if items.count != before { save() }
    }

    /// 在本地与 iCloud 容器之间切换历史存储位置。
    func setICloudSyncEnabled(_ enabled: Bool) {
        let newURL = Self.historyFileURL(iCloud: enabled)
        guard newURL != fileURL else { return }
        fileURL = newURL
        save()
    }

    private static func historyFileURL(iCloud: Bool) -> URL {
        if iCloud, let container = FileManager.default.url(forUbiquityContainerIdentifier: nil) {
            return container.appending(path: "Documents/EasyPaste/history.json")
        }
        return URL.applicationSupportDirectory.appending(path: "EasyPaste/history.json")
    }

    private func update(_ id: UUID, _ change: (inout Clip) -> Void) { guard let i = items.firstIndex(where: { $0.id == id }) else { return }; change(&items[i]); save() }
    private struct Archive: Codable {
        var items: [Clip]; var boards: [Pasteboard]; var rules: [AutomationRule]
        init(items: [Clip], boards: [Pasteboard], rules: [AutomationRule]) { self.items = items; self.boards = boards; self.rules = rules }
        enum CodingKeys: String, CodingKey { case items, boards, rules }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            items = try values.decode([Clip].self, forKey: .items)
            boards = try values.decode([Pasteboard].self, forKey: .boards)
            rules = try values.decodeIfPresent([AutomationRule].self, forKey: .rules) ?? []
        }
    }
    private func load() { guard let data = try? Data(contentsOf: fileURL), let archive = try? JSONDecoder().decode(Archive.self, from: data) else { return }; items = archive.items; boards = archive.boards; rules = archive.rules }
    private func save() { try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true); guard let data = try? JSONEncoder().encode(Archive(items: items, boards: boards, rules: rules)) else { return }; try? data.write(to: fileURL, options: .atomic) }
}

/// 计算 Clip 的 allPasteboardData 哈希值，用于去重。
/// 将 UTI 类型和数据长度组合成一个字符串后计算 SHA-256。
private func clipHash(_ clip: Clip) -> String {
    guard let entries = clip.allPasteboardData else { return "" }
    var components = [String]()
    for entry in entries.sorted(by: { $0.uti < $1.uti }) {
        components.append("\(entry.uti):\(entry.data.count)")
    }
    let input = components.joined(separator: "|")
    if let data = input.data(using: .utf8) {
        return data.sha256Hex
    }
    return input
}

extension Data {
    var sha256Hex: String {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        withUnsafeBytes { buf in
            buf.baseAddress?.assumingMemoryBound(to: UInt8.self)
        }
        CC_SHA256(self.withUnsafeBytes { $0.baseAddress }, CC_LONG(self.count), &hash)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
import CommonCrypto
