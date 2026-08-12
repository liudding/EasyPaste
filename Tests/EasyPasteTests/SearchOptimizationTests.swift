import Testing
import Foundation
import SwiftData
@testable import EasyPaste

/// 搜索/检索优化测试：锁定全文索引、缓存失效、rename 重建、防抖行为。
///
/// 设计说明：
/// - 全文索引实现后，`filteredItems` 的过滤基于预构建的 `searchText`（小写归一化全量文本）。
/// - 本文件先锁定行为（全文不截断、大小写不敏感、索引随 rename 重建、查询/插入后结果刷新），
///   再用防抖测试驱动 RED→GREEN。
/// - 防抖依赖 150ms 定时器：Swift Testing 并行执行下固定 sleep 会与主线程调度产生竞态，
///   因此"等待防抖应用"统一用轮询 `effectiveQuery`（带 3s 超时）。
/// 防抖依赖 MainActor 上的 150ms 定时器：并行测试（均 @MainActor）会饿死防抖 Task，
/// 因此整个 suite 串行执行。
@Suite(.serialized)
struct SearchOptimizationTests {

    private func makeTempDB() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "easypaste_search_tests/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "db.sqlite")
    }

    // MARK: - 全文索引行为

    /// 全文搜索：长文本（远超截断上限）尾部内容可被检索到。
    @Test @MainActor func searchMatchesFullTextNotTruncated() async throws {
        let url = try makeTempDB()
        let store = ClipboardStore(databaseURL: url)
        // 3000 字符长文本，唯一词在尾部
        let longText = String(repeating: "commonword ", count: 500) + "uniqueTailToken"
        store.add(Clip(kind: .text, text: longText))
        store.query = "uniqueTailToken"
        try await waitForQueryApplied(store, "uniqueTailToken")
        #expect(store.filteredItems.count == 1)
        #expect(store.filteredItems.first?.text == longText)
    }

    @Test @MainActor func searchIsCaseInsensitive() async throws {
        let url = try makeTempDB()
        let store = ClipboardStore(databaseURL: url)
        store.add(Clip(kind: .text, text: "Hello SwiftUI World"))
        store.query = "hello"
        try await waitForQueryApplied(store, "hello")
        #expect(store.filteredItems.count == 1)
    }

    /// 富文本（无 text 字段，仅 HTML）也要全文可搜：索引必须覆盖 HTML 全量可见文本，
    /// 而非 previewPlainText 的 200 字符截断。
    @Test @MainActor func richTextClipWithoutTextIsSearchableFullText() async throws {
        let url = try makeTempDB()
        let store = ClipboardStore(databaseURL: url)
        // 构造 >200 字符的 HTML：唯一词出现在 200 字符之后
        let prefix = String(repeating: "filler ", count: 40) // 240 字符
        let html = "<html><body><p>\(prefix)</p><p>deepTailToken</p></body></html>"
        let entry = UTIEntry(uti: "public.html", data: Data(html.utf8))
        store.add(Clip(kind: .text, text: nil, allPasteboardData: [entry]))
        store.query = "deepTailToken"
        try await waitForQueryApplied(store, "deepTailToken")
        #expect(store.filteredItems.count == 1)
    }

    /// url 属性进入索引：link 类型可按 host 检索。
    @Test @MainActor func searchMatchesURLForLinkClips() async throws {
        let url = try makeTempDB()
        let store = ClipboardStore(databaseURL: url)
        store.add(Clip(kind: .link, url: URL(string: "https://example.com/page")!))
        store.query = "example.com"
        try await waitForQueryApplied(store, "example.com")
        #expect(store.filteredItems.count == 1)
    }

    /// 本地化类别名进入索引：query 匹配类型名时命中（对齐原 displayTitle 语义）。
    @Test @MainActor func searchMatchesLocalizedKindTitle() async throws {
        let url = try makeTempDB()
        let store = ClipboardStore(databaseURL: url)
        store.add(Clip(kind: .text, text: "some body"))
        store.query = ClipKind.text.title
        try await waitForQueryApplied(store, ClipKind.text.title)
        #expect(store.filteredItems.count == 1)
    }

    // MARK: - 索引更新

    /// rename 后索引重建：新标题可被检索到。
    @Test @MainActor func searchIndexRebuildsOnRename() async throws {
        let url = try makeTempDB()
        let store = ClipboardStore(databaseURL: url)
        let clip = Clip(kind: .text, text: "body text")
        store.add(clip)
        store.rename(clip.id, title: "ONLY_IN_TITLE")
        store.query = "only_in_title"
        try await waitForQueryApplied(store, "only_in_title")
        #expect(store.filteredItems.count == 1)
    }

    // MARK: - 缓存失效正确性

    /// query 变化后结果随之刷新（过滤结果缓存不得 stale）。
    @Test @MainActor func filteredItemsReflectsQueryChange() async throws {
        let url = try makeTempDB()
        let store = ClipboardStore(databaseURL: url)
        store.add(Clip(kind: .text, text: "aaa"))
        store.add(Clip(kind: .text, text: "bbb"))

        store.query = "aaa"
        try await waitForQueryApplied(store, "aaa")
        #expect(store.filteredItems.map(\.text) == ["aaa"])

        store.query = "bbb"
        try await waitForQueryApplied(store, "bbb")
        #expect(store.filteredItems.map(\.text) == ["bbb"])
    }

    /// 新插入的条目立即可见（items 变化后过滤缓存失效）。
    @Test @MainActor func filteredItemsReflectsNewInsertion() throws {
        let url = try makeTempDB()
        let store = ClipboardStore(databaseURL: url)
        // 先读取一次，填充过滤缓存
        _ = store.filteredItems
        #expect(store.filteredItems.isEmpty)
        store.add(Clip(kind: .text, text: "brandnew"))
        #expect(store.filteredItems.count == 1)
        #expect(store.filteredItems.first?.text == "brandnew")
    }

    /// 删除后结果同步移除（items 变化后过滤缓存失效）。
    @Test @MainActor func filteredItemsRemovesDeletedClip() throws {
        let url = try makeTempDB()
        let store = ClipboardStore(databaseURL: url)
        let clip = Clip(kind: .text, text: "doomed")
        store.add(clip)
        _ = store.filteredItems
        store.delete([clip.id])
        #expect(store.filteredItems.isEmpty)
    }

    /// distinctSourceApps 缓存失效：新增 app 来源后列表刷新。
    @Test @MainActor func distinctSourceAppsRefreshesAfterInsert() throws {
        let url = try makeTempDB()
        let store = ClipboardStore(databaseURL: url)
        #expect(store.distinctSourceApps.isEmpty)
        let clip = Clip(kind: .text, text: "x")
        clip.sourceApplication = "Photon"
        store.add(clip)
        #expect(store.distinctSourceApps == ["Photon"])
    }

    // MARK: - 防抖（RED 驱动）

    /// 过滤输入防抖：query 变化后，防抖窗口内沿用旧结果，窗口结束才按新 query 过滤。
    @Test @MainActor func queryDebouncesThenApplies() async throws {
        let url = try makeTempDB()
        let store = ClipboardStore(databaseURL: url)
        store.add(Clip(kind: .text, text: "alpha only"))

        // 防抖窗口内：仍显示空 query 的全量结果
        store.query = "nonexistentzzz"
        try await Task.sleep(for: .milliseconds(30))
        #expect(store.filteredItems.count == 1)

        // 窗口结束后：新 query 生效，无匹配
        try await waitForQueryApplied(store, "nonexistentzzz")
        #expect(store.filteredItems.isEmpty)
    }

    /// 防抖期间新按键取消旧定时：连续输入只触发最终一次过滤。
    @Test @MainActor func rapidQueryChangesSettleOnLastValue() async throws {
        let url = try makeTempDB()
        let store = ClipboardStore(databaseURL: url)
        store.add(Clip(kind: .text, text: "granular input"))

        // 模拟连续击键：每 50ms 换一个 query，全部落在防抖窗口内
        for q in ["g", "gr", "gra", "gran", "granu"] {
            store.query = q
            try await Task.sleep(for: .milliseconds(50))
        }
        // 最后一次击键后 <150ms：仍应是最初的空 query 结果（全量=1）
        #expect(store.filteredItems.count == 1)

        // 防抖收敛到最后一个 query
        try await waitForQueryApplied(store, "granu")
        #expect(store.filteredItems.count == 1) // "granu" 命中该文本
    }

    // MARK: - Helpers

    /// 轮询等待防抖后的 `effectiveQuery` 更新为期望值（超时 3s）。
    /// 固定 sleep 在并行测试下会与主线程上的防抖定时器产生竞态，轮询语义更稳。
    @MainActor
    private func waitForQueryApplied(_ store: ClipboardStore, _ expected: String) async throws {
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if store.effectiveQuery == expected { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(store.effectiveQuery == expected,
                "防抖 query 未在 3s 内更新为 \(expected)，当前 \(store.effectiveQuery)")
    }
}