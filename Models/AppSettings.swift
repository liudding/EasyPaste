import AppKit
import Foundation
import Observation
import ServiceManagement

@Observable @MainActor
final class AppSettings {
    enum PanelPosition: String, Codable, CaseIterable, Identifiable {
        case bottom, top, left, right
        var id: String { rawValue }
        var title: String {
            switch self { case .bottom: "底部"; case .top: "顶部"; case .left: "左侧"; case .right: "右侧" }
        }
        var isVertical: Bool { self == .left || self == .right }
    }

    struct IgnoredApp: Codable, Identifiable, Hashable {
        var id: String { bundleID }
        let bundleID: String
        let name: String
    }

    /// (days, label)；days == 0 表示无限保留。
    static let historySteps: [(days: Int, label: String)] = [
        (1, "1 天"), (2, "2 天"), (3, "3 天"), (4, "4 天"), (5, "5 天"), (6, "6 天"),
        (7, "1 周"), (14, "2 周"), (21, "3 周"),
        (30, "1 个月"), (60, "2 个月"), (90, "3 个月"), (120, "4 个月"), (150, "5 个月"),
        (180, "6 个月"), (210, "7 个月"), (240, "8 个月"), (270, "9 个月"),
        (300, "10 个月"), (330, "11 个月"), (365, "1 年"), (0, "无限")
    ]

    static let soundNames = ["Pop", "Ping", "Tink", "Glass", "Hero", "Submarine", "Blow", "Bottle", "Frog", "Funk", "Morse", "Purr", "Sosumi"]

    var panelPosition: PanelPosition = .bottom { didSet { save() } }
    var openAtLogin = false { didSet { applyLoginItem(); save() } }
    var iCloudSync = false { didSet { save(); onStorageLocationChanged?() } }
    var showInMenuBar = true { didSet { save() } }
    var soundName = "Pop" { didSet { save() } }
    var alwaysPastePlainText = false { didSet { save() } }
    var historyStepIndex = AppSettings.historySteps.count - 1 { didSet { save(); onHistoryLimitChanged?() } }
    var ignoredApps: [IgnoredApp] = [
        IgnoredApp(bundleID: "com.apple.keychainaccess", name: "钥匙串访问"),
        IgnoredApp(bundleID: "com.apple.Passwords", name: "密码")
    ] { didSet { save() } }
    var invokeShortcut: Shortcut = .invokeDefault { didSet { save() } }
    var boardSwitchShortcut: Shortcut = .boardSwitchDefault { didSet { save() } }
    var hasCompletedOnboarding = false { didSet { save() } }

    var onStorageLocationChanged: (() -> Void)?
    var onHistoryLimitChanged: (() -> Void)?

    var historyLimitDays: Int {
        let clamped = min(max(historyStepIndex, 0), AppSettings.historySteps.count - 1)
        return AppSettings.historySteps[clamped].days
    }
    var historyLimitLabel: String {
        let clamped = min(max(historyStepIndex, 0), AppSettings.historySteps.count - 1)
        return AppSettings.historySteps[clamped].label
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
        var alwaysPastePlainText: Bool
        var historyStepIndex: Int
        var ignoredApps: [IgnoredApp]
        var invokeShortcut: Shortcut
        var boardSwitchShortcut: Shortcut
        var hasCompletedOnboarding: Bool

        init(panelPosition: PanelPosition, openAtLogin: Bool, iCloudSync: Bool,
             showInMenuBar: Bool, soundName: String, alwaysPastePlainText: Bool,
             historyStepIndex: Int, ignoredApps: [IgnoredApp],
             invokeShortcut: Shortcut, boardSwitchShortcut: Shortcut,
             hasCompletedOnboarding: Bool) {
            self.panelPosition = panelPosition
            self.openAtLogin = openAtLogin
            self.iCloudSync = iCloudSync
            self.showInMenuBar = showInMenuBar
            self.soundName = soundName
            self.alwaysPastePlainText = alwaysPastePlainText
            self.historyStepIndex = historyStepIndex
            self.ignoredApps = ignoredApps
            self.invokeShortcut = invokeShortcut
            self.boardSwitchShortcut = boardSwitchShortcut
            self.hasCompletedOnboarding = hasCompletedOnboarding
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            panelPosition = try c.decode(PanelPosition.self, forKey: .panelPosition)
            openAtLogin = try c.decode(Bool.self, forKey: .openAtLogin)
            iCloudSync = try c.decode(Bool.self, forKey: .iCloudSync)
            showInMenuBar = try c.decode(Bool.self, forKey: .showInMenuBar)
            soundName = try c.decode(String.self, forKey: .soundName)
            alwaysPastePlainText = try c.decode(Bool.self, forKey: .alwaysPastePlainText)
            historyStepIndex = try c.decode(Int.self, forKey: .historyStepIndex)
            ignoredApps = try c.decode([IgnoredApp].self, forKey: .ignoredApps)
            invokeShortcut = try c.decode(Shortcut.self, forKey: .invokeShortcut)
            boardSwitchShortcut = try c.decode(Shortcut.self, forKey: .boardSwitchShortcut)
            hasCompletedOnboarding = try c.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
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
        alwaysPastePlainText = snapshot.alwaysPastePlainText
        historyStepIndex = snapshot.historyStepIndex
        ignoredApps = snapshot.ignoredApps
        invokeShortcut = snapshot.invokeShortcut
        boardSwitchShortcut = snapshot.boardSwitchShortcut
        hasCompletedOnboarding = snapshot.hasCompletedOnboarding
    }

    func save() {
        let snapshot = Snapshot(panelPosition: panelPosition, openAtLogin: openAtLogin, iCloudSync: iCloudSync,
                                showInMenuBar: showInMenuBar, soundName: soundName,
                                alwaysPastePlainText: alwaysPastePlainText, historyStepIndex: historyStepIndex,
                                ignoredApps: ignoredApps, invokeShortcut: invokeShortcut,
                                boardSwitchShortcut: boardSwitchShortcut,
                                hasCompletedOnboarding: hasCompletedOnboarding)
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
