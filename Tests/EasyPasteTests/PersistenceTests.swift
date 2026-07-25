import Testing
import Foundation
import GRDB
@testable import EasyPaste

/// 持久层（GRDB）单元测试。所有用例使用临时目录数据库，避免污染真实数据。
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

        // 重建 store（新 DatabaseQueue）验证持久化
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
        let c1 = Clip(kind: .text, text: "a", allPasteboardData: [entry])
        let c2 = Clip(kind: .text, text: "b", allPasteboardData: [entry]) // 相同哈希 -> 去重
        store.add(c1)
        store.add(c2)
        #expect(store.items.count == 1)
    }

    // MARK: - blob 往返

    @Test func blobRoundTrip() throws {
        let url = try makeTempDB()
        let db = try DatabaseManager.open(url)
        let image = Data("imagedata".utf8)
        let entries = [UTIEntry(uti: "public.png", data: Data("pngbytes".utf8))]
        let clip = Clip(kind: .image, imageData: image, allPasteboardData: entries)
        try db.write { db in
            try ClipRow(clip).upsert(db)
            try ClipBlobRow(clip).upsert(db)
        }

        let loaded = try db.read { try ClipRow.fetchAll($0) }
        let blobs = try db.read { try ClipBlobRow.fetchAll($0) }
        #expect(loaded.count == 1)
        #expect(blobs.count == 1)
        #expect(blobs.first?.imageData == image)
        #expect(blobs.first?.allPasteboardData != nil)

        let decoded = try JSONDecoder().decode([UTIEntry].self, from: blobs.first!.allPasteboardData!)
        #expect(decoded.count == 1)
        #expect(decoded.first?.uti == "public.png")

        // 列表查询只 SELECT clips 表，不触碰 clip_blobs
        let clipsOnlyCount = (try? db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM clips") }) ?? 0
        #expect(clipsOnlyCount == 1)
        let blobCount = (try? db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM clip_blobs") }) ?? 0
        #expect(blobCount == 1)
    }

    // MARK: - 保留策略：按天

    @Test @MainActor func pruneByDays() throws {
        let url = try makeTempDB()
        let db = try DatabaseManager.open(url)
        let old = ClipRow(Clip(kind: .text, text: "old"))
        let recent = ClipRow(Clip(kind: .text, text: "recent"))
        try db.write { db in
            try old.upsert(db)
            try recent.upsert(db)
            // 把 old 的 createdAt 调早 10 天
            try db.execute(sql: "UPDATE clips SET createdAt = ? WHERE id = ?",
                           arguments: [Date().timeIntervalSince1970 - 10 * 86_400, old.id])
        }

        let store = ClipboardStore(databaseURL: url)
        #expect(store.items.count == 2)

        store.historyLimitDays = 1
        let deleted = store.pruneExpired()
        #expect(deleted == 1)
        #expect(store.items.count == 1)
        #expect(store.items.first?.text == "recent")

        // 持久化层也确认已删除
        let remaining = try db.read { try ClipRow.fetchAll($0) }
        #expect(remaining.count == 1)
    }

    // MARK: - 保留策略：按条数 + 回收 blob 孤儿

    @Test @MainActor func pruneByMaxItemsCleansOrphanBlobs() throws {
        let url = try makeTempDB()
        let db = try DatabaseManager.open(url)
        for i in 0..<5 {
            let c = Clip(kind: .text, text: "item\(i)", imageData: Data("blob\(i)".utf8))
            try db.write { db in
                try ClipRow(c).upsert(db)
                try ClipBlobRow(c).upsert(db)
            }
        }

        let store = ClipboardStore(databaseURL: url)
        store.maxItems = .limited(3)
        let deleted = store.pruneExpired()
        #expect(deleted >= 2)

        let clipCount = (try? db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM clips") }) ?? 0
        let blobCount = (try? db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM clip_blobs") }) ?? 0
        #expect(blobCount == clipCount, "不应存在孤儿 clip_blobs")
        #expect(clipCount <= 3)
    }

    // MARK: - 保留策略：磁盘压力 + 回收 blob 孤儿

    @Test @MainActor func pruneByDiskPressureCleansOrphanBlobs() throws {
        let url = try makeTempDB()
        let db = try DatabaseManager.open(url)
        for i in 0..<60 {
            let c = Clip(kind: .text, text: "item\(i)",
                         imageData: Data(repeating: UInt8(i & 0xFF), count: 64))
            try db.write { db in
                try ClipRow(c).upsert(db)
                try ClipBlobRow(c).upsert(db)
            }
        }

        let store = ClipboardStore(databaseURL: url)
        // 显式触发磁盘压力分支：每批删 50 条，保留 ≤ 10 条
        let deleted = store.pruneNow(days: 0, diskPressure: true)
        #expect(deleted >= 50)

        let clipCount = (try? db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM clips") }) ?? 0
        let blobCount = (try? db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM clip_blobs") }) ?? 0
        #expect(blobCount == clipCount, "不应存在孤儿 clip_blobs")
        #expect(clipCount <= 10)
    }
}
