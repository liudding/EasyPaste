import Foundation
import SwiftData

/// iCloud ubiquity 文件级备份调度器。
///
/// 策略（架构评审 §10.A，SwiftData 迁移后）：本地实时库在 `Application Support` 高频读写；
/// 后台定时（进后台 / 每约 5 分钟 / 空闲 debounce）对本地库做文件级快照——先 `context.save()`
/// 刷新所有待写变更，再拷贝 SQLite 文件（`.sqlite` / `.sqlite-wal` / `.sqlite-shm`）到
/// ubiquity 容器，用 `FileManager.replaceItemAt` **原子替换**主库文件触发上传。
///
/// - 单写者假设：绝不在 ubiquity 内开库高频读写。
/// - ubiquity 同步需真实 iCloud 账号 + Developer ID 签名，沙箱内无法验证。
@MainActor
final class BackupService {
    private let dbURL: URL
    private let context: ModelContext
    private var enabled = false
    private var periodicTask: Task<Void, Never>?
    private var idleTask: Task<Void, Never>?

    /// 定时备份间隔（秒）。
    static let backupInterval: TimeInterval = 300
    /// 空闲 debounce 时长（秒）。
    static let idleDebounce: TimeInterval = 1.0
    /// 磁盘压力淘汰每批删除条数。
    static let diskPressureBatch = 50

    init(dbURL: URL, context: ModelContext) {
        self.dbURL = dbURL
        self.context = context
    }

    var isEnabled: Bool { enabled }

    /// 启用 / 停用 ubiquity 备份。启用时立即备份一次并启动定时任务。
    func setEnabled(_ enabled: Bool) {
        self.enabled = enabled
        if enabled {
            Task { @MainActor in await self.backupNow() }
            startPeriodicBackup()
        } else {
            periodicTask?.cancel()
            periodicTask = nil
        }
    }

    /// 立即执行一次备份（拷贝 SQLite 文件到 ubiquity 容器）。
    /// 无 iCloud 账号 / ubiquity 容器不可用时静默跳过，不影响本地使用。
    func backupNow() async {
        guard enabled else { return }
        guard let container = FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
            return
        }
        let destDir = container.appending(path: "EasyPaste")
        do {
            try FileManager.default.createDirectory(
                at: destDir,
                withIntermediateDirectories: true
            )
        } catch {
            print("[BackupService] 无法创建 ubiquity 目录: \(error)")
            return
        }

        // 刷新所有待写变更到持久存储，确保文件级快照一致。
        try? context.save()

        // 拷贝 SQLite 文件（.sqlite / .sqlite-wal / .sqlite-shm）保证 WAL 模式一致性。
        let destMain = destDir.appending(path: "db.sqlite")
        for suffix in ["", "-wal", "-shm"] {
            let srcURL = URL(fileURLWithPath: dbURL.path + suffix)
            let destURL = URL(fileURLWithPath: destMain.path + suffix)
            guard FileManager.default.fileExists(atPath: srcURL.path) else { continue }
            // 主库文件用原子替换；WAL/SHM 用删除+拷贝（replaceItemAt 仅替换单个文件）。
            if suffix.isEmpty {
                _ = try? FileManager.default.replaceItemAt(
                    destURL,
                    withItemAt: srcURL,
                    backupItemName: nil,
                    options: []
                )
            } else {
                if FileManager.default.fileExists(atPath: destURL.path) {
                    try? FileManager.default.removeItem(at: destURL)
                }
                try? FileManager.default.copyItem(at: srcURL, to: destURL)
            }
        }
    }

    /// 空闲 debounce 后触发一次备份（每次写入后调用）。
    func scheduleBackupOnIdle() {
        guard enabled else { return }
        idleTask?.cancel()
        idleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.idleDebounce * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            await self.backupNow()
        }
    }

    private func startPeriodicBackup() {
        periodicTask?.cancel()
        periodicTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Self.backupInterval * 1_000_000_000))
                guard !Task.isCancelled else { break }
                await self.backupNow()
            }
        }
    }

    deinit {
        periodicTask?.cancel()
        idleTask?.cancel()
    }
}
