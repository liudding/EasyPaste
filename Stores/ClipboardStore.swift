import Foundation
import Observation
import GRDB
import SwiftUI

@Observable @MainActor
final class ClipboardStore {
    private(set) var items: [Clip] = []
    private(set) var boards: [Pasteboard] = [Pasteboard(name: L10n.defaultBoardIdeas, color: "orange"), Pasteboard(name: L10n.defaultBoardWork, color: "blue")]
    private(set) var rules: [AutomationRule] = []
    var selectedBoardID: UUID?
    var selectedKind: ClipKind?
    var query = ""
    var isFavoritesOnly = false
    /// 历史保留天数（0 = 无限）。由 AppServices 从设置同步。
    var historyLimitDays = 0

    /// 可配置条目上限（默认 2000，支持无限）。
    /// 由 AppServices 在启动时从 AppSettings 的 `maxItemsMode` / `maxItemsCount` 同步，
    /// 运行时亦通过 `settings.onMaxItemsChanged` 回写并触发 prune。
    enum MaxItems {
        case unlimited
        case limited(Int)
    }
    var maxItems: MaxItems = .limited(2000)

    private let dbQueue: DatabaseQueue
    private let dbURL: URL
    private let backupService: BackupService

    /// - Parameter databaseURL: 数据库文件路径。传 nil 使用本地实时库默认路径
    ///   （`Application Support/EasyPaste/db.sqlite`）；测试可传入临时目录。
    init(databaseURL: URL? = nil) {
        let url = databaseURL ?? DatabaseManager.databaseFileURL
        self.dbURL = url
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        do {
            self.dbQueue = try DatabaseManager.open(url)
        } catch {
            fatalError("EasyPaste: 无法打开本地数据库: \(error)")
        }
        self.backupService = BackupService(dbQueue: dbQueue, localURL: url)
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

    // MARK: - 读取（从 GRDB 全量填充内存，保持 UI 门面不变）

    private func load() {
        reloadItems()
        // 看板：空库时播种默认看板（应用默认数据，非旧历史导入）。
        do {
            let rows = try dbQueue.read { try PasteboardRow.fetchAll($0, sql: "SELECT * FROM pasteboards ORDER BY sortIndex IS NULL, sortIndex, rowid") }
            boards = rows.map { $0.toPasteboard() }
        } catch {
            boards = []
        }
        if boards.isEmpty {
            let defaults = [Pasteboard(name: L10n.defaultBoardIdeas, color: "orange"), Pasteboard(name: L10n.defaultBoardWork, color: "blue")]
            boards = defaults
            _ = try? dbQueue.write { db in
                for b in defaults { try PasteboardRow(b).insert(db) }
            }
        }
        // 规则
        do {
            let rows = try dbQueue.read { try AutomationRuleRow.fetchAll($0) }
            rules = rows.map { $0.toAutomationRule() }
        } catch {
            rules = []
        }
    }

    /// 从 `clips` + `clip_blobs` 重新加载内存 items（列表按 createdAt 倒序，最新在前）。
    private func reloadItems() {
        do {
            let clips = try dbQueue.read { try ClipRow.fetchAll($0, sql: "SELECT * FROM clips ORDER BY createdAt DESC") }
            let blobs = try dbQueue.read { try ClipBlobRow.fetchAll($0) }
            let blobByID = Dictionary(uniqueKeysWithValues: blobs.map { ($0.clipID, $0) })
            items = clips.map { $0.toClip(blob: blobByID[$0.id]) }
        } catch {
            // 读取失败保持内存现状，不破坏 UI。
        }
    }

    // MARK: - 写入（更新内存 + 写穿 GRDB）

    func add(_ item: Clip) {
        // 基于 contentHash 去重：重复时更新 createdAt 并置顶，而非跳过
        if let hash = item.contentHash {
            if let existingIndex = items.firstIndex(where: {
                $0.kind == item.kind && $0.contentHash == hash
            }) {
                promoteClip(at: existingIndex)
                return
            }
        } else {
            // 无 contentHash 的旧数据回退到 displayTitle + detail 去重
            let fallbackHash = ClipTypeDetector.computeFallbackHash(
                kind: item.kind, title: item.displayTitle, detail: item.detail)
            if let existingIndex = items.firstIndex(where: {
                $0.kind == item.kind &&
                ($0.contentHash ?? ClipTypeDetector.computeFallbackHash(
                    kind: $0.kind, title: $0.displayTitle, detail: $0.detail)) == fallbackHash
            }) {
                promoteClip(at: existingIndex)
                return
            }
        }
        var classified = item
        if let match = rules.first(where: { $0.matches(item) }) { classified.boardID = match.targetBoardID }
        items.insert(classified, at: 0)
        writeClip(classified)
        pruneExpired()
        backupService.scheduleBackupOnIdle()
    }

    /// 将已有条目更新 createdAt 并移至列表最前（重复内容置顶）。
    private func promoteClip(at index: Int) {
        items[index].createdAt = .now
        let promoted = items.remove(at: index)
        items.insert(promoted, at: 0)
        writeClip(promoted)
        backupService.scheduleBackupOnIdle()
    }

    func toggleFavorite(_ id: UUID) { update(id) { $0.isFavorite.toggle() } }
    func move(_ id: UUID, to board: UUID?) { update(id) { $0.boardID = board } }
    func rename(_ id: UUID, title: String?) { update(id) { $0.title = (title?.isEmpty == true) ? nil : title } }

    func delete(_ ids: Set<UUID>) {
        items.removeAll { ids.contains($0.id) }
        let keys = ids.map { $0.uuidString }
        _ = try? dbQueue.write { db in
            try ClipRow.deleteAll(db, keys: keys)
            try db.execute(literal: "DELETE FROM clip_blobs WHERE clipID NOT IN (SELECT id FROM clips)")
        }
        backupService.scheduleBackupOnIdle()
    }

    func clearAll() {
        items.removeAll()
        _ = try? dbQueue.write { db in
            try ClipRow.deleteAll(db)
            try ClipBlobRow.deleteAll(db)
        }
        backupService.scheduleBackupOnIdle()
    }

    func addBoard(named name: String, color: String = "purple") {
        let board = Pasteboard(name: name, color: color)
        boards.append(board)
        _ = try? dbQueue.write { db in try PasteboardRow(board, sortIndex: boards.count - 1).insert(db) }
        backupService.scheduleBackupOnIdle()
    }

    /// 重命名看板（空名则忽略）。
    func renameBoard(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              let i = boards.firstIndex(where: { $0.id == id }) else { return }
        boards[i].name = trimmed
        _ = try? dbQueue.write { db in try PasteboardRow(boards[i], sortIndex: i).upsert(db) }
        backupService.scheduleBackupOnIdle()
    }

    /// 修改看板颜色。
    func updateBoardColor(_ id: UUID, color: String) {
        guard let i = boards.firstIndex(where: { $0.id == id }) else { return }
        boards[i].color = color
        _ = try? dbQueue.write { db in try PasteboardRow(boards[i], sortIndex: i).upsert(db) }
        backupService.scheduleBackupOnIdle()
    }

    /// 删除看板：移除看板行，并将该看板上的所有剪贴项解绑（boardID 置 nil）。
    func deleteBoard(_ id: UUID) {
        let boardKey = id.uuidString
        boards.removeAll { $0.id == id }
        for i in items.indices where items[i].boardID == id {
            items[i].boardID = nil
        }
        _ = try? dbQueue.write { db in
            try PasteboardRow.deleteOne(db, key: boardKey)
            try db.execute(sql: "UPDATE clips SET boardID = NULL WHERE boardID = ?", arguments: [boardKey])
        }
        if selectedBoardID == id { selectedBoardID = nil }
        backupService.scheduleBackupOnIdle()
    }

    /// 删除看板及其所有剪贴项。
    func deleteBoardAndClips(_ id: UUID) {
        let boardKey = id.uuidString
        let clipIDs = items.filter { $0.boardID == id }.map(\.id)
        let clipKeys = clipIDs.map(\.uuidString)
        boards.removeAll { $0.id == id }
        items.removeAll { $0.boardID == id }
        _ = try? dbQueue.write { db in
            try PasteboardRow.deleteOne(db, key: boardKey)
            if !clipKeys.isEmpty {
                try ClipRow.deleteAll(db, keys: clipKeys)
                try db.execute(literal: "DELETE FROM clip_blobs WHERE clipID NOT IN (SELECT id FROM clips)")
            }
        }
        if selectedBoardID == id { selectedBoardID = nil }
        backupService.scheduleBackupOnIdle()
    }

    /// 返回指定看板上的剪贴项数量。
    func clipCount(for boardID: UUID) -> Int {
        items.filter { $0.boardID == boardID }.count
    }

    /// 看板拖拽重排：把 `sourceID` 看板移动到 `targetID` 看板之前，并持久化新顺序。
    func moveBoard(_ sourceID: UUID, to targetID: UUID) {
        guard sourceID != targetID,
              boards.firstIndex(where: { $0.id == sourceID }) != nil,
              boards.firstIndex(where: { $0.id == targetID }) != nil else { return }
        var reordered = boards
        guard let from = reordered.firstIndex(where: { $0.id == sourceID }) else { return }
        let moved = reordered.remove(at: from)
        let insertAt = reordered.firstIndex(where: { $0.id == targetID }) ?? reordered.count
        reordered.insert(moved, at: insertAt)
        boards = reordered
        persistBoardOrder()
    }

    /// 看板实时重排（拖拽手势用）：把 `sourceID` 看板移动到 `gap` 间隔位
    /// （`gap` 为移除自身后数组中的插入下标，0...count-1），带弹簧动画。
    /// 返回顺序是否真的发生了变化。
    @discardableResult
    func moveBoardToGap(_ sourceID: UUID, gap: Int) -> Bool {
        guard let from = boards.firstIndex(where: { $0.id == sourceID }) else { return false }
        var reordered = boards
        let moved = reordered.remove(at: from)
        let insertAt = min(max(gap, 0), reordered.count)
        reordered.insert(moved, at: insertAt)
        guard reordered.map({ $0.id }) != boards.map({ $0.id }) else { return false }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            boards = reordered
        }
        return true
    }

    /// 将当前内存中的看板顺序写穿到 DB（sortIndex 列），供重排后持久化。
    func persistBoardOrder() {
        _ = try? dbQueue.write { db in
            for (index, board) in boards.enumerated() {
                try PasteboardRow(board, sortIndex: index).upsert(db)
            }
        }
        backupService.scheduleBackupOnIdle()
    }

    func addRule(_ rule: AutomationRule) {
        rules.append(rule)
        _ = try? dbQueue.write { db in try AutomationRuleRow(rule).insert(db) }
        backupService.scheduleBackupOnIdle()
    }

    func deleteRules(_ ids: Set<UUID>) {
        rules.removeAll { ids.contains($0.id) }
        let keys = ids.map { $0.uuidString }
        _ = try? dbQueue.write { db in try AutomationRuleRow.deleteAll(db, keys: keys) }
        backupService.scheduleBackupOnIdle()
    }

    func toggleRule(_ id: UUID) {
        guard let index = rules.firstIndex(where: { $0.id == id }) else { return }
        rules[index].enabled.toggle()
        let rule = rules[index]
        _ = try? dbQueue.write { db in try AutomationRuleRow(rule).upsert(db) }
        backupService.scheduleBackupOnIdle()
    }

    /// 单条更新：改内存 + 写穿 GRDB（upsert）。
    private func update(_ id: UUID, _ change: (inout Clip) -> Void) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[i])
        let clip = items[i]
        writeClip(clip)
        backupService.scheduleBackupOnIdle()
    }

    /// 将 Clip（含 blob）写穿到 GRDB，与 `clip_blobs` 在同一事务内同步。
    private func writeClip(_ clip: Clip) {
        let clipRow = ClipRow(clip)
        let hasBlob = clip.imageData != nil
            || clip.utiData != nil
            || (clip.allPasteboardData?.isEmpty == false)
        _ = try? dbQueue.write { db in
            try clipRow.upsert(db)
            if hasBlob {
                try ClipBlobRow(clip).upsert(db)
            } else {
                // 无 blob 数据时确保清理可能残留的旧 blob 行。
                try ClipBlobRow.deleteAll(db, keys: [clipRow.id])
            }
        }
    }

    // MARK: - 保留策略（按天 + 按条数 + 磁盘压力）

    /// 删除超过保留时长的历史；days <= 0 表示不限制。返回删除条数。
    /// 同时执行可配置条数上限与磁盘压力淘汰，并回收孤立的 `clip_blobs`。
    @discardableResult
    func pruneExpired(limitDays: Int? = nil) -> Int {
        pruneNow(days: limitDays ?? historyLimitDays, diskPressure: shouldEvictByDiskPressure())
    }

    /// 内部 prune 入口（供测试显式触发磁盘压力分支）。
    func pruneNow(days: Int, diskPressure: Bool) -> Int {
        let max = maxItems
        var deleted = 0
        _ = try? dbQueue.write { db in
            // 1) 按天保留
            if days > 0 {
                let cutoff = Date().timeIntervalSince1970 - Double(days) * 86_400
                try db.execute(sql: "DELETE FROM clips WHERE createdAt < ?", arguments: [cutoff])
                deleted += (try? Int.fetchOne(db, sql: "SELECT changes()")) ?? 0
            }
            // 2) 按条数上限（去掉原 600 硬上限）
            if case let .limited(limit) = max {
                let count = (try? Int.fetchOne(db, sql: "SELECT COUNT(*) FROM clips")) ?? 0
                let over = count - limit
                if over > 0 {
                try db.execute(
                    sql: "DELETE FROM clips WHERE id IN (SELECT id FROM clips ORDER BY createdAt ASC LIMIT ?)",
                    arguments: [over]
                )
                    deleted += (try? Int.fetchOne(db, sql: "SELECT changes()")) ?? 0
                }
            }
            // 3) 磁盘压力淘汰
            if diskPressure {
                try db.execute(
                    sql: "DELETE FROM clips WHERE id IN (SELECT id FROM clips ORDER BY createdAt ASC LIMIT ?)",
                    arguments: [BackupService.diskPressureBatch]
                )
                deleted += (try? Int.fetchOne(db, sql: "SELECT changes()")) ?? 0
            }
            // 统一回收 clip_blobs 孤儿（单 SQL，原子）
            if deleted > 0 {
                try db.execute(literal: "DELETE FROM clip_blobs WHERE clipID NOT IN (SELECT id FROM clips)")
            }
        }
        if deleted > 0 { reloadItems() }
        return deleted
    }

    /// 是否触发磁盘压力淘汰：本地库文件超过阈值，或所在卷可用空间不足。
    private func shouldEvictByDiskPressure() -> Bool {
        let dbSize = (try? FileManager.default.attributesOfItem(atPath: dbURL.path)[.size] as? UInt64) ?? 0
        if dbSize > Self.diskPressureThresholdBytes { return true }
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: dbURL.path),
           let free = attrs[.systemFreeSize] as? UInt64,
           free < Self.minFreeSpaceBytes { return true }
        return false
    }

    /// 本地库文件超过该大小（默认 200MB）触发磁盘压力淘汰。
    private static let diskPressureThresholdBytes: UInt64 = 200 * 1024 * 1024
    /// 所在卷可用空间低于该值（默认 500MB）触发磁盘压力淘汰。
    private static let minFreeSpaceBytes: UInt64 = 500 * 1024 * 1024

    // MARK: - iCloud ubiquity 备份

    /// 控制 ubiquity 备份开关（启用/停用 BackupService 的定时备份）。
    /// 原语义为切换 history.json 路径，现改为控制 ubiquity 文件级备份。
    func setICloudSyncEnabled(_ enabled: Bool) {
        backupService.setEnabled(enabled)
    }

    /// 应用进后台时立即触发一次备份。
    func triggerCloudBackup() {
        Task { @MainActor in await backupService.backupNow() }
    }

    /// 空闲时调度一次备份（每次写入后由内部调用）。
    func scheduleCloudBackup() {
        backupService.scheduleBackupOnIdle()
    }
}

/// 计算 Clip 的内容 hash，用于去重。
/// 基于 allPasteboardData 实际内容计算 SHA-256，回退到 displayTitle + detail。
private func clipHash(_ clip: Clip) -> String {
    ClipTypeDetector.computeContentHash(clip.allPasteboardData)
        ?? ClipTypeDetector.computeFallbackHash(
            kind: clip.kind, title: clip.displayTitle, detail: clip.detail)
}

extension Data {
    var sha256Hex: String {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        self.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(buffer.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
import CommonCrypto
