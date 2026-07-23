# EasyPaste CI/CD 配置清单

## 前置条件

在开始之前，你需要准备以下材料：

### 1. Apple Developer 账号（必需）
- 付费开发者计划（$99/年）
- **Developer ID Application** 证书
- **Apple ID**（用于公证）
- **Team ID**（10 字符，在 developer.apple.com/account 查看）

### 2. 生成 App-Specific Password
1. 访问 https://appleid.apple.com
2. 登录 → Sign-In & Security → App-Specific Passwords
3. 点击 "Generate an app-specific password"
4. 记录生成的密码（格式如 `abcd-efgh-ijkl-mnop`）

### 3. 生成 Sparkle EdDSA 密钥对
```bash
# 方法 A：使用已下载的 Sparkle
curl -L https://github.com/sparkle-project/Sparkle/releases/download/2.8.1/Sparkle.tar.xz | tar xJ
./Sparkle*/bin/generate_keys

# 输出示例：
# A key has been generated and saved in your login keychain.
# SUPublicEDKey = pfIShU4dEXqPd5ObYNfDBiQWcXozk7estwzTnF9BamQ=
```

将**公钥**填入 `Info.plist`：
```xml
<key>SUPublicEDKey</key>
<string>pfIShU4dEXqPd5ObYNfDBiQWcXozk7estwzTnF9BamQ=</string>
```

将**私钥**保存为 GitHub Secret（见下方）。

### 4. 导出 Developer ID 证书
1. 打开 Keychain Access
2. 找到 "Developer ID Application: Your Name (TEAMID)"
3. 右键 → 导出 → 选择 `.p12` 格式
4. 设置密码（可以为空）

Base64 编码：
```bash
base64 -i DeveloperID.p12 > developer_id_base64.txt
cat developer_id_base64.txt  # 复制全部内容
```

---

## GitHub Secrets 配置

进入你的仓库 → **Settings → Secrets and variables → Actions → New repository secret**

添加以下 7 个 Secret：

| Secret 名称 | 值 | 说明 |
|------------|-----|------|
| `DEV_ID_P12_BASE64` | `cat developer_id_base64.txt` 的输出 | Developer ID 证书的 base64 |
| `DEV_ID_P12_PASSWORD` | 导出证书时设置的密码 | 无密码则留空 |
| `APPLE_ID` | `your@appleid.com` | Apple ID 邮箱 |
| `APPLE_APP_PASSWORD` | `abcd-efgh-ijkl-mnop` | App-Specific Password |
| `APPLE_TEAM_ID` | `XXXXXXXXXX` | 10 字符 Team ID |
| `SPARKLE_ED_PRIVATE_KEY` | Sparkle 生成的私钥字符串 | 用于签名 DMG |
| `UPDATES_REPO_SSH_KEY` | SSH 私钥内容 | 推送更新到 updates 仓库 |

---

## 创建 Updates 仓库

创建一个**独立的公开仓库**用于托管 appcast.xml 和 DMG：

```bash
# 在你的电脑上
mkdir easypaste-updates
cd easypaste-updates
git init
echo "# EasyPaste Updates" > README.md
git add .
git commit -m "Initial commit"
git branch -M main
git remote add origin git@github.com:liudding/easypaste-updates.git
git push -u origin main
```

### 配置 Deploy Key

```bash
# 生成专用密钥对（无密码）
ssh-keygen -t ed25519 -C "easypaste-updates deploy key" -N "" -f github_deploy_key

# 查看公钥
cat github_deploy_key.pub
```

1. 在 **easypaste-updates** 仓库：
   - Settings → Deploy keys → Add deploy key
   - Title: `GitHub Actions`
   - Key: 粘贴 `github_deploy_key.pub` 的内容
   - ✅ 勾选 "Allow write access"

2. 在 **EasyPaste** 仓库的 Secrets 中：
   - 添加 Secret `UPDATES_REPO_SSH_KEY`
   - Value: `github_deploy_key` 文件的全部内容

---

## 启用 GitHub Pages

在 **easypaste-updates** 仓库：
1. Settings → Pages
2. Source: **Deploy from a branch**
3. Branch: **main** / folder: **/ (root)**
4. Save

Pages URL 将为：`https://liudding.github.io/easypaste-updates/`

---

## 本地测试 Sparkle 集成

### 步骤 1：安装 Sparkle.framework
```bash
bash script/setup_sparkle.sh
```

### 步骤 2：构建并运行
```bash
bash script/build_and_run.sh run
```

### 步骤 3：模拟版本检查
1. 修改 Info.plist 中的 `CFBundleShortVersionString` 为 `0.0.1`
2. 重新构建
3. 运行应用
4. 菜单栏 → "检查更新…"

---

## 发布新版本

### 方式 A：通过 GitHub UI（推荐）
1. 修改 `Info.plist` 中的版本号：
   ```xml
   <key>CFBundleShortVersionString</key>
   <string>1.1.0</string>    <!-- 营销版本号 -->
   <key>CFBundleVersion</key>
   <string>11</string>       <!-- 内部构建号 -->
   ```
2. 提交并打 tag：
   ```bash
   git add .
   git commit -m "Release v1.1.0"
   git tag v1.1.0
   git push origin main --tags
   ```
3. 在 GitHub → Releases → Create a new release
   - Tag: `v1.1.0`
   - Title: `EasyPaste 1.1.0`
   - Description: 更新说明（Markdown 格式）
4. 点击 **Publish release** → Workflow 自动触发

### 方式 B：手动触发
1. Actions → Build & Release
2. Run workflow → 选择分支 → Run workflow

---

## 验证发布

### 检查 appcast.xml
访问：`https://liudding.github.io/easypaste-updates/appcast.xml`

应包含类似内容：
```xml
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="...">
  <channel>
    <title>EasyPaste Updates</title>
    <link>https://liudding.github.io/easypaste-updates/</link>
    <item>
      <title>Version 1.1.0</title>
      <description>...</description>
      <enclosure url="https://liudding.github.io/easypaste-updates/EasyPaste-1.1.0.dmg"
                 sparkle:version="11"
                 sparkle:shortVersionString="1.1.0"
                 sparkle:edSignature="abc123..."
                 length="45678912"
                 type="application/octet-stream" />
    </item>
  </channel>
</rss>
```

### 检查应用内更新提示
1. 安装旧版本应用
2. 打开应用
3. 等待 24 小时（或清除缓存：`defaults delete com.easypaste.app SULastCheckTime`）
4. 菜单栏 → "检查更新…"

---

## 故障排查

| 问题 | 解决方案 |
|------|---------|
| Notarization 失败 | 检查 entitlements 是否正确；查看 notarization log |
| Sparkle 无法加载 | 确认 Sparkle.framework 已嵌入且签名正确 |
| DMG 签名验证失败 | 确认 SPARKLE_ED_PRIVATE_KEY 与 Info.plist 中的 SUPublicEDKey 匹配 |
| Deploy key 权限不足 | 确认 easypaste-updates 仓库的 Deploy key 启用了 write access |
| GitHub Pages 不更新 | 确认 workflow 成功运行且 publish_dir 配置正确 |
| codesign 失败 | 确认 DEV_ID_P12_BASE64 有效且证书未过期 |

---

## 文件结构

```
.github/workflows/
  └── sparkle-publish.yml     ← CI/CD 工作流
script/
  ├── build_and_run.sh        ← 开发构建（含 Sparkle 拷贝）
  ├── create_dmg.sh           ← DMG 打包
  ├── setup_sparkle.sh        ← 下载 Sparkle.framework
  └── SPARKLE_SETUP.md        ← 详细设置指南
Info.plist                    ← SUFeedURL + SUPublicEDKey
EasyPaste.xcodeproj/          ← Xcode 项目（含 Sparkle SPM）
dist/                         ← 构建输出
  ├── EasyPaste.app/
  │   ├── Contents/MacOS/EasyPaste
  │   └── Contents/Frameworks/Sparkle.framework/
  └── EasyPasteInstaller.dmg
```
