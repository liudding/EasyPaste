# EasyPaste 功能增强 PRD

## 项目信息

- **Language**: 中文
- **Programming Language**: Swift 6 + SwiftUI + AppKit + GRDB (SQLite)
- **Project Name**: easypaste_ideas_enhancement
- **原始需求复述**: 基于 `docs/ideas.md` 中的功能想法，为 EasyPaste 剪贴板管理器增加四项功能：(1) Clip 去重增强（基于内容 hash + 重复时置顶更新）、(2) 启动时读取已有剪贴板内容、(3) 多类型 Context Menu（按 Clip 类型分化专属操作）、(4) Dock 图标隐藏设置。

---

## 产品目标

1. **精准去重**：基于剪贴板实际内容生成唯一 hash，消除"不同内容相同长度被误判为重复"的问题，重复项自动置顶更新时间而非静默丢弃，确保用户最近复制的相同内容始终在列表最前。
2. **零遗漏捕获**：应用每次启动时主动读取系统剪贴板当前内容，确保用户在应用未运行期间复制的内容不会丢失。
3. **类型感知操作**：根据 Clip 类型（文本/富文本/图片/邮件/颜色/URL/JSON）在右键菜单中提供专属快捷操作，减少用户跨应用操作步骤。
4. **隐蔽运行**：支持隐藏 Dock 图标，让 EasyPaste 以纯菜单栏/快捷键方式后台运行，减少桌面干扰。

---

## 用户故事

1. **作为用户**，我希望复制相同内容时不会在历史中产生重复条目，而是把已有条目更新到最前面，这样我的剪贴板历史保持简洁且最新。
2. **作为用户**，我希望每次启动 EasyPaste 时，它能自动读取当前系统剪贴板中的内容，这样即使应用刚打开也不会遗漏之前复制的东西。
3. **作为用户**，我希望能隐藏 Dock 中的 EasyPaste 图标，让它像系统服务一样在后台安静运行，需要时通过快捷键唤起即可。
4. **作为用户**，我希望右键点击一个颜色 Clip 时，能直接看到并复制它的 hex / rgb / hsl 色值，而不需要自己手动转换。
5. **作为用户**，我希望右键点击一个 URL Clip 时，能直接打开链接或生成二维码，而不需要先复制再粘贴到浏览器。
6. **作为用户**，我希望右键点击一段 JSON 文本时，能直接看到格式化的结构预览，而不需要去在线工具中格式化。

---

## 需求池

| 优先级 | 需求 | 描述 |
|--------|------|------|
| **P0** | Clip 去重增强 | 基于实际内容生成 hash 进行去重；重复时更新 createdAt 并置顶，而非跳过 |
| **P0** | 启动读取剪贴板 | 应用每次启动时主动读取系统剪贴板当前内容并加入历史 |
| **P1** | 多类型 Context Menu | 按 Clip 类型在右键菜单中增加类型专属操作（通用菜单保留） |
| **P1** | Dock 隐藏设置 | 在设置中增加"隐藏 Dock 图标"开关，切换 `NSApp.setActivationPolicy` |
| **P2** | 各类型专属操作完整覆盖 | 实现所有类型（text/富文本/image/email/color/URL/JSON）的专属操作 |

---

## 需求详细规格

### P0-1: Clip 去重增强

#### 功能描述

当前 `clipHash()` 函数仅使用 `uti:data.count`（UTI 类型 + 数据长度）计算 hash，导致不同内容但相同长度的 Clip 会被误判为重复。需改为基于实际数据内容计算唯一 hash，并在检测到重复时更新已有条目的 `createdAt` 并置顶，而非直接 `return` 跳过。

#### 验收标准

1. **Must**：`clipHash()` 使用 `uti:actual_data_content` 计算 SHA-256，而非 `uti:data.count`
2. **Must**：当检测到重复 Clip 时（相同 kind + 相同 content hash），更新已有条目的 `createdAt` 为当前时间，并将其移动到 `items` 数组最前面（`items[0]`）
3. **Must**：更新后的 `createdAt` 持久化到 GRDB 数据库（upsert）
4. **Must**：重复检测不插入新条目，不产生新的 UUID
5. **Must**：无 `allPasteboardData` 的旧数据仍按现有 `displayTitle + detail` 逻辑去重，但同样改为"更新置顶"而非"跳过"
6. **Should**：hash 计算对大体积数据（如图片 > 10MB）有性能考量，不阻塞主线程

#### 边界情况

- **空剪贴板数据**：`allPasteboardData` 为空或 nil 时，回退到 `displayTitle + detail` 字符串去重
- **图片去重**：两张相同内容的图片（相同像素数据）应被识别为重复，即使来源 app 不同
- **富文本 vs 纯文本**：同一段文字以纯文本和富文本（带格式）分别复制时，若 `allPasteboardData` 不同则不视为重复（格式不同 = 内容不同）
- **并发写入**：如果轮询定时器在去重判断和写入之间有新的 `add` 调用，需确保不会出现竞态导致插入重复

---

### P0-2: 启动读取剪贴板

#### 功能描述

当前 `ClipboardService.start()` 中 `lastChangeCount` 在 `init` 时初始化为 `NSPasteboard.general.changeCount`，导致首次启动时 `readIfChanged()` 认为"没有变化"而跳过。需在首次启动时强制读取一次剪贴板内容。

#### 验收标准

1. **Must**：应用每次启动（冷启动或从 Dock 重新打开）时，主动读取一次系统剪贴板内容
2. **Must**：读取的内容经过与正常轮询相同的处理流程（`makeItem()` → `onItem` → `store.add()`）
3. **Must**：读取的内容受安全标记过滤（`org.nspasteboard.ConcealedType` 等）和忽略应用列表约束
4. **Must**：启动读取不应导致用户在 EasyPaste 中自身复制的内容被重复捕获（需正确设置 `lastChangeCount`）
5. **Should**：启动读取在 `boot()` 中 `clipboard.start()` 之后异步执行，不阻塞面板预热

#### 边界情况

- **空剪贴板**：系统剪贴板为空时，不产生错误，不插入空 Clip
- **安全标记内容**：密码管理器复制的临时内容（带 `ConcealedType` 标记）不应被捕获
- **已在忽略列表的 app**：如果当前前台 app 在忽略列表中，跳过启动读取
- **重复内容**：如果系统剪贴板当前内容已在历史中，触发 P0-1 的去重置顶逻辑（而非插入重复条目）
- **应用已在运行时再次"打开"**：从 Dock 点击图标重新激活（`applicationShouldHandleReopen`）时是否也读取？——建议不读取，仅冷启动读取

---

### P1-1: 多类型 Context Menu

#### 功能描述

当前 `ClipCardView.contextMenu` 只有通用操作（粘贴/纯文本粘贴/复制/重命名/固定到看板/预览/删除）。需在通用操作之前或之后，根据 Clip 的类型（含子类型）增加类型专属操作菜单项。

类型专属操作定义如下：

| 类型 | 专属操作 |
|------|----------|
| **text**（纯文本） | 导出为 .txt 文件、生成二维码 |
| **富文本**（text 子类型） | 导出为 .txt 文件、导出为 .rtf 文件、生成二维码 |
| **image** | 另存为…（NSSavePanel 选择路径保存） |
| **email**（text 子类型） | 发送邮件（打开 mailto: 链接） |
| **color** | 复制 hex 色值、复制 rgb 色值、复制 hsl 色值 |
| **URL / link** | 打开链接（默认浏览器）、生成二维码 |
| **JSON**（text 子类型） | 结构化预览（格式化展示） |

#### 验收标准

1. **Must**：通用操作菜单项（粘贴/纯文本粘贴/复制/重命名/固定到看板/预览/删除）在所有类型下保留不变
2. **Must**：类型专属操作在通用操作之前展示，以 Divider 分隔
3. **Must**：仅在匹配到类型时显示对应专属操作，不匹配时不显示空菜单项
4. **Must**：所有新增菜单文案支持 10 种语言的国际化（L10n）
5. **Should**：二维码生成使用系统原生 `CIFilter.qrCodeGenerator`，以弹窗/浮层形式展示
6. **Should**：导出文件使用 `NSSavePanel`，默认文件名基于内容摘要

#### 边界情况

- **空文本**：text 类型内容为空时，导出和二维码操作禁用或隐藏
- **无效 URL**：link 类型的 URL 无法打开时（如自定义 scheme），优雅降级
- **无效 JSON**：被识别为 JSON 但实际解析失败时，结构化预览展示原始文本
- **无邮件客户端**：email 类型在系统未配置邮件客户端时，`mailto:` 链接可能静默失败
- **颜色格式不完整**：color 类型仅支持 hex 解析（当前 `resolvedColorValue` 只解析 `#RRGGBB`），rgb/hsl 转换需从已解析的颜色值计算
- **大文本二维码**：文本过长导致二维码过于密集无法扫描时，应提示用户

---

### P1-2: Dock 隐藏设置

#### 功能描述

在 `AppSettings` 中新增 `hideDockIcon` 布尔设置项，在设置界面 General 标签页增加开关。开启时调用 `NSApp.setActivationPolicy(.accessory)` 隐藏 Dock 图标，关闭时恢复 `.regular`。

#### 验收标准

1. **Must**：`AppSettings` 新增 `hideDockIcon: Bool` 属性，默认 `false`，持久化到 UserDefaults
2. **Must**：设置界面 General 标签页新增"隐藏 Dock 图标"开关
3. **Must**：开启时 Dock 图标立即消失，关闭时立即恢复
4. **Must**：隐藏 Dock 图标后，菜单栏图标（`MenuBarExtra`）和全局快捷键仍然正常工作
5. **Must**：设置变更后，下次启动应用时保持上次的状态
6. **Should**：隐藏 Dock 图标时，从 Dock 拖拽文件到应用图标的操作不再可用（已知限制，非 bug）

#### 边界情况

- **首次启动**：默认不隐藏（`hideDockIcon = false`），用户完成 onboarding 后再决定是否隐藏
- **隐藏后打开设置**：隐藏 Dock 图标后，用户通过菜单栏 → Settings 打开设置窗口，此时不应自动恢复 Dock 图标（当前 `openSettingsWindow` 中有 `NSApp.setActivationPolicy(.regular)`，需调整）
- **隐藏后关闭设置窗口**：关闭设置窗口后是否重新隐藏？——建议不自动重新隐藏，保持用户手动控制
- **Spotlight 搜索**：隐藏 Dock 图标后仍可通过 Spotlight 搜索到应用

---

### P2: 各类型专属操作完整覆盖

#### 功能描述

实现 P1-1 中定义的所有类型专属操作。以下为各操作的详细规格。

#### 导出为 .txt 文件（text / 富文本）

- 从 `clip.text` 或 `clip.previewPlainText` 提取纯文本内容
- 使用 `NSSavePanel` 让用户选择保存路径，默认文件名 `clip_<时间戳>.txt`
- 写入 UTF-8 编码的 .txt 文件

#### 导出为 .rtf 文件（富文本）

- 从 `clip.attributedText` 获取 `NSAttributedString`
- 使用 `NSAttributedString.data(from:range:options:documentAttributes:)` 以 `.rtf` 文档类型生成 RTF 数据
- 使用 `NSSavePanel` 让用户选择保存路径，默认文件名 `clip_<时间戳>.rtf`

#### 生成二维码（text / 富文本 / URL）

- 使用 `CIFilter(name: "CIQRCodeGenerator")` 生成二维码 `CIImage`
- 将 `CIImage` 转换为 `NSImage`，在弹出窗口/浮层中展示
- 支持用户右键保存二维码图片
- 二维码内容：text/富文本用纯文本，URL 用 `url.absoluteString`

#### 另存为（image）

- 从 `clip.imageData` 获取原始图片数据
- 使用 `NSSavePanel`，根据原始 UTI 格式（PNG/JPEG/HEIC 等）设置默认文件扩展名
- 直接写入原始数据（不转码），保持质量

#### 发送邮件（email）

- 从 clip 文本中提取 email 地址
- 构造 `mailto:<email>` URL
- 调用 `NSWorkspace.shared.open(mailtoURL)` 打开默认邮件客户端

#### 复制色值（color）

- **hex**：从 `clip.text` 获取或从 `resolvedColorValue` 反算 `#RRGGBB` 格式
- **rgb**：从 `resolvedColorValue` 计算 `rgb(r, g, b)` 格式（0-255）
- **hsl**：从 `resolvedColorValue` 转换为 `hsl(h, s%, l%)` 格式
- 点击后将对应格式的色值字符串写入系统剪贴板（`NSPasteboard.general.setString`）
- 不触发 EasyPaste 自身的内容捕获（需设置 `lastChangeCount`）

#### 打开链接（URL）

- 从 `clip.url` 获取 URL
- 调用 `NSWorkspace.shared.open(url)` 在默认浏览器中打开

#### JSON 结构化预览（JSON）

- 使用 `JSONSerialization` 解析 JSON 字符串
- 使用 `.prettyPrinted` 选项重新序列化为格式化文本
- 在预览浮层中展示（复用现有 preview 机制或新建 JSON 专用预览视图）
- 解析失败时展示原始文本 + 错误提示

---

## 子类型检测设计

### 设计思路

当前 `ClipKind` 枚举有 `text` / `link` / `image` / `file` / `color` 五种。`ideas.md` 提出富文本、email、JSON 可作为 text 的子类型。设计方案为在 `Clip` 模型中新增 `subkind` 可选字段，在 `ClipboardService.makeItem()` 中对 text 类型进行子类型检测。

### 子类型定义

```
enum ClipSubkind: String, Codable {
    case richText     // 富文本（含 RTF/RTFD/HTML 原始格式数据）
    case email        // 邮箱地址
    case json         // JSON 格式文本
    // nil = 普通纯文本
}
```

### 检测规则（在 `makeItem()` 中，text 类型确定后执行）

按优先级从高到低检测，命中即停止：

1. **富文本（richText）**
   - 条件：`allPasteboardData` 中存在 `public.rtf` / `com.apple.flat-rtfd` / `public.html` 任一 UTI 条目
   - 判定：有富文本格式数据 → `subkind = .richText`

2. **颜色值（已有逻辑）**
   - 条件：`isColorValue == true`（`#RGB` / `#RRGGBB` / `#RRGGBBAA` / `rgb()` / `hsl()`）
   - 判定：直接将 `kind` 重分类为 `.color`（现有逻辑不变，不改 subkind）

3. **JSON**
   - 条件：`text` 能被 `JSONSerialization.jsonObject(with:options:)` 成功解析，且首字符为 `{` 或 `[`
   - 判定：`subkind = .json`
   - 边界：纯文本 `"hello"` 虽然是合法 JSON 字符串，但首字符非 `{`/`[`，不识别为 JSON

4. **Email**
   - 条件：`text` 去除首尾空白后，匹配 email 正则 `^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$`
   - 判定：`subkind = .email`
   - 边界：单个 email 地址才识别；包含 email 的长段文本不识别（如 "Contact me at a@b.com" 不触发）

5. **普通纯文本**
   - 以上均不匹配 → `subkind = nil`

### 数据持久化

- `Clip` 模型新增 `subkind: ClipSubkind?` 字段
- `ClipRow` 新增 `subkind` 列（TEXT，可空），数据库迁移新增列
- `toClip()` 和 `init(_ clip:)` 中增加 `subkind` 的编解码

### Context Menu 分发逻辑

```swift
// 伪代码：contextMenu 根据类型组合菜单
if item.kind == .text {
    switch item.subkind {
    case .richText:  // 富文本专属菜单
    case .email:    // email 专属菜单
    case .json:     // JSON 专属菜单
    case nil:       // 普通纯文本菜单
    }
}
if item.kind == .color { /* color 专属菜单 */ }
if item.kind == .image { /* image 专属菜单 */ }
if item.kind == .link  { /* URL 专属菜单 */ }
// 通用菜单（粘贴/复制/重命名/固定/预览/删除）始终追加
```

---

## 待确认问题

1. **启动读取剪贴板的时机**：是仅在冷启动（`applicationDidFinishLaunching`）时读取，还是从 Dock 重新点击图标（`applicationShouldHandleReopen`）时也读取？当前建议仅冷启动读取。

2. **Dock 隐藏后打开设置窗口的行为**：当前 `openSettingsWindow` 中有 `NSApp.setActivationPolicy(.regular)`，会强制恢复 Dock 图标。若用户已设置隐藏 Dock 图标，打开设置窗口时是否应保持隐藏状态（仅设置窗口显示，Dock 不出现）？建议：设置窗口显示时不改变 `activationPolicy`，保持用户设置。

3. **子类型是否需要持久化到数据库**：`subkind` 字段是否需要新增数据库列持久化？还是每次加载时从 `allPasteboardData` + `text` 动态检测？建议持久化，避免每次读取都重新检测，且历史数据可通过迁移补检测。

4. **二维码展示方式**：是在现有 preview 浮层中展示，还是新建一个独立的二维码弹窗？现有 preview 机制是通过 `onPreview` 回调触发的浮层，二维码弹窗可能需要独立窗口。

5. **颜色 rgb/hsl 复制的值范围**：rgb 使用 0-255 整数还是 0-1 浮点？hsl 中 h 的单位是度还是弧度？建议：rgb 用 `rgb(255, 128, 0)` 格式（0-255 整数），hsl 用 `hsl(30, 100%, 50%)` 格式（度/百分比）。

6. **JSON 结构化预览是否支持折叠/展开**：简单实现是 `.prettyPrinted` 格式化文本展示，增强实现是带语法高亮和折叠的树形视图。建议 P2 先做简单格式化预览，树形视图作为后续迭代。

7. **富文本导出 RTF 时是否包含图片**：如果富文本中包含内嵌图片（RTFD），导出为 .rtf 时图片会丢失。是否需要同时支持导出为 .rtfd？建议 P2 仅支持 .rtf，RTFD 作为后续迭代。

8. **去重 hash 是否需要持久化**：是否在数据库中新增 `contentHash` 列缓存 hash 值，避免每次去重都要重新计算所有已有条目的 hash？对于 2000 条历史的全量遍历，每次 add 都重新计算可能影响性能。建议持久化 hash 列 + 建索引。

9. **email 子类型的正则严格程度**：当前正则 `^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$` 是否足够？是否需要支持 Unicode 域名（如 `用户@例子.中国`）？建议 P2 先用 ASCII 正则，Unicode 支持作为后续迭代。
