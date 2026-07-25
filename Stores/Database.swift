import Foundation
import GRDB

/// 本地持久化层入口：负责 schema 定义、一次性迁移，以及创建 `DatabaseQueue`。
///
/// 设计要点（来自架构评审 §10）：
/// - 数据库从零设计，建表后为空；不做旧 `history.json` 导入，无数据迁移。
/// - 所有表之间**不建外键**（`boardID` / `targetBoardID` 以普通 UUID TEXT 存储），
///   为阶段二 Harmony / CloudKit 铺路。
/// - 二进制（`imageData` / `utiData` / `allPasteboardData`）存在独立的 `clip_blobs` 表，
///   列表查询只 SELECT `clips` 小字段。
/// - 所有 GRDB 访问都发生在 `@MainActor`（与 `ClipboardStore` 一致）；`DatabaseQueue` 为 Sendable。
enum DatabaseManager {

    /// 本地实时库路径：`Application Support/EasyPaste/db.sqlite`。
    static var databaseFileURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "EasyPaste")
            .appending(path: "db.sqlite")
    }

    /// 打开（或创建）指定路径的数据库，执行迁移后返回 `DatabaseQueue`。
    /// - Parameter url: 数据库文件路径。
    static func open(_ url: URL) throws -> DatabaseQueue {
        let queue = try DatabaseQueue(path: url.path)
        try migrator.migrate(queue)
        return queue
    }

    /// 初始迁移：建立 `clips` / `clip_blobs` / `pasteboards` / `automation_rules` 四张表。
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1.0.0") { db in
            try db.create(table: "clips") { t in
                t.column("id", .text).primaryKey()
                t.column("kind", .text).notNull()
                t.column("createdAt", .double).notNull().indexed()
                t.column("text", .text)
                t.column("url", .text)
                t.column("fileURLs", .text)
                t.column("boardID", .text)              // 普通 UUID 引用，无外键
                t.column("isFavorite", .integer).notNull()
                t.column("sourceApplication", .text)
                t.column("sourceApplicationBundleID", .text)
                t.column("uti", .text)
                t.column("sourceAppColorRed", .double)
                t.column("sourceAppColorGreen", .double)
                t.column("sourceAppColorBlue", .double)
                t.column("title", .text)
            }

            try db.create(table: "clip_blobs") { t in
                t.column("clipID", .text).primaryKey()  // 指向 clips.id，无外键约束
                t.column("imageData", .blob)
                t.column("utiData", .blob)
                t.column("allPasteboardData", .blob)     // [UTIEntry] 编码为 JSON Data
            }

            try db.create(table: "pasteboards") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("color", .text).notNull()
            }

            try db.create(table: "automation_rules") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("keyword", .text).notNull()
                t.column("sourceApplication", .text).notNull()
                t.column("targetBoardID", .text)         // 普通 UUID 引用，无外键
                t.column("enabled", .integer).notNull()
            }
        }
        // v1.0.1：看板支持手动排序，新增 sortIndex 列并回填既有行顺序。
        migrator.registerMigration("v1.0.1-board-order") { db in
            let hasColumn = try db.columns(in: "pasteboards").contains { $0.name == "sortIndex" }
            if !hasColumn {
                try db.alter(table: "pasteboards") { t in
                    t.add(column: "sortIndex", .integer)
                }
            }
            let rows = try PasteboardRow.fetchAll(db)
            for (index, var row) in rows.enumerated() {
                row.sortIndex = index
                try row.upsert(db)
            }
        }
        return migrator
    }
}
