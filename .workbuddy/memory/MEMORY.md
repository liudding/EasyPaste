# EasyPaste 项目长期备忘

## 构建
- SwiftPM 可执行 target，源码直接在仓库根目录（App/Models/Stores/Services/Views），`Package.swift` 用 `sources:` 指定。
- 打包：`script/build_and_run.sh`（build → dist/EasyPaste.app → ad-hoc codesign → open）。
- **WorkBuddy 沙箱内必须加 `--disable-sandbox`**（swift build/test/show-bin-path），否则 SwiftPM 嵌套 sandbox-exec 会 posix_spawn "Operation not permitted"。脚本本身未加，必要时手动分步执行。
- ad-hoc 签名（`codesign --sign -`）每次重打包 cdhash 变化 → macOS 辅助功能(TCC)授权身份失效，需提醒用户重新授权。
- **swift build/test 卡死、build.db 膨胀到 GB 级**：根因曾是 `dist/dmg_staging/Applications -> /Applications` 符号链接残留（中断的 DMG 构建留下），`swift test` 的 llbuild 目录扫描跟随它索引整个 /Applications（54 万文件）。已根治：create_dmg.sh staging 改用包外 mktemp + trap 清理。**包根目录下（含 dist/）绝不能放指向大目录的符号链接**；再遇卡死先查包内符号链接和 build.db 大小。

## 架构要点
- **clip list 按需滚动**（PanelView `scrollSelectedClipIntoView`）：Preference 采集卡片 frame 到**非观察** `ClipFrameStore`（绝不能放 @State——滚动中逐帧更新会把整个面板打入重渲染循环；Lazy 卡片销毁后条目自动从聚合消失，无需失效校验）；完全可见不动，单侧被裁则用 UnitPoint 对齐语义反解 anchor 滚到"刚好可见 + 露出相邻卡 36pt"，位置未知退化为 `scrollTo(id)`（anchor nil = 最小滚动）。
- **图片卡片性能**：列表缩略图走 `ImageSizeCache.thumbnail(for:)`（@Observable，未命中后台 ImageIO 340px 降采样再触发刷新），全尺寸图只给预览浮层；尺寸描述读 CGImageSource 元数据不解码。面板 onAppear 用 `AppIconCache.warm` 后台预热图标。
- 跨应用粘贴在 `ClipboardService.paste`：目标解析（前台非本 app 优先，否则 `AppDelegate.invokingApplication`）→ hide + activate → 轮询前台 → hidSystemState + cghidEventTap 发 ⌘V。不要用 `postToPid`（不可靠）。
- 全局快捷键：Carbon RegisterEventHotKey（⌘⇧V）在 `GlobalShortcutService`。
- 权限：辅助功能未授权时绝不静默失败——系统提示 + NSAlert 引导去设置。
- **设置窗口打开**：PanelView 在独立 NSHostingView 中，无法直接访问 `@Environment(\.openSettings)`。通过 `SettingsActionCapture` 视图在场景层次（MenuBarExtra/Settings scene）内捕获 openSettings 动作，存入 `AppServices.openSettingsAction` 传给 PanelController。`sendAction(Selector(("showSettingsWindow:")))` 在 macOS 15 上不可靠，仅作兜底。打开设置时需等面板隐藏动画完成（0.2s 延迟），否则 `.floating` 层级面板会遮挡设置窗口。

## Onboarding 引导
- `AppSettings.hasCompletedOnboarding` 控制是否展示（Snapshot 持久化，`decodeIfPresent` 兼容旧存档）。
- 6 页引导（欢迎/自动捕获/一键唤起/智能整理/搜索与预览/准备就绪），`OnboardingView` + `OnboardingWindowController`。
- macOS 不支持 `.page(indexDisplayMode:)`，用手动 ZStack + `@State direction` + `.move(edge:)` transition 实现页面滑动。
