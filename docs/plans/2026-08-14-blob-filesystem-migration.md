# Blob 文件系统迁移 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 将 Clip 的三个 `@Attribute(.externalStorage)` blob 列（imageData / utiData / allPasteboardDataRaw）从 SwiftData 移出，改为文件系统存储，根治 `context.fetch` 急切解码导致的启动 RSS 峰值，并顺带修复 iCloud 备份未含 blob 的问题。

**Architecture:** 新增 `BlobStore` 服务按 `clip.id` 命名存文件；`Clip` 模型的三个 blob 属性改为读写 BlobStore 的计算属性（24 个调用点零改动）；用 VersionedSchema + custom MigrationStage 把存量 blob 导出到文件；`ImageSizeCache.dataLoader` 直读 BlobStore 取代临时 ModelContext；删除路径配对清理 blob 文件；BackupService 补拷 blobs 目录。

**Tech Stack:** SwiftData (VersionedSchema / SchemaMigrationPlan), Core Data 底层, FileManager, Swift Testing

---

## 前置背景（执行者必读）

当前性能问题根因：`ClipboardStore.reloadItems()` 的 `context.fetch(FetchDescriptor<Clip>())` 会对 fetch 涉及的全部属性做急切解码，externalStorage 列会把 `.db_SUPPORT/_EXTERNAL_DATA/` 的 128 个文件（≈1.3GB）逐个读进内存。两条 SwiftData 绕行路线均已证伪：`FetchDescriptor.propertiesToFetch` 对 transformable 部分 fault 解码崩溃；`NSFetchRequest` 方案因 SwiftData 不公开底层 `NSManagedObjectContext` 走不通。用户已确认采用**文件系统方案**：把 blob 彻底移出 DB。

**既有事实（已验证）**：
- `swift build` 通过；`swift test` 130 个测试全绿。
- 工作区含用户未提交 WIP：`App/EasyPasteApp.swift`(+3)、`Services/AppIconCache.swift`(+167，ImageSizeCache 重构)、`Stores/ClipboardStore.swift`(+8，`container` 属性 + 5 处 `ImageSizeCache.remove/removeAll` 调用)、`Tests/EasyPasteTests/ImageSizeCacheTests.swift`(新增)。勿破坏这些 WIP。
- `Clip` 模型三个 blob 存储属性：`Models/Clip.swift:77-94`。`allPasteboardData` 是计算属性（:131-134），getter 从 `allPasteboardDataRaw` 解码 `[UTIEntry]`，setter 反向编码。
- `ImageSizeCache.dataLoader: @Sendable (UUID) -> Data?` 默认 `{ _ in nil }`（AppIconCache.swift:206）；`configure(container:)`（:217-226）生产环境用它注入临时 ModelContext 读取器。
- `ClipboardStore.container: ModelContainer { context.container }`（ClipboardStore.swift:54）仅被 `EasyPasteApp.swift:54` 的 `ImageSizeCache.configure(container:)` 使用。
- `BackupService.backupNow` 只拷贝 `.sqlite/-wal/-shm` 三元组（BackupService.swift:69-88），`_EXTERNAL_DATA/` 从未备份。

---

### Task 1: BlobStore 服务 + 单元测试（TDD）

**Files:**
- Create: `Services/BlobStore.swift`
- Create: `Tests/EasyPasteTests/BlobStoreTests.swift`

**Step 1: 先写失败的测试** `Tests/EasyPasteTests/BlobStoreTests.swift`

```swift
import Testing
import Foundation

final class BlobStoreTests {
    private func makeStore() throws -> (BlobStore, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "easypaste_blobstore_tests/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (BlobStore(directory: dir), dir)
    }

    @Test func writeReadRoundTrip() throws {
        let (store, _) = try makeStore()
        let id = UUID(); let data = Data("hello".utf8)
        store.write(data, for: id, kind: .image)
        #expect(store.read(id: id, kind: .image) == data)
    }

    @Test func writeNilRemovesFile() throws {
        let (store, dir) = try makeStore()
        let id = UUID()
        store.write(Data("x".utf8), for: id, kind: .uti)
        store.write(nil, for: id, kind: .uti)
        #expect(store.read(id: id, kind: .uti) == nil)
        #expect(try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).isEmpty)
    }

    @Test func existsReflectsFilePresence() throws {
        let (store, _) = try makeStore()
        let id = UUID()
        #expect(!store.exists(id: id, kind: .image))
        store.write(Data("img".utf8), for: id, kind: .image)
        #expect(store.exists(id: id, kind: .image))
    }

    @Test func removeAllDeletesAllKinds() throws {
        let (store, dir) = try makeStore()
        let id = UUID()
        for kind in BlobKind.allCases { store.write(Data("\(kind.rawValue)".utf8), for: id, kind: kind) }
        store.remove(for: id)
        #expect(try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).isEmpty)
    }

    @Test func removeAllGlobalClearsEverything() throws {
        let (store, dir) = try makeStore()
        store.write(Data("a".utf8), for: UUID(), kind: .image)
        store.write(Data("b".utf8), for: UUID(), kind: .pasteboard)
        store.removeAll()
        #expect(try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).isEmpty)
    }

    @Test func atomicWriteNeverLeavesPartialFile() throws {
        let (store, dir) = try makeStore()
        let id = UUID()
        store.write(Data(repeating: 0xAB, count: 1024), for: id, kind: .pasteboard)
        // 模拟并发写不同文件不互相破坏
        let group = DispatchGroup()
        for i in 0..<8 {
            group.enter()
            DispatchQueue.global().async {
                store.write(Data([UInt8(i)]), for: UUID(), kind: .image)
                group.leave()
            }
        }
        group.wait()
        #expect(try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).count == 9)
    }
}
```

**Step 2: 运行测试确认失败**（编译失败即可，因为 BlobStore 尚不存在）
```bash
swift test --filter BlobStoreTests 2>&1 | tail -10
```

**Step 3: 实现 `Services/BlobStore.swift`**

```swift
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
    static var shared = BlobStore(directory: defaultDirectory)

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

    /// 清空整个 blobs 目录（clearAll / 测试用）。
    func removeAll() {
        try? FileManager.default.removeItem(at: directory)
        lock.lock(); isPrepared = false; lock.unlock()
    }
}
```

**Step 4: 运行测试确认通过**
```bash
swift test --filter BlobStoreTests 2>&1 | tail -10
```

**Step 5: 提交**
```bash
git add Services/BlobStore.swift Tests/EasyPasteTests/BlobStoreTests.swift && git commit -m "feat: add BlobStore for filesystem-backed clipboard blobs"
```

---

### Task 2: Clip 模型改造为 BlobStore 计算属性

**Files:**
- Modify: `Models/Clip.swift`
- Test: `Tests/EasyPasteTests/PersistenceTests.swift`（后续 Task 逐步适配）

**Step 1: 修改 `Models/Clip.swift`**

移除三个存储属性（:77-94）：
```swift
// 删除这三段——不再作为 SwiftData 存储属性：
// @Attribute(.externalStorage) var imageData: Data?
// @Attribute(.externalStorage) var utiData: Data?
// @Attribute(.externalStorage) var allPasteboardDataRaw: Data?
```

新增三个访问 BlobStore 的计算属性（放在 `id` 之后，放回原位附近）：
```swift
/// 原始图片数据（文件系统存储，按 clip.id 命名）。
var imageData: Data? {
    get { BlobStore.shared.read(id: id, kind: .image) }
    set { BlobStore.shared.write(newValue, for: id, kind: .image) }
}

/// UTI 元数据（文件系统存储）。
var utiData: Data? {
    get { BlobStore.shared.read(id: id, kind: .uti) }
    set { BlobStore.shared.write(newValue, for: id, kind: .uti) }
}

/// 多格式剪贴板原始数据（文件系统存储）。
var allPasteboardDataRaw: Data? {
    get { BlobStore.shared.read(id: id, kind: .pasteboard) }
    set { BlobStore.shared.write(newValue, for: id, kind: .pasteboard) }
}
```

`allPasteboardData` 计算属性（:131-134）保持不变（它读写 `allPasteboardDataRaw`，现在间接走 BlobStore）。

注意：`init` 中设置 blob 的赋值顺序必须在 `self.id = UUID()` 之后（现有代码已是如此，:137-142），否则 `id` 尚为默认值导致文件名错乱。

**Step 2: 确认现有测试在此刻仍编译通过**
```bash
swift build 2>&1 | tail -15
```
> 预期：编译通过。所有对 `clip.imageData` / `clip.allPasteboardData` 的调用点（ClipboardService.copy、ClipActionService.exportAsImage、ClipCardView、ImageSizeCache.dataLoader、PersistenceTests）因计算属性保持同名，零改动。

> ⚠️ 此时未写迁移，存量 DB 打开可能因 schema 不匹配失败或 warning——这是预期中间态，Task 3 立刻补迁移。

**Step 3: 运行测试**（PersistenceTests 的 blobRoundTrip 可能因 BlobStore.shared 指向真实目录而写污染，Task 5 会适配测试目录；此刻先确认编译）
```bash
swift build 2>&1 | tail -5
```

**Step 4: 提交**
```bash
git add Models/Clip.swift && git commit -m "refactor: make Clip blob properties BlobStore-backed computed accessors"
```

---

### Task 3: 存量 blob 导出 + 删列（实证推翻 VersionedSchema，改用 SQL 预导出）

> ⚠️ **实证结论（2026-08-14 执行时验证）**：原计划的 VersionedSchema + custom MigrationStage 方案**不可行**——
> SwiftData 的 `VersionedSchema` 要求模型的**实体名**与库中已有实体完全一致（否则报 "entity name mismatch"），
> 而克隆的 `ClipV1` 实体名是 `ClipV1` ≠ 现存 `Clip`，custom migration 无法触发。
> 同时实测发现：**当前 Clip 模型（无 blob 属性）打开旧库即触发轻量迁移自动删列**，数据保留（1424 条），
> 但 blob 数据随之丢失。因此改为 **SQL 预导出**方案：

**最终方案（已实现）**：`LegacyBlobExporter` 在 `makeContainer` 打开容器**之前**，用 SQLite C API 直接：
1. 检测 `ZCLIP` 是否残留 blob 列（`ZIMAGEDATA`/`ZUTIDATA`/`ZALLPASTEBOARDDATARAW`）；
2. 解析 0x01 内联 / 0x02 外部引用（`.db_SUPPORT/_EXTERNAL_DATA/`）两种 blob 形态，写入 `BlobStore` 文件；
3. `ALTER TABLE ZCLIP DROP COLUMN` 删除三列 → 之后 SwiftData 打开**零迁移**。

**Files:**
- Create: `Services/LegacyBlobExporter.swift`
- Modify: `Stores/Database.swift`
- Create: `Tests/EasyPasteTests/MigrationTests.swift`

**Step 1: 创建 `Services/LegacyBlobExporter.swift`**（已实现，幂等：无 blob 列则直接跳过）

**Step 2: 写迁移测试** `Tests/EasyPasteTests/MigrationTests.swift`（已实现）

> ⚠️ **测试载体实证**：自建简化 ZCLIP 表**无法**被 SwiftData 打开（模型校验失败返回空集）；
> 必须用**真实旧库副本**（含完整列 + `_EXTERNAL_DATA` 目录 + Z_METADATA）做端到端验证。
> 拷贝 `_EXTERNAL_DATA` 时 `copyItem` 对含隐藏父目录的源偶发 "doesn't exist"，需逐文件拷贝。

**Step 3: 修改 `Stores/Database.swift` 的 `makeContainer`**（已实现）
在创建 `ModelContainer` 前调用 `LegacyBlobExporter.exportIfNeeded(databaseURL: targetURL)`。

**Step 4: 运行迁移测试确认通过**
```bash
swift test --filter MigrationTests 2>&1 | tail -10
```
（✔ 已通过：导出 + 删列 + 零迁移打开 + 数据保留 + 幂等，全链路验证）

**Step 5: 提交**
```bash
git add Stores/EasyPasteMigrationPlan.swift Stores/Database.swift Tests/EasyPasteTests/MigrationTests.swift && git commit -m "feat: migrate blobs to filesystem via SchemaMigrationPlan"
```

---

### Task 4: ImageSizeCache 直读 BlobStore，移除 container

**Files:**
- Modify: `Services/AppIconCache.swift`
- Modify: `App/EasyPasteApp.swift`
- Modify: `Stores/ClipboardStore.swift`

**Step 1: 修改 `Services/AppIconCache.swift`**

把 `dataLoader` 默认值从 `{ _ in nil }`（:206）改为直读 BlobStore：
```swift
@ObservationIgnored var dataLoader: @Sendable (UUID) -> Data? = { id in
    BlobStore.shared.read(id: id, kind: .image)
}
```

删除 `configure(container:)` 方法（:217-226 附近）及其调用；`configure` 已无存在必要。

**Step 2: 修改 `App/EasyPasteApp.swift`**

删除第 54 行 `ImageSizeCache.configure(container: store.container)`（连同其上注释）。启动时不再需要任何 blob 相关配置。

**Step 3: 修改 `Stores/ClipboardStore.swift`**

移除第 53-54 行的 `container` 计算属性（用户 WIP 加的那段）：
```swift
// 删除：
// /// 共享 ModelContainer：ImageSizeCache 用临时 ModelContext 读取图片 blob 时复用同一容器。
// var container: ModelContainer { context.container }
```

**Step 4: 构建 + 运行 ImageSizeCacheTests**
```bash
swift build 2>&1 | tail -5 && swift test --filter ImageSizeCacheTests 2>&1 | tail -10
```
（ImageSizeCacheTests 注入自己的 dataLoader，不受默认值影响，应通过）

**Step 5: 提交**
```bash
git add Services/AppIconCache.swift App/EasyPasteApp.swift Stores/ClipboardStore.swift && git commit -m "refactor: ImageSizeCache reads blobs directly from BlobStore"
```

---

### Task 5: 删除路径清理 blob 文件 + 渲染热路径 exists()

**Files:**
- Modify: `Stores/ClipboardStore.swift`
- Modify: `Views/ClipboardPanel/ClipCardView.swift`

**Step 1: 在 `ClipboardStore` 所有 `context.delete` 调用点配对 `BlobStore.remove`**

已知删除点（与用户 WIP 已有的 `ImageSizeCache.remove/removeAll` 一一配对）：
- `delete(_:)` 内 `context.delete(clip)` 处（:261 附近）→ `BlobStore.shared.remove(for: clip.id)`
- `clearAll()` 内（:285 附近）→ 清空后 `BlobStore.shared.removeAll()`
- pruneExpired / pruneExcess 三处（:450/:468/:484 附近）→ 每处 `context.delete(clip)` 后 `BlobStore.shared.remove(for: clip.id)`
- **`deleteBoardAndClips`（:338 附近）**：删除看板及其所有剪贴项，用户 WIP 的 ImageSizeCache.remove 未覆盖此点 → 需补 `ImageSizeCache.shared.remove(for: clip.id)` **和** `BlobStore.shared.remove(for: clip.id)`

原则：每个 `context.delete(x)` 之后紧跟 `BlobStore.shared.remove(for: x.id)`；清空操作后 `removeAll()`。

> 提示：用 `grep -n "context.delete" Stores/ClipboardStore.swift` 核对全部调用点，勿遗漏。

**Step 2: `ClipCardView` 渲染热路径改用廉价 exists()**

`:281` 与 `:345` 的 `item.imageData != nil` 改为 `BlobStore.shared.exists(id: item.id, kind: .image)`（渲染路径逐卡调用，避免整文件读）。

`:376` 与 `:393`（拖拽 provider，用户交互触发）保持 `item.imageData` / `item.allPasteboardData` 整读不变。

**Step 3: 构建 + 跑全量测试**
```bash
swift build 2>&1 | tail -5 && swift test 2>&1 | tail -20
```

> ⚠️ 此刻 `PersistenceTests.blobRoundTrip` 与部分 `deduplicationByAllPasteboardData` 测试会因 `BlobStore.shared` 指向真实 Application Support 目录而产生文件污染 / 失败，Task 6 修复。

**Step 4: 提交**
```bash
git add Stores/ClipboardStore.swift Views/ClipboardPanel/ClipCardView.swift && git commit -m "perf: clean up blob files on delete, cheap exists() on render path"
```

---

### Task 6: 测试适配（BlobStore 目录注入）

**Files:**
- Modify: `Tests/EasyPasteTests/PersistenceTests.swift`
- Modify: `Tests/EasyPasteTests/ImageSizeCacheTests.swift`（如涉及）
- Modify: `Tests/EasyPasteTests/MigrationTests.swift`（已验证）

**Step 1: 为 blob 相关测试注入临时 BlobStore 目录**

`PersistenceTests` 中所有创建带 blob 的 `Clip` 或依赖 `imageData`/`allPasteboardData` 的测试（`blobRoundTrip`、`deduplicationByAllPasteboardData` 等）需先替换全局 `BlobStore.shared` 为临时目录实例，并在结束后恢复。

建议加一个测试辅助（放在 `PersistenceTests.swift` 顶部或测试 target 内）：
```swift
@Suite(.serialized)
struct BlobBackedPersistenceTests {
    private func withTempBlobStore(_ body: () throws -> Void) throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "easypaste_test_blobs/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let original = BlobStore.shared
        BlobStore.shared = BlobStore(directory: dir)
        defer { BlobStore.shared = original }
        try body()
    }
    // 各测试用 withTempBlobStore { ... } 包裹
}
```

> ⚠️ Swift Testing 默认并行执行测试，读写全局 `BlobStore.shared` 有竞态。所有触及 blob 的测试 suite 必须标记 `@Suite(.serialized)` 且串行修改/恢复 shared。

**Step 2: 确认所有测试隔离**
```bash
swift test 2>&1 | tail -20   # 应全绿：130 + BlobStoreTests + MigrationTests
```

**Step 3: 提交**
```bash
git add Tests/EasyPasteTests/PersistenceTests.swift Tests/EasyPasteTests/ImageSizeCacheTests.swift && git commit -m "test: isolate blob-backed tests with temp BlobStore directory"
```

---

### Task 7: BackupService 补拷 blobs 目录（顺带修复 iCloud 备份空洞）

**Files:**
- Modify: `Services/BackupService.swift`

**Step 1: 修改 `backupNow`**

在现有拷贝 `.sqlite/-wal/-shm` 三元组之后，追加 blobs 目录的拷贝：

```swift
// 现有：拷贝 sqlite 三元组到 ubiquity 容器后

// 追加：拷贝 blobs 目录（blob 已从 DB 移到文件系统，必须一并备份）
if let destRoot = ... /* 现有 ubiquity 目标目录 */ {
    let srcBlobs = BlobStore.shared.directory
    let destBlobs = destRoot.appending(path: "blobs")
    try? FileManager.default.removeItem(at: destBlobs)
    if FileManager.default.fileExists(atPath: srcBlobs.path) {
        try? FileManager.default.copyItem(at: srcBlobs, to: destBlobs)
    }
}
```

> 提示：阅读 BackupService.swift:69-88 现有实现，把 srcBlobs/destBlobs 放进与 sqlite 相同的替换/上传逻辑中，保持原子性与与原有一致的错误处理风格。

**Step 2: 构建确认**
```bash
swift build 2>&1 | tail -5
```

> BackupService 无覆盖测试（blast radius 显示 no covering tests）。此改动用构建验证即可；如需，可后续补备份单元测试（超出本计划范围，YAGNI）。

**Step 3: 提交**
```bash
git add Services/BackupService.swift && git commit -m "fix: backup blob files alongside sqlite for iCloud ubiquity"
```

---

### Task 8: 最终验证与回归

**Files:** 无需改动

**Step 1: 全量测试 + 构建**
```bash
swift build 2>&1 | tail -5
swift test 2>&1 | tail -20
```

**Step 2: 手工冒烟（可选，需 GUI）**
- 启动 app，确认列表加载无 RSS 尖峰（可用 Instruments / malloc_history 复核）。
- 复制文本/图片 → 列表出现 → 粘贴还原 → 导出图片 → 拖拽，确认 blob 读写正常。
- 删除/清空/prune 后，确认 `Application Support/EasyPaste/blobs/` 对应文件被清除。

**Step 3: 收尾确认**
```bash
git status --short
```
应只剩用户原始 WIP（EasyPasteApp / AppIconCache / ClipboardStore / ImageSizeCacheTests）+ 本计划新增文件。

---

## 风险与注意事项

1. **迁移版本匹配（最大风险）**：Task 3 的 `versionIdentifier` 必须与实际 V1 库匹配。执行时先用 `sqlite3 db.sqlite "SELECT * FROM Z_METADATA"` 检查现有 Schema 版本；若现有库非 `(1,0,0)`，需调整 `EasyPasteSchemaV1.versionIdentifier`。
2. **用户 WIP 勿破坏**：Task 4 删除 `container` 属性是**有意为之**（它仅服务已废弃的 `configure(container:)`），删除前确认无其它引用（已 grep 确认仅 EasyPasteApp.swift:54 引用）。
3. **`ClipV1` 字段镜像**：需与实际库列名完全一致，否则迁移读不到数据。执行时对照现有 `Clip` 模型逐字段核对。
4. **测试并行竞态**：所有触碰全局 `BlobStore.shared` 的测试 suite 必须 `.serialized`。
5. **`.unique` 约束**：现有 `Clip` 若 `id` 有 `@Attribute(.unique)`（Database.swift 定义），`ClipV1` 需保持一致。
6. **不做的事**：不改 ClipboardService.copy 逻辑（计算属性同名，无需改）；不新增备份单元测试（YAGNI）。