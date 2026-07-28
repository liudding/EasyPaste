import AppKit
import CryptoKit
import Foundation

// MARK: - Appcast Installer（PasteMemo 风格的安装方式）

/// 替代 Sparkle 自带的「下载 → 解压 → 安装 → 重启」流程。
///
/// 我们保留 Sparkle / AppCast 只用于「检查更新」（拿 enclosure 里的 .dmg 地址），
/// 真正的安装改用 PasteMemo 同款方案：
///   1. 自己下载 .dmg（带进度 / 可选 SHA-256 校验）；
///   2. 用 `hdiutil attach` 挂载；
///   3. 把新 .app 的 `Contents/{MacOS,Resources}`、`Info.plist`、所有 `*.bundle`
///      复制到当前运行中的 app bundle 上；
///   4. 退出 App，由一个 detached bash 脚本延时 `detach` 并 `open` 新 app，
///      即「重启 App 才完成安装」。
///
/// 之所以要「重启才装」：App 正在运行时无法稳定替换自身可执行文件，
/// 先把新文件摆好，退出后由外部脚本完成解挂与重新拉起，最稳妥。
///
/// ⚠️ 依赖：app 必须**未沙盒化**（本项目 entitlements 无 App Sandbox），
/// 否则无法写入 `/Applications` 下的自身 bundle。
@MainActor
final class AppcastInstaller: ObservableObject {

    static let shared = AppcastInstaller()

    @Published var isDownloading = false
    @Published var progress: Double = 0
    @Published var downloadedBytes: Int64 = 0
    @Published var totalBytes: Int64 = 0
    @Published var downloadComplete = false
    @Published var downloadedFileURL: URL?

    private var downloadTask: URLSessionDownloadTask?
    private var downloadDelegate: DownloadDelegate?

    private init() {}

    // MARK: - 下载

    /// 下载指定 DMG。完成 / 失败通过 completion 回调，UI 由调用方根据 `downloadComplete` 切换。
    func download(_ url: URL,
                  expectedSHA256: String? = nil,
                  completion: @escaping @Sendable (Result<URL, Error>) -> Void) {
        guard !isDownloading else { return }

        isDownloading = true
        progress = 0
        downloadedBytes = 0
        totalBytes = 0
        downloadComplete = false
        downloadedFileURL = nil

        let delegate = DownloadDelegate(
            expectedSHA256: expectedSHA256,
            onProgress: { [weak self] p, received, total in
                Task { @MainActor in
                    self?.progress = p
                    self?.downloadedBytes = received
                    self?.totalBytes = total
                }
            },
            onComplete: { [weak self] fileURL in
                Task { @MainActor in
                    self?.downloadComplete = true
                    self?.downloadedFileURL = fileURL
                    self?.isDownloading = false
                    completion(.success(fileURL))
                }
            },
            onError: { [weak self] message in
                Task { @MainActor in
                    self?.isDownloading = false
                    self?.downloadComplete = false
                    self?.progress = 0
                    completion(.failure(NSError(domain: "AppcastInstaller",
                                                code: -1,
                                                userInfo: [NSLocalizedDescriptionKey: message])))
                }
            }
        )
        self.downloadDelegate = delegate

        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        downloadTask = session.downloadTask(with: url)
        downloadTask?.resume()
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        isDownloading = false
        progress = 0
        downloadComplete = false
        downloadedFileURL = nil
    }

    // MARK: - 安装（挂载 → 复制 → 重启）

    /// 把已下载的 DMG 挂载，把新 .app 复制覆盖当前运行实例，随后退出并由脚本重启。
    /// 该过程会**终止当前进程**，调用前请确保用户已确认。
    func installAndRestart() {
        guard let fileURL = downloadedFileURL else { return }

        let mountPoint = mountDMG(at: fileURL.path)
        guard let mountPoint else {
            showDMGErrorAlert()
            return
        }

        let sourceApp = "\(mountPoint)/EasyPaste.app"
        guard FileManager.default.fileExists(atPath: sourceApp) else {
            detachDMG(mountPoint)
            showDMGErrorAlert()
            return
        }

        let destApp = Bundle.main.bundlePath
        let script = """
        #!/bin/bash
        sleep 2
        # 只替换内部内容，保留 app bundle 身份（辅助功能授权等不被重置）。
        rm -rf "\(destApp)/Contents/MacOS"
        rm -rf "\(destApp)/Contents/Resources"
        rm -rf "\(destApp)"/*.bundle
        cp -R "\(sourceApp)/Contents/MacOS" "\(destApp)/Contents/MacOS"
        cp -R "\(sourceApp)/Contents/Resources" "\(destApp)/Contents/Resources"
        cp "\(sourceApp)/Contents/Info.plist" "\(destApp)/Contents/Info.plist"
        for b in "\(sourceApp)"/*.bundle; do
            [ -d "$b" ] && cp -R "$b" "\(destApp)/"
        done
        hdiutil detach "\(mountPoint)" -quiet 2>/dev/null
        open "\(destApp)"
        rm -f "$0"
        """

        do {
            let scriptPath = NSTemporaryDirectory() + "easypaste_update.sh"
            try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [scriptPath]
            try process.run()

            // 先让脚本开始执行（sleep 2 后才会写文件），再终止自身。
            // 终止后新实例由脚本 open 拉起，完成「重启安装」。
            NSApp.terminate(nil)
        } catch {
            detachDMG(mountPoint)
            NSWorkspace.shared.open(fileURL)
        }
    }

    // MARK: - hdiutil

    private func mountDMG(at path: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["attach", path, "-nobrowse", "-noverify"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do { try process.run() } catch { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard let line = output.components(separatedBy: "\n").first(where: { $0.contains("/Volumes/") }),
              let range = line.range(of: "/Volumes/") else { return nil }
        return String(line[range.lowerBound...]).trimmingCharacters(in: .whitespaces)
    }

    private func detachDMG(_ mountPoint: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["detach", mountPoint, "-quiet"]
        try? process.run()
        process.waitUntilExit()
    }

    // MARK: - 提示

    private func showDMGErrorAlert() {
        let alert = NSAlert()
        alert.messageText = L10n.updateError
        alert.informativeText = L10n.updateDmgError
        alert.alertStyle = .critical
        alert.addButton(withTitle: L10n.ok)
        alert.runModal()
    }
}

// MARK: - 下载代理

/// 与 UpdateChecker 中的 DownloadDelegate 同款：下载完成后做字节数 + 可选 SHA-256 校验。
final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, Sendable {
    let expectedSHA256: String?
    let onProgress: @Sendable (Double, Int64, Int64) -> Void
    let onComplete: @Sendable (URL) -> Void
    let onError: @Sendable (String) -> Void

    init(
        expectedSHA256: String? = nil,
        onProgress: @escaping @Sendable (Double, Int64, Int64) -> Void,
        onComplete: @escaping @Sendable (URL) -> Void,
        onError: @escaping @Sendable (String) -> Void
    ) {
        self.expectedSHA256 = expectedSHA256
        self.onProgress = onProgress
        self.onComplete = onComplete
        self.onError = onError
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("EasyPaste-update.dmg")
        try? FileManager.default.removeItem(at: dest)

        do {
            try FileManager.default.moveItem(at: location, to: dest)
        } catch {
            do {
                try FileManager.default.copyItem(at: location, to: dest)
            } catch {
                onError("Download incomplete")
                return
            }
        }

        if let attrs = try? FileManager.default.attributesOfItem(atPath: dest.path),
           let fileSize = attrs[.size] as? Int64,
           let response = downloadTask.response as? HTTPURLResponse,
           response.expectedContentLength > 0,
           fileSize != response.expectedContentLength {
            try? FileManager.default.removeItem(at: dest)
            onError("Download incomplete")
            return
        }

        if let expected = expectedSHA256?.lowercased(), !expected.isEmpty {
            guard let data = try? Data(contentsOf: dest) else {
                try? FileManager.default.removeItem(at: dest)
                onError("Download incomplete")
                return
            }
            let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            if actual != expected {
                try? FileManager.default.removeItem(at: dest)
                onError("Download incomplete")
                return
            }
        }

        onComplete(dest)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : 1
        let progress = Double(totalBytesWritten) / Double(total)
        onProgress(progress, totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        if let error {
            onError(error.localizedDescription)
        }
    }
}
