import AppKit
import Foundation

// MARK: - Sparkle Bridge

/// Sparkle 桥接：在 SwiftUI @main 生命周期中初始化 SPUUpdater，并用自定义 SPUUserDriver 接管全部 UI。
/// Sparkle 依赖 AppKit，更新器需在主线程创建与启动。
///
/// ⚠️ 此文件仅在 Xcode / SPM 构建中包含 Sparkle.framework 时编译（#if canImport(Sparkle)）。
///
/// 双源无感知分流：启动时异步探测「海外源（GitHub）」是否可达，
/// 可达 → 用海外 appcast；不可达（国内被墙/超时） → 回退国内 appcast（阿里云 OSS）。
/// 用户完全无感知，也无需任何手动设置。
///
/// 更新 UI 内联化：使用自定义 SPUUserDriver（UpdateUserDriver）接管全部 UI，
/// 检查中 / 下载进度 / 更新可用 等状态写入 SparkleUIState，由 SettingsView 内联渲染，
/// 不再弹出 Sparkle 原生独立窗口。

#if canImport(Sparkle)
import Sparkle

@MainActor
final class SparkleBridge: NSObject, SPUUpdaterDelegate {

    /// Sparkle 更新桥接单例
    static let shared = SparkleBridge()

    /// 内联更新状态，供 SettingsView 观察。
    let uiState = SparkleUIState()

    private let userDriver: UpdateUserDriver

    // MARK: - Feed 配置（部署时只需改这两项）

    /// 国内源：阿里云 OSS（建议开启 CDN 加速）。
    /// 请将 bucket / endpoint 替换为你的真实地址；appcast.xml 与 enclosure 的 .dmg 都部署在此，需国内网络可达。
    private let domesticFeedURL =
        URL(string: "https://easypaste-updates.oss-cn-hangzhou.aliyuncs.com/appcast.xml")!

    /// 海外源：GitHub Releases。Sparkle 会自动跟随 302 到最新 release 的 appcast.xml。
    /// enclosure 的 .dmg 即对应 release 资产，海外网络可达。
    private let internationalFeedURL =
        URL(string: "https://github.com/liudding/EasyPaste/releases/latest/download/appcast.xml")!

    /// 启动后解析出的 feed 地址（存 UserDefaults，每次启动重新探测，避免网络环境变化后状态过期）。
    private let feedChoiceKey = "sparkleResolvedFeedURL"

    private var started = false

    /// 直接用自定义 user driver 创建 SPUUpdater（SPUStandardUpdaterController 会忽略自定义 driver，故不能复用）。
    private(set) lazy var updater: SPUUpdater = {
        SPUUpdater(hostBundle: Bundle.main,
                   applicationBundle: Bundle.main,
                   userDriver: userDriver,
                   delegate: self)
    }()

    private override init() {
        userDriver = UpdateUserDriver(state: uiState)
        super.init()
        // 非阻塞地探测可达性，结果写入 UserDefaults；不依赖它来启动更新器。
        Task { [weak self] in
            await self?.probeAndResolveFeed()
        }
    }

    /// 启动更新器（首次检查或自动更新前必须调用一次）。
    func start() {
        guard !started else { return }
        started = true
        do {
            try updater.start()
        } catch {
            print("[Sparkle] failed to start updater: \(error.localizedDescription)")
        }
    }

    // MARK: - SPUUpdaterDelegate

    /// Sparkle 每次检查更新都会来问 feed 地址。
    /// 探测未完成前默认回退国内源（对国内用户最安全）。
    func feedURLString(for updater: SPUUpdater) -> String? {
        UserDefaults.standard.string(forKey: feedChoiceKey) ?? domesticFeedURL.absoluteString
    }

    // MARK: - 对外接口

    /// 触发“检查更新”操作（供 SwiftUI 菜单 / 设置调用）。
    /// 立即在内联状态中进入「检查中」，并请求打开「设置 → 更新」以展示状态。
    func checkForUpdates() {
        start()
        uiState.phase = .checking
        uiState.install = nil
        uiState.skip = nil
        uiState.dismiss = nil
        NotificationCenter.default.post(name: .revealUpdatesTab, object: nil)
        updater.checkForUpdates()
    }

    /// 是否在菜单栏显示“检查更新”按钮
    var showCheckForUpdatesInMenuBar: Bool {
        get { UserDefaults.standard.bool(forKey: "sparkleShowCheckForUpdates") }
        set { UserDefaults.standard.set(newValue, forKey: "sparkleShowCheckForUpdates") }
    }

    // MARK: - 可达性探测

    /// 轻量可达性探测：GET + Range 头（避免真正下载整文件），短超时。
    /// 用于判别「能否连上海外源」从而决定走国内/海外。
    private func probeAndResolveFeed() async {
        let reachable = await isReachable(internationalFeedURL, timeout: 3)
        let chosen = reachable ? internationalFeedURL : domesticFeedURL
        UserDefaults.standard.set(chosen.absoluteString, forKey: feedChoiceKey)
    }

    private func isReachable(_ url: URL, timeout: TimeInterval) async -> Bool {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse {
                return (200...399).contains(http.statusCode)
            }
        } catch {
            // 超时或连接失败（典型：国内连 GitHub 超时） → 视为不可达
        }
        return false
    }
}

#else

/// 当 Sparkle.framework 不可用时（理论上不会走此分支，Sparkle 已是 SPM 依赖），
/// 提供空实现，保证 SettingsView 仍可观察、不崩溃。
@MainActor
final class SparkleBridge {

    static let shared = SparkleBridge()

    let uiState = SparkleUIState()

    func checkForUpdates() {
        print("[Sparkle] Not available — build with Xcode to enable auto-updates.")
    }

    var showCheckForUpdatesInMenuBar: Bool {
        get { false }
        set {}
    }
}

#endif
