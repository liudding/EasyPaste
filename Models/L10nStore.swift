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

    /// 语言标签（用于查找 JSON 文件键名）。
    var lookupTag: String {
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
        // 1) Bundle.module — SPM 构建下资源在 bundle 根目录（如 en.json）
        if let moduleURL = Bundle.module.resourceURL {
            loadJSONFiles(from: moduleURL)
            if !bundles.isEmpty { return }
        }

        // 2) Xcode 构建：查找 Contents/Resources/L10n/ 子目录
        let contentsResources = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources")
        let l10nDir = contentsResources.appendingPathComponent("L10n")
        if (try? l10nDir.checkResourceIsReachable()) ?? false {
            loadJSONFiles(from: l10nDir)
            if !bundles.isEmpty { return }
        }

        // 3) Xcode 构建：查找 Contents/Resources/ 下的 L10n_*.json 文件
        let l10nFlat = contentsResources
        if (try? l10nFlat.checkResourceIsReachable()) ?? false {
            loadFlatL10nFiles(from: l10nFlat)
            if !bundles.isEmpty { return }
        }

        // 4) 最终回退：Bundle.main.resourceURL 下直接加载所有 *.json（Xcode 构建时文件平铺在 Resources/ 根目录）
        if let resourceURL = Bundle.main.resourceURL {
            loadJSONFiles(from: resourceURL)
        }
    }

    /// 从指定目录加载所有 *.json 文件到 bundles 字典。
    /// key 使用文件名去掉 .json 后的部分（如 "zh-Hans"、"en"）。
    private func loadJSONFiles(from directory: URL) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else { return }

        for file in files where file.pathExtension == "json" {
            let fileName = file.deletingPathExtension().lastPathComponent
            // 跳过 Info.plist 等非翻译文件
            guard fileName != "Info" else { continue }
            if let data = try? Data(contentsOf: file),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
                bundles[fileName] = dict
            }
        }
    }

    /// 从指定目录加载 L10n_*.json 格式的文件（旧版兼容）。
    private func loadFlatL10nFiles(from directory: URL) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else { return }

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
        let lang = lookupTag

        // 1) 精确匹配当前语言
        if let bundle = bundles[lang], let value = bundle[key] {
            return value
        }

        // 2) 中文区域回退：zh-Hans → zh-Hant（或反向）
        if lang != "zh-Hans" && lang != "zh-Hant",
           let fallback = fallbackLanguage(for: lang),
           let fallbackBundle = bundles[fallback],
           let value = fallbackBundle[key] {
            return value
        }
        // 特判：zh-Hans 找不到时尝试 zh-Hant，反之亦然
        if lang == "zh-Hans" || lang == "zh-Hant" {
            let other = lang == "zh-Hans" ? "zh-Hant" : "zh-Hans"
            if let otherBundle = bundles[other], let value = otherBundle[key] {
                return value
            }
        }

        // 3) 回退到英语。
        if lang != "en", let enBundle = bundles["en"], let value = enBundle[key] {
            return value
        }

        // 4) 最后回退到返回 key 自身。
        return key
    }

    /// 为给定语言标签返回备用语言（如 "zh-CN" → "zh-Hans"）。
    private func fallbackLanguage(for tag: String) -> String? {
        // zh-CN / zh-SG → zh-Hans
        if tag.hasPrefix("zh-Hans") || tag == "zh-CN" || tag == "zh-SG" { return "zh-Hans" }
        // zh-TW / zh-HK / zh-MO → zh-Hant
        if tag.hasPrefix("zh-Hant") || tag == "zh-TW" || tag == "zh-HK" || tag == "zh-MO" { return "zh-Hant" }
        return nil
    }
}
