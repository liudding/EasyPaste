# EasyPaste 项目长期备忘

## 构建
- SwiftPM 可执行 target，源码在仓库根目录（App/Models/Stores/Services/Views），`Package.swift` 用 `sources:` 指定。打包走 `script/build_and_run.sh`（build → dist/EasyPaste.app → codesign → open）。
- **WorkBuddy 沙箱内 swift build/test/show-bin-path 必须加 `--disable-sandbox`**，否则 SwiftPM 嵌套 sandbox-exec 报 posix_spawn "Operation not permitted"。
- **双构建体系（SwiftPM + Xcode）**：`Package.swift`（真实构建）+ `EasyPaste.xcodeproj`（编辑/分发）。决策：保留双体系（2026-07-24）。**.xcodeproj 绝不能把 `Package.swift` 列入 Compile Sources**（会报 `No such module 'PackageDescription'`）。
- **GRDB 7.11.1 已对齐**（commit `b83108d`）：Package.swift 用 `.exact`，.xcodeproj 用 `exactVersion`，Package.resolved 同 commit → 两条构建路径无漂移。
- **手动改 Package.resolved 的坑**：Xcode 的 `project.xcworkspace/.../Package.resolved`（v3 含 `originHash`）手改 pins 后，旧 `originHash` 与新包图不符 → Xcode 报 `Missing package product`。修：删 `originHash` 行让 Xcode 重算。
- **签名**：`build_and_run.sh` 自动选 Developer ID Application > Apple Development > Mac Developer，都没有才 ad-hoc。用户有免费 `Apple Development: Ding Liu (JV4FM5Z2PZ)`（Team EEGY7XHC46）→ 开发构建身份稳定，辅助功能授权仅首次换身份重授一次。ad-hoc 签名 cdhash 每次变 → TCC 授权必失效。正式分发需付费 Developer ID + 公证。
- **swift build 卡死/build.db 膨胀**：曾因 `dist/dmg_staging/Applications -> /Applications` 符号链接，llbuild 跟随索引整个 /Applications。已根治（create_dmg.sh 用包外 mktemp）。**包根目录下绝不能放指向大目录的符号链接**。

## 架构要点
- **clip list 按需滚动**（`PanelView.scrollSelectedClipIntoView`）：卡片 frame 采到**非观察** `ClipFrameStore`（绝不能放 @State，否则滚动逐帧更新把整个面板打入重渲染循环）。位置未知退化为 `scrollTo(id)`（anchor nil = 最小滚动）。
- **图片卡片性能**：缩略图走 `ImageSizeCache.thumbnail(for:)`（未命中后台 ImageIO 340px 降采样），全尺寸图只给预览浮层。
- 跨应用粘贴 `ClipboardService.paste`：目标解析 → hide+activate → 轮询前台 → cghidEventTap 发 ⌘V。**不要用 `postToPid`**（不可靠）。
- **`ClipboardStore.filteredItems` 禁止"命中即跳过读源"缓存**：曾因 `@ObservationIgnored` 缓存导致 SwiftUI 丢失对 `items` 的 Observation 依赖 → 增删偶发不刷新。任何被 SwiftUI 直接读取的派生属性若要缓存，必须保证每次读取仍触碰被观察源属性。
- 全局快捷键：Carbon RegisterEventHotKey（⌘⇧V）在 `GlobalShortcutService`。权限：辅助功能未授权绝不静默失败。
- **看板拖拽重排（2026-07-25）**：DragGesture 手势驱动，不走 pasteboard/落点。`DragGesture(minimumDistance: 4)` 放 `.onTapGesture` 之后。拖动中芯片 0.25 半透明占位，克隆层（scale 1.06+shadow）以 `dragStartFrame.minX + translation` 跟随手指；插入位 = 中心越过其他芯片 midX 的个数 → `store.moveBoardToGap`。**防抖三件套（缺了就抖）**：① 拖拽期间冻结芯片宽度 `frozenChipWidths`；② 克隆层状态更新包 `withTransaction(disablesAnimations)`；③ 占位用虚线间隙胶囊（`.opacity(0)`+dashed Capsule），不做成与克隆层同款复制体。
- **设置窗口（2026-07-25 终版）**：**macOS 14 移除了 `showSettingsWindow:` 选择器**，`openSettings` 环境动作需场景内懒捕获、对只用快捷键的用户恒 nil → 设置永久打不开。**终版方案**：删除 SwiftUI `Settings { }` 场景，在 `AppServices` 用 AppKit 直接托管 `SettingsView` 于 `NSWindowController`（`openSettingsWindow()`）。面板/菜单栏都走它。**教训**：macOS 菜单栏/无主窗口 App 打开设置，优先用自托管 NSWindow 呈现 `SettingsView`，别依赖 `openSettings`/`SettingsLink`/`showSettingsWindow:`。
  - **布局（2026-07-25）**：`SettingsView` 用 `NavigationSplitView`（sidebar `.listStyle(.sidebar)` + detail），非 `TabView`。透明标题栏配方（无单一 SwiftUI 修饰符，须 NSWindow 层）：`styleMask` 加 `.fullSizeContentView` + `titlebarAppearsTransparent=true` + `titleVisibility=.hidden` + `isMovableByWindowBackground=true`（**保留 `.titled`** 否则无交通灯）。sidebar List 与 detail 各加 `.safeAreaInset(.top, Color.clear.frame(height: 28))` 让出按钮空间（标准 titled 窗口无 toolbar 时标题栏 28pt；交通灯底 ≈20.5）。sidebar 毛玻璃延伸到顶 → 交通灯浮于其上（无缝）。sidebar 宽度 `.navigationSplitViewColumnWidth(min:200,ideal:220,max:260)`。

## Onboarding
- `AppSettings.hasCompletedOnboarding` 控制（Snapshot 持久化，`decodeIfPresent` 兼容旧存档）。6 页引导，`OnboardingView`+`OnboardingWindowController`。用手动 ZStack+`@State direction`+`.move(edge:)`（macOS 不支持 `.page(indexDisplayMode:)`）。

## 性能：冷启动预热（2026-07-25）
- **冷启动延迟主因 = AppIconCache 冷缓存**：`ClipCardView.sourceAppIconImage` 渲染时同步读 `AppIconCache.icon`，冷缓存下每卡做 LaunchServices+解码+采样，8~10 张累加成大延迟。`PanelView.onAppear` 的 warm 在首次渲染之后才触发，救不了首次渲染。
- **修复**：`AppServices.boot()` 加载 store 后后台 `AppIconCache.shared.warm(bundleIDs:)`；`PanelController.prewarm()`：离屏 makePanel + layoutSubtreeIfNeeded 提前编译 `.ultraThinMaterial` 着色器。**教训**：SwiftUI `onAppear` 在首次渲染之后才触发，重计算预热必须提前到 `boot()` 或更早。

## 多语言本地化（2026-07-25）
- **`L10nStore`**（`@Observable`，`@unchecked Sendable`，**不能 @MainActor**——`L10n.tr()` 被任意上下文调用）：`version: UInt` 计数器驱动无重启切换。`L10n.tr(_:)` 查找链：当前语言 JSON → 英语兜底 → key。
- **视图订阅**：每个用 `L10n.xxx` 的 SwiftUI 视图必须 body 直接读 `version`（`@State private var l10nStore = L10nStore.shared` + `let _ = l10nStore.version`）。**绝不能用 ViewModifier 间接观察**——modifier 的 `body(content:)` 只让包装层重渲染，SwiftUI structural identity 优化会跳过 content。
- JSON 资源 `L10n/` 目录 10 文件（en,zh-Hans,zh-Hant,ja,ko,fr,es,pt,ru,de），各 168 键。SwiftPM `.copy("L10n")`。运行时多路径搜索 Bundle.main/Bundle.module。`Locale` 枚举 11 种（含 followSystem）。
- 设置页语言选择器 `.pickerStyle(.menu)`，`onChange` 写 `L10nStore.shared.locale`。
