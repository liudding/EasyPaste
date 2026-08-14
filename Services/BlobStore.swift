import Foundation

/// 剪贴板二进制大对象（图片 / UTI / 多格式剪贴板数据）的文件系统存储。
///
/// 设计动机：SwiftData `context.fetch` 对 `@Attribute(.externalStorage)` 列做急切解码，
/// 列表查询会把 `.db_SUPPORT/_EXTERNAL_DATA/` 的大文件逐个读进内存（本库 128 文件 ≈ 1.3GB），
/// 是启动 RSS 峰值主因。把 blob 移出 DB、按 `clip.id` 命名存文件后，列表查询不再触碰 blob，
/// 仅在真正访问（预览 / 粘贴 / 导出）时读对应文件，等价于原 GRDB `clip_blobs` 按需加载语义。
///
/// 线程安全：`ImageSizeCache.dataLoader` 在后台队列调用，本类用 `NSLock` 保护目录就绪检查；
/// 文件写入用 `Data.write(.atomic)` 保证原子性。
final class BlobStore {
    /// 文件类型（文件名后缀）。
    enum BlobKind: String, CaseIterable {
        case image
        case uti
        case pasteboard
    }

    /// 默认目录：`Application Support/EasyPaste/blobs/`。
    static var defaultDirectory: URL {
        URL.applicationSupportDirectory
            .appending(path: "EasyPaste")
            .appending(path: "blobs")
    }

    /// 共享实例，生产环境使用。测试可替换为注入临时目录的实例。
    /// `nonisolated(unsafe)`：目录操作由内部 NSLock 保护；测试替换仅发生在 .serialized suite 内。
    nonisolated(unsafe) static var shared = BlobStore(directory: defaultDirectory)

    private let lock = NSLock()
    /// 存储根目录。
    let directory: URL
    private var isPrepared = false

    init(directory: URL) {
        self.directory = directory
    }

    private func prepareIfNeeded() {
        lock.lock(); defer { lock.unlock() }
        guard !isPrepared else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        isPrepared = true
    }

    private func url(for id: UUID, kind: BlobKind) -> URL {
        directory.appending(path: "\(id.uuidString).\(kind.rawValue)")
    }

    /// 写入 blob；传 nil 表示删除该文件。
    func write(_ data: Data?, for id: UUID, kind: BlobKind) {
        let url = url(for: id, kind: kind)
        if let data {
            prepareIfNeeded()
            try? data.write(to: url, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// 读取 blob；文件不存在返回 nil。
    func read(id: UUID, kind: BlobKind) -> Data? {
        prepareIfNeeded()
        return try? Data(contentsOf: url(for: id, kind: kind))
    }

    /// 廉价的存在性检查（渲染热路径用，避免整文件读）。
    func exists(id: UUID, kind: BlobKind) -> Bool {
        FileManager.default.fileExists(atPath: url(for: id, kind: kind).path)
    }

    /// 删除某个 clip 的全部 blob 文件（delete / dedup / prune 路径调用）。
    func remove(for id: UUID) {
        for kind in BlobKind.allCases {
            try? FileManager.default.removeItem(at: url(for: id, kind: kind))
        }
    }

    /// 清空整个 blobs 目录（clearAll / 测试用）。保留目录根，避免其他路径假设目录存在。
    func removeAll() {
        prepareIfNeeded()
        let contents = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for url in contents { try? FileManager.default.removeItem(at: url) }
    }
}
