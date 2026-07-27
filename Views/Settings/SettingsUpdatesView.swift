import SwiftUI

// MARK: - Updates Settings

struct SettingsUpdatesView: View {
    /// 内联更新状态（检查中 / 下载进度 / 更新可用 等），由自定义 Sparkle user driver 写入。
    @ObservedObject private var updateState = SparkleBridge.shared.uiState

    var body: some View {
        Form {
            Section() {
                let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? L10n.unknownVersion
                let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? L10n.unknownVersion

                LabeledContent(L10n.currentVersion) { Text("\(version) (\(build))") }

                HStack {
                    Button(L10n.checkUpdatesButton) {
                        SparkleBridge.shared.checkForUpdates()
                    }
                    Spacer()
                    if updateState.phase == .checking {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text(L10n.checkingForUpdates).foregroundStyle(.secondary)
                        }
                    }
                }

                updateStatusInline

                if let result = updateState.resultMessage {
                    Label(result, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }

    
                // #if canImport(Sparkle)
                // LabeledContent(L10n.updateEngine) {
                //     Image(systemName: "checkmark.circle.fill")
                //         .foregroundStyle(.green)
                //     Text(L10n.updateEngineEnabled)
                // }
                // #else
                // LabeledContent(L10n.updateEngine) {
                //     Image(systemName: "exclamationmark.triangle.fill")
                //         .foregroundStyle(.orange)
                //     Text(L10n.updateEngineDevMode)
                // }
                // #endif
            }

            // Section(L10n.releaseNotesSection) {
            //     Text(L10n.releaseNotesPlaceholder)
            //         .font(.caption)
            //         .foregroundStyle(.secondary)
            // }

            // Section(L10n.updateConfigSection) {
            //     Text(L10n.updateConfigText)
            //         .font(.caption)
            //         .foregroundStyle(.secondary)
            //         .textSelection(.enabled)
            // }
        }
        .formStyle(.grouped)
        .alert(L10n.updateError, isPresented: Binding(
            get: { updateState.errorMessage != nil },
            set: { if !$0 { updateState.errorMessage = nil } }
        )) {
            Button(L10n.ok) { updateState.errorMessage = nil }
        } message: {
            Text(updateState.errorMessage ?? "")
        }
    }

    /// 检查 / 下载 / 可用 / 安装中 等瞬态更新状态的内联渲染（替代 Sparkle 原生独立窗口）。
    /// 终态结果（已是最新 / 出错）分别由 resultMessage / errorMessage 承载，不在本开关内。
    @ViewBuilder
    private var updateStatusInline: some View {
        switch updateState.phase {
        case .idle, .checking:
            EmptyView()
        case .updateAvailable(let version):
            VStack(alignment: .leading, spacing: 10) {
                Label(String(format: L10n.updateAvailable, version), systemImage: "arrow.down.circle.fill")
                    .foregroundStyle(.blue)
                HStack(spacing: 8) {
                    Button(L10n.updateNow) { updateState.install?() }
                        .controlSize(.small)
                    Button(L10n.skipThisVersion) { updateState.skip?() }
                        .controlSize(.small)
                    Button(L10n.remindLater) { updateState.dismiss?() }
                        .controlSize(.small)
                }
            }
        case .downloading(let progress):
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.downloadingUpdate).foregroundStyle(.secondary)
                ProgressView(value: progress).progressViewStyle(.linear)
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .installing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(L10n.installingUpdate).foregroundStyle(.secondary)
            }
        }
    }
}
