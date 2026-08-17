import Foundation
import SQLite3

/// 一次性把旧库（SwiftData externalStorage 时代）的 blob 列导出到 BlobStore 文件系统，
/// 然后删除 blob 列，使新模型（Clip 已无 blob 属性）打开时零迁移。
///
/// 背景：SwiftData `@Attribute(.externalStorage)` 的列在 Core Data 底层有两种存储形态：
/// - `0x01` 前缀 + 内联数据：去掉首字节即为原始 blob（如 `[UTIEntry]` 的 JSON 编码）；
/// - `0x02` 前缀 + ASCII UUID + `0x00`：外部文件引用，实际字节在 `.db_SUPPORT/_EXTERNAL_DATA/<UUID>`；
/// - `NULL`：无该 blob。
///
/// 导出后 `ALTER TABLE DROP COLUMN` 移除三列（SQLite 3.35+ 支持），
/// 随后 `ModelContainer` 打开时当前 schema 与库完全匹配，无需任何迁移。
enum LegacyBlobExporter {

    /// 对指定库执行一次性 blob 导出 + 删列。幂等：无 blob 列时直接返回。
    /// - Parameter blobStore: 导出目标。默认全局 shared（生产路径）；测试传入显式实例，
    ///   避免依赖可被并发 suite 替换的可变全局。
    static func exportIfNeeded(databaseURL: URL, blobStore: BlobStore = .shared) {
        var db: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &db) == SQLITE_OK else { return }
        defer { sqlite3_close(db) }

        guard hasBlobColumns(db) else { return }

        let externalDir = databaseURL.deletingLastPathComponent()
            .appending(path: ".db_SUPPORT/_EXTERNAL_DATA")

        let rows = readBlobRows(db, externalDir: externalDir)
        writeToBlobStore(rows, blobStore: blobStore)

        dropBlobColumns(db)
        sqlite3_exec(db, "PRAGMA wal_checkpoint(TRUNCATE);", nil, nil, nil)
    }

    // MARK: - SQL 读取

    private struct BlobRow {
        let clipID: UUID
        let imageData: Data?
        let utiData: Data?
        let allPasteboardDataRaw: Data?
    }

    private static func hasBlobColumns(_ db: OpaquePointer?) -> Bool {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(ZCLIP);", -1, &stmt, nil) == SQLITE_OK else { return false }
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let name = sqlite3_column_text(stmt, 1) else { continue }
            let col = String(cString: name)
            if col == "ZIMAGEDATA" || col == "ZUTIDATA" || col == "ZALLPASTEBOARDDATARAW" {
                return true
            }
        }
        return false
    }

    /// 读取全部行的 blob 列，解析 0x01 内联 / 0x02 外部引用 / NULL。
    private static func readBlobRows(_ db: OpaquePointer?, externalDir: URL) -> [BlobRow] {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let sql = "SELECT ZID, ZIMAGEDATA, ZUTIDATA, ZALLPASTEBOARDDATARAW FROM ZCLIP;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }

        var rows: [BlobRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let idRaw = sqlite3_column_blob(stmt, 0), sqlite3_column_bytes(stmt, 0) == 16 else { continue }
            var bytes = [UInt8](repeating: 0, count: 16)
            memcpy(&bytes, idRaw, 16)
            let clipID = UUID(uuid: uuidFromBytes(bytes))

            let imageData = decodeBlobColumn(stmt, index: 1, externalDir: externalDir)
            let utiData = decodeBlobColumn(stmt, index: 2, externalDir: externalDir)
            let allPasteboardDataRaw = decodeBlobColumn(stmt, index: 3, externalDir: externalDir)
            rows.append(BlobRow(clipID: clipID, imageData: imageData,
                                 utiData: utiData, allPasteboardDataRaw: allPasteboardDataRaw))
        }
        return rows
    }

    private static func uuidFromBytes(_ bytes: [UInt8]) -> uuid_t {
        var u = uuid_t(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        withUnsafeMutablePointer(to: &u) { ptr in
            ptr.withMemoryRebound(to: UInt8.self, capacity: 16) { dest in
                for i in 0..<16 { dest[i] = bytes[i] }
            }
        }
        return u
    }

    private static func decodeBlobColumn(_ stmt: OpaquePointer?, index: Int32, externalDir: URL) -> Data? {
        let type = sqlite3_column_type(stmt, index)
        guard type != SQLITE_NULL else { return nil }
        guard let ptr = sqlite3_column_blob(stmt, index) else { return nil }
        let len = Int(sqlite3_column_bytes(stmt, index))
        guard len > 0 else { return nil }
        let raw = Data(bytes: ptr, count: len)

        guard let first = raw.first else { return nil }
        switch first {
        case 0x01:
            // 内联：去掉 0x01 前缀
            return raw.dropFirst()
        case 0x02:
            // 外部引用：0x02 + ASCII UUID(36) + 0x00
            guard raw.count >= 38 else { return nil }
            let uuidStr = String(data: raw.subdata(in: 1..<37), encoding: .ascii) ?? ""
            let file = externalDir.appending(path: uuidStr)
            return try? Data(contentsOf: file)
        default:
            return nil
        }
    }

    // MARK: - 写出 + 删列

    private static func writeToBlobStore(_ rows: [BlobRow], blobStore: BlobStore) {
        for row in rows {
            blobStore.write(row.imageData, for: row.clipID, kind: .image)
            blobStore.write(row.utiData, for: row.clipID, kind: .uti)
            blobStore.write(row.allPasteboardDataRaw, for: row.clipID, kind: .pasteboard)
        }
    }

    private static func dropBlobColumns(_ db: OpaquePointer?) {
        _ = sqlite3_exec(db, "ALTER TABLE ZCLIP DROP COLUMN ZIMAGEDATA;", nil, nil, nil)
        _ = sqlite3_exec(db, "ALTER TABLE ZCLIP DROP COLUMN ZUTIDATA;", nil, nil, nil)
        _ = sqlite3_exec(db, "ALTER TABLE ZCLIP DROP COLUMN ZALLPASTEBOARDDATARAW;", nil, nil, nil)
    }
}