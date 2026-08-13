# 分词检索 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 把 ClipboardStore 的检索从单字符串 `contains` 升级为「查询输入分词 + 每 token 在 searchText 索引上 contains」的 AND 匹配。

**Architecture:** 查询侧预分词：`effectiveQuery` didSet 时把 query 按空白+标点拆成小写 tokens 数组 `filterTokens`；`filteredItems` 热路径改为 `filterTokens.allSatisfy { searchText.contains($0) }`。索引侧（Clip.searchText）零改动，保持 contains 查找。

**Tech Stack:** Swift 6, Swift Testing, @Observable @MainActor

**设计文档:** `docs/plans/2026-08-12-tokenized-search-design.md`

---

### Task 1: 写失败测试（分词 AND 行为）

**Files:**
- Modify: `Tests/EasyPasteTests/SearchOptimizationTests.swift`（追加到 suite 内，防抖测试之前）

**Step 1: 追加 4 个测试**

在 `SearchOptimizationTests` 的「过滤正确性」区段追加：

```swift
    // MARK: - 分词检索

    /// 多关键词 AND：两个词都命中才显示（顺序不限）。
    @Test @MainActor func multiKeywordQueryRequiresAllTokens() async throws {
        let url = try makeTempDB()
        let store = ClipboardStore(databaseURL: url)
        store.add(Clip(kind: .text, text: "foo bar baz"))
        store.add(Clip(kind: .text, text: "foo only"))
        store.add(Clip(kind: .text, text: "bar only"))
        store.query = "foo bar"
        try await waitForQueryApplied(store, "foo bar")
        #expect(store.filteredItems.map(\.text) == ["foo bar baz"])
    }

    /// 标点拆分："foo,bar" 等价于 "foo bar"。
    @Test @MainActor func punctuationSeparatesTokens() async throws {
        let url = try makeTempDB()
        let store = ClipboardStore(databaseURL: url)
        store.add(Clip(kind: .text, text: "hello world"))
        store.add(Clip(kind: .text, text: "hello"))
        store.query = "hello,world"
        try await waitForQueryApplied(store, "hello,world")
        #expect(store.filteredItems.map(\.text) == ["hello world"])
    }

    /// 中文整句（无空格）保持子串匹配。
    @Test @MainActor func chinesePhraseStillMatchesSubstring() async throws {
        let url = try makeTempDB()
        let store = ClipboardStore(databaseURL: url)
        store.add(Clip(kind: .text, text: "你好世界"))
        store.query = "世界"
        try await waitForQueryApplied(store, "世界")
        #expect(store.filteredItems.map(\.text) == ["你好世界"])
    }

    /// 纯标点/空白查询：tokens 为空 → 显示全部。
    @Test @MainActor func punctuationOnlyQueryShowsAll() async throws {
        let url = try makeTempDB()
        let store = ClipboardStore(databaseURL: url)
        store.add(Clip(kind: .text, text: "aaa"))
        store.add(Clip(kind: .text, text: "bbb"))
        store.query = " ,."
        try await waitForQueryApplied(store, " ,.")
        #expect(store.filteredItems.count == 2)
    }
```

**Step 2: 运行确认失败（RED）**

Run: `swift test --no-parallel --filter SearchOptimizationTests/multiKeywordQueryRequiresAllTokens`
Expected: FAIL —— 旧代码 `filterKeyword = "foo bar"`，searchText `"foo bar baz"` 不连续包含 `"foo bar"`，`count == 0` ≠ 1。

### Task 2: 实现分词过滤

**Files:**
- Modify: `Stores/ClipboardStore.swift:16-26`（filterKeyword 属性 → filterTokens）
- Modify: `Stores/ClipboardStore.swift:79-83`（过滤条件）

**Step 1: 替换属性声明**

```swift
    /// 预归一化的过滤关键词（小写），供热路径逐条 contains。
    private var filterKeyword = ""
```
改为：
```swift
    /// 查询输入分词后的 tokens（小写），供热路径逐条 contains（AND 匹配）。
    private var filterTokens: [String] = []
```

**Step 2: 替换 effectiveQuery didSet 内部分词逻辑**

```swift
            filteredCache = nil
            filterKeyword = effectiveQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
```
改为：
```swift
            filteredCache = nil
            filterTokens = Self.tokenize(effectiveQuery)
```

**Step 3: 添加分词函数**（`filteredItems` 上方或类内私有方法区）

```swift
    /// 按空白+标点拆分查询为小写 tokens（中文整句无分隔符时保持单 token 子串匹配）。
    private static func tokenize(_ query: String) -> [String] {
        let separators = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        return query.lowercased()
            .components(separatedBy: separators)
            .filter { !$0.isEmpty }
    }
```

**Step 4: 替换过滤条件**

```swift
            (filterKeyword.isEmpty || item.searchText?.contains(filterKeyword) == true) &&
```
改为：
```swift
            (filterTokens.isEmpty || filterTokens.allSatisfy { item.searchText?.contains($0) == true }) &&
```

**Step 5: 运行确认通过（GREEN）**

Run: `swift test --no-parallel --filter SearchOptimizationTests`
Expected: 全部 PASS（含既有 12 个回归测试：URL/大小写/富文本/防抖等）

### Task 3: 全量验证 + 提交

**Step 1: 全量测试**

Run: `swift test`
Expected: `119 tests in 9 suites passed`（原有 119 + 新 4 = 123）

**Step 2: lsp_diagnostics**

Run: `lsp_diagnostics` on `Stores/ClipboardStore.swift` 与 `Tests/EasyPasteTests/SearchOptimizationTests.swift`
Expected: 无诊断

**Step 3: 提交**

```bash
git add Stores/ClipboardStore.swift Tests/EasyPasteTests/SearchOptimizationTests.swift
git commit -m "feat: 检索分词——查询输入按空白+标点拆分 tokens，AND 匹配 searchText 索引"
```
