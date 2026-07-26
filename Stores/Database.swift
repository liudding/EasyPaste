import Foundation
import SwiftData

/// 本地持久化层入口：负责创建 `ModelContainer`（SwiftData / Core Data SQLite 后端）。
///
/// 设计要点（来自架构评审 §10，SwiftData 迁移后）：
/// - 数据库从零设计，无旧 `history.json` 导入，无 GRDB migration 包袱。
/// - 所有表之间**不建外键**（`boardID` / `targetBoardID` 以普通 UUID 存储），
///   为阶段二 Harmony / CloudKit 铺路。
/// - 二进制（`imageData` / `utiData` / `allPasteboardDataRaw`）使用
///   `@Attribute(.externalStorage)` 存储在辅助文件中，列表查询不加载 blob。
/// - 所有 SwiftData 访问都发生在 `@MainActor`（与 `ClipboardStore` 一致）。
enum DataManager {

    /// 本地实时库路径：`Application Support/EasyPaste/db.sqlite`。
    static var databaseFileURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "EasyPaste")
            .appending(path: "db.sqlite")
    }

    /// 打开（或创建）指定路径的 SwiftData 容器。
    /// - Parameter url: 数据库文件路径。传 nil 使用默认路径。
    static func makeContainer(url: URL? = nil) throws -> ModelContainer {
        let targetURL = url ?? databaseFileURL
        try FileManager.default.createDirectory(
            at: targetURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let schema = Schema([Clip.self, Pasteboard.self, AutomationRule.self])
        let config = ModelConfiguration("EasyPaste", schema: schema, url: targetURL)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// 创建内存容器（供测试使用）。
    static func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([Clip.self, Pasteboard.self, AutomationRule.self])
        let config = ModelConfiguration("EasyPasteTest", schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }
}
