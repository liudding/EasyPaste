import Foundation
import Observation

@Observable @MainActor
final class ClipboardStore {
    private(set) var items: [ClipboardItem] = []
    private(set) var boards: [Pasteboard] = [Pasteboard(name: "Ideas", color: "orange"), Pasteboard(name: "Work", color: "blue")]
    private(set) var rules: [AutomationRule] = []
    var selectedBoardID: UUID?
    var selectedKind: ClipboardKind?
    var query = ""
    var isFavoritesOnly = false
    private let fileURL: URL

    init() {
        fileURL = URL.applicationSupportDirectory.appending(path: "EasyPaste/history.json")
        load()
    }
    var filteredItems: [ClipboardItem] {
        items.filter { item in
            (!isFavoritesOnly || item.isFavorite) &&
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
        save()
    }
    func toggleFavorite(_ id: UUID) { update(id) { $0.isFavorite.toggle() } }
    func move(_ id: UUID, to board: UUID?) { update(id) { $0.boardID = board } }
    func delete(_ ids: Set<UUID>) { items.removeAll { ids.contains($0.id) }; save() }
    func addBoard(named name: String) { boards.append(Pasteboard(name: name, color: "purple")); save() }
    func addRule(_ rule: AutomationRule) { rules.append(rule); save() }
    func deleteRules(_ ids: Set<UUID>) { rules.removeAll { ids.contains($0.id) }; save() }
    func toggleRule(_ id: UUID) { guard let index = rules.firstIndex(where: { $0.id == id }) else { return }; rules[index].enabled.toggle(); save() }
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
