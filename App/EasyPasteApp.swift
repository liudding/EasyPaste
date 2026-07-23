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
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(settings: services.settings, store: services.store, onInvokeShortcutChanged: { _ in services.registerShortcut() })
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
    private(set) var panel: PanelController?

    init() {
        store = ClipboardStore(iCloud: false)
    }

    func boot() {
        NSApp.setActivationPolicy(.regular)
        clipboard.settings = settings
        clipboard.onItem = { [weak self] item in self?.store.add(item) }
        clipboard.start()

        store.setICloudSyncEnabled(settings.iCloudSync)
        store.historyLimitDays = settings.historyLimitDays
        store.pruneExpired()

        panel = PanelController(store: store, clipboard: clipboard, settings: settings, panelState: panelState)

        settings.onStorageLocationChanged = { [weak self] in
            self?.store.setICloudSyncEnabled(self?.settings.iCloudSync ?? false)
        }
        settings.onHistoryLimitChanged = { [weak self] in
            guard let self else { return }
            self.store.historyLimitDays = self.settings.historyLimitDays
            self.store.pruneExpired()
        }

        registerShortcut()
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
        services?.boot()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { services?.showPanel() }
        return true
    }
}
