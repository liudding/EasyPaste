import AppKit
import SwiftUI

/// 管理「从屏幕边缘弹出的剪贴板面板」：非激活 NSPanel（不抢占前台应用），
/// 底部/顶部/左右定位 + 滑入滑出动画；点击面板外或 Esc 自动隐藏；
/// 键盘监控负责输入即搜索、回车粘贴、Shift+回车纯文本、空格预览、方向键选择、⌘C 拷贝。
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private final class KeyPanel: NSPanel {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
    }

    private let store: ClipboardStore
    private let clipboard: ClipboardService
    private let settings: AppSettings
    private let panelState: PanelState

    private var panel: KeyPanel?
    private var localKeyMonitor: Any?
    private var isAnimating = false
    private var hiding = false

    var isVisible: Bool { panel?.isVisible ?? false }

    init(store: ClipboardStore, clipboard: ClipboardService, settings: AppSettings, panelState: PanelState) {
        self.store = store
        self.clipboard = clipboard
        self.settings = settings
        self.panelState = panelState
        super.init()
        panelState.hidePanel = { [weak self] in self?.hide() }
    }

    func toggle() {
        if isVisible && !hiding { hide() } else { show() }
    }

    func show() {
        let panel = makePanel()
        hiding = false

        let frontmost = NSWorkspace.shared.frontmostApplication
        if let frontmost, frontmost.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            AppDelegate.invokingApplication = frontmost
            panelState.targetAppName = frontmost.localizedName
        } else {
            panelState.targetAppName = AppDelegate.invokingApplication?.localizedName
        }

        store.pruneExpired(limitDays: settings.historyLimitDays)
        if panelState.selectedID == nil || !store.filteredItems.contains(where: { $0.id == panelState.selectedID }) {
            panelState.selectedID = store.filteredItems.first?.id
        }

        let finalFrame = frameForPanel(on: currentScreen())

        stopMonitors()
        if isAnimating {
            panel.setFrame(finalFrame, display: true)
            panel.makeKeyAndOrderFront(nil)
        } else {
            let offscreen = offscreenFrame(for: finalFrame)
            panel.setFrame(offscreen, display: false)
            panel.makeKeyAndOrderFront(nil)
            isAnimating = true
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.26
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(finalFrame, display: true)
            } completionHandler: { [weak self] in
                self?.isAnimating = false
            }
        }
        startMonitors()
    }

    func hide() {
        guard let panel, panel.isVisible, !isAnimating else { return }
        stopMonitors()
        hiding = true
        isAnimating = true
        let offscreen = offscreenFrame(for: panel.frame)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(offscreen, display: true)
        } completionHandler: { [weak self] in
            guard let self else { return }
            if self.hiding { panel.orderOut(nil) }
            self.isAnimating = false
        }
        panelState.previewItem = nil
        panelState.renamingID = nil
        panelState.addingBoard = false
        store.query = ""
        panelState.searchExpanded = false
    }

    // MARK: - Layout

    private func currentScreen() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) { return screen }
        return NSScreen.main ?? (NSScreen.screens.first ?? NSScreen())
    }

    private func frameForPanel(on screen: NSScreen) -> NSRect {
        let frame = screen.visibleFrame
        let margin: CGFloat = 10
        switch settings.panelPosition {
        case .bottom:
            return NSRect(x: frame.minX + margin, y: frame.minY + margin,
                          width: frame.width - margin * 2, height: 250)
        case .top:
            return NSRect(x: frame.minX + margin, y: frame.maxY - 250 - margin,
                          width: frame.width - margin * 2, height: 250)
        case .left:
            return NSRect(x: frame.minX + margin, y: frame.minY + margin,
                          width: 340, height: frame.height - margin * 2)
        case .right:
            return NSRect(x: frame.maxX - 340 - margin, y: frame.minY + margin,
                          width: 340, height: frame.height - margin * 2)
        }
    }

    private func offscreenFrame(for frame: NSRect) -> NSRect {
        var off = frame
        switch settings.panelPosition {
        case .bottom: off.origin.y = frame.minY - frame.height - 40
        case .top: off.origin.y = frame.maxY + 40
        case .left: off.origin.x = frame.minX - frame.width - 40
        case .right: off.origin.x = frame.maxX + 40
        }
        return off
    }

    private func makePanel() -> KeyPanel {
        if let panel { return panel }
        let panel = KeyPanel(contentRect: .zero,
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = false
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: PanelView(store: store, clipboard: clipboard, settings: settings, panelState: panelState))
        self.panel = panel
        return panel
    }

    // MARK: - Auto-hide

    func windowDidResignKey(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self, let panel = self.panel, panel.isVisible else { return }
            // 右键菜单/系统菜单弹出时，key window 会切到菜单窗口——此时不隐藏。
            if let key = NSApp.keyWindow, key !== panel { return }
            self.hide()
        }
    }

    // MARK: - Keyboard

    private func startMonitors() {
        stopMonitors()
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyDown(event)
        }
    }

    private func stopMonitors() {
        if let m = localKeyMonitor { NSEvent.removeMonitor(m) }
        localKeyMonitor = nil
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        guard let panel, panel.isKeyWindow else { return event }
        let keyCode = event.keyCode
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if panelState.previewItem != nil {
            if keyCode == 49 || keyCode == 53 { withAnimation { panelState.previewItem = nil } }
            return nil
        }
        if panelState.renamingID != nil {
            if keyCode == 53 { panelState.renamingID = nil }
            return event
        }
        if panelState.addingBoard {
            if keyCode == 53 { panelState.addingBoard = false }
            return event
        }
        if keyCode == 53 {
            if panelState.searchExpanded { collapseSearch() } else { hide() }
            return nil
        }
        if panelState.searchFocused { return event }

        if matchesShortcut(event, settings.boardSwitchShortcut) {
            cycleBoard()
            return nil
        }
        if keyCode == 8, flags.contains(.command) {
            if let item = selectedItem { clipboard.copy(item) }
            return nil
        }

        switch keyCode {
        case 36, 76:
            if let item = selectedItem { paste(item, plain: flags.contains(.shift)) }
            return nil
        case 49:
            if let item = selectedItem { withAnimation { panelState.previewItem = item } }
            return nil
        case 123:
            moveSelection(-1); return nil
        case 124:
            moveSelection(1); return nil
        case 125:
            if settings.panelPosition.isVertical { moveSelection(1) }; return nil
        case 126:
            if settings.panelPosition.isVertical { moveSelection(-1) }; return nil
        default:
            break
        }

        let typingFlags = flags.intersection([.command, .option, .control, .function])
        if typingFlags.isEmpty, let characters = event.characters, !characters.isEmpty,
           characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) {
            expandSearch(with: characters)
            return nil
        }
        return event
    }

    private func matchesShortcut(_ event: NSEvent, _ shortcut: Shortcut) -> Bool {
        guard event.keyCode == shortcut.keyCode else { return false }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        return flags == NSEvent.ModifierFlags(rawValue: shortcut.modifierFlags).intersection([.command, .shift, .option, .control])
    }

    private func expandSearch(with characters: String) {
        withAnimation(.easeOut(duration: 0.15)) { panelState.searchExpanded = true }
        store.query += characters
        panelState.focusSearch()
    }

    private func collapseSearch() {
        store.query = ""
        withAnimation(.easeOut(duration: 0.15)) { panelState.searchExpanded = false }
    }

    private func cycleBoard() {
        let boards = store.boards
        let ids: [UUID?] = [nil] + boards.map { Optional($0.id) }
        let current = ids.firstIndex(where: { $0 == store.selectedBoardID }) ?? 0
        store.selectedBoardID = ids[(current + 1) % ids.count]
    }

    private func moveSelection(_ delta: Int) {
        let items = store.filteredItems
        guard !items.isEmpty else { return }
        let current = items.firstIndex(where: { $0.id == panelState.selectedID }) ?? 0
        let next = min(max(current + delta, 0), items.count - 1)
        panelState.selectedID = items[next].id
    }

    private var selectedItem: ClipboardItem? {
        let items = store.filteredItems
        if let id = panelState.selectedID, let item = items.first(where: { $0.id == id }) { return item }
        return items.first
    }

    private func paste(_ item: ClipboardItem, plain: Bool) {
        // 同步移除面板，让目标 app 的窗口重新成为 key window，
        // 否则非激活面板仍是 key，⌘V 会被面板吞掉。
        panel?.orderOut(nil)
        stopMonitors()
        panelState.previewItem = nil
        panelState.renamingID = nil
        panelState.addingBoard = false
        store.query = ""
        panelState.searchExpanded = false
        clipboard.paste(item, plainText: plain)
    }
}
