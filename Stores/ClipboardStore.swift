import Foundation
import Observation

@Observable @MainActor
final class ClipboardStore {
    private(set) var items: [ClipboardItem] = []
    private(set) var boards: [Pasteboard] = [Pasteboard(name: "灵感", color: "orange"), Pasteboard(name: "工作", color: "blue")]
    private(set) var rules: [AutomationRule] = []
    var selectedBoardID: UUID?
    var selectedKind: ClipboardKind?
    var query = ""
    var isFavoritesOnly = false
    /// 历史保留天数（0 = 无限）。由 AppServices 从设置同步。
    var historyLimitDays = 0
    private var fileURL: URL

    init(iCloud: Bool = false) {
        fileURL = Self.historyFileURL(iCloud: iCloud)
        load()
    }

    var filteredItems: [ClipboardItem] {
        items.filter { item in
            (selectedBoardID == nil || item.boardID == selectedBoardID) &&
            (selectedKind == nil || item.kind == selectedKind) &&
            (query.isEmpty || item.displayTitle.localizedCaseInsensitiveContains(query) || item.detail.localizedCaseInsensitiveContains(query))
        }
    }
    func add(_ item: ClipboardItem) {
        guard !items.contains(where: { $0.kind == item.kind && $0.displayTitle == item.displayTitle && $0.detail == item.detail }) else { return }
        var classified = item
        if let match = rules.first(where: { $0.matches(item) }) { classified.boardID = match.targetBoardID }
        items.insert(classified, at: 0)
        if items.count > 600 { items.removeLast(items.count - 600) }
        pruneExpired()
        save()
    }
    func toggleFavorite(_ id: UUID) { update(id) { $0.isFavorite.toggle() } }
    func move(_ id: UUID, to board: UUID?) { update(id) { $0.boardID = board } }
    func rename(_ id: UUID, title: String?) { update(id) { $0.customTitle = (title?.isEmpty == true) ? nil : title } }
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

    private func update(_ id: UUID, _ change: (inout ClipboardItem) -> Void) { guard let i = items.firstIndex(where: { $0.id == id }) else { return }; change(&items[i]); save() }
    private struct Archive: Codable {
        var items: [ClipboardItem]; var boards: [Pasteboard]; var rules: [AutomationRule]
        init(items: [ClipboardItem], boards: [Pasteboard], rules: [AutomationRule]) { self.items = items; self.boards = boards; self.rules = rules }
        enum CodingKeys: String, CodingKey { case items, boards, rules }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            items = try values.decode([ClipboardItem].self, forKey: .items)
            boards = try values.decode([Pasteboard].self, forKey: .boards)
            rules = try values.decodeIfPresent([AutomationRule].self, forKey: .rules) ?? []
        }
    }
    private func load() { guard let data = try? Data(contentsOf: fileURL), let archive = try? JSONDecoder().decode(Archive.self, from: data) else { return }; items = archive.items; boards = archive.boards; rules = archive.rules }
    private func save() { try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true); guard let data = try? JSONEncoder().encode(Archive(items: items, boards: boards, rules: rules)) else { return }; try? data.write(to: fileURL, options: .atomic) }
}
