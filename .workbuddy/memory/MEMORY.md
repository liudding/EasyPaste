# EasyPaste 项目长期备忘

## 构建
- SwiftPM 可执行 target，源码直接在仓库根目录（App/Models/Stores/Services/Views），`Package.swift` 用 `sources:` 指定。
- 打包：`script/build_and_run.sh`（build → dist/EasyPaste.app → ad-hoc codesign → open）。
- **WorkBuddy 沙箱内必须加 `--disable-sandbox`**（swift build/test/show-bin-path），否则 SwiftPM 嵌套 sandbox-exec 会 posix_spawn "Operation not permitted"。脚本本身未加，必要时手动分步执行。
- **双构建体系（SwiftPM + 遗留 Xcode）**：仓库同时有 `Package.swift`（SwiftPM，真实构建路径，`script/build_and_run.sh` 用 `swift build`）和 `EasyPaste.xcodeproj`（Xcode 编辑/分发构建用）。**.xcodeproj 绝不能把 `Package.swift` 列入 Compile Sources**——manifest 当普通源文件编译会报 `Package.swift:2:8 No such module 'PackageDescription'`；Xcode 已用自带 SPM 包引用 + 源文件引用，不需要 manifest。
- **GRDB 版本已对齐 7.11.1**（commit `b83108d`）：Package.swift 用 `.exact`，.xcodeproj 用 `exactVersion`，`.xcodeproj/.../Package.resolved` 用同 commit 的 version 条目 → 两条构建路径解出的 GRDB 完全一致，无漂移。Xcode 可原生 `open Package.swift`（无需 .xcodeproj）做开发/编辑，但 Xcode 内 Run 不会套 `EasyPaste.entitlements`（辅助功能授权缺失），实际运行仍走 `build_and_run.sh`（脚本打包+签名）。
- **决策（2026-07-24）：保留双构建体系，不收敛到 Package.swift-only**。理由：GRDB 已对齐无漂移风险，且 .xcodeproj 保留 Xcode 一键分发签名 + 可视化 entitlement 编辑更顺。同日用户指令「把 Xcode Project 的孤儿全部清掉」：已移除 `.xcodeproj` 中全部孤儿——`swift-algorithms`+`swift-numerics`（`Package.resolved` 仅留 `grdb.swift`）、冗余 `GRDB-dynamic` 框架链接、以及 `OnboardingView.swift` 的重复 PBXFileReference（App target 曾双编译）。清理后 pbxproj `plutil -lint` OK，resolved JSON 合法。
- **手动编辑 Package.resolved 的坑**：`project.xcworkspace/xcshareddata/swiftpm/Package.resolved`（Xcode SPM 解析缓存，v3 含 `originHash`）一旦手改 pins（删孤儿依赖等），旧 `originHash`（按旧包图算）与新包图不符 → Xcode 拒绝信任解析、报 `Missing package product 'GRDB'`。修复：删掉 `originHash` 这一行让 Xcode 重算/重新解析（pins 本身正确时 Xcode 直接采信并复用已克隆的包，无需联网）。此文件与仓库根 `Package.swift` 的 SwiftPM `Package.resolved` 是两套、互不影响。
- ad-hoc 签名（`codesign --sign -`）无身份，cdhash 每次编译都变 → TCC 辅助功能授权必失效，每版需重授。
- **签名自动检测已实现**（build_and_run.sh）：依次选 Developer ID Application > Apple Development > Mac Developer，都没有才退回 ad-hoc；Sparkle 嵌套组件用同一身份重签（否则 library validation 拒绝加载）。用户现有免费 `Apple Development: Ding Liu (JV4FM5Z2PZ)`（Team ID EEGY7XHC46）→ 开发构建身份稳定，辅助功能授权不再每次重授（仅**首次**换身份需重授一次）；但 Gatekeeper 不信任、不能分发给他人。正式分发仍须付费 Developer ID + 公证。
- **swift build/test 卡死、build.db 膨胀到 GB 级**：根因曾是 `dist/dmg_staging/Applications -> /Applications` 符号链接残留（中断的 DMG 构建留下），`swift test` 的 llbuild 目录扫描跟随它索引整个 /Applications（54 万文件）。已根治：create_dmg.sh staging 改用包外 mktemp + trap 清理。**包根目录下（含 dist/）绝不能放指向大目录的符号链接**；再遇卡死先查包内符号链接和 build.db 大小。

## 架构要点
- **clip list 按需滚动**（PanelView `scrollSelectedClipIntoView`）：Preference 采集卡片 frame 到**非观察** `ClipFrameStore`（绝不能放 @State——滚动中逐帧更新会把整个面板打入重渲染循环；Lazy 卡片销毁后条目自动从聚合消失，无需失效校验）；完全可见不动，单侧被裁则用 UnitPoint 对齐语义反解 anchor 滚到"刚好可见 + 露出相邻卡 36pt"，位置未知退化为 `scrollTo(id)`（anchor nil = 最小滚动）。
- **图片卡片性能**：列表缩略图走 `ImageSizeCache.thumbnail(for:)`（@Observable，未命中后台 ImageIO 340px 降采样再触发刷新），全尺寸图只给预览浮层；尺寸描述读 CGImageSource 元数据不解码。面板 onAppear 用 `AppIconCache.warm` 后台预热图标。
- 跨应用粘贴在 `ClipboardService.paste`：目标解析（前台非本 app 优先，否则 `AppDelegate.invokingApplication`）→ hide + activate → 轮询前台 → hidSystemState + cghidEventTap 发 ⌘V。不要用 `postToPid`（不可靠）。
- **`ClipboardStore.filteredItems` 禁止做"命中即跳过读源"的缓存**：曾被手动缓存（`@ObservationIgnored` 的 `_filteredCache`）导致命中时 getter 不读 `items`，SwiftUI 丢失对 `items` 的 Observation 依赖 → 增删剪贴项偶发不刷新（需点其他 item 才刷新）。已改为每次直接 `items.filter{...}`。任何被 SwiftUI 直接读取的派生属性若要缓存，必须保证每次读取仍触碰被观察的源属性。
- 全局快捷键：Carbon RegisterEventHotKey（⌘⇧V）在 `GlobalShortcutService`。
- 权限：辅助功能未授权时绝不静默失败——系统提示 + NSAlert 引导去设置。
- **看板拖拽重排终版（2026-07-25）：DragGesture 手势驱动，不走任何 pasteboard/落点**。教训：① SwiftUI `.onDrop(of:)` 的 `hasItemsConforming` 对自研 UTI 校验静默失败、回调从不触发（clip 拖放走 AppKit `BoardChipDropZone` 原始字符串匹配所以正常）；② 即便改用 AppKit 落点让"拖到芯片左/右半"能跑，交互本质仍是"把 chip 投进另一个 chip"，用户明确否决——列表级排序的正解是手势：`DragGesture(minimumDistance: 4)` 放在 `.onTapGesture` 之后（点击选中不受影响）；拖动中被拖芯片变 0.25 半透明占位，HStack `.overlay(topLeading)` 里的 `BoardChipLabel` 克隆层（scale 1.06 + shadow）以 `dragStartFrame.minX + translation` 跟随手指；插入位 = 被拖中心越过其他芯片 midX 的个数（gap，移除自身后的下标）→ `store.moveBoardToGap`（带弹簧动画、有变化才赋值）；松手 `persistBoardOrder` 一次。**防抖三件套（必备，缺了就抖）**：① 拖拽期间冻结各芯片宽度 `frozenChipWidths`，插入位用「当前顺序 + 冻结宽度」推导静止槽位中点——绝不能用让位动画中 GeometryReader 上报的插值 frame 算中点（中心相对滑动中的中点会反复翻转）；② 克隆层/锚点状态更新包 `withTransaction(disablesAnimations)`，否则与 boards 弹簧同事务合并、克隆层 lag 偏离鼠标；③ 占位是虚线"间隙"胶囊（`.opacity(0)` + dashed Capsule background），不做成与克隆层同款的半透明复制体（同款会被误认为芯片从鼠标位置飘走）。芯片 frame 走 `BoardFrameKey` preference 采到 @State（拖拽期间闸停更新：松手才恢复）；`dragBaseMinX` 用最左槽位 minX 作推导基准（重排不变量）。`UTType.easypasteBoard` 及 Info.plist 声明已随该方案移除（无用即删）。
- **设置窗口打开（2026-07-25 三刀，终版稳定）**：真正根因——**Apple 在 macOS 14 (Sonoma) 移除了 `showSettingsWindow:` 选择器**，所以任何 `sendAction(Selector("showSettingsWindow:"))` / 主菜单遍历该 action 的兜底都是**死代码**，永远打不开设置；而唯一可靠的 `openSettings` 环境动作由 `SettingsActionCapture.onAppear` **懒捕获**，只在该视图挂载后（即用户点开过菜单栏菜单或设置窗口）才非空——只用 ⌘⇧V 唤起面板、从没开过菜单/设置的用户，`openSettingsAction` 恒为 nil，于是「捕获动作 no-op + 死兜底」双双失效 → 设置永久打不开。前两次修复（修遮挡 0.2s 时序、去掉 early-return 并延迟 sendAction）都没用，因为根因在选择器已被移除、不在时序。
  - **终版方案（彻底绕开 SwiftUI Settings 场景）**：删除 `Settings { }` 场景、`SettingsActionCapture`、`openSettingsAction` 及所有 `showSettingsWindow:` 兜底；改为在 `AppServices` 用 AppKit 直接托管 `SettingsView` 于自有 `NSWindowController`（`openSettingsWindow()`：`setActivationPolicy(.regular)` → `activate` → 复用或新建 `NSWindow(NSHostingController(rootView: SettingsView(...)))`，标题"设置"，`isReleasedWhenClosed=false`），面板按钮与菜单栏都走它。面板侧：`PanelController.openSettingsFromPanel()` 仅做 `forceHidePanel()`（立即 orderOut 移除 `.floating` 面板防遮挡）+ `activate` + 调注入的 `openSettingsHandler`（→ `AppServices.openSettingsWindow()`）。菜单栏 `MenuBarView` 用 `Button("设置…") { onOpenSettings() }` 取代 `SettingsLink`（后者依赖已删的 Settings 场景）。
  - 改动文件：`App/EasyPasteApp.swift`（删 Settings 场景/捕获体、加 `settingsWC`+`openSettingsWindow()`、boot 注入 `openSettingsHandler`）、`Services/PanelController.swift`（`openSettings`→`openSettingsHandler`、简化 `openSettingsFromPanel`）、`Views/MenuBarView.swift`（加 `onOpenSettings` 参数、换 Button）。`forceHidePanel`/`paste()`/状态机未动。
  - ⚠️ **教训**：macOS 菜单栏/无主窗口 App 从 AppKit 面板打开 SwiftUI `Settings` 场景不可靠——优先用自己托管的 NSWindow 呈现 `SettingsView`，别依赖 `openSettings`/`SettingsLink`/`showSettingsWindow:`。
  - QA：build 干净 + 11 项持久层测试全绿。

## Onboarding 引导
- `AppSettings.hasCompletedOnboarding` 控制是否展示（Snapshot 持久化，`decodeIfPresent` 兼容旧存档）。
- 6 页引导（欢迎/自动捕获/一键唤起/智能整理/搜索与预览/准备就绪），`OnboardingView` + `OnboardingWindowController`。
- macOS 不支持 `.page(indexDisplayMode:)`，用手动 ZStack + `@State direction` + `.move(edge:)` transition 实现页面滑动。

## 性能：首次唤起面板冷启动预热（2026-07-25）
- **冷启动延迟主因 = AppIconCache 冷缓存**：`ClipCardView.sourceAppIconImage` 渲染时同步读 `AppIconCache.icon(forBundleID:displaySize:)`，冷缓存下每卡做 LaunchServices `urlForApplication` + icon 解码 + TIFF 像素采样 + lockFocus 缩放；旧数据无 `sourceAppColor` 时 `headerColor` 还经 `sourceAppDominantColor` 再触发一遍。`PanelView.onAppear` 的 `warm()` 在首次渲染**之后**才触发，救不了首次渲染。
- **修复**：① `AppServices.boot()` 加载完 store 后用 `store.items.compactMap(\.sourceApplicationBundleID)` 在后台队列 `AppIconCache.shared.warm(...)`（warm 内部 dispatch .utility，非阻塞）→ 首次渲染即命中字典缓存；② `PanelController.prewarm()`：`makePanel()` + 离屏真实尺寸 frame + `contentView.layoutSubtreeIfNeeded()` 提前编译 `.ultraThinMaterial` 着色器/构建视图图，`boot()` 里 `DispatchQueue.main.async` 调用。预建面板不 `orderFront` → `isVisible` 仍 false，`windowDidResignKey` 只对曾成为 key 的窗口触发，无误触自动隐藏。
- **教训**：SwiftUI `onAppear` 在首次渲染之后才触发，不能用来预热首次渲染——重计算/缓存预热必须提前到 `boot()` 或更早。
