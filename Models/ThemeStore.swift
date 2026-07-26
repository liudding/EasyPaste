import AppKit
import Foundation
import Observation
import SwiftUI

// MARK: - Theme Appearance

/// 主题外观模式：自动（跟随系统）、浅色、深色。
enum ThemeAppearance: String, CaseIterable, Identifiable {
    case auto
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: L10n.tr("theme.auto")
        case .light: L10n.tr("theme.light")
        case .dark: L10n.tr("theme.dark")
        }
    }

    var icon: String {
        switch self {
        case .auto: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }

    /// 转为 SwiftUI ColorScheme（auto → nil 表示跟随系统）。
    var colorScheme: ColorScheme? {
        switch self {
        case .auto: nil
        case .light: .light
        case .dark: .dark
        }
    }

    /// 转为 NSAppearance（auto → nil 表示跟随系统）。
    var nsAppearance: NSAppearance? {
        switch self {
        case .auto: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

// MARK: - Observable Theme Store

/// 管理主题外观设置的 @Observable 存储。
/// 与 L10nStore 模式一致：version 计数器驱动 SwiftUI 视图实时刷新，无需重启。
/// 注意：appearance 写入始终发生在主线程（SwiftUI Picker onChange），故不加 @MainActor。
@Observable @MainActor
final class ThemeStore: @unchecked Sendable {
    static let shared = ThemeStore()

    private let userDefaultsKey = "EasyPasteTheme"

    /// 当主题切换时递增，驱动 SwiftUI 视图刷新。
    private(set) var version: UInt = 0

    var appearance: ThemeAppearance {
        get {
            if let raw = UserDefaults.standard.string(forKey: userDefaultsKey),
               let theme = ThemeAppearance(rawValue: raw) {
                return theme
            }
            return .auto
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: userDefaultsKey)
            version &+= 1
            applyToApp()
        }
    }

    /// 解析后的 SwiftUI ColorScheme（auto → nil = 跟随系统）。
    var effectiveColorScheme: ColorScheme? {
        appearance.colorScheme
    }

    /// 解析后的 NSAppearance（auto → nil = 跟随系统）。
    var effectiveNSAppearance: NSAppearance? {
        appearance.nsAppearance
    }

    private init() {
        applyToApp()
    }

    /// 将主题应用到整个 App（影响所有窗口的标题栏等 AppKit chrome）。
    /// auto 模式设为 nil（跟随系统），light/dark 模式设为对应 NSAppearance。
    @MainActor
    func applyToApp() {
        NSApp.appearance = effectiveNSAppearance
    }
}
