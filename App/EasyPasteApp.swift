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
        MenuBarExtra(L10n.appName, systemImage: "clipboard.on.clipboard", isInserted: Binding(
            get: { services.settings.showInMenuBar },
            set: { services.settings.showInMenuBar = $0 }
        )) {
            MenuBarView(
                store: services.store,
                clipboard: services.clipboard,
                onShowPanel: { services.showPanel() },
                onOpenSettings: { services.openSettingsWindow() }
            )
        }
        .menuBarExtraStyle(.menu)
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
    let clipAction: ClipActionService
    private let onboarding = OnboardingWindowController()
    private(set) var panel: PanelController?
    /// 设置窗口控制器：直接用 AppKit 托管 SettingsView。
    /// 不再依赖 SwiftUI Settings 场景 / openSettings 环境动作（该动作需场景内捕获，
    /// 对只用快捷键唤起面板的用户恒为 nil），也不依赖 macOS 14+ 已移除的
    /// showSettingsWindow: 选择器，从而从面板与菜单栏都能稳定打开设置。
    private var settingsWC: NSWindowController?

    init() {
        store = ClipboardStore()
        clipAction = ClipActionService(clipboard: clipboard, panelState: panelState)
    }

    func boot() {
        // 根据 hideDockIcon 设置初始 Dock 策略
        applyDockPolicy()
        clipboard.settings = settings
        clipboard.onItem = { [weak self] item in self?.store.add(item) }
        clipboard.start()

        store.setICloudSyncEnabled(settings.iCloudSync)
        store.historyLimitDays = settings.historyLimitDays
        store.maxItems = settings.maxItems
        store.pruneExpired()

        // 性能：预热来源 app 图标缓存。首次唤起面板时，每张可见卡片都会在主线程同步调用
        // AppIconCache.icon(forBundleID:displaySize:)；冷缓存下每次都要做 LaunchServices 查询
        // (urlForApplication) + icon 解码 + TIFF 像素采样(主色调) + lockFocus 缩放，单卡数十 ms，
        // 8~10 张可见卡片累加即首次唤起「大延迟」的主因。
        // 这里在后台队列提前预热（warm 内部已 dispatch 到 .utility），使首次渲染即命中字典缓存。
        // 注意：PanelView.onAppear 里也有一句 warm，但 onAppear 在首次渲染「之后」才触发，
        // 无法救首次渲染；放到 boot 才能真正提前。onAppear 那句保留，兜底启动后新捕获的条目。
        let bundleIDs = store.items.compactMap { $0.sourceApplicationBundleID }
        AppIconCache.shared.warm(bundleIDs: bundleIDs)

        panel = PanelController(store: store, clipboard: clipboard, settings: settings, panelState: panelState, clipAction: clipAction)
        panel?.openSettingsHandler = { [weak self] screen in self?.openSettingsWindow(on: screen) }

        // 性能：预建面板与其 SwiftUI 视图树（离屏、不显示）并触发一次布局，
        // 提前编译 .ultraThinMaterial 着色器、构建头部视图图，使首次真实唤起只做定位 + 动画。
        // 延后一拍执行，避免阻塞菜单栏图标出现；makePanel() 在首次 show() 时直接命中已建好的面板。
        DispatchQueue.main.async { [weak self] in self?.panel?.prewarm() }

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
        // Dock 图标可见性变化回调：如果有设置窗口打开，延迟到窗口关闭后再切换。
        settings.onDockIconVisibilityChanged = { [weak self] in
            guard let self else { return }
            // 先移除旧的观察者（防止重复注册）。
            NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: nil)
            if let wc = self.settingsWC, let win = wc.window, win.isVisible {
                NotificationCenter.default.addObserver(
                    forName: NSWindow.willCloseNotification,
                    object: win,
                    queue: .main
                ) { [weak self] _ in
                    self?.applyDockPolicy()
                }
            } else {
                self.applyDockPolicy()
            }
        }

        // 面板 edge 位置变更回调：实时重定位已显示的窗口，否则只在下次 show() 生效。
        settings.onPanelPositionChanged = { [weak self] in
            self?.panel?.reposition()
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

    /// 应用 Dock 图标策略（.regular / .accessory）。
    private func applyDockPolicy() {
        NSApp.setActivationPolicy(settings.hideDockIcon ? .accessory : .regular)
    }

    func registerShortcut() {
        shortcut.register(shortcut: settings.invokeShortcut) { [weak self] in
            self?.panel?.toggle()
        }
    }

    func showPanel() { panel?.show() }

    /// 直接以 AppKit 窗口托管 SettingsView 并置前。
    /// 不依赖 SwiftUI Settings 场景 / openSettings 环境动作（只对已打开过场景的用户有效），
    /// 也不依赖 macOS 14+ 已移除的 showSettingsWindow: 选择器。
    func openSettingsWindow(on screen: NSScreen? = nil) {
        // 隐藏 Dock 时不强制恢复 .regular，保持 .accessory
        if !settings.hideDockIcon { applyDockPolicy() }
        NSApp.activate(ignoringOtherApps: true)

        let window: NSWindow
        if let wc = settingsWC, let existing = wc.window {
            window = existing
        } else {
            let root = SettingsView(
                settings: settings,
                store: store,
                onInvokeShortcutChanged: { [weak self] _ in self?.registerShortcut() }
            )
            let hosting = NSHostingController(rootView: root)
            window = NSWindow(contentViewController: hosting)
            window.title = L10n.settings
            // 透明标题栏 + 全尺寸内容视图：移除可见的顶部标题栏带，但保留红黄绿三按钮，
            // 使其悬浮在左侧 sidebar 顶部（类似系统设置/Mail）。侧栏内容由 SwiftUI 的
            // safeAreaInset 顶部内边距让出按钮空间。isMovableByWindowBackground 让用户可
            // 从侧栏顶部非交互区拖动窗口。
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.contentMinSize = NSSize(width: 680, height: 460)
            settingsWC = NSWindowController(window: window)
        }

        // 定位屏幕：优先用调用方传入的（面板所在屏），否则用鼠标所在屏，再退主屏。
        // 从面板「设置…」唤起时传的是面板 screen，所以设置窗口一定落在面板所在屏幕。
        let targetScreen: NSScreen
        if let s = screen {
            targetScreen = s
        } else {
            let mouse = NSEvent.mouseLocation
            targetScreen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
                ?? NSScreen.main
                ?? NSScreen.screens.first
                ?? NSScreen()
        }
        let size = NSSize(width: 780, height: 540)
        var frame = NSRect(origin: .zero, size: size)
        frame.origin.x = targetScreen.visibleFrame.midX - size.width / 2
        frame.origin.y = targetScreen.visibleFrame.midY - size.height / 2
        window.setFrame(frame, display: true)

        settingsWC?.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var services: AppServices?
    /// 唤起面板时记录的前台应用——粘贴时作为目标应用的回退来源。
    static var invokingApplication: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        SentrySDK.start { options in
            options.dsn = "https://5c451e16cf24d13b9f7e00789331255a@o4507779151888384.ingest.us.sentry.io/4511796503642112"
            options.debug = true // Enabling debug when first installing is always helpful

            // Adds IP for users.
            // For more information, visit: https://docs.sentry.io/platforms/apple/data-management/data-collected/
            options.sendDefaultPii = true
        }

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
