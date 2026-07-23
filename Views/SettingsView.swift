import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Bindable var settings: AppSettings
    let store: ClipboardStore
    let onInvokeShortcutChanged: (Shortcut) -> Void
    @State private var showClearConfirm = false

    var body: some View {
        TabView {
            general.tabItem { Label("通用", systemImage: "gear") }
            privacy.tabItem { Label("隐私", systemImage: "hand.raised") }
            shortcuts.tabItem { Label("快捷键", systemImage: "keyboard") }
            updates.tabItem { Label("更新", systemImage: "arrow.down.circle") }
        }
        .padding(20)
        .frame(width: 480, height: 440)
    }

    // MARK: General

    private var general: some View {
        Form {
            Section("面板") {
                Picker("面板位置", selection: $settings.panelPosition) {
                    ForEach(AppSettings.PanelPosition.allCases) { Text($0.title).tag($0) }
                }
            }
            Section("通用") {
                Toggle("登录时打开", isOn: $settings.openAtLogin)
                Toggle("iCloud 同步剪贴板历史", isOn: $settings.iCloudSync)
                Toggle("在菜单栏显示", isOn: $settings.showInMenuBar)
                Picker("粘贴音效", selection: $settings.soundName) {
                    Text("无").tag("")
                    ForEach(AppSettings.soundNames, id: \.self) { Text($0).tag($0) }
                }
                Toggle("始终以纯文本粘贴", isOn: $settings.alwaysPastePlainText)
            }
            Section("历史") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack { Text("保留时长"); Spacer(); Text(settings.historyLimitLabel).foregroundStyle(.secondary) }
                    Slider(value: historyIndexBinding, in: 0...Double(AppSettings.historySteps.count - 1), step: 1)
                }
                Button("清除全部历史…", role: .destructive) { showClearConfirm = true }
                    .alert("清除全部剪贴板历史？", isPresented: $showClearConfirm) {
                        Button("清除", role: .destructive) { store.clearAll() }
                        Button("取消", role: .cancel) {}
                    } message: { Text("此操作不可撤销。") }
            }
        }
        .formStyle(.grouped)
    }

    private var historyIndexBinding: Binding<Double> {
        Binding(get: { Double(settings.historyStepIndex) }, set: { settings.historyStepIndex = Int($0) })
    }

    // MARK: Privacy

    private var privacy: some View {
        Form {
            Section {
                if settings.ignoredApps.isEmpty {
                    Text("没有忽略的 App").foregroundStyle(.secondary)
                }
                ForEach(settings.ignoredApps) { app in
                    HStack(spacing: 8) {
                        Image(nsImage: icon(for: app.bundleID)).resizable().frame(width: 20, height: 20)
                        VStack(alignment: .leading) {
                            Text(app.name)
                            Text(app.bundleID).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { settings.ignoredApps.removeAll { $0.id == app.id } } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                        }.buttonStyle(.plain)
                    }
                }
                Button("添加 App…") { addIgnoredApp() }
            } header: {
                Text("忽略以下 App 的剪贴板内容")
            } footer: {
                Text("在这些 App 中拷贝的内容不会保存到历史。").font(.caption)
            }
        }
        .formStyle(.grouped)
    }

    private func icon(for bundleID: String) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
    }

    private func addIgnoredApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = "选择要忽略的应用"
        if panel.runModal() == .OK, let url = panel.url, let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier {
            let name = bundle.infoDictionary?["CFBundleName"] as? String ?? url.deletingPathExtension().lastPathComponent
            if !settings.ignoredApps.contains(where: { $0.bundleID == bundleID }) {
                settings.ignoredApps.append(AppSettings.IgnoredApp(bundleID: bundleID, name: name))
            }
        }
    }

    // MARK: Shortcuts

    private var shortcuts: some View {
        Form {
            Section {
                LabeledContent("唤起面板") { ShortcutRecorderView(shortcut: invokeBinding) }
                LabeledContent("切换 Pinboard（面板内）") { ShortcutRecorderView(shortcut: $settings.boardSwitchShortcut) }
            } footer: {
                Text("点击右侧按钮后按下新的快捷键，Esc 取消。修改立即生效。").font(.caption)
            }
        }
        .formStyle(.grouped)
    }

    private var invokeBinding: Binding<Shortcut> {
        Binding(get: { settings.invokeShortcut }, set: { settings.invokeShortcut = $0; onInvokeShortcutChanged($0) })
    }
    
    // MARK: Updates
    
    private var updates: some View {
        Form {
            Section("自动更新") {
                Button("检查更新…") {
                    SparkleBridge.shared.checkForUpdates()
                }
                
                let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "未知"
                let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "未知"
                
                LabeledContent("当前版本") { Text("\(version) (\(build))") }
                
                #if canImport(Sparkle)
                LabeledContent("更新引擎") {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Sparkle 已启用")
                }
                #else
                LabeledContent("更新引擎") {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("仅开发模式（需 Xcode 构建）")
                }
                #endif
            }
            
            Section("更新说明") {
                Text("新版本将在此处显示更新说明。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Section("配置") {
                Text("部署 appcast.xml 后，取消 Info.plist 中 SUFeedURL 和 SUPublicEDKey 的注释即可启用自动更新。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
    }
}
