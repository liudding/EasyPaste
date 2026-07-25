import AppKit
import Carbon
import Foundation
import Observation
import ServiceManagement

@Observable @MainActor
final class AppSettings {
    enum PanelPosition: String, Codable, CaseIterable, Identifiable {
        case bottom, top, left, right
        var id: String { rawValue }
        var title: String {
            switch self {
            case .bottom: L10n.tr("settings.position_bottom")
            case .top: L10n.tr("settings.position_top")
            case .left: L10n.tr("settings.position_left")
            case .right: L10n.tr("settings.position_right")
            }
        }
        var isVertical: Bool { self == .left || self == .right }
    }

    /// 历史最大保留条数模式。`limited` 由 `maxItemsCount` 决定上限，`unlimited` 表示不限条数。
    enum MaxItemsMode: String, Codable, CaseIterable, Identifiable {
        case limited, unlimited
        var id: String { rawValue }
        var title: String {
            switch self {
            case .limited: L10n.tr("settings.max_items_limited")
            case .unlimited: L10n.tr("settings.max_items_unlimited")
            }
        }
    }

    struct IgnoredApp: Codable, Identifiable, Hashable {
        var id: String { bundleID }
        let bundleID: String
        let name: String
    }

    /// (days, labelKey)；days == 0 表示无限保留。labelKey maps to L10n for i18n.
    static let historyStepsRaw: [(days: Int, labelKey: String)] = [
        (1, "history.1d"), (2, "history.2d"), (3, "history.3d"), (4, "history.4d"), (5, "history.5d"), (6, "history.6d"),
        (7, "history.1w"), (14, "history.2w"), (21, "history.3w"),
        (30, "history.1mo"), (60, "history.2mo"), (90, "history.3mo"), (120, "history.4mo"), (150, "history.5mo"),
        (180, "history.6mo"), (210, "history.7mo"), (240, "history.8mo"), (270, "history.9mo"),
        (300, "history.10mo"), (330, "history.11mo"), (365, "history.1y"), (0, "history.unlimited")
    ]
    
    static func historyStepLabel(forIndex index: Int) -> String {
        let clamped = min(max(index, 0), historyStepsRaw.count - 1)
        return L10n.tr(historyStepsRaw[clamped].labelKey)
    }

    static let soundNames = ["Pop", "Ping", "Tink", "Glass", "Hero", "Submarine", "Blow", "Bottle", "Frog", "Funk", "Morse", "Purr", "Sosumi"]

    var panelPosition: PanelPosition = .bottom { didSet { save(); onPanelPositionChanged?() } }
    var openAtLogin = false { didSet { applyLoginItem(); save() } }
    var iCloudSync = false { didSet { save(); onStorageLocationChanged?() } }
    var showInMenuBar = true { didSet { save() } }
    var soundName = "Pop" { didSet { save() } }
    /// 快捷面板声音开关：当 soundName != "" 时有效；"" 时音效始终关闭。
    var soundEnabled = true { didSet { save() } }
    var alwaysPastePlainText = false { didSet { save() } }
    var historyStepIndex = AppSettings.historyStepsRaw.count - 1 { didSet { save(); onHistoryLimitChanged?() } }
    var maxItemsMode: MaxItemsMode = .limited { didSet { save(); onMaxItemsChanged?() } }
    var maxItemsCount: Int = 2000 { didSet { save(); onMaxItemsChanged?() } }
    var ignoredApps: [IgnoredApp] = [
        IgnoredApp(bundleID: "com.apple.keychainaccess", name: "Keychain Access"),
        IgnoredApp(bundleID: "com.apple.Passwords", name: "Passwords")
    ] { didSet { save() } }
    var invokeShortcut: Shortcut = .invokeDefault { didSet { save() } }
    var boardSwitchShortcut: Shortcut = .boardSwitchDefault { didSet { save() } }
    /// 面板内 Tab / Shift+Tab 切换看板（正向/反向）。
    var tabSwitchBoardEnabled = true { didSet { save() } }
    var hasCompletedOnboarding = false { didSet { save() } }
    
    /// 上下文菜单项的快捷键配置。key 为 action ID，value 为对应的 Shortcut 和启用状态。
    var contextMenuShortcuts: [String: ContextMenuItemShortcut] = [:] { didSet { save() } }

    /// 隐藏 Dock 图标。true = .accessory, false = .regular。
    var hideDockIcon = false { didSet { save(); onDockIconVisibilityChanged?() } }

    /// 上下文菜单项的快捷键配置。
    struct ContextMenuItemShortcut: Codable, Equatable {
        var shortcut: Shortcut?
        var enabled: Bool = true
    }
    
    /// 上下文菜单项默认快捷键映射。
    static let contextMenuShortcutDefaults: [String: ContextMenuItemShortcut] = [
        "paste": .init(shortcut: .init(keyCode: UInt16(kVK_ANSI_V), modifierFlags: NSEvent.ModifierFlags.command.rawValue)),
        "paste_plain": .init(shortcut: .init(keyCode: UInt16(kVK_ANSI_V), modifierFlags: NSEvent.ModifierFlags([.command, .shift]).rawValue)),
        "copy": .init(shortcut: .init(keyCode: UInt16(kVK_ANSI_C), modifierFlags: NSEvent.ModifierFlags.command.rawValue)),
        "rename": .init(shortcut: .init(keyCode: UInt16(kVK_ANSI_R), modifierFlags: NSEvent.ModifierFlags.command.rawValue)),
        "preview": .init(shortcut: .init(keyCode: UInt16(kVK_Space), modifierFlags: 0)),
        "delete": .init(shortcut: .init(keyCode: UInt16(kVK_Delete), modifierFlags: 0)),
        "export_txt": .init(shortcut: .init(keyCode: UInt16(kVK_ANSI_E), modifierFlags: NSEvent.ModifierFlags.command.rawValue)),
        "export_rtf": .init(shortcut: .init(keyCode: UInt16(kVK_ANSI_E), modifierFlags: NSEvent.ModifierFlags([.command, .shift]).rawValue)),
        "save_as": .init(shortcut: .init(keyCode: UInt16(kVK_ANSI_S), modifierFlags: NSEvent.ModifierFlags.command.rawValue)),
        "send_email": .init(shortcut: .init(keyCode: UInt16(kVK_ANSI_M), modifierFlags: NSEvent.ModifierFlags.command.rawValue)),
        "json_preview": .init(shortcut: .init(keyCode: UInt16(kVK_ANSI_J), modifierFlags: NSEvent.ModifierFlags.command.rawValue)),
        "open_link": .init(shortcut: .init(keyCode: UInt16(kVK_ANSI_L), modifierFlags: NSEvent.ModifierFlags.command.rawValue)),
        "qr_code": .init(shortcut: .init(keyCode: UInt16(kVK_ANSI_Q), modifierFlags: NSEvent.ModifierFlags.command.rawValue)),
        "paste_color_hex": .init(shortcut: .init(keyCode: UInt16(kVK_ANSI_H), modifierFlags: NSEvent.ModifierFlags.command.rawValue)),
        "paste_color_rgb": .init(shortcut: .init(keyCode: UInt16(kVK_ANSI_G), modifierFlags: NSEvent.ModifierFlags.command.rawValue)),
        "paste_color_hsl": .init(shortcut: .init(keyCode: UInt16(kVK_ANSI_F), modifierFlags: NSEvent.ModifierFlags.command.rawValue)),
    ]
    
    /// 获取默认的上下文菜单快捷键配置。
    static func getDefaultContextMenuShortcuts() -> [String: ContextMenuItemShortcut] {
        contextMenuShortcutDefaults
    }
    
    var onDockIconVisibilityChanged: (() -> Void)?

    /// 面板 edge 变更回调：面板可见时需实时重定位窗口 frame，否则只在下次 show() 生效。
    var onPanelPositionChanged: (() -> Void)?

    var onStorageLocationChanged: (() -> Void)?
    var onHistoryLimitChanged: (() -> Void)?
    var onMaxItemsChanged: (() -> Void)?

    var historyLimitDays: Int {
        let clamped = min(max(historyStepIndex, 0), AppSettings.historyStepsRaw.count - 1)
        return AppSettings.historyStepsRaw[clamped].days
    }
    var historyLimitLabel: String {
        AppSettings.historyStepLabel(forIndex: historyStepIndex)
    }
    var maxItemsLabel: String {
        switch maxItemsMode {
        case .limited: "\(maxItemsCount) \(L10n.tr("clip.count_suffix"))"
        case .unlimited: L10n.tr("settings.max_items_unlimited")
        }
    }
    var maxItems: ClipboardStore.MaxItems {
        switch maxItemsMode { case .limited: .limited(max(1, maxItemsCount)); case .unlimited: .unlimited }
    }

    init() { load() }

    // MARK: - Persistence

    private var defaultsKey: String { "EasyPasteSettings" }

    private struct Snapshot: Codable {
        var panelPosition: PanelPosition
        var openAtLogin: Bool
        var iCloudSync: Bool
        var showInMenuBar: Bool
        var soundName: String
        var soundEnabled: Bool
        var alwaysPastePlainText: Bool
        var historyStepIndex: Int
        var maxItemsMode: MaxItemsMode
        var maxItemsCount: Int
        var ignoredApps: [IgnoredApp]
        var invokeShortcut: Shortcut
        var boardSwitchShortcut: Shortcut
        var tabSwitchBoardEnabled: Bool
        var hasCompletedOnboarding: Bool
        var hideDockIcon: Bool
        var contextMenuShortcuts: [String: ContextMenuItemShortcut]

        init(panelPosition: PanelPosition, openAtLogin: Bool, iCloudSync: Bool,
             showInMenuBar: Bool, soundName: String, soundEnabled: Bool,
             alwaysPastePlainText: Bool, historyStepIndex: Int,
             maxItemsMode: MaxItemsMode, maxItemsCount: Int,
             ignoredApps: [IgnoredApp], invokeShortcut: Shortcut,
             boardSwitchShortcut: Shortcut, tabSwitchBoardEnabled: Bool,
             hasCompletedOnboarding: Bool,
             hideDockIcon: Bool = false,
             contextMenuShortcuts: [String: ContextMenuItemShortcut] = [:]) {
            self.panelPosition = panelPosition
            self.openAtLogin = openAtLogin
            self.iCloudSync = iCloudSync
            self.showInMenuBar = showInMenuBar
            self.soundName = soundName
            self.soundEnabled = soundEnabled
            self.alwaysPastePlainText = alwaysPastePlainText
            self.historyStepIndex = historyStepIndex
            self.maxItemsMode = maxItemsMode
            self.maxItemsCount = maxItemsCount
            self.ignoredApps = ignoredApps
            self.invokeShortcut = invokeShortcut
            self.boardSwitchShortcut = boardSwitchShortcut
            self.tabSwitchBoardEnabled = tabSwitchBoardEnabled
            self.hasCompletedOnboarding = hasCompletedOnboarding
            self.hideDockIcon = hideDockIcon
            self.contextMenuShortcuts = contextMenuShortcuts
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            panelPosition = try c.decode(PanelPosition.self, forKey: .panelPosition)
            openAtLogin = try c.decode(Bool.self, forKey: .openAtLogin)
            iCloudSync = try c.decode(Bool.self, forKey: .iCloudSync)
            showInMenuBar = try c.decode(Bool.self, forKey: .showInMenuBar)
            soundName = try c.decode(String.self, forKey: .soundName)
            soundEnabled = try c.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? true
            alwaysPastePlainText = try c.decode(Bool.self, forKey: .alwaysPastePlainText)
            historyStepIndex = try c.decode(Int.self, forKey: .historyStepIndex)
            maxItemsMode = try c.decodeIfPresent(MaxItemsMode.self, forKey: .maxItemsMode) ?? .limited
            maxItemsCount = try c.decodeIfPresent(Int.self, forKey: .maxItemsCount) ?? 2000
            ignoredApps = try c.decode([IgnoredApp].self, forKey: .ignoredApps)
            invokeShortcut = try c.decode(Shortcut.self, forKey: .invokeShortcut)
            boardSwitchShortcut = try c.decode(Shortcut.self, forKey: .boardSwitchShortcut)
            tabSwitchBoardEnabled = try c.decodeIfPresent(Bool.self, forKey: .tabSwitchBoardEnabled) ?? true
            hasCompletedOnboarding = try c.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
            hideDockIcon = try c.decodeIfPresent(Bool.self, forKey: .hideDockIcon) ?? false
            contextMenuShortcuts = try c.decodeIfPresent([String: ContextMenuItemShortcut].self, forKey: .contextMenuShortcuts) ?? [:]
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        panelPosition = snapshot.panelPosition
        openAtLogin = snapshot.openAtLogin
        iCloudSync = snapshot.iCloudSync
        showInMenuBar = snapshot.showInMenuBar
        soundName = snapshot.soundName
        soundEnabled = snapshot.soundEnabled
        alwaysPastePlainText = snapshot.alwaysPastePlainText
        historyStepIndex = snapshot.historyStepIndex
        maxItemsMode = snapshot.maxItemsMode
        maxItemsCount = snapshot.maxItemsCount
        ignoredApps = snapshot.ignoredApps
        invokeShortcut = snapshot.invokeShortcut
        boardSwitchShortcut = snapshot.boardSwitchShortcut
        tabSwitchBoardEnabled = snapshot.tabSwitchBoardEnabled
        hasCompletedOnboarding = snapshot.hasCompletedOnboarding
        hideDockIcon = snapshot.hideDockIcon
        contextMenuShortcuts = snapshot.contextMenuShortcuts.isEmpty ? Self.contextMenuShortcutDefaults : snapshot.contextMenuShortcuts
    }

    func save() {
        let snapshot = Snapshot(panelPosition: panelPosition, openAtLogin: openAtLogin, iCloudSync: iCloudSync,
                                showInMenuBar: showInMenuBar, soundName: soundName, soundEnabled: soundEnabled,
                                alwaysPastePlainText: alwaysPastePlainText, historyStepIndex: historyStepIndex,
                                maxItemsMode: maxItemsMode, maxItemsCount: maxItemsCount,
                                ignoredApps: ignoredApps, invokeShortcut: invokeShortcut,
                                boardSwitchShortcut: boardSwitchShortcut,
                                tabSwitchBoardEnabled: tabSwitchBoardEnabled,
                                hasCompletedOnboarding: hasCompletedOnboarding,
                                hideDockIcon: hideDockIcon,
                                contextMenuShortcuts: contextMenuShortcuts)
        UserDefaults.standard.set(try? JSONEncoder().encode(snapshot), forKey: defaultsKey)
    }

    private func applyLoginItem() {
        do {
            if openAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            // ad-hoc 签名的本地构建可能注册失败，静默忽略；切换回 false 以反映真实状态。
            openAtLogin = false
        }
    }
}
