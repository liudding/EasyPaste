# macOS UTI 与粘贴板（Pasteboard）深度研究

> 研究对象：macOS 上 Uniform Type Identifier（UTI）体系 + `NSPasteboard` 粘贴板系统
> 目的：为 EasyPaste 剪贴板管理器提供底层机制梳理、正确性校验与可落地的改进建议
> 生成日期：2026-07-24

---

## 0. 为什么研究这两个东西

剪贴板管理器（Clipboard Manager）的本质，就是一台**持续监听系统粘贴板、把每一次拷贝的多格式数据原样抓取、归类、存储，并在粘贴时保真写回**的机器。它每天要回答三个问题，而这三个问题全部落在 UTI + 粘贴板上：

1. **「这次拷贝了什么类型的数据？」** → 由粘贴板上的 *types*（本质是 UTI 字符串）回答。
2. **「多个表示里我该抓哪一个 / 保真写回哪些？」** → 由 *UTI 一致性层次（conformance）* 与 *多表示模型* 回答。
3. **「哪些数据我不该存？」** → 由 `org.nspasteboard.ConcealedType` 等*社区约定的安全标记* 回答。

EasyPaste 当前的 `ClipboardService.makeItem()` / `copy()` 已经实现了上面 1、2 的大部分，但第 3 点存在真实隐私缺口（见 §5.3）。

---

## 1. Uniform Type Identifier（UTI）体系

### 1.1 一句话定义

UTI 是一个**字符串**，用来标识「一类实体」（文件格式、内存数据类型、目录/卷/包的结构）。在粘贴板场景里，它专门用来标记「写入的那段数据是什么格式」。

### 1.2 语法：反向 DNS（reverse-DNS）

```
com.apple.application
public.html
public.jpeg
com.easypaste.clip
dyn.ah62d4r34gq81k3p2su1zuppgsm10esvvhzxhe55c
```

- 顶层域（com / public / dyn …）→ 子域 → 末级 token。
- 受 RFC 1035 DNS 命名限制：**不能**出现大写、下划线 `_`、冒号 `:`、空格。用了非法字符 UTI 会静默失效，API 不会报错——这是经典坑。
- 域（com / public）**只表示在层次树中的位置**，不代表「同类分组」。

### 1.3 域的语义

| 域 | 含义 | 示例 |
|----|------|------|
| `public.` | Apple 定义的通用/标准类型，所有应用共享 | `public.text`、`public.png`、`public.utf8-plain-text` |
| `com.` | 企业或应用的专有类型，通常用 `com.<company>.<app>.<type>` | `com.adobe.pdf`、`com.apple.rtfd` |
| `dyn.` | **动态 UTI**，系统为「没有声明 UTI 的未知类型」自动生成的兼容包装（见 §1.6） | `dyn.xxx` |
| 其他 | 任意组织都可声明，只要唯一 | `org.nspasteboard.ConcealedType` |

### 1.4 一致性层次结构（Conformance Hierarchy）—— UTI 的核心超能力

UTI 可以像面向对象语言的类一样形成**继承树**，且支持**多继承**。底层类型「是」所有父类型的实例。

```
public.item                  (最通用：文件系统中的条目)
  └─ public.data             (可用字节流表示)
       └─ public.content     (可成为文档)
            └─ public.image  (图片)
                 ├─ public.png
                 ├─ public.jpeg
                 └─ public.tiff
  └─ public.text             (文本)
       └─ public.plain-text
            └─ public.utf8-plain-text
       └─ public.html        ← 因为继承 public.text，能打开纯文本的程序也能打开 HTML
```

**意义（对剪贴板管理器至关重要）：**
- 一个应用只要声明「我能读 `public.text`」，就自动能读 `public.html`、`public.utf8-plain-text` 等所有子类。
- 管理器在「选择最合适表示」时，应该**一致性感知**地判断，而不是字符串精确匹配（EasyPaste 当前用的是字符串匹配，见 §5.3 #2 的改进建议）。
- 设计自定义 UTI 时，物理维度与功能维度要分开：`com.apple.application-package` 同时继承 `com.apple.bundle` 和 `com.apple.package`（多继承典范）。

### 1.5 类型标签（Tags）：UTI 与外部识别法的桥接

一个 UTI 可以有多个等价的「旧世界」标识，记录在 `UTTypeTagSpecification` 里：

| Tag Class | 含义 | 示例 |
|-----------|------|------|
| `public.filename-extension` | 文件扩展名 | `jpeg`, `jpg` |
| `public.mime-type` | MIME 类型 | `image/jpeg` |
| `com.apple.ostype` | 4 字符 OSType（经典 Mac） | `JPEG` |
| `com.apple.nspboard-type` | 旧粘贴板类型 | `NSStringPboardType` |
| `public.url-scheme` | URL scheme | `https` |

转换函数（macOS 11 之前在 `CoreServices`/`MobileCoreServices`，之后在 `UniformTypeIdentifiers`）：
- `UTTypeCreatePreferredIdentifierForTag(tagClass, tag, conformTo)` — 扩展名/MIME → UTI
- `UTTypeCopyPreferredTagWithClass(uti, tagClass)` — UTI → 扩展名/MIME
- 新版等价：`UTType(filenameExtension:)`、`UTType(mimeType:)`、`UTType.Reference.preferredFilenameExtension`、`preferredMIMEType`

```swift
// 扩展名 → UTI → MIME（macOS 11+）
if let uti = UTType(filenameExtension: "png") {
    print(uti.identifier)          // "public.png"
    print(uti.preferredMIMEType)   // "image/png"
    print(uti.conforms(to: .image))// true
}
```

### 1.6 声明 UTI：导出 vs 导入（Info.plist）

应用通过在 bundle 的 `Info.plist` 里声明 UTI，告诉系统「我认识这个格式」。

- **UTExportedTypeDeclarations**：你**拥有**的类型（你的专有格式）。导出声明优先于导入声明。
- **UTImportedTypeDeclarations**：你**不拥有**、但希望系统也认识的类型（比如你依赖别人的私有格式，但那家应用可能没装）。

声明字段：`UTTypeIdentifier`（必需）、`UTTypeConformsTo`（数组）、`UTTypeTagSpecification`、`UTTypeDescription`、`UTTypeIconFile`、`UTTypeReferenceURL`。

> EasyPaste 已在 `Clip.swift` 里用 `UTType(importedAs: "com.easypaste.clip")` 声明了一个内部拖拽类型 `com.easypaste.clip`（用于 Pinboard 间拖拽），方向是对的。

### 1.7 动态 UTI（dyn. 域）与解码

当遇到**没有任何声明的未知类型**时（例如某个 App 往粘贴板写了一个私有 `com.xxx.yyy` 但没声明过），macOS 不会报错，而是生成 `dyn.<opaque>` 作为「围绕未知类型的 UTI 兼容包装」。

- `dyn.` 后面的字符是**不透明**的 base-32 编码，里面其实藏回了原始 tag（扩展名 / MIME / OSType / pasteboard-type 以及它 conform 到的类型）。
- 你可以**像普通 UTI 一样对待** `dyn.xxx`，也能用 `UTTypeCopyPreferredTagWithClass` 反解出原始标签。
- 解码对照（Apple 未公开文档，社区已破译）：`1`=filename-extension, `2`=ostype, `3`=mime-type, `4`=nspboard-type, `6`=public.data, `7`=public.text, `B`=public.image, `C`=public.video, `D`=public.audio …

```swift
// 把 dyn.xxx 还原成人类可读标签，用于调试/诊断
if let uti = UTType("dyn.ah62d4r34gq81k3p2su1zuppgsm10esvvhzxhe55c") {
    let ext = uti.preferredFilenameExtension  // 可能解出原始扩展名
    let mime = uti.preferredMIMEType
}
```

EasyPaste 当前对 `dyn.` 类型是「原样存成 `types.first?.rawValue`」字符串，没做解码（见 §5.3 #5），调试日志里看到 `dyn.xxx` 会很难读。

### 1.8 `UTType` 结构体（macOS 11+ / iOS 14+）

`UniformTypeIdentifiers` 框架把旧 C API 包成了 Swift 友好的结构体：

- `struct UTType`：`UTType.image` / `UTType.png` / `UTType.utf8PlainText` / `UTType.fileURL` …
- 关键方法：`conforms(to:)`、`isSubtype(of:)`、`referenceURL`、`localizedDescription`
- `struct UTTagClass`：`.filenameExtension`、`.mimeType`、`.ostype`、`.nsPboardType`
- 比较两个 UTI 是否「等价」要用 `UTTypeEqual`，**不要直接 `==` 字符串**（动态 UTI 的标签是另一个 UTI 标签子集时也算相等）。

---

## 2. 粘贴板（Pasteboard）系统

### 2.1 `NSPasteboard` 是什么

一个**系统级的共享数据中介**。源 App 把数据写上去，目标 App 从上面读，**两个 App 从不直接通信**。API 极其古老（NeXTSTEP 时代），但模型其实很现代。

```
源 App  ──写入──▶  NSPasteboard.general  ──读取──▶  目标 App
```

### 2.2 命名粘贴板

| 名称 | 用途 |
|------|------|
| `.general` | 普通 ⌘C/⌘V；macOS 10.12+ 自动参与 Handoff / Universal Clipboard |
| `.find` | 查找面板的搜索词，跨 App 共享（被严重低估的好特性） |
| `.font` / `.ruler` | 字体 / 段落格式 |
| `.sound` | 声音 |
| 拖拽粘贴板 | 拖放过程中临时使用 |
| `withUniqueName()` | 应用自建私有粘贴板（内部用途） |

剪贴板管理器**只关心 `.general`**（以及可选的 Universal Clipboard 远程标记）。

### 2.3 多条目 + 多表示（核心模型）

一个粘贴板可以含**多个 item**，每个 item 含**多个表示（type → data）**：

- 从网页复制富文本，粘贴板上可能同时有：`public.html`、`public.rtf`、`public.utf8-plain-text` 三种表示。
- 拖 10 个文件，粘贴板有 10 个 item，每个 item 一个 `public.file-url`。
- **目标 App 自己挑它最喜欢的那个表示**：粘到终端 → 拿纯文本；粘到 Pages → 拿 RTF/HTML。同一份数据，不同 App 读到不同格式。

> 这是剪贴板管理器「保真」的理论基础：**存的时候把所有表示都抓下来，粘回去的时候把所有表示都写回去**。EasyPaste 的 `richTextData: [UTIEntry]` 就是为文本类做的这件事。

### 2.4 类型即 UTI：`PasteboardType` ↔ `UTType`

`NSPasteboard.PasteboardType` 本质就是个 UTI 字符串的封装。Apple 提供了一组常量（见 §6 速查表），旧字符串常量（如 `NSStringPboardType`）在 10.6 起已被 UTI 常量取代并大多 `Deprecated`。

```swift
let t = NSPasteboard.PasteboardType("public.png")   // 直接用 UTI 字符串构造
let ut = UTType("public.png")                        // 转成 UTType 做一致性判断
```

### 2.5 读取 API（关键方法）

| 方法 | 作用 |
|------|------|
| `var types: [PasteboardType]?` | 第一个 item 上**所有可用类型**（仅验证用；多 item 时不完整） |
| `func data(forType:)` | 取某类型的 `Data`（第一个含它的 item） |
| `func string(forType:)` | 取字符串（会拼接**所有**含该类型的 item） |
| `func propertyList(forType:)` | 取 plist |
| `func availableType(from: [PasteboardType]) -> PasteboardType?` | 在给定列表里返回**第一个被支持**的类型（精确匹配，非一致性匹配） |
| `func readObjects(forClasses:options:) -> [Any]?` | 按类读取最匹配的 objects（`NSURL`/`NSImage`/`NSString`/`NSColor`…） |
| `func canReadObject(forClasses:options:)` | 是否含某类可读对象 |
| `var pasteboardItems: [NSPasteboardItem]?` | 所有 item（逐 item 逐类型精读时用） |
| `var changeCount: Int` | 内容变更计数（见 §2.7） |

`readObjects` 的常用 `options`：`.urlReadingFileURLsOnly`（只要文件 URL）、`.urlReadingContentsConformToTypes`（URL 内容需 conform 到给定 UTI 数组）。

### 2.6 写入 API

| 方法 | 作用 |
|------|------|
| `func clearContents() -> Int` | 清空（**注意：清空也会让 `changeCount` +1**） |
| `func setData(_:forType:)` | 给第一个 item 写某类型数据 |
| `func setString(_:forType:)` | 写字符串 |
| `func setPropertyList(_:forType:)` | 写 plist |
| `func writeObjects([NSPasteboardWriting])` | 写一组对象（自动展开其 `writableTypes`） |
| `func prepareForNewContents(with:)` | 带选项清内容（`ContentsOptions`） |

> ⚠️ `clearContents()` 会触发 `changeCount` 自增。管理器在**自己写回**后必须把本地 `lastChangeCount` 同步成新的 `changeCount`，否则下一轮轮询会误判成「用户又拷贝了一次」而把刚写回的内容又抓进历史（EasyPaste 的 `copy()` 末尾已做 `lastChangeCount = pasteboard.changeCount`，正确）。

### 2.7 没有通知：只能轮询 `changeCount`

**macOS 没有**任何 `NSNotification` / delegate / Combine  publisher 来告知粘贴板变化。唯一办法是定时读 `changeCount`：

```swift
var last = NSPasteboard.general.changeCount
Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { _ in
    let now = NSPasteboard.general.changeCount
    if now != last { last = now; /* 有新内容，抓取 */ }
}
```

- 轮询间隔是 CPU 与「漏抓」的权衡，常见 0.3–0.5s，单整数比较几乎零成本。
- 必须处理「`changeCount` 变了但无可读数据」的情况（clear 后没写）。

### 2.8 承诺/代理类型（懒加载，简述）

经典 `NSFilesPromisePboardType`（已废弃，改用 `kPasteboardTypeFileURLPromise`）允许拖放时**先只承诺「我能给出某种文件」**，目标 App 真正 drop 时才生成实际文件内容。剪贴板管理器一般不直接处理承诺类型，但要能识别并跳过。

### 2.9 社区约定的特殊标记（重点：安全相关）

由 [nspasteboard.org](http://www.nspasteboard.org/)（现为 utis.cc / GitHub `NSPasteboard` 组织维护）约定，被 1Password、Bitwarden、Alfred、Keyboard Maestro、Paste 等广泛采用：

| 标记 UTI | 含义 | 管理器应如何反应 |
|----------|------|------------------|
| `org.nspasteboard.ConcealedType` | **敏感数据**（密码等）。通常由密码管理器在 `public.utf8-plain-text` 之外**额外**写入这个空值标记 | 应**不存入明文历史**或遮罩显示（防肩窥 + 防落盘泄露） |
| `org.nspasteboard.TransientType` | 瞬态数据（例如文字展开工具临时放进粘贴板、用完即还原）。**不应**进入历史 | 跳过 |
| `org.nspasteboard.AutoGeneratedType` | 自动生成内容（区别于瞬态） | 视策略 |
| `org.nspasteboard.RestoredType` | 被工具「还原」回粘贴板的内容 | 视策略 |
| `org.nspasteboard.source` | 标注数据来源 App | 可选：用于来源展示 |
| `com.apple.is-remote-clipboard` | 来自 Universal Clipboard（其他设备的远程拷贝） | 可选：标注「来自 iPhone/iPad」 |

> **关键事实**：1Password/Chrome 复制密码时，粘贴板**同时**有 `public.utf8-plain-text`（真实密码）和 `org.nspasteboard.ConcealedType`（空值标记）。Firefox、老版 Bitwarden 扩展**漏写** ConcealedType，导致密码进历史——这正是该标记要解决的问题。

---

## 3. 关键机制深挖

### 3.1 目标 App 怎么选「最合适表示」

粘贴不是「全给」，而是目标 App 构造一个**它接受的类型列表（含父类型）**，再调 `availableType(from:)` 取第一个命中的。例如一个能读 `public.text` 的 App 会传 `[public.text, public.utf8-plain-text, public.html, …]`，于是即使只提供了 HTML 它也能读。管理器做反向操作：保存时把整张「类型→Data」表都留着。

### 3.2 保真写回

写回时**按优先级顺序把多个表示都 `setData` 上去**（RTF > HTML > 纯文本），目标 App 自己挑。EasyPaste 的 `copy()` 对非纯文本分支正是这么做的（`richTextData` 排序写入）。

### 3.3 来源 App 推断

粘贴板**本身不记录**是谁写的。管理器只能在「检测到 `changeCount` 变化那一刻」读取 `NSWorkspace.shared.frontmostApplication` 来推断来源。EasyPaste 的 `readIfChanged()` 正是这么做的——但要注意：如果用户拷贝后立刻切走窗口，抓到的 frontmost 可能不准（这是系统限制，不是代码 bug）。

---

## 4. 与 EasyPaste 代码的映射

### 4.1 现有实现梳理（`Services/ClipboardService.swift` 为主）

- **轮询**：`Timer` 0.45s 读 `changeCount`，变化后 `readIfChanged()` —— 符合 §2.7。
- **来源过滤**：`AppSettings.ignoredApps`（钥匙串访问、密码 App 默认忽略）—— 但这是按**来源 App** 过滤，不覆盖「在浏览器里用密码扩展拷贝」的情况（见 §5.3 #1）。
- **类型抓取**：`makeItem()` 先过滤掉 `ConcealedType` 这个 type 字符串（仅从类型列表移除，**并未据此判定为敏感**，见 §5.3 #1），然后按 文件 → 链接 → 图片 → 文本 顺序识别。
- **多表示保存**：文本类用 `preferredUTIsForText` 抓全部有数据的类型进 `richTextData`，优先 RTF>HTML>utf8>plain。
- **保真写回**：`copy()` 非纯文本时把 `richTextData` 按优先级全部 `setData` 写回；纯文本走 `.string`。
- **写回后同步**：`lastChangeCount = pasteboard.changeCount` —— 正确避免自我循环捕获。
- **跨 App 粘贴**：`paste()` → `ensureAccessibilityPermission()` → 激活目标 → 轮询焦点 → `CGEvent` 发 ⌘V（用 HID event tap 而非 `postToPid`，正确）。

### 4.2 做得好的地方

1. 多格式文本保真（RTF/HTML/纯文本一起存、一起写回）。
2. 写回后同步 `changeCount`，无自我循环。
3. 跨 App 粘贴用真实 HID keystroke，兼容性好。
4. 内部类型 `com.easypaste.clip` 用 `UTType(importedAs:)` 正规声明。
5. 大图 12MB 上限保护（防止巨图撑爆粘贴板/内存）。

### 4.3 可改进点（按优先级）

> **实现状态（2026-07-24 代码已演进）**：当前代码版本已内置 `hasSecurityMarker` / `filteredTypes`（覆盖 `ConcealedType` / `TransientType` / `AutoGeneratedType`，默认跳过），并改用 `allPasteboardData` 保存全部多格式表示——即文档 #1 的安全标记处理与多表示保真部分**已完成**（且比文档建议更严格）。本次代码调整落地了 **#2**（UTI 一致性感知的类型选择）、**#3**（图片优先保存原始格式而非统一 TIFF）、**#4**（`NSFilenamesPboardType` → `public.file-url`）。**#5 / #6** 为低优先级可选项，暂未做。

#### #1 隐私缺口：未真正处理 `ConcealedType`（高优先级）
`makeItem()` 第 45 行只是把 `org.nspasteboard.ConcealedType` 从 `availableTypes` 里 `filter` 掉，**用户密码仍会被当作普通文本抓取并存进历史明文**。这违背了该标记的初衷。

建议：检测标记后，按策略处理（跳过 / 遮罩 / 加密落盘）。Eg：

```swift
private func makeItem() -> Clip? {
    let types = pasteboard.types ?? []
    let isConcealed = types.contains { $0.rawValue == "org.nspasteboard.ConcealedType" }
    // 也识别来源是密码类 App 的情况
    let sourceIsPasswordManager = (NSWorkspace.shared.frontmostApplication?
        .bundleIdentifier ?? "").contains("password") // 或匹配已知 bundleID 列表

    if isConcealed {
        switch settings.concealedHandling {   // 新增设置项：skip / mask / store
        case .skip: return nil                 // 不进历史（推荐默认）
        case .mask: /* 抓取但不显示明文，存遮罩 */
        case .store: break                     // 原样存（不推荐）
        }
    }
    // ... 其余逻辑
}
```

并在 `AppSettings` 新增 `concealedHandling` 枚举 + 设置 UI。注意：对「浏览器里的密码扩展」只能靠 `ConcealedType` 识别（来源 App 是浏览器，不在 ignore 列表），所以**处理标记比加 ignore 列表更根本**。

#### #2 类型选择用字符串精确匹配，非一致性感知（中）
`preferredUTI(forImage:)` / `forFiles:` / `forLink:` 都是 `rawValue == "public.png"` 这种精确比较。如果粘贴板给的是 `public.jpeg`、`public.heic`、`public.webp` 或 `dyn.xxx`，会退化到 `types.first`（可能取到非图片类型）。

建议：改用 `UTType.conforms(to:)` 做一致性判断：

```swift
private func preferredUTI(forImage types: [NSPasteboard.PasteboardType]) -> String? {
    // 优先取真正的图片子类，而非死磕 png/tiff
    let imageTypes = types.compactMap { UTType($0.rawValue) }
        .first { $0.conforms(to: .image) }?.identifier
    return imageTypes ?? types.first?.rawValue
}
```

同理，文件/链接也可用 `conforms(to: .fileURL)` / `conforms(to: .url)` 判断，比字符串匹配稳健得多。

#### #3 图片统一转 TIFF 存储，原始格式仅 `utiData` 保留（中/低）
`makeItem()` 里图片分支用 `image.tiffRepresentation` 作为 `imageData`（用于预览/落盘），而 `utiData` 单独存原始 PNG/JPEG 数据。结果是：**历史里存的是 TIFF，粘贴写回的是原始格式**——预览与落盘都丢了原始格式信息，且 TIFF 体积大、HEIC/WebP 等无法被 `NSImage` 无损转回。

建议：优先用粘贴板上**原始格式**的 `Data` 作为 `imageData`（按 §4.3 #2 选出的图片 UTI 直接 `pasteboard.data(forType:)`），仅当取不到时才回退 `tiffRepresentation`；预览层再做缩略图降采样。这样历史文件更小、格式更真。

#### #4 弃用的 `NSFilenamesPboardType`（低）
`preferredUTI(forFiles:)` 仍以 `"NSFilenamesPboardType"` 作为首选 UTI 标签。该类型 10.6 起废弃，现代应直接用 `.fileURL` + `readObjects(forClasses:[NSURL.self], options:[.urlReadingFileURLsOnly:true])`（代码已经这么读了，只是「首选 UTI 标签」还写着旧名）。建议首选标签改为 `public.file-url`。

#### #5 `dyn.` 动态 UTI 未解码（低，调试体验）
DEBUG 日志里出现 `dyn.xxx` 时无法直接看出原始类型。建议在 DEBUG 打印里调用 §1.7 的解码逻辑，输出 `preferredFilenameExtension` / `preferredMIMEType`，便于排查。

#### #6 Universal Clipboard 远程标记（低）
未处理 `com.apple.is-remote-clipboard`。可选：识别后给卡片标注「来自其他设备」，并在来源推断不准时作为提示。

#### #7 多 item 粘贴板的完整处理（低）
`types` 只反映第一个 item。当前逻辑用 `readObjects` 读全部文件 URL是对的，但 `availableTypes` 过滤后再做「文件/链接/图片/文本」的 if-else 分支，**只会处理第一个匹配的分支**（即一次拷贝如果同时含文件和文本，只会归为文件类）。这符合多数场景，但若想支持「一次拷贝多类」需改为多 Clip 或复合 Clip。当前实现可接受，仅记录。

---

## 5. 实践速查表

### 5.1 常用 UTI ↔ PasteboardType 对照

| 语义 | UTI（PasteboardType 字符串） | AppKit 常量 |
|------|------------------------------|-------------|
| 纯文本（UTF-8） | `public.utf8-plain-text` | `.string` |
| 纯文本（UTF-16） | `public.utf16-plain-text` | — |
| 富文本 RTF | `public.rtf` | `.rtf` |
| 带附件 RTFD | `com.apple.flat-rtfd` | `.rtfd` |
| HTML | `public.html` | `.html` |
| PDF | `com.adobe.pdf` | `.pdf` |
| PNG | `public.png` | `.png` |
| TIFF | `public.tiff` | `.tiff` |
| JPEG | `public.jpeg` | — |
| 文件 URL | `public.file-url` | `.fileURL` |
| 任意 URL | `public.url` | `.URL` |
| 颜色 | `com.apple.icns`/… | `.color` |
| 文件名数组（弃用） | `NSFilenamesPboardType` | — |
| 文件承诺（弃用） | `NSFilesPromisePboardType` | — |

### 5.2 常用 UTType 一致性判断

```swift
UTType.png.conforms(to: .image)         // true
UTType.html.conforms(to: .text)         // true
UTType.rtfd.conforms(to: .rtf)          // true
UTType("public.jpeg")?.conforms(to: .image) // true
```

### 5.3 类型转换片段（macOS 11+）

```swift
// 扩展名 → MIME
UTType(filenameExtension: "heic")?.preferredMIMEType   // "image/heic"
// MIME → UTI → 是否图片
UTType(mimeType: "image/png")?.conforms(to: .image)    // true
// 任意字符串能否当成 UTI 解析
if let t = UTType("dyn.ah62...") { t.preferredFilenameExtension }
```

---

## 6. 参考来源

- Apple — Uniform Type Identifiers 框架文档（UTType / UTTagClass）
  https://developer.apple.com/documentation/uniformtypeidentifiers
- Apple — NSPasteboard 类参考
  https://developer.apple.com/documentation/appkit/nspasteboard
- Apple — NSPasteboard.PasteboardType
  https://developer.apple.com/documentation/appkit/nspasteboard/pasteboardtype
- Apple — Pasteboard Programming Guide（类型常量对照表）
  https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/PasteboardGuide106/
- Apple — Understanding UTIs（声明 / 一致性 / 动态 UTI）
  https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/understanding_utis/
- nspasteboard.org（社区约定的 ConcealedType / TransientType / source 等）
  http://www.nspasteboard.org/
- 动态 UTI 解码原理（base-32 编码与对照表）
  https://www.macscripter.net/t/native-applescript-decoder-for-dynamic-uniform-type-identifiers/70958
- UTI 标签转换（UTTypeCreatePreferredIdentifierForTag）
  https://robinthrift.com/posts/swift-detect-mime-and-filetype/
- Mozilla Bug 1801880（ConcealedType 在密码管理器中的实践与缺失案例）
  https://bugzilla.mozilla.org/show_bug.cgi?id=1801880
- EasyPaste 源码：`Services/ClipboardService.swift`、`Models/Clip.swift`、`Stores/ClipboardStore.swift`、`Models/AppSettings.swift`、`Services/PanelController.swift`

---

## 7. 一句话结论

UTI 是 macOS 描述「数据是什么」的统一语言，粘贴板是「多 App 间搬运多格式数据」的共享总线；**剪贴板管理器的全部正确性都建立在「用 UTI 一致性而非字符串匹配来识别类型」「保存并保真写回全部表示」「尊重 `org.nspasteboard.ConcealedType` 等安全标记」这三件事上**。EasyPaste 已覆盖前两点的大半，但**第 3 点（ConcealedType 隐私处理）是当前最该补的缺口**，其次是把类型选择从字符串匹配升级为 `UTType.conforms(to:)` 一致性判断。
