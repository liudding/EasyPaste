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
