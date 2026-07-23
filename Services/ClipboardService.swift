import AppKit
@preconcurrency import ApplicationServices
import Carbon.HIToolbox
import Foundation

@MainActor
final class ClipboardService {
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var timer: Timer?
    var onItem: ((ClipboardItem) -> Void)?
    var settings: AppSettings?

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.readIfChanged() }
        }
    }
    func stop() { timer?.invalidate() }

    private func readIfChanged() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        let frontmost = NSWorkspace.shared.frontmostApplication
        if let bundleID = frontmost?.bundleIdentifier,
           settings?.ignoredApps.contains(where: { $0.bundleID == bundleID }) == true {
            return
        }
        guard var item = makeItem() else { return }
        item.sourceApplication = frontmost?.localizedName
        item.sourceApplicationBundleID = frontmost?.bundleIdentifier
        // 自动检测色值文本 → 重分类为 .colorValue
        if item.kind == .text && item.isColorValue {
            item.kind = .colorValue
        }
        onItem?(item)
    }

    private func makeItem() -> ClipboardItem? {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            return ClipboardItem(kind: .file, fileURLs: urls)
        }
        if let url = pasteboard.readObjects(forClasses: [NSURL.self], options: nil)?.first as? URL, url.scheme != "file" {
            return ClipboardItem(kind: .link, url: url)
        }
        if let image = NSImage(pasteboard: pasteboard), let data = image.tiffRepresentation, data.count < 12_000_000 {
            return ClipboardItem(kind: .image, imageData: data)
        }
        if let text = pasteboard.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ClipboardItem(kind: text.hasPrefix("http://") || text.hasPrefix("https://") ? .link : .text, text: text, url: URL(string: text))
        }
        return nil
    }

    func copy(_ item: ClipboardItem, plainText: Bool = false) {
        let plain = plainText || (settings?.alwaysPastePlainText ?? false)
        pasteboard.clearContents()
        if plain {
            switch item.kind {
            case .text: pasteboard.setString(item.text ?? "", forType: .string)
            case .link: pasteboard.setString(item.url?.absoluteString ?? item.text ?? "", forType: .string)
            case .file: pasteboard.setString((item.fileURLs ?? []).map(\.path).joined(separator: "\n"), forType: .string)
            case .image:
                if let data = item.imageData, let image = NSImage(data: data) { pasteboard.writeObjects([image]) }
            case .colorValue: pasteboard.setString(item.text ?? "", forType: .string)
            }
        } else {
            switch item.kind {
            case .text: pasteboard.setString(item.text ?? "", forType: .string)
            case .link: pasteboard.setString(item.url?.absoluteString ?? item.text ?? "", forType: .string)
            case .image:
                if let data = item.imageData, let image = NSImage(data: data) { pasteboard.writeObjects([image]) }
            case .file: pasteboard.writeObjects((item.fileURLs ?? []).map { $0 as NSURL })
            case .colorValue: pasteboard.setString(item.text ?? "", forType: .string)
            }
        }
        lastChangeCount = pasteboard.changeCount
    }

    func paste(_ item: ClipboardItem, plainText: Bool = false) {
        copy(item, plainText: plainText)
        guard ensureAccessibilityPermission() else { return }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let frontmost = NSWorkspace.shared.frontmostApplication
        let target: NSRunningApplication?
        if let frontmost, frontmost.processIdentifier != ownPID {
            target = frontmost
        } else {
            target = AppDelegate.invokingApplication
        }
        performPaste(into: target)
    }

    private func ensureAccessibilityPermission() -> Bool {
        if AXIsProcessTrusted() { return true }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        let alert = NSAlert()
        alert.messageText = "需要辅助功能权限"
        alert.informativeText = "EasyPaste 需要辅助功能权限才能把内容粘贴到其他应用。请在系统设置中启用 EasyPaste，然后再次粘贴。内容已写入剪贴板，也可手动按 ⌘V。"
        alert.addButton(withTitle: "打开设置")
        alert.addButton(withTitle: "稍后")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
        return false
    }

    private func performPaste(into target: NSRunningApplication?) {
        // 不再调用 NSApp.hide — 面板由 PanelController 在粘贴前同步 orderOut。
        // 此时 app 未激活（非激活面板），目标 app 仍是前台。
        if let target, !target.isTerminated {
            target.activate(options: [.activateAllWindows])
        }
        waitForTargetFocus(target, attempts: 0)
    }

    /// 轮询直到目标 app 真正前台 **且本 app 不再持有 key window**（面板已消失），
    /// 再发送 ⌘V。否则面板仍是 key window，按键会被面板吞掉。
    private func waitForTargetFocus(_ target: NSRunningApplication?, attempts: Int) {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let targetIsFrontmost = target.map { frontmostPID == $0.processIdentifier } ?? (frontmostPID != nil && frontmostPID != ownPID)
        let weAreNotKey = NSApp.keyWindow == nil
        if (targetIsFrontmost && weAreNotKey) || attempts >= 25 {
            postPasteKeystroke()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
            self?.waitForTargetFocus(target, attempts: attempts + 1)
        }
    }

    /// Post ⌘V through the HID event tap so it is indistinguishable from a real
    /// keystroke. `postToPid` bypasses the HID layer and is ignored by many apps.
    private func postPasteKeystroke() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyCode = CGKeyCode(kVK_ANSI_V)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
        if let name = settings?.soundName, !name.isEmpty {
            NSSound(named: NSSound.Name(name))?.play()
        }
    }
}
