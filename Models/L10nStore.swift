import Foundation
import Observation

// MARK: - Observable Locale Store

/// 管理当前语言设置的 @Observable 存储。SwiftUI 视图通过在 body 中直接读取 `version` 来订阅 locale 变化：
/// ```
/// @State private var l10nStore = L10nStore.shared
/// var body: some View { let _ = l10nStore.version; ... }
/// ```
/// 切换语言无需重启 app。
/// 注意：locale 写入始终发生在主线程（SwiftUI Picker onChange），
/// 故不加 @MainActor 以避免跨 actor 隔离问题（L10n.tr() 在任意上下文调用）。
@Observable
final class L10nStore: @unchecked Sendable {
    static let shared = L10nStore()

    private let userDefaultsKey = "EasyPasteLocale"

    // MARK: - Locale

    /// 当语言切换时递增，驱动 SwiftUI 视图刷新。
    private(set) var version: UInt = 0

    var locale: L10n.Locale {
        get {
            if let raw = UserDefaults.standard.string(forKey: userDefaultsKey),
               let loc = L10n.Locale(rawValue: raw) {
                return loc
            }
            return .followSystem
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: userDefaultsKey)
            version &+= 1
        }
    }

    /// 解析后的生效语言（followSystem → 实际语言）。
    var effectiveLocale: L10n.Locale {
        switch locale {
        case .followSystem:
            let sysLang = Foundation.Locale.preferredLanguages.first?.prefix(2) ?? "en"
            if sysLang == "zh" {
                let region = Foundation.Locale.current.region?.identifier
                if region == "TW" || region == "HK" { return .traditionalChinese }
                return .simplifiedChinese
            }
            return .english
        case .simplifiedChinese: return .simplifiedChinese
        case .traditionalChinese: return .traditionalChinese
        case .english: return .english
        case .japanese: return .japanese
        case .korean: return .korean
        case .french: return .french
        case .spanish: return .spanish
        case .portuguese: return .portuguese
        case .russian: return .russian
        case .german: return .german
        }
    }

    /// 语言标签（用于系统 API）。
    var languageTag: String {
        switch effectiveLocale {
        case .english: return "en"
        case .simplifiedChinese: return "zh-Hans"
        case .traditionalChinese: return "zh-Hant"
        case .japanese: return "ja"
        case .korean: return "ko"
        case .french: return "fr"
        case .spanish: return "es"
        case .portuguese: return "pt"
        case .russian: return "ru"
        case .german: return "de"
        case .followSystem: return Foundation.Locale.preferredLanguages.first ?? "en"
        }
    }

    // MARK: - Translation Engine

    private var bundles: [String: [String: String]] = [:]

    private init() {
        loadAllBundles()
    }

    /// 加载所有语言 JSON 文件。
    private func loadAllBundles() {
        // 从 Bundle 中查找 L10n 目录
        let possibleDirs: [URL?] = [
            Bundle.main.resourceURL?.appendingPathComponent("L10n"),
            Bundle.module.resourceURL?.appendingPathComponent("L10n"),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/L10n"),
        ]

        guard let l10nDir = possibleDirs.compactMap({ $0 }).first(where: {
            (try? $0.checkResourceIsReachable()) ?? false
        }) else {
            loadFromFlatBundle()
            return
        }

        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: l10nDir, includingPropertiesForKeys: nil) else {
            loadFromFlatBundle()
            return
        }

        for file in files where file.pathExtension == "json" {
            let lang = file.deletingPathExtension().lastPathComponent
            if let data = try? Data(contentsOf: file),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
                bundles[lang] = dict
            }
        }
    }

    /// 回退：从 Bundle 根目录查找 L10n_*.json 文件。
    private func loadFromFlatBundle() {
        guard let resourceURL = Bundle.main.resourceURL else { return }
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: resourceURL, includingPropertiesForKeys: nil) else { return }

        for file in files {
            let name = file.lastPathComponent
            guard name.hasPrefix("L10n_"), name.hasSuffix(".json") else { continue }
            var lang = String(name.dropFirst(5)) // "L10n_" →
            lang = String(lang.dropLast(5))       // ".json"  ←
            if let data = try? Data(contentsOf: file),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
                bundles[lang] = dict
            }
        }
    }

    // MARK: - Public API

    /// 获取翻译字符串。
    func tr(_ key: String) -> String {
        let lang = effectiveLocale.languageTag
        if let bundle = bundles[lang], let value = bundle[key] {
            return value
        }
        // 回退到英语。
        if lang != "en", let enBundle = bundles["en"], let value = enBundle[key] {
            return value
        }
        // 最后回退��返回 key 自身。
        return key
    }
}
