import AppKit
import Foundation

// MARK: - Sparkle Bridge

/// Sparkle 桥接：在 SwiftUI @main 生命周期中初始化 SPUStandardUpdaterController。
/// Sparkle 依赖 AppKit，通过 SPUStandardUpdaterController 管理更新流程。
///
/// ⚠️ 此文件仅在 Xcode 构建中包含 Sparkle.framework 时编译。
/// SPM 命令行构建（swift build）使用 #if canImport(Sparkle) 条件编译跳过。

#if canImport(Sparkle)
import Sparkle

@MainActor
final class SparkleBridge {
    
    /// Sparkle 更新控制器（全局单例）
    static let shared = SparkleBridge()
    
    /// Sparkle 标准更新控制器
    private(set) lazy var updaterController: SPUStandardUpdaterController = {
        // startingUpdater: true → 启动时自动检查更新
        // updaterDelegate: nil → 使用默认行为
        // userDriverDelegate: nil → 使用标准 UI（对话框/菜单）
        return SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }()
    
    /// 触发"检查更新"操作（供 SwiftUI 菜单调用）
    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
    
    /// 是否在菜单栏显示"检查更新"按钮
    var showCheckForUpdatesInMenuBar: Bool {
        get { UserDefaults.standard.bool(forKey: "sparkleShowCheckForUpdates") }
        set { UserDefaults.standard.set(newValue, forKey: "sparkleShowCheckForUpdates") }
    }
}

#else

/// 当 Sparkle.framework 不可用时（SPM 命令行构建），提供空实现。
/// 实际构建和分发必须通过 Xcode，在 Xcode 中会添加 Sparkle SPM 依赖。
@MainActor
final class SparkleBridge {
    
    static let shared = SparkleBridge()
    
    /// 空实现：提示用户需要 Xcode 构建
    func checkForUpdates() {
        print("[Sparkle] Not available — build with Xcode to enable auto-updates.")
    }
    
    var showCheckForUpdatesInMenuBar: Bool {
        get { false }
        set {}
    }
}

#endif
