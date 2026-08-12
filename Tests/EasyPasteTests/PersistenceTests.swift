import Testing
import Foundation
import SwiftData
@testable import EasyPaste

/// 持久层（SwiftData）单元测试。所有用例使用临时目录数据库，避免污染真实数据。
@Suite
struct PersistenceTests {

    private func makeTempDB() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "easypaste_tests/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "db.sqlite")
    }

    // MARK: - 空库启动

    @Test @MainActor func emptyDatabaseLoadsWithNoClips() throws {
        let url = try makeTempDB()
        let store = ClipboardStore(databaseURL: url)
        #expect(store.items.isEmpty)
        // 默认看板已播种（应用默认数据，非旧历史导入）
        #expect(store.boards.count == 2)
        #expect(store.rules.isEmpty)
    }

    // MARK: - CRUD 往返

    @Test @MainActor func clipCRUDRoundTrip() throws {
        let url = try makeTempDB()
        let store = ClipboardStore(databaseURL: url)
        let clip = Clip(kind: .text, text: "hello world")
        store.add(clip)
        #expect(store.items.count == 1)

        // 重建 store（新 ModelContainer）验证持久化
        let store2 = ClipboardStore(databaseURL: url)
        #expect(store2.items.count == 1)
        #expect(store2.items.first?.text == "hello world")
        #expect(store2.items.first?.id == clip.id)
        #expect(store2.items.first?.kind == .text)
    }

    @Test @MainActor func updateAndDeleteRoundTrip() throws {
        let url = try makeTempDB()
        let store = ClipboardStore(databaseURL: url)
        let clip = Clip(kind: .link, url: URL(string: "https://example.com")!)
        store.add(clip)
        store.toggleFavorite(clip.id)
        #expect(store.items.first?.isFavorite == true)

        store.rename(clip.id, title: "示例")
        #expect(store.items.first?.title == "示例")

        store.delete([clip.id])
        #expect(store.items.isEmpty)

        let store2 = ClipboardStore(databaseURL: url)
        #expect(store2.items.isEmpty)
    }

    // MARK: - 删除后自动选择下一条

    @Test @MainActor func nextSelectionAfterDeletingMiddle() throws {
        let url = try makeTempDB()
        let store = ClipboardStore(databaseURL: url)
        // add 会置顶：列表为 [c3, c2, c1]（c3 最新在前）
        let c1 = Clip(kind: .text, text: "first")
        let c2 = Clip(kind: .text, text: "middle")
        let c3 = Clip(kind: .text, text: "last")
        store.add(c1); store.add(c2); store.add(c3)
        #expect(store.filteredItems.map(\.text) == ["last", "middle", "first"])

        // 删除中间项（c2，index 1）→ 选中原位置下一条（c1）
        let next = store.nextSelectionID(afterDeleting: c2.id)
        #expect(next == c1.id)
        store.delete([c2.id])
        #expect(store.items.count == 2)
        #expect(store.items.map(\.id) == [c3.id, c1.id])
        #expect(store.items.contains(where: { $0.id == next }))
    }

    @Test @MainActor func nextSelectionAfterDeletingFirst() throws {
        let url = try makeTempDB()
        let store = ClipboardStore(databaseURL: url)
        let c1 = Clip(kind: .text, text: "first")
        let c2 = Clip(kind: .text, text: "middle")
        let c3 = Clip(kind: .text, text: "last")
        store.add(c1); store.add(c2); store.add(c3)
        // 删除最新一条（c3，index 0）→ 选中原位置下一条（c2）
        let next = store.nextSelectionID(afterDeleting: c3.id)
        #expect(next == c2.id)
        store.delete([c3.id])
        #expect(store.items.map(\.id) == [c2.id, c1.id])
        #expect(store.items.contains(where: { $0.id == next }))
    }

    @Test @MainActor func nextSelectionAfterDeletingLast() throws {
        let url = try makeTempDB()
        let store = ClipboardStore(databaseURL: url)
        let c1 = Clip(kind: .text, text: "first")
        let c2 = Clip(kind: .text, text: "middle")
        let c3 = Clip(kind: .text, text: "last")
        store.add(c1); store.add(c2); store.add(c3)
        // 删除最旧一条（c1，index 2）→ 选中新的最后一条（c2）
        let next = store.nextSelectionID(afterDeleting: c1.id)
        #expect(next == c2.id)
        store.delete([c1.id])
        #expect(store.items.map(\.id) == [c3.id, c2.id])
        #expect(store.items.contains(where: { $0.id == next }))
    }

    @Test @MainActor func nextSelectionDeletingOnlyItemReturnsNil() throws {
        let url = try makeTempDB()
        let store = ClipboardStore(databaseURL: url)
        let clip = Clip(kind: .text, text: "solo")
        store.add(clip)
        #expect(store.nextSelectionID(afterDeleting: clip.id) == nil)

        store.delete([clip.id])
        #expect(store.items.isEmpty)
        #expect(store.nextSelectionID(afterDeleting: clip.id) == nil)
    }

    @Test @MainActor func boardsAndRulesRoundTrip() throws {
        let url = try makeTempDB()
        let store = ClipboardStore(databaseURL: url)
        store.addBoard(named: "临时", color: "teal")
        store.addRule(AutomationRule(name: "规则A", keyword: "test", sourceApplication: "Xcode"))

        let store2 = ClipboardStore(databaseURL: url)
        #expect(store2.boards.contains(where: { $0.name == "临时" && $0.color == "teal" }))
        #expect(store2.rules.contains(where: { $0.name == "规则A" && $0.keyword == "test" }))

        if let rule = store2.rules.first {
            store2.toggleRule(rule.id)
            #expect(store2.rules.first?.enabled == false)
        }
    }

    // MARK: - 去重

    @Test @MainActor func deduplicationByAllPasteboardData() throws {
        let url = try makeTempDB()
        let store = ClipboardStore(databaseURL: url)
        let entry = UTIEntry(uti: "public.plain-text", data: Data("dup".utf8))
        // 新版去重基于 contentHash（由 ClipboardService.makeItem() 在生产中设置）。
        // 测试需显式设置 contentHash 以匹配生产行为。
        let c1 = Clip(kind: .text, text: "a", allPasteboardData: [entry])
        c1.contentHash = ClipTypeDetector.computeContentHash([entry])
        let c2 = Clip(kind: .text, text: "b", allPasteboardData: [entry]) // 相同哈希 -> 去重
        c2.contentHash = ClipTypeDetector.computeContentHash([entry])
        store.add(c1)
        store.add(c2)
        #expect(store.items.count == 1)
    }

    // MARK: - blob 往返（SwiftData @Attribute(.externalStorage)）

    @Test @MainActor func blobRoundTrip() throws {
        let url = try makeTempDB()
        let container = try DataManager.makeContainer(url: url)
        let context = ModelContext(container)

        let image = Data("imagedata".utf8)
        let entries = [UTIEntry(uti: "public.png", data: Data("pngbytes".utf8))]
        let clip = Clip(kind: .image, imageData: image, allPasteboardData: entries)
        context.insert(clip)
        try context.save()

        // 重新 fetch 验证 blob 数据往返
        let descriptor = FetchDescriptor<Clip>()
        let loaded = try context.fetch(descriptor)
        #expect(loaded.count == 1)
        #expect(loaded.first?.imageData == image)
        #expect(loaded.first?.allPasteboardData != nil)

        let decoded = loaded.first?.allPasteboardData
        #expect(decoded?.count == 1)
        #expect(decoded?.first?.uti == "public.png")
    }

    // MARK: - 保留策略：按天

    @Test @MainActor func pruneByDays() throws {
        let url = try makeTempDB()
        let container = try DataManager.makeContainer(url: url)
        let context = ModelContext(container)

        let old = Clip(kind: .text, text: "old")
        old.createdAt = Date().addingTimeInterval(-10 * 86_400)
        let recent = Clip(kind: .text, text: "recent")
        context.insert(old)
        context.insert(recent)
        try context.save()

        let store = ClipboardStore(databaseURL: url)
        #expect(store.items.count == 2)

        store.historyLimitDays = 1
        let deleted = store.pruneExpired()
        #expect(deleted == 1)
        #expect(store.items.count == 1)
        #expect(store.items.first?.text == "recent")
    }

    // MARK: - 保留策略：按条数

    @Test @MainActor func pruneByMaxItems() throws {
        let url = try makeTempDB()
        let container = try DataManager.makeContainer(url: url)
        let context = ModelContext(container)
        for i in 0..<5 {
            let c = Clip(kind: .text, text: "item\(i)", imageData: Data("blob\(i)".utf8))
            context.insert(c)
        }
        try context.save()

        let store = ClipboardStore(databaseURL: url)
        #expect(store.items.count == 5)
        store.maxItems = .limited(3)
        let deleted = store.pruneExpired()
        #expect(deleted >= 2)
        // SwiftData @Model 删除时自动回收 externalStorage blob，无孤儿问题
        #expect(store.items.count <= 3)
    }

    // MARK: - 保留策略：磁盘压力

    @Test @MainActor func pruneByDiskPressure() throws {
        let url = try makeTempDB()
        let container = try DataManager.makeContainer(url: url)
        let context = ModelContext(container)
        for i in 0..<60 {
            let c = Clip(kind: .text, text: "item\(i)",
                         imageData: Data(repeating: UInt8(i & 0xFF), count: 64))
            context.insert(c)
        }
        try context.save()

        let store = ClipboardStore(databaseURL: url)
        #expect(store.items.count == 60)
        // 显式触发磁盘压力分支：每批删 50 条，保留 ≤ 10 条
        let deleted = store.pruneNow(days: 0, diskPressure: true)
        #expect(deleted >= 50)
        // SwiftData @Model 删除时自动回收 externalStorage blob，无孤儿问题
        #expect(store.items.count <= 10)
    }
}
