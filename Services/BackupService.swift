import Foundation
import GRDB

/// iCloud ubiquity 文件级备份调度器。
///
/// 策略（架构评审 §10.A）：本地实时库在 `Application Support` 高频读写；后台定时
/// （进后台 / 每约 5 分钟 / 空闲 debounce）对本地库做一致性快照（GRDB `backup`），
/// 再用 `FileManager.replaceItemAt` **原子替换** ubiquity 容器内的 `db.sqlite` 触发上传。
///
/// - 单写者假设：绝不在 ubiquity 内开库高频读写。
/// - ubiquity 同步需真实 iCloud 账号 + Developer ID 签名，沙箱内无法验证。
@MainActor
final class BackupService {
    private let dbQueue: DatabaseQueue
    private let localURL: URL
    private var enabled = false
    private var periodicTask: Task<Void, Never>?
    private var idleTask: Task<Void, Never>?

    /// 定时备份间隔（秒）。
    static let backupInterval: TimeInterval = 300
    /// 空闲 debounce 时长（秒）。
    static let idleDebounce: TimeInterval = 1.0
    /// 磁盘压力淘汰每批删除条数。
    static let diskPressureBatch = 50

    init(dbQueue: DatabaseQueue, localURL: URL) {
        self.dbQueue = dbQueue
        self.localURL = localURL
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

    /// 立即执行一次备份（原子替换 ubiquity 内的 db.sqlite）。
    /// 无 iCloud 账号 / ubiquity 容器不可用时静默跳过，不影响本地使用。
    func backupNow() async {
        guard enabled else { return }
        guard let container = FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
            return
        }
        let destination = container.appending(path: "EasyPaste/db.sqlite")
        do {
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            // 先落到临时一致副本，再原子替换，避免上传半文件。
            let temp = FileManager.default.temporaryDirectory
                .appending(path: "easypaste_backup_\(UUID().uuidString).sqlite")
            try? FileManager.default.removeItem(at: temp)
            do {
                let destQueue = try DatabaseQueue(path: temp.path)
                // 用 GRDB 的 backup API 做一致快照（不能用 VACUUM INTO——它不能在事务内执行）。
                // 目标用 barrierWriteWithoutTransaction 避免嵌套事务；源在 read 事务内读取即可。
                try await destQueue.barrierWriteWithoutTransaction { destDb in
                    try dbQueue.read { sourceDb in
                        try sourceDb.backup(to: destDb)
                    }
                }
                // destQueue 离开作用域即关闭，确保文件刷盘后再替换。
            }
            _ = try FileManager.default.replaceItemAt(
                destination,
                withItemAt: temp,
                backupItemName: nil,
                options: []
            )
        } catch {
            // ubiquity 备份失败不应中断本地使用；需在真实 macOS + 开发者账号手动验收。
            print("[BackupService] iCloud 备份失败（可忽略，需真实 macOS + 开发者账号验收）: \(error)")
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
