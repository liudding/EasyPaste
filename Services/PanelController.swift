import AppKit
import Carbon
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
    private let clipAction: ClipActionService

    private var panel: KeyPanel?
    private var localKeyMonitor: Any?
    private var isAnimating = false
    private var hiding = false

    /// 打开设置窗口的回调（由 AppServices 注入：自己托管的 NSWindow）。
    var openSettingsHandler: ((NSScreen?) -> Void)?

    var isVisible: Bool { panel?.isVisible ?? false }

    init(store: ClipboardStore, clipboard: ClipboardService, settings: AppSettings, panelState: PanelState, clipAction: ClipActionService) {
        self.store = store
        self.clipboard = clipboard
        self.settings = settings
        self.panelState = panelState
        self.clipAction = clipAction
        super.init()
        panelState.hidePanel = { [weak self] in self?.hide() }
    }

    func toggle() {
        if isVisible && !hiding { hide() } else { show() }
    }

    /// 预建面板与其 SwiftUI 视图树（离屏、不显示），并触发一次布局。
    /// 提前编译 `.ultraThinMaterial` 着色器、构建头部视图图与 NSHostingView，
    /// 使首次真实唤起时 `makePanel()` 直接返回已建好的面板，只做定位 + 滑入动画。
    ///
    /// 不调用 `orderFront`，因此 `panel.isVisible` 仍为 false，`toggle()`/`show()`
    /// 的可见性判断不受影响；`windowDidResignKey` 也只对「曾成为 key」的窗口触发，
    /// 从未成为 key 的预建面板不会误触发自动隐藏。
    func prewarm() {
        let panel = makePanel()
        // 用真实面板尺寸的离屏 frame 触发 SwiftUI 首次布局（origin 在 .zero 即可，
        // 因为不会 orderFront，不会出现在屏幕上）。
        let size = frameForPanel(on: currentScreen()).size
        panel.setFrame(NSRect(origin: .zero, size: size), display: false)
        panel.contentView?.layoutSubtreeIfNeeded()
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
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(finalFrame, display: true)
            } completionHandler: { [weak self] in
                Task { @MainActor in
                    self?.isAnimating = false
                }
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
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(offscreen, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.hiding { panel.orderOut(nil) }
                self.isAnimating = false
            }
        }
        panelState.previewItem = nil
        panelState.qrCodeContent = nil
        panelState.jsonPreviewItem = nil
        panelState.renamingID = nil
        panelState.addingBoard = false
        store.query = ""
        panelState.searchExpanded = false
    }

    // MARK: - Layout

    /// 面板 edge 位置变更时实时重定位窗口。
    /// - 面板可见且无进行中动画：带短动画过渡到新 edge 的 final frame；
    /// - 面板不可见（含已预建但未显示）：静默对齐到新 frame，下次 show() 自然落到正确位置。
    /// 不处理滑入/滑出（offscreenFrame）——只在已显示时做 final frame 的就地迁移，
    /// 避免与 show()/hide() 的滑入滑出动画冲突。
    func reposition() {
        guard let panel else { return }
        let finalFrame = frameForPanel(on: currentScreen())
        if panel.isVisible && !isAnimating {
            isAnimating = true
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(finalFrame, display: true)
            } completionHandler: { [weak self] in
                Task { @MainActor in self?.isAnimating = false }
            }
        } else if !panel.isVisible {
            panel.setFrame(finalFrame, display: false)
        }
        // 正在动画中（show/hide 滑入滑出）：跳过，show()/hide() 会以新 position 的 frame 结束/开始。
    }

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
        let hostingView = NSHostingView(rootView: PanelView(store: store, clipboard: clipboard, clipAction: clipAction, settings: settings, panelState: panelState, onOpenSettings: { [weak self] in
            self?.openSettingsFromPanel()
        }))
        // NSHostingView 默认绘制不透明灰色背景，会在面板 8pt 透明 padding 区可见 → 设为透明
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear
        panel.contentView = hostingView
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
        // QR 码浮层：Esc/空格关闭
        if panelState.qrCodeContent != nil {
            if keyCode == 49 || keyCode == 53 { withAnimation { panelState.qrCodeContent = nil } }
            return nil
        }
        // JSON 预览浮层：Esc/空格关闭
        if panelState.jsonPreviewItem != nil {
            if keyCode == 49 || keyCode == 53 { withAnimation { panelState.jsonPreviewItem = nil } }
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

        // 检查上下文菜单快捷键（当面板可见且无浮层弹出时）
        if handleContextMenuShortcut(event, flags: flags) {
            return nil
        }

        if matchesShortcut(event, settings.boardSwitchShortcut) {
            cycleBoard(direction: 1)
            return nil
        }
        // Tab / Shift+Tab 切换看板（仅无 command/option/control 修饰键时拦截）
        if settings.tabSwitchBoardEnabled && keyCode == 48 {
            let tabFlags = flags.intersection([.command, .option, .control])
            if tabFlags.isEmpty {
                cycleBoard(direction: flags.contains(.shift) ? -1 : 1)
                return nil
            }
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
    
    /// 处理上下文菜单快捷键。如果匹配成功则执行相应操作并返回 true。
    private func handleContextMenuShortcut(_ event: NSEvent, flags: NSEvent.ModifierFlags) -> Bool {
        guard let item = selectedItem else { return false }
        
        // 跳过系统保留快捷键
        let systemReservedKeys: [UInt16] = [
            UInt16(kVK_ANSI_Q), UInt16(kVK_ANSI_W), UInt16(kVK_ANSI_Z), UInt16(kVK_ANSI_A)
        ]
        if systemReservedKeys.contains(event.keyCode) {
            let sysFlags: NSEvent.ModifierFlags = [.command]
            if flags.contains(sysFlags) { return false }
        }
        
        // 跳过面板切换快捷键
        if matchesShortcut(event, settings.invokeShortcut) || matchesShortcut(event, settings.boardSwitchShortcut) {
            return false
        }
        
        let currentShortcut = Shortcut(keyCode: event.keyCode, modifierFlags: flags.rawValue)
        
        // 遍历所有配置的上下文菜单快捷键，查找匹配项
        for (actionID, config) in settings.contextMenuShortcuts where config.enabled {
            if let shortcut = config.shortcut, matchesShortcut(currentShortcut, shortcut) {
                executeAction(actionID: actionID, item: item, flags: flags)
                return true
            }
        }
        
        return false
    }
    
    /// 根据 actionID 执行对应的操作。
    private func executeAction(actionID: String, item: Clip, flags: NSEvent.ModifierFlags) {
        switch actionID {
        case "paste":
            paste(item, plain: false)
        case "paste_plain":
            paste(item, plain: true)
        case "copy":
            clipboard.copy(item)
        case "rename":
            panelState.renamingID = item.id
        case "preview":
            withAnimation { panelState.previewItem = item }
        case "delete":
            store.delete([item.id])
        case "export_txt":
            clipAction.exportAsText(item)
        case "export_rtf":
            clipAction.exportAsRTF(item)
        case "save_as":
            clipAction.exportAsImage(item)
        case "qr_code":
            if let text = item.text, !text.isEmpty {
                withAnimation { panelState.qrCodeContent = text }
            } else if let url = item.url?.absoluteString {
                withAnimation { panelState.qrCodeContent = url }
            }
        case "send_email":
            if let text = item.text {
                clipAction.sendEmail(to: text)
            }
        case "json_preview":
            if !(item.text?.isEmpty ?? true) {
                withAnimation { panelState.jsonPreviewItem = item }
            }
        case "open_link":
            if let url = item.url {
                clipAction.openURL(url)
            }
        default:
            break
        }
    }

    private func matchesShortcut(_ event: NSEvent, _ shortcut: Shortcut) -> Bool {
        guard event.keyCode == shortcut.keyCode else { return false }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        return flags == NSEvent.ModifierFlags(rawValue: shortcut.modifierFlags).intersection([.command, .shift, .option, .control])
    }
    
    /// 比较两个 Shortcut 是否相同。
    private func matchesShortcut(_ a: Shortcut, _ b: Shortcut) -> Bool {
        a.keyCode == b.keyCode && a.modifierFlags == b.modifierFlags
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

    private func cycleBoard(direction: Int = 1) {
        let boards = store.boards
        let ids: [UUID?] = [nil] + boards.map { Optional($0.id) }
        let current = ids.firstIndex(where: { $0 == store.selectedBoardID }) ?? 0
        let next = (current + direction + ids.count) % ids.count
        store.selectedBoardID = ids[next]
        // 切换看板后重置选中 clip 为当前看板下第一个
        panelState.selectedID = store.filteredItems.first?.id
    }

    private func moveSelection(_ delta: Int) {
        let items = store.filteredItems
        guard !items.isEmpty else { return }
        let current = items.firstIndex(where: { $0.id == panelState.selectedID }) ?? 0
        let next = min(max(current + delta, 0), items.count - 1)
        panelState.selectedID = items[next].id
    }

    private var selectedItem: Clip? {
        let items = store.filteredItems
        if let id = panelState.selectedID, let item = items.first(where: { $0.id == id }) { return item }
        return items.first
    }

    /// 立即移除浮动面板：无动画、不受 `isAnimating` 早返回限制，
    /// 确保它不会以 `.floating` 层级覆盖普通层级的设置窗口。
    private func forceHidePanel() {
        stopMonitors()
        hiding = false
        isAnimating = false
        panel?.orderOut(nil)
        panelState.previewItem = nil
        panelState.qrCodeContent = nil
        panelState.jsonPreviewItem = nil
        panelState.renamingID = nil
        panelState.addingBoard = false
        store.query = ""
        panelState.searchExpanded = false
    }

    private func openSettingsFromPanel() {
        // 隐藏 Dock 时不强制恢复 .regular，保持 .accessory
        if !settings.hideDockIcon { NSApp.setActivationPolicy(.regular) }
        // 在隐藏面板前先记录面板当前所在屏幕（此时面板仍可见，screen 可靠）。
        // 设置窗口应出现在“唤起它的面板”所在屏幕，而不是主屏——用面板屏幕最确定。
        let screen = self.panel?.screen
        // 立即移除浮动面板，避免 .floating 层级遮挡设置窗口。
        forceHidePanel()
        // 先激活 app，再触发设置窗口。
        NSApp.activate(ignoringOtherApps: true)
        // 窗口呈现交由 AppServices 自己托管的 NSWindow 完成：
        // 不依赖 macOS 14+ 已移除的 showSettingsWindow: 选择器，
        // 也不依赖需在 SwiftUI 场景内捕获、对“只用快捷键唤起面板”的用户为 nil 的 openSettings 环境动作。
        openSettingsHandler?(screen)
    }

    private func paste(_ item: Clip, plain: Bool) {
        // 同步移除面板，让目标 app 的窗口重新成为 key window，
        // 否则非激活面板仍是 key，⌘V 会被面板吞掉。
        panel?.orderOut(nil)
        stopMonitors()
        panelState.previewItem = nil
        panelState.qrCodeContent = nil
        panelState.jsonPreviewItem = nil
        panelState.renamingID = nil
        panelState.addingBoard = false
        store.query = ""
        panelState.searchExpanded = false
        clipboard.paste(item, plainText: plain)
    }
}
