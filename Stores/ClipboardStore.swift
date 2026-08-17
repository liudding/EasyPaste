import CommonCrypto
import Foundation
import Observation
import SwiftData
import SwiftUI

@Observable @MainActor
final class ClipboardStore {
    private(set) var items: [Clip] = [] {
        didSet { sourceAppsCache = nil; filteredCache = nil }
    }
    private(set) var boards: [Pasteboard] = [Pasteboard(name: L10n.defaultBoardIdeas, color: "orange"), Pasteboard(name: L10n.defaultBoardWork, color: "blue")]
    private(set) var rules: [AutomationRule] = []
    var selectedBoardID: UUID? { didSet { filteredCache = nil } }
    var selectedKind: ClipKind? { didSet { filteredCache = nil } }
    /// TextField 实时绑定的原始 query（用于输入与 suggestion，过滤由 `effectiveQuery` 驱动）。
    var query = "" { didSet { scheduleQueryDebounce() } }
    /// 防抖后的过滤 query（150ms 窗口），驱动 `filteredItems`。
    private(set) var effectiveQuery = "" {
        didSet {
            filteredCache = nil
            filterTokens = Self.tokenize(effectiveQuery)
        }
    }
    /// 查询输入分词后的 tokens（小写），供热路径逐条 contains（AND 匹配）。
    private var filterTokens: [String] = []
    private var queryDebounceTask: Task<Void, Never>?
    /// 过滤结果缓存：同一组过滤条件内多次读取（ForEach / isEmpty / validateSelection）只算一次。
    private var filteredCache: [Clip]?
    /// `distinctSourceApps` 缓存，items 变化时失效。
    private var sourceAppsCache: [String]?
    /// 存量数据 searchText 索引懒回填标记（进程内只执行一次）。
    private var didBackfillSearchIndex = false
    var isFavoritesOnly = false { didSet { filteredCache = nil } }
    /// 搜索栏激活的筛选 tag（类型 / 应用 / 日期）。board 维度通过 selectedBoardID 联动。
    var activeFilters: [SearchFilter] = []
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

    private let context: ModelContext
    private let dbURL: URL
    private let backupService: BackupService

    /// - Parameter databaseURL: 数据库文件路径。传 nil 使用本地实时库默认路径
    ///   （`Application Support/EasyPaste/db.sqlite`）；测试可传入临时目录。
    init(databaseURL: URL? = nil) {
        let url = databaseURL ?? DataManager.databaseFileURL
        self.dbURL = url
        do {
            let container = try DataManager.makeContainer(url: url)
            self.context = ModelContext(container)
        } catch {
            fatalError("EasyPaste: 无法打开本地数据库: \(error)")
        }
        self.backupService = BackupService(dbURL: url, context: context)
        load()
    }

    /// 过滤结果：基于内存 items + 预构建 searchText 索引计算，带结果缓存。
    /// 热路径只做小写 `contains`（索引在写入时归一化一次），不再逐条计算 detail/previewPlainText。
    /// 必须显式读取参与过滤的源状态（items / effectiveQuery / selectedBoardID / selectedKind / activeFilters），
    /// 确保 SwiftUI 的 Observation 在本次渲染中登记依赖；缓存命中时同样需要这些读取以保持依赖注册。
    var filteredItems: [Clip] {
        _ = items
        _ = effectiveQuery
        _ = selectedBoardID
        _ = selectedKind
        _ = activeFilters
        if let cached = filteredCache { return cached }
        let result = items.filter { item in
            (selectedBoardID == nil || item.boardID == selectedBoardID) &&
            (selectedKind == nil || item.kind == selectedKind) &&
            (filterTokens.isEmpty || filterTokens.allSatisfy { item.searchText?.contains($0) == true }) &&
            facetFilterPasses(item)
        }
        filteredCache = result
        return result
    }

    /// 按空白+标点拆分查询为小写 tokens（中文整句无分隔符时保持单 token 子串匹配）。
    private static func tokenize(_ query: String) -> [String] {
        let separators = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        return query.lowercased()
            .components(separatedBy: separators)
            .filter { !$0.isEmpty }
    }

    /// 所有剪贴项中出现过的来源 app 名称（去重，按字母排序）。带缓存，items 变化时失效。
    var distinctSourceApps: [String] {
        if let cached = sourceAppsCache { return cached }
        let apps = Set(items.compactMap { $0.sourceApplication }.filter { !$0.isEmpty })
        let sorted = apps.sorted()
        sourceAppsCache = sorted
        return sorted
    }

    /// query 防抖：150ms 窗口内连续输入只触发一次过滤（取消前序任务）。
    private func scheduleQueryDebounce() {
        queryDebounceTask?.cancel()
        let snapshot = query
        queryDebounceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            effectiveQuery = snapshot
        }
    }

    /// 分面筛选：同一维度内为 OR（任一匹配），不同维度间为 AND（全部满足）。
    private func facetFilterPasses(_ item: Clip) -> Bool {
        if activeFilters.isEmpty { return true }
        let kindFilters = activeFilters.compactMap { if case .kind(let k) = $0 { return k } else { return nil } }
        let appFilters = activeFilters.compactMap { if case .app(let a) = $0 { return a } else { return nil } }
        let dateFilters = activeFilters.compactMap { if case .dateRange(let d) = $0 { return d } else { return nil } }
        if !kindFilters.isEmpty && !kindFilters.contains(item.kind) { return false }
        if !appFilters.isEmpty && !(item.sourceApplication.map { appFilters.contains($0) } ?? false) { return false }
        if !dateFilters.isEmpty && !dateFilters.contains(where: { $0.contains(item.createdAt) }) { return false }
        return true
    }

    /// 切换筛选 tag（已存在则移除，不存在则添加）。board 维度联动 selectedBoardID。
    func toggleFilter(_ filter: SearchFilter) {
        switch filter {
        case .board(let id):
            selectedBoardID = (selectedBoardID == id) ? nil : id
        default:
            if let idx = activeFilters.firstIndex(of: filter) {
                activeFilters.remove(at: idx)
            } else {
                activeFilters.append(filter)
            }
        }
    }

    /// 移除指定筛选 tag。
    func removeFilter(_ filter: SearchFilter) {
        switch filter {
        case .board:
            selectedBoardID = nil
        default:
            activeFilters.removeAll { $0 == filter }
        }
    }

    /// 清除所有筛选（activeFilters + selectedBoardID），但不清除 query。
    func clearAllFilters() {
        activeFilters.removeAll()
        selectedBoardID = nil
    }

    // MARK: - 读取（从 SwiftData 全量填充内存，保持 UI 门面不变）

    private func load() {
        reloadItems()
        // 看板：空库时播种默认看板（应用默认数据，非旧历史导入）。
        let boardDescriptor = FetchDescriptor<Pasteboard>(
            sortBy: [SortDescriptor(\.sortIndex, order: .forward), SortDescriptor(\.id, order: .forward)]
        )
        boards = (try? context.fetch(boardDescriptor)) ?? []
        if boards.isEmpty {
            let defaults = [
                Pasteboard(name: L10n.defaultBoardIdeas, color: "orange", sortIndex: 0),
                Pasteboard(name: L10n.defaultBoardWork, color: "blue", sortIndex: 1)
            ]
            boards = defaults
            for b in defaults { context.insert(b) }
            try? context.save()
        }
        // 规则
        let ruleDescriptor = FetchDescriptor<AutomationRule>()
        rules = (try? context.fetch(ruleDescriptor)) ?? []
    }

    /// 从 SwiftData 重新加载内存 items（列表按 createdAt 倒序，最新在前）。
    private func reloadItems() {
        let descriptor = FetchDescriptor<Clip>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        items = (try? context.fetch(descriptor)) ?? []
        backfillSearchIndexIfNeeded()
    }

    /// 存量数据迁移：对 searchText 为 nil 的条目构建一次全文索引并持久化（进程内只跑一次）。
    private func backfillSearchIndexIfNeeded() {
        guard !didBackfillSearchIndex else { return }
        didBackfillSearchIndex = true
        var changed = false
        for item in items where item.searchText == nil {
            item.buildSearchText()
            changed = true
        }
        if changed { try? context.save() }
    }

    // MARK: - 写入（更新内存 + 写穿 SwiftData）

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
        // 应用自动化规则
        if let match = rules.first(where: { $0.matches(item) }) {
            item.boardID = match.targetBoardID
        }
        context.insert(item)
        try? context.save()
        items.insert(item, at: 0)
        pruneExpired()
        backupService.scheduleBackupOnIdle()
    }

    /// 将已有条目更新 createdAt 并移至列表最前（重复内容置顶）。
    private func promoteClip(at index: Int) {
        items[index].createdAt = .now
        let promoted = items.remove(at: index)
        items.insert(promoted, at: 0)
        try? context.save()
        backupService.scheduleBackupOnIdle()
    }

    func toggleFavorite(_ id: UUID) { update(id) { $0.isFavorite.toggle() } }
    func move(_ id: UUID, to board: UUID?) { update(id) { $0.boardID = board } }
    func rename(_ id: UUID, title: String?) {
        update(id) {
            $0.title = (title?.isEmpty == true) ? nil : title
            $0.buildSearchText()
        }
    }

    func delete(_ ids: Set<UUID>) {
        for clip in items where ids.contains(clip.id) {
            context.delete(clip)
            ImageSizeCache.shared.remove(for: clip.id)
            BlobStore.shared.remove(for: clip.id)
        }
        items.removeAll { ids.contains($0.id) }
        try? context.save()
        backupService.scheduleBackupOnIdle()
    }

    /// 计算删除 `id` 后应自动选中的 clip id（基于当前过滤列表）：
    /// - 优先选中原位置的下一条（删除后前移填补空位的那条，即删除前 index+1 处）；
    /// - 被删的是最后一条 → 选中新的最后一条（删除前 index-1 处）；
    /// - 列表删空 → nil；`id` 不在列表中 → 兜底选第一条。
    func nextSelectionID(afterDeleting id: UUID) -> UUID? {
        let items = filteredItems
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            return items.first?.id
        }
        guard items.count > 1 else { return nil }
        let nextIndex = (index < items.count - 1) ? index + 1 : index - 1
        return items[nextIndex].id
    }

    func clearAll() {
        for clip in items {
            context.delete(clip)
        }
        items.removeAll()
        ImageSizeCache.shared.removeAll()
        BlobStore.shared.removeAll()
        try? context.save()
        backupService.scheduleBackupOnIdle()
    }

    func addBoard(named name: String, color: String = "purple") {
        let board = Pasteboard(name: name, color: color, sortIndex: boards.count)
        context.insert(board)
        try? context.save()
        boards.append(board)
        backupService.scheduleBackupOnIdle()
    }

    /// 重命名看板（空名则忽略）。
    func renameBoard(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              let i = boards.firstIndex(where: { $0.id == id }) else { return }
        boards[i].name = trimmed
        try? context.save()
        backupService.scheduleBackupOnIdle()
    }

    /// 修改看板颜色。
    func updateBoardColor(_ id: UUID, color: String) {
        guard let i = boards.firstIndex(where: { $0.id == id }) else { return }
        boards[i].color = color
        try? context.save()
        backupService.scheduleBackupOnIdle()
    }

    /// 删除看板：移除看板行，并将该看板上的所有剪贴项解绑（boardID 置 nil）。
    func deleteBoard(_ id: UUID) {
        if let i = boards.firstIndex(where: { $0.id == id }) {
            let board = boards[i]
            context.delete(board)
            boards.remove(at: i)
        }
        for clip in items where clip.boardID == id {
            clip.boardID = nil
        }
        try? context.save()
        if selectedBoardID == id { selectedBoardID = nil }
        backupService.scheduleBackupOnIdle()
    }

    /// 删除看板及其所有剪贴项。
    func deleteBoardAndClips(_ id: UUID) {
        let clipsToDelete = items.filter { $0.boardID == id }
        for clip in clipsToDelete {
            context.delete(clip)
            BlobStore.shared.remove(for: clip.id)
        }
        items.removeAll { $0.boardID == id }
        if let i = boards.firstIndex(where: { $0.id == id }) {
            let board = boards[i]
            context.delete(board)
            boards.remove(at: i)
        }
        try? context.save()
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
        for (index, board) in boards.enumerated() {
            board.sortIndex = index
        }
        try? context.save()
        backupService.scheduleBackupOnIdle()
    }

    func addRule(_ rule: AutomationRule) {
        context.insert(rule)
        try? context.save()
        rules.append(rule)
        backupService.scheduleBackupOnIdle()
    }

    func deleteRules(_ ids: Set<UUID>) {
        for rule in rules where ids.contains(rule.id) {
            context.delete(rule)
        }
        rules.removeAll { ids.contains($0.id) }
        try? context.save()
        backupService.scheduleBackupOnIdle()
    }

    func toggleRule(_ id: UUID) {
        guard let index = rules.firstIndex(where: { $0.id == id }) else { return }
        rules[index].enabled.toggle()
        try? context.save()
        backupService.scheduleBackupOnIdle()
    }

    /// 单条更新：改对象属性 + 写穿 SwiftData + 刷新内存以触发 Observation。
    private func update(_ id: UUID, _ change: (inout Clip) -> Void) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[i])
        try? context.save()
        reloadItems()
        backupService.scheduleBackupOnIdle()
    }

    // MARK: - 保留策略（按天 + 按条数 + 磁盘压力）

    /// 删除超过保留时长的历史；days <= 0 表示不限制。返回删除条数。
    /// 同时执行可配置条数上限与磁盘压力淘汰。
    @discardableResult
    func pruneExpired(limitDays: Int? = nil) -> Int {
        pruneNow(days: limitDays ?? historyLimitDays, diskPressure: shouldEvictByDiskPressure())
    }

    /// 内部 prune 入口（供测试显式触发磁盘压力分支）。
    func pruneNow(days: Int, diskPressure: Bool) -> Int {
        let max = maxItems
        var deleted = 0

        // 1) 按天保留
        if days > 0 {
            let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
            let descriptor = FetchDescriptor<Clip>(
                predicate: #Predicate { $0.createdAt < cutoff }
            )
            if let oldClips = try? context.fetch(descriptor) {
                for clip in oldClips {
                    context.delete(clip)
                    ImageSizeCache.shared.remove(for: clip.id)
                    BlobStore.shared.remove(for: clip.id)
                    deleted += 1
                }
            }
        }

        // 2) 按条数上限
        if case let .limited(limit) = max {
            let count = (try? context.fetchCount(FetchDescriptor<Clip>())) ?? 0
            let over = count - limit
            if over > 0 {
                var descriptor = FetchDescriptor<Clip>(
                    sortBy: [SortDescriptor(\.createdAt, order: .forward)]
                )
                descriptor.fetchLimit = over
                if let excessClips = try? context.fetch(descriptor) {
                    for clip in excessClips {
                        context.delete(clip)
                        ImageSizeCache.shared.remove(for: clip.id)
                        BlobStore.shared.remove(for: clip.id)
                        deleted += 1
                    }
                }
            }
        }

        // 3) 磁盘压力淘汰
        if diskPressure {
            var descriptor = FetchDescriptor<Clip>(
                sortBy: [SortDescriptor(\.createdAt, order: .forward)]
            )
            descriptor.fetchLimit = BackupService.diskPressureBatch
            if let oldClips = try? context.fetch(descriptor) {
                for clip in oldClips {
                    context.delete(clip)
                    ImageSizeCache.shared.remove(for: clip.id)
                    BlobStore.shared.remove(for: clip.id)
                    deleted += 1
                }
            }
        }

        if deleted > 0 {
            try? context.save()
            reloadItems()
        }
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

// MARK: - SHA-256 Helper

extension Data {
    var sha256Hex: String {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        self.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(buffer.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
