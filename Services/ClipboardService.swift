import AppKit
@preconcurrency import ApplicationServices
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
        guard requestAccessibilityIfNeeded() else { return }
        let targetProcess = AppDelegate.returnToInvokingApplication()
        let delay: TimeInterval = targetProcess == nil ? 0 : 0.35
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.sendPasteKeystroke(to: targetProcess) }
    }

    private func requestAccessibilityIfNeeded() -> Bool {
        if AXIsProcessTrusted() { return true }
        let preferenceKey = "hasRequestedAccessibilityPermission"
        guard !UserDefaults.standard.bool(forKey: preferenceKey) else { return false }
        UserDefaults.standard.set(true, forKey: preferenceKey)
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        return false
    }

    private func sendPasteKeystroke(to processIdentifier: pid_t?) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        down?.flags = .maskCommand; up?.flags = .maskCommand
        if let processIdentifier {
            down?.postToPid(processIdentifier)
            up?.postToPid(processIdentifier)
        } else {
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
        }
    }
}
