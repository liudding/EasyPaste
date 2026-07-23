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

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.readIfChanged() }
        }
    }
    func stop() { timer?.invalidate() }

    private func readIfChanged() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        guard var item = makeItem() else { return }
        item.sourceApplication = NSWorkspace.shared.frontmostApplication?.localizedName
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

    func copy(_ item: ClipboardItem) {
        pasteboard.clearContents()
        switch item.kind {
        case .text: pasteboard.setString(item.text ?? "", forType: .string)
        case .link: pasteboard.setString(item.url?.absoluteString ?? item.text ?? "", forType: .string)
        case .image:
            if let data = item.imageData, let image = NSImage(data: data) { pasteboard.writeObjects([image]) }
        case .file: pasteboard.writeObjects((item.fileURLs ?? []).map { $0 as NSURL })
        }
        lastChangeCount = pasteboard.changeCount
    }

    func paste(_ item: ClipboardItem) {
        copy(item)
        guard ensureAccessibilityPermission() else { return }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        // If some other app is frontmost right now (e.g. paste was chosen from the
        // menu-bar menu, which never activates EasyPaste), that app is the target.
        // Otherwise fall back to the app that invoked the library window.
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
        // The system prompt only appears once per app identity (and ad-hoc signed
        // rebuilds get a new identity), so also surface our own guidance every
        // time — pasting must never fail silently.
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = "EasyPaste needs Accessibility access to paste into other apps. Enable EasyPaste in System Settings, then paste again. The clip is already on your clipboard, so ⌘V works manually too."
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
        return false
    }

    private func performPaste(into target: NSRunningApplication?) {
        NSApp.hide(nil)
        if let target, !target.isTerminated {
            target.activate(options: [.activateAllWindows])
        }
        waitForTargetFocus(target, attempts: 0)
    }

    /// Activation is asynchronous; poll until the target app is really frontmost
    /// (or give up after ~1s) before posting the keystroke.
    private func waitForTargetFocus(_ target: NSRunningApplication?, attempts: Int) {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let settled = target.map { frontmostPID == $0.processIdentifier } ?? (frontmostPID != nil && frontmostPID != ownPID)
        if settled || attempts >= 25 {
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
    }
}
