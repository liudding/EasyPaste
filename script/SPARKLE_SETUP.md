# EasyPaste 更新设置指南（Sparkle）

## 快速开始

### 1. 在 Xcode 中添加 Sparkle 依赖

1. 用 Xcode 打开 `EasyPaste.xcodeproj`
2. **File → Add Packages…**
3. 输入：`https://github.com/sparkle-project/Sparkle`
4. 选择版本：**Version 2.8.1**（或最新稳定版）
5. 点击 **Add Package**

### 2. 生成 EdDSA 密钥对

从 Sparkle 发行版中提取签名工具：

```bash
# 方式 A：如果 SPM 已拉取 Sparkle
SPARKLE_DIR="$HOME/Library/Developer/Xcode/DerivedData/**/Build/Products/Debug/Sparkle.framework"
# 实际路径因项目而异，在 Finder 中右键 Sparkle package → Show in Finder

# 方式 B：手动下载 Sparkle 发行版
curl -L https://github.com/sparkle-project/Sparkle/releases/latest/download/Sparkle.tar.xz | tar xz

# 运行密钥生成工具
./Sparkle*/bin/generate_keys
```

输出类似：
```
A key has been generated and saved in your login keychain.

SUPublicEDKey = pfIShU4dEXqPd5ObYNfDBiQWcXozk7estwzTnF9BamQ=
```

将公钥填入 `Info.plist`：

```xml
<key>SUPublicEDKey</key>
<string>pfIShU4dEXqPd5ObYNfDBiQWcXozk7estwzTnF9BamQ=</string>
```

### 3. 配置更新源

Sparkle 支持多种更新源。选择一个部署 appcast.xml 的端点：

#### 方案 A：GitHub Releases + GitHub Pages（推荐）

1. 在仓库中创建一个 `gh-pages` 分支
2. 将 `appcast.xml` 放在该分支根目录
3. 填入 `SUFeedURL`：

```xml
<key>SUFeedURL</key>
<string>https://your-username.github.io/easypaste/appcast.xml</string>
```

#### 方案 B：自定义 JSON 端点

如果你的源提供标准 JSON（如 `update.json`），需要转换为 Sparkle 的 appcast.xml 格式。

#### 方案 C：S3 / OSS / R2 等对象存储

将 `appcast.xml` 和 `.dmg` 上传到任意 HTTP 可访问的位置：

```xml
<key>SUFeedURL</key>
<string>https://your-bucket.s3.amazonaws.com/easypaste/appcast.xml</string>
```

### 4. 生成 appcast.xml

使用 Sparkle 的 `generate_appcast` 工具：

```bash
# 准备一个存放所有历史 DMG 的文件夹
mkdir -p ~/easypaste-updates

# 把当前版本的 DMG 放进去
cp dist/EasyPasteInstaller.dmg ~/easypaste-updates/

# 运行 generate_appcast（需要密钥链访问权限）
./Sparkle*/bin/generate_appcast ~/easypaste-updates/
```

这会生成：
- `appcast.xml` — 更新清单
- `EasyPasteInstaller-1.0.0.delta` — 二进制增量更新（可选）

上传 `appcast.xml` 和 `.dmg` 到你的更新源服务器。

### 5. 代码签名与公证

```bash
# 签名（生产环境用 Developer ID）
codesign --force --sign "Developer ID Application: Your Name" \
    --deep --timestamp --options runtime \
    dist/EasyPaste.app

# 公证
xcrun notarytool submit dist/EasyPasteInstaller.dmg \
    --apple-id "your@appleid.com" \
    --password "@env:NOTARY_PASSWORD" \
    --team-id "YOUR_TEAM_ID" \
    --wait
```

## 文件结构

```
EasyPaste/
├── EasyPaste.xcodeproj/          ← Xcode 项目（含 Sparkle SPM 集成）
├── Info.plist                    ← SUFeedURL、SUPublicEDKey 配置
├── App/
│   └── EasyPasteApp.swift        ← AppDelegate 初始化 SparkleBridge
├── Services/
│   ├── SparkleBridge.swift       ← SPUStandardUpdaterController 桥接
│   └── ...
├── Views/
│   ├── MenuBarView.swift         ← "检查更新…" 菜单项
│   └── ...
├── script/
│   ├── build_and_run.sh          ← SPM 开发构建
│   └── create_dmg.sh             ← DMG 打包
└── Package.swift                 ← SPM manifest（不含 Sparkle）
```

## 注意事项

### ad-hoc 签名的限制

- **开发阶段**：ad-hoc 签名（`--sign -`）可以正常工作，Sparkle 会尝试检查但不会提示用户安装
- **分发阶段**：必须使用 **Developer ID Application** 签名 + **公证**，否则 Sparkle 无法静默替换应用
- **Library Validation**：启用 Hardened Runtime 时，ad-hoc 签名会导致 Sparkle.framework 加载失败。开发阶段可临时关闭 Library Validation

### 首次启动行为

Sparkle 默认在**第二次启动**时才弹出更新提示（避免首次打开就打扰用户）。测试时可以清除上次检查时间：

```bash
defaults delete com.easypaste.app SULastCheckTime
```

### 测试更新

1. 将当前版本的 `CFBundleVersion` 临时改为较小值（如 `0`）
2. 确保 appcast.xml 中有更高版本的条目
3. 重启应用，菜单栏会出现 "检查更新…" 选项

## 参考文档

- [Sparkle 官方文档](https://sparkle-project.org/documentation/)
- [程序化设置](https://sparkle-project.org/documentation/programmatic-setup/)
- [SwiftUI 集成示例](https://amore.computer/help/sparkle/)
