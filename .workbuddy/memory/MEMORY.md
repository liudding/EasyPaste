# EasyPaste 项目长期备忘

## 构建
- SwiftPM 可执行 target，源码直接在仓库根目录（App/Models/Stores/Services/Views），`Package.swift` 用 `sources:` 指定。
- 打包：`script/build_and_run.sh`（build → dist/EasyPaste.app → ad-hoc codesign → open）。
- **WorkBuddy 沙箱内必须加 `--disable-sandbox`**（swift build/test/show-bin-path），否则 SwiftPM 嵌套 sandbox-exec 会 posix_spawn "Operation not permitted"。脚本本身未加，必要时手动分步执行。
- ad-hoc 签名（`codesign --sign -`）每次重打包 cdhash 变化 → macOS 辅助功能(TCC)授权身份失效，需提醒用户重新授权。

## 架构要点
- 跨应用粘贴在 `ClipboardService.paste`：目标解析（前台非本 app 优先，否则 `AppDelegate.invokingApplication`）→ hide + activate → 轮询前台 → hidSystemState + cghidEventTap 发 ⌘V。不要用 `postToPid`（不可靠）。
- 全局快捷键：Carbon RegisterEventHotKey（⌘⇧V）在 `GlobalShortcutService`。
- 权限：辅助功能未授权时绝不静默失败——系统提示 + NSAlert 引导去设置。
- **设置窗口打开**：PanelView 在独立 NSHostingView 中，无法直接访问 `@Environment(\.openSettings)`。通过 `SettingsActionCapture` 视图在场景层次（MenuBarExtra/Settings scene）内捕获 openSettings 动作，存入 `AppServices.openSettingsAction` 传给 PanelController。`sendAction(Selector(("showSettingsWindow:")))` 在 macOS 15 上不可靠，仅作兜底。打开设置时需等面板隐藏动画完成（0.2s 延迟），否则 `.floating` 层级面板会遮挡设置窗口。

## Onboarding 引导
- `AppSettings.hasCompletedOnboarding` 控制是否展示（Snapshot 持久化，`decodeIfPresent` 兼容旧存档）。
- 6 页引导（欢迎/自动捕获/一键唤起/智能整理/搜索与预览/准备就绪），`OnboardingView` + `OnboardingWindowController`。
- macOS 不支持 `.page(indexDisplayMode:)`，用手动 ZStack + `@State direction` + `.move(edge:)` transition 实现页面滑动。
