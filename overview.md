# EasyPaste 四项功能想法 — 交付概览

> 日期: 2026-07-25 | 团队: software-easypaste-ideas | 工作流: 标准 SOP

## TL;DR
基于 `docs/ideas.md` 的四项功能请求，通过标准 SOP（PRD → 架构 → 工程 → QA）完成全部设计与实现，57 个测试全部通过。

## 交付状态
- **构建**: Build complete! — 0 errors
- **测试**: 57 通过 / 0 失败（2 轮，第1轮自修2个预置测试bug）
- **路由判定**: NoOne（无源码 bug）
- **已知问题**: 0 阻塞；1 非阻塞（`ClipboardStore.clipHash` 死代码，建议后续清理）

## 四项功能

### 1. 启动读取剪贴板
- **问题**: `lastChangeCount` 初始化为当前 `changeCount`，首次 timer tick 不触发读取
- **修复**: `ClipboardService.start()` 中 `lastChangeCount = -1`

### 2. Dock 中隐藏 icon
- **实现**: `AppSettings.hideDockIcon` 设置 + `NSApp.setActivationPolicy(.accessory/.regular)` 切换
- **UI**: 设置页通用区 Toggle；`onDockIconVisibilityChanged` 回调驱动实时切换

### 3. Clip 去重增强
- **哈希**: `ClipTypeDetector.computeContentHash()` — SHA-256 内容哈希（替代旧 `uti:data.count` 弱哈希）
- **去重逻辑**: 重复时 `promoteClip(at:)`（更新 `createdAt` + 移到顶部），而非静默跳过
- **子类型**: `ClipSubkind` 枚举（richText/email/json），检测优先级 richText > json > email > nil
- **迁移**: GRDB migration `v1.0.3-contentHash-subkind`

### 4. 多类型 Context Menu
- **类型分化**: text/richText → 导出txt/rtf/QR；email → 发送邮件；json → 结构化预览；color → 复制hex/rgb/hsl；image → 另存为；link → 打开链接/QR
- **执行器**: `ClipActionService` — QR 用 `CIFilter CIQRCodeGenerator`，导出用 `NSSavePanel`，邮件用 `mailto:`
- **浮层**: `QRCodeView` + `JSONPreviewView` 复用 PanelState overlay 机制

## 文件清单

### 新增文件（5 个）
| 文件 | 说明 |
|------|------|
| `Services/ClipTypeDetector.swift` | 子类型检测 + SHA-256 内容哈希 |
| `Services/ClipActionService.swift` | 类型专属操作执行器 |
| `Views/ClipboardPanel/QRCodeView.swift` | CIFilter 二维码浮层 |
| `Views/ClipboardPanel/JSONPreviewView.swift` | JSON 格式化预览浮层 |
| `Tests/EasyPasteTests/ClipTypeDetectorTests.swift` | 50 个新测试用例 |

### 修改文件（13 个）
| 文件 | 主要变更 |
|------|---------|
| `Models/Clip.swift` | ClipSubkind 枚举 + subkind/contentHash 字段 |
| `Models/AppSettings.swift` | hideDockIcon 设置 + 回调 |
| `Models/PanelState.swift` | qrCodeContent + jsonPreviewItem 浮层状态 |
| `Stores/Database.swift` | migration v1.0.3-contentHash-subkind |
| `Stores/DatabaseModels.swift` | ClipRow 新字段映射 |
| `Stores/ClipboardStore.swift` | SHA-256 去重 + promoteClip |
| `Services/ClipboardService.swift` | lastChangeCount=-1 + ClipTypeDetector 集成 |
| `Views/ClipboardPanel/ClipCardView.swift` | 类型专属 context menu + 10 回调 |
| `Views/ClipboardPanel/PanelView.swift` | QR/JSON 浮层 + 回调注入 |
| `Services/PanelController.swift` | action wiring |
| `App/EasyPasteApp.swift` | Dock 策略 + ClipActionService 集成 |
| `Views/SettingsView.swift` | 隐藏 Dock Toggle |
| `Models/L10n.swift` + `L10n/*.json` | 13 新 key × 10 语言 |

### 交付文档（2 个）
| 文件 | 作者 | 说明 |
|------|------|------|
| `docs/prd-ideas.md` | 许清楚（PM） | 产品需求文档 |
| `docs/architecture-ideas.md` | 高见远（架构师） | 架构设计 + 任务分解 |

## 测试覆盖
| Suite | 用例数 | 覆盖范围 |
|-------|--------|---------|
| ClipTypeDetectorTests | 30 | isRichText/isJSON/isEmail/detect/computeContentHash/computeFallbackHash |
| ClipSubkindTests | 7 | 枚举 rawValue/编解码/兼容性 |
| ClipboardStoreDedupTests | 6 | promoteClip 去重 + DB 持久化 |
| AppSettingsHideDockTests | 6 | hideDockIcon 默认值/回调/Snapshot 兼容 |
| ClipboardServiceStartTests | 1 | lastChangeCount=-1 启动修复 |
| **合计** | **50 新 + 7 既有** | **57 全绿** |

## 用户下一步建议
1. **运行应用**: `bash script/build_and_run.sh` 体验新功能
2. **验证去重**: 复制相同内容两次，确认第二条提升到顶部而非被跳过
3. **验证 Dock 隐藏**: 设置 → 通用 → 勾选"隐藏 Dock 图标"
4. **验证 Context Menu**: 右键不同类型的 clip，查看类型专属菜单项
5. **清理建议**: `ClipboardStore.clipHash` 为死代码，后续可清理
