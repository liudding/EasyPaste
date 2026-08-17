import Testing
import Foundation
import SwiftData
import SQLite3
@testable import EasyPaste

/// SQLITE_TRANSIENT 是 SQLite 的 C 宏（让绑定数据在语句执行期间保持有效），
/// Swift 不自动导入 C 宏，需手动重建：`((sqlite3_destructor_type)-1)`。
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// 验证旧库 → 文件系统迁移完整链路（基于真实库副本）：
/// 1. LegacyBlobExporter 把 blob 列导出到 BlobStore 文件并删除列；
/// 2. 之后 makeContainer 打开零迁移，数据保留（含非 blob 字段）。
///
/// 使用真实库副本的原因：SwiftData 打开库时要求完整 schema 匹配，
/// 自建简化表无法通过模型校验（已在探索期实证）。
/// 导出目标为显式传入的临时 BlobStore，不依赖可被并发 suite 替换的全局 shared。
///
/// 自包含：源库可能已被生产环境（app 启动时 `ClipboardStore()` → `makeContainer()`）
/// 迁移过（blob 列已删除）。此时给副本补回三列并注入一行模拟旧库数据，
/// 使「导出 → 删列 → 零迁移打开」链路在源库两种状态下都可验证。
@Suite(.serialized)
struct MigrationTests {
    @Test @MainActor func legacyBlobsExportedThenZeroMigrationOpen() throws {
        // 真实库副本（schema 基础）
        let supportDir = URL.applicationSupportDirectory.appending(path: "EasyPaste")
        let src = supportDir.appending(path: "db.sqlite")
        let srcExt = supportDir.appending(path: ".db_SUPPORT/_EXTERNAL_DATA")
        #expect(FileManager.default.fileExists(atPath: src.path), "旧库应存在")
        #expect(FileManager.default.fileExists(atPath: srcExt.path), "外部数据目录应存在")

        let dir = FileManager.default.temporaryDirectory
            .appending(path: "easypaste_migration_tests/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: "db.sqlite")
        try FileManager.default.copyItem(at: src, to: url)
        // 逐文件拷贝 _EXTERNAL_DATA（copyItem 对含隐藏父目录的源偶发 "doesn't exist"）
        let dstExtDir = dir.appending(path: ".db_SUPPORT/_EXTERNAL_DATA")
        try FileManager.default.createDirectory(at: dstExtDir, withIntermediateDirectories: true)
        let extFiles = try FileManager.default.contentsOfDirectory(at: srcExt, includingPropertiesForKeys: nil)
        for f in extFiles {
            try FileManager.default.copyItem(at: f, to: dstExtDir.appending(path: f.lastPathComponent))
        }
        defer { try? FileManager.default.removeItem(at: dir) }

        // 若源库已被生产环境迁移（blob 列已删），补回三列并注入模拟旧库数据。
        try restoreLegacyBlobState(in: url)

        // 指向临时 BlobStore 目录；导出与验证都用显式实例，
        // 不依赖可被并发 suite 替换的全局 shared。
        let testBlobDir = dir.appending(path: "blobs")
        let testBlobStore = BlobStore(directory: testBlobDir)

        // 1) 导出 + 删列
        LegacyBlobExporter.exportIfNeeded(databaseURL: url, blobStore: testBlobStore)

        // 2) 验证 BlobStore 有文件（模拟行导出 image blob；若源库未迁移则为真实 blob）
        let files = try FileManager.default.contentsOfDirectory(at: testBlobDir, includingPropertiesForKeys: nil)
        #expect(!files.isEmpty, "应导出 blob 文件")

        // 3) 打开零迁移，数据保留
        let container = try DataManager.makeContainer(url: url)
        let ctx = ModelContext(container)
        let clips = try ctx.fetch(FetchDescriptor<Clip>())
        #expect(clips.count > 1000, "应保留全部剪贴项，实际 \(clips.count)")

        // 4) 抽查：有 image 的 clip，其 blob 能从 BlobStore 读回
        let withImage = clips.filter { testBlobStore.exists(id: $0.id, kind: .image) }
        #expect(withImage.count > 0, "应有 clip 的图片 blob 导出到文件")
        let sample = withImage[0]
        let img = testBlobStore.read(id: sample.id, kind: .image)
        #expect(img != nil && img!.count > 1000, "图片 blob 应完整")

        // 5) 幂等：再次导出应无操作（无 blob 列）
        LegacyBlobExporter.exportIfNeeded(databaseURL: url, blobStore: testBlobStore)
        let filesAfter = try FileManager.default.contentsOfDirectory(at: testBlobDir, includingPropertiesForKeys: nil)
        #expect(filesAfter.count == files.count, "幂等：不应重复导出")
    }

    /// 源库可能已被生产环境（app 启动）迁移：blob 列已删除。
    /// 若副本缺少 blob 列，补回 ZIMAGEDATA / ZUTIDATA / ZALLPASTEBOARDDATARAW 三列，
    /// 并给一行注入 0x01 前缀的模拟图片 blob（旧库内联格式），
    /// 使导出链路在源库两种状态下都可验证。已含 blob 列（源库未迁移）时不做任何修改。
    private func restoreLegacyBlobState(in url: URL) throws {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { return }
        defer { sqlite3_close(db) }

        // 已有 blob 列 → 源库尚未迁移，无需处理
        var hasBlobColumns = false
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "PRAGMA table_info(ZCLIP);", -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let name = sqlite3_column_text(stmt, 1) {
                    let col = String(cString: name)
                    if col == "ZIMAGEDATA" || col == "ZUTIDATA" || col == "ZALLPASTEBOARDDATARAW" {
                        hasBlobColumns = true
                    }
                }
            }
            sqlite3_finalize(stmt)
        }
        guard !hasBlobColumns else { return }

        // 补回三列（SQLite 3.35+ ADD COLUMN 可逆于 DROP COLUMN）
        for col in ["ZIMAGEDATA", "ZUTIDATA", "ZALLPASTEBOARDDATARAW"] {
            let sql = "ALTER TABLE ZCLIP ADD COLUMN \(col) BLOB;"
            guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { return }
        }

        // 给任意一行注入 0x01 前缀 + 2000 字节的模拟图片（旧库内联格式），
        // 导出后可读回 >1000 字节（0x01 前缀会被剥离）。
        let mockImage = Data([0x01]) + Data(repeating: 0xAB, count: 2000)
        var update: OpaquePointer?
        defer { sqlite3_finalize(update) }
        let sql = "UPDATE ZCLIP SET ZIMAGEDATA = ?1 WHERE ZID = (SELECT ZID FROM ZCLIP LIMIT 1);"
        guard sqlite3_prepare_v2(db, sql, -1, &update, nil) == SQLITE_OK else { return }
        let bindOK = mockImage.withUnsafeBytes { buf -> Bool in
            sqlite3_bind_blob(update, 1, buf.baseAddress, Int32(buf.count), SQLITE_TRANSIENT) == SQLITE_OK
        }
        guard bindOK, sqlite3_step(update) == SQLITE_DONE else { return }
    }
}
