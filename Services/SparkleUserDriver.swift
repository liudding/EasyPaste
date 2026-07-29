import AppKit
import Foundation

// MARK: - 更新 UI 状态（供 SwiftUI 内联渲染）

/// 更新流程的 UI 状态机。由自定义 SPUUserDriver 写入，SettingsView 读取并内联渲染，
/// 从而完全替代 Sparkle 默认的标准窗口（检查中 / 下载进度 / 更新可用 等）。
///
/// 设计要点：
/// - `phase` 只承载**瞬态** UI（检查中 / 下载中 / 安装中 / 有可用更新）。这些会在
///   `dismissUpdateInstallation` 时被清回 `.idle`。
/// - `errorMessage` / `resultMessage` 承载**终态结果**（出错 / 未找到更新）。
///   它们与瞬态解耦，不会被 `dismissUpdateInstallation` 清除，必须等用户显式关闭，
///   因此不会出现「报错一闪即逝」的问题；错误以 alert 形式持续展示。
@MainActor
final class SparkleUIState: ObservableObject {
    enum Phase: Equatable {
        case idle
        case checking
        case updateAvailable(version: String)
        case downloading(Double)   // 0...1
        case downloaded            // DMG 已下载，等待用户「重启并安装」
        case installing            // 已退出、等待新实例接管
    }

    @Published var phase: Phase = .idle

    /// 出错信息（弹 alert，需用户关闭）。
    @Published var errorMessage: String?

    /// 良性结果信息（如「已是最新版本」），内联展示，需用户关闭或下次检查覆盖。
    @Published var resultMessage: String?

    /// 当展示「有可用更新」时，由 user driver 注入的用户操作回调。
    /// `install` = 开始下载 DMG。
    /// `restartAndInstall` = DMG 下载完成后，执行「挂载 → 复制 → 重启 App」。
    var install: (() -> Void)?
    var restartAndInstall: (() -> Void)?
    var skip: (() -> Void)?
    var dismiss: (() -> Void)?

    /// 仅重置瞬态 UI（phase 与操作回调），不清空终态的 errorMessage / resultMessage。
    func reset() {
        phase = .idle
        install = nil
        restartAndInstall = nil
        skip = nil
        dismiss = nil
    }

    /// 一次新的检查开始时，清掉上一次残留的终态信息。
    func beginNewCheck() {
        reset()
        errorMessage = nil
        resultMessage = nil
    }
}

#if canImport(Sparkle)
import Sparkle

// MARK: - 自定义 User Driver

/// 接管 Sparkle 的全部 UI：不弹出任何独立窗口，全部转写为 SparkleUIState 供内联展示。
///
/// 注意：SPUUserDriver 是 NS_SWIFT_UI_ACTOR 协议，所有回调都在主线程，因此本类标记为 @MainActor。
@MainActor
final class UpdateUserDriver: NSObject, SPUUserDriver {
    private weak var state: SparkleUIState?

    init(state: SparkleUIState) {
        self.state = state
        super.init()
    }

    // MARK: 权限请求（首次启动）

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        // 内联模式不做交互，直接授予「自动检查」权限（不发系统画像）。
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
    }

    // MARK: 用户发起的检查

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        state?.beginNewCheck()
        state?.phase = .checking
    }

    // MARK: 发现更新

    func showUpdateFound(with appcastItem: SUAppcastItem,
                         state: SPUUserUpdateState,
                         reply: @escaping (SPUUserUpdateChoice) -> Void) {
        let version = appcastItem.displayVersionString
        self.state?.phase = .updateAvailable(version: version)

        // enclosure 指向的 .dmg 地址（AppCast 只用于「检查更新」，安装我们自己来）。
        let downloadURL = appcastItem.fileURL

        self.state?.install = { [weak self] in
            guard let self else { return }
            // 释放 Sparkle 的更新会话：我们不再走 Sparkle 的「下载 → 安装」，
            // 而是自己下载 DMG 后用「挂载 → 复制 → 重启」安装。
            reply(.dismiss)
            self.state?.reset()
            self.beginLocalDownload(downloadURL: downloadURL)
        }
        self.state?.skip = {
            reply(.skip)
            self.state?.reset()
        }
        self.state?.dismiss = {
            reply(.dismiss)
            self.state?.reset()
        }
        // 确保「设置 → 更新」内联卡片可见（用户才能点击安装 / 跳过）。
        NotificationCenter.default.post(name: .revealUpdatesTab, object: nil)
    }

    // MARK: 本地下载 + 安装（替代 Sparkle 自带安装）

    private func beginLocalDownload(downloadURL: URL?) {
        guard let downloadURL else {
            self.state?.errorMessage = L10n.updateDownloadFailed
            return
        }
        let installer = AppcastInstaller.shared
        self.state?.phase = .downloading(0)
        installer.download(downloadURL) { [weak self] result in
            guard let self else { return }
            Task { @MainActor in
                switch result {
                case .success:
                    // 下载完成：展示「重启并安装」按钮，由用户确认后再替换 + 重启。
                    self.state?.phase = .downloaded
                    self.state?.restartAndInstall = {
                        AppcastInstaller.shared.installAndRestart()
                    }
                case .failure(let error):
                    self.state?.reset()
                    self.state?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
        // 内联模式不单独展示发布说明窗口。
    }

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {
        // 忽略；不影响更新流程。
    }

    // MARK: 未找到更新 / 错误

    func showUpdateNotFoundWithError(_ error: Error) async {
        NSLog("[Sparkle] showUpdateNotFoundWithError: \(error.localizedDescription)")
        // 检查结束：复位瞬态 phase（停止 spinner），保留 resultMessage 内联展示「已是最新」。
        state?.reset()
        state?.resultMessage = error.localizedDescription
    }

    func showUpdaterError(_ error: Error) async {
        NSLog("[Sparkle] showUpdaterError: \(error.localizedDescription)")
        // 检查结束：复位瞬态 phase（停止 spinner），errorMessage 由 SettingsView 弹 alert 呈现。
        state?.reset()
        state?.errorMessage = error.localizedDescription
    }

    // MARK: 下载进度（已由 AppcastInstaller 接管，这里忽略 Sparkle 自带的下载事件）

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        // 本地下载由 AppcastInstaller 驱动，忽略 Sparkle 的下载回调。
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        // 忽略。
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        // 忽略。
    }

    func showDownloadDidStartExtractingUpdate() {
        // 忽略。
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        // 忽略。
    }

    // MARK: 安装（已由 AppcastInstaller.installAndRestart 接管）

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        // 安装不再走 Sparkle：直接放行，避免 Sparkle 尝试下载/替换自身而失败。
        reply(.dismiss)
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool,
                              retryTerminatingApplication: @escaping () -> Void) {
        // 忽略：真正的重启由 AppcastInstaller 完成。
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool) async {
        state?.reset()
    }

    func dismissUpdateInstallation() {
        // 若已转入本地下载 / 安装流程，不要清掉进度 UI，
        // 否则 Sparkle 结束更新会话时会把「下载中」卡片误清掉。
        if case .downloading = state?.phase { return }
        if case .downloaded = state?.phase { return }
        if case .installing = state?.phase { return }
        // 仅清瞬态 UI；终态的 errorMessage / resultMessage 保留（由用户关闭后才清除）。
        state?.reset()
    }

    // MARK: 可选：聚焦

    func showUpdateInFocus() {
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - 通知

extension Notification.Name {
    /// 请求将「设置」窗口打开并切换到 Updates 分区（用于展示内联更新状态）。
    static let revealUpdatesTab = Notification.Name("EasyPaste.revealUpdatesTab")
}

#endif
