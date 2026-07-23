import AppKit
import SwiftUI

@main
struct EasyPasteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = ClipboardStore()
    @State private var clipboard = ClipboardService()
    @State private var shortcut = GlobalShortcutService()

    var body: some Scene {
        WindowGroup(id: "library") {
            ContentView(store: store, clipboard: clipboard)
                .task {
                    clipboard.onItem = { store.add($0) }
                    clipboard.start()
                    shortcut.registerDefaultShortcut { AppDelegate.showLibrary() }
                }
        }
        .defaultSize(width: 1_020, height: 680)
        .commands { PasteCommands(store: store, clipboard: clipboard) }

        MenuBarExtra("EasyPaste", systemImage: "clipboard") {
            MenuBarView(store: store, clipboard: clipboard)
        }
        Settings { SettingsView(store: store) }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static var invokingApplication: NSRunningApplication?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }
    static func showLibrary() {
        // Capture synchronously: by the next main-loop turn the hot-key handler may
        // already have made EasyPaste the frontmost application.
        let previousApplication = NSWorkspace.shared.frontmostApplication
        DispatchQueue.main.async {
            invokingApplication = previousApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : previousApplication
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first(where: { $0.canBecomeKey })?.makeKeyAndOrderFront(nil)
            NotificationCenter.default.post(name: .easyPasteLibraryShown, object: nil)
        }
    }

    static func returnToInvokingApplication() -> pid_t? {
        guard let invokingApplication else { return nil }
        NSApp.hide(nil)
        guard invokingApplication.activate(options: [.activateAllWindows]) else { return nil }
        return invokingApplication.processIdentifier
    }
}

extension Notification.Name {
    static let easyPasteLibraryShown = Notification.Name("easyPasteLibraryShown")
}

private struct PasteCommands: Commands {
    let store: ClipboardStore
    let clipboard: ClipboardService
    var body: some Commands {
        CommandMenu("Clipboard") {
            Button("Paste Most Recent") { if let item = store.filteredItems.first { clipboard.paste(item) } }
                .keyboardShortcut("v", modifiers: [.command, .shift])
            Button("Clear History") { store.delete(Set(store.items.map(\.id))) }
                .keyboardShortcut(.delete, modifiers: [.command, .option])
        }
    }
}
