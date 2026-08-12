# 分词检索设计

日期：2026-08-12

## 问题

当前检索把查询输入当单个字符串做 `contains` 子串匹配：
`item.searchText?.contains(filterKeyword)`。
多关键词查询（如 `"foo bar"`）要求连续子串出现，无法按词匹配。

## 方案

对**检索输入**分词，得到 tokens；每个 token 在 clip 的 `searchText` 索引上做 `contains` 查找。

### 改动（集中在 `Stores/ClipboardStore.swift`）

| 组件 | 现状 | 改造后 |
|---|---|---|
| 存储 | `filterKeyword: String` | `filterTokens: [String]`（查询侧预分词） |
| 分词时机 | `effectiveQuery` didSet（防抖后） | 同位置，拆分为 tokens |
| 过滤条件 | `searchText.contains(filterKeyword)` | `filterTokens.allSatisfy { searchText.contains($0) }`（AND） |
| 空查询 | 跳过过滤 | tokens 为空 → 跳过过滤（不变） |

### 分词规则

`query.lowercased()` 按**空白 + 全部标点**（`CharacterSet.punctuationCharacters`，含全角中文标点）拆分，过滤空串。

### 边界行为

- 多关键词 `"foo bar"` → `["foo","bar"]` AND 匹配，顺序不限
- 中文整句 `"世界你好"` 无空格 → 单 token，保持原 `contains` 子串行为
- URL `"example.com"` → `["example","com"]`；link 索引 `"https://example.com/page"` 同时含两子串 → 仍命中

## 测试（SearchOptimizationTests 追加）

1. 多关键词 AND：需同时命中
2. 标点拆分：`"foo,bar"` 等价于 `"foo bar"`
3. 中文子串回归：整句 contains
4. 纯标点/空白查询：显示全部
5. 既有 `searchMatchesURLForLinkClips` 等回归通过

## 不做（YAGNI）

- 精确短语引号
- token 最小长度过滤
- 索引侧改造
