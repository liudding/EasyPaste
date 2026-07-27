import Foundation
import SwiftUI

// MARK: - 设置导航请求

/// 跨视图的设置分区切换请求：例如用户发起「检查更新」时，需要把设置窗口切到 Updates 分区，
/// 以便内联展示检查 / 下载进度（替代 Sparkle 原生的独立窗口）。
@MainActor
final class SettingsNavigation: ObservableObject {
    static let shared = SettingsNavigation()

    /// 由外部请求切换到的设置分区（如 .updates）；视图消费后置空。
    @Published var pendingSection: SettingsSection?
}
