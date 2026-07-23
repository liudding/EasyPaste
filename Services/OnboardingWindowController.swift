import AppKit
import SwiftUI

/// 管理首次启动引导窗口：展示 OnboardingView，完成后标记 hasCompletedOnboarding。
@MainActor
final class OnboardingWindowController {
    private var window: NSWindow?

    func show(settings: AppSettings) {
        guard !settings.hasCompletedOnboarding else { return }

        let contentView = OnboardingView {
            settings.hasCompletedOnboarding = true
            self.dismiss()
        }

        let hostingView = NSHostingView(rootView: contentView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 440),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.center()
        window.contentView = hostingView
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.makeKeyAndOrderFront(nil)

        // 居中（考虑多屏幕）
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowFrame = window.frame
            let centerX = screenFrame.midX - windowFrame.width / 2
            let centerY = screenFrame.midY - windowFrame.height / 2
            window.setFrameOrigin(NSPoint(x: centerX, y: centerY))
        }

        self.window = window
    }

    private func dismiss() {
        window?.close()
        window = nil
    }
}
