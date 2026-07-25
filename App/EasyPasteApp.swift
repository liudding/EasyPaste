import AppKit
import Observation
import SwiftUI

@main
struct EasyPasteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var services: AppServices

    init() {
        let services = AppServices()
        _services = State(initialValue: services)
        appDelegate.services = services
    }

    var body: some Scene {
        MenuBarExtra("EasyPaste", systemImage: "clipboard.on.clipboard", isInserted: Binding(
            get: { services.settings.showInMenuBar },
            set: { services.settings.showInMenuBar = $0 }
        )) {
            MenuBarView(store: services.store, clipboard: services.clipboard, onShowPanel: { services.showPanel() })
            SettingsActionCapture(services: services)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(settings: services.settings, store: services.store, onInvokeShortcutChanged: { _ in services.registerShortcut() })
                .background(SettingsActionCapture(services: services))
                .onAppear {
                    // 设置窗口出现时确保 app 激活、窗口置前
                    // （SettingsLink / openSettings 不一定自动激活 app）。
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
    }
}

/// 组合根：集中持有 store / clipboard / settings / 快捷键 / 面板控制器，负责启动接线。
@Observable @MainActor
final class AppServices {
    let settings = AppSettings()
    let store: ClipboardStore
    let clipboard = ClipboardService()
    let shortcut = GlobalShortcutService()
    let panelState = PanelState()
    private let onboarding = OnboardingWindowController()
    private(set) var panel: PanelController?
    /// 从 SwiftUI 场景层次中捕获的 openSettings 动作。
    /// PanelView 在独立 NSHostingView 中，无法直接访问 @Environment(\.openSettings)，
    /// 需要在场景内部捕获后传递给 PanelController 使用。
    var openSettingsAction: (() -> Void)?

    init() {
        store = ClipboardStore()
    }

    func boot() {
        NSApp.setActivationPolicy(.regular)
        clipboard.settings = settings
        clipboard.onItem = { [weak self] item in self?.store.add(item) }
        clipboard.start()

        store.setICloudSyncEnabled(settings.iCloudSync)
        store.historyLimitDays = settings.historyLimitDays
        store.maxItems = settings.maxItems
        store.pruneExpired()

        panel = PanelController(store: store, clipboard: clipboard, settings: settings, panelState: panelState)
        panel?.openSettings = { [weak self] in self?.openSettingsAction?() }

        settings.onStorageLocationChanged = { [weak self] in
            self?.store.setICloudSyncEnabled(self?.settings.iCloudSync ?? false)
        }
        settings.onHistoryLimitChanged = { [weak self] in
            guard let self else { return }
            self.store.historyLimitDays = self.settings.historyLimitDays
            self.store.pruneExpired()
        }
        settings.onMaxItemsChanged = { [weak self] in
            guard let self else { return }
            self.store.maxItems = self.settings.maxItems
            self.store.pruneExpired()
        }

        registerShortcut()

        // 首次启动时展示引导（延迟以确保窗口已完全就绪）
        if !settings.hasCompletedOnboarding {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self else { return }
                self.onboarding.show(settings: self.settings)
            }
        }
    }

    func registerShortcut() {
        shortcut.register(shortcut: settings.invokeShortcut) { [weak self] in
            self?.panel?.toggle()
        }
    }

    func showPanel() { panel?.show() }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var services: AppServices?
    /// 唤起面板时记录的前台应用——粘贴时作为目标应用的回退来源。
    static var invokingApplication: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 初始化 Sparkle 更新服务（在 AppKit 启动阶段）
        _ = SparkleBridge.shared
        services?.boot()
    }

    func applicationWillResignActive(_ notification: Notification) {
        // 应用进后台前立即触发一次 iCloud ubiquity 备份（见 PersistenceTests / BackupService）。
        services?.store.triggerCloudBackup()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { services?.showPanel() }
        return true
    }
}

/// 在 SwiftUI 场景层次中捕获 @Environment(\.openSettings) 动作。
/// PanelView 寄宿在独立 NSHostingView 中，无法访问该环境值；
/// 通过此视图捕获后存入 AppServices，供 PanelController 使用。
private struct SettingsActionCapture: View {
    @Environment(\.openSettings) private var openSettings
    let services: AppServices

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear { services.openSettingsAction = { openSettings() } }
    }
}
