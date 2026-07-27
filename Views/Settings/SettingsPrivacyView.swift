import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Privacy Settings

struct SettingsPrivacyView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section {
                if settings.ignoredApps.isEmpty {
                    Text(L10n.noIgnoredApps).foregroundStyle(.secondary)
                }
                ForEach(settings.ignoredApps) { app in
                    HStack(spacing: 8) {
                        Image(nsImage: icon(for: app.bundleID)).resizable().frame(width: 20, height: 20)
                        VStack(alignment: .leading) {
                            Text(app.name)
                            Text(app.bundleID).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { settings.ignoredApps.removeAll { $0.id == app.id } } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                        }.buttonStyle(.plain)
                    }
                }
                Button(L10n.addApp) { addIgnoredApp() }
            } header: {
                Text(L10n.ignoredAppsHeader)
            } footer: {
                Text(L10n.ignoredAppsFooter).font(.caption)
            }
        }
        .formStyle(.grouped)
    }

    private func icon(for bundleID: String) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
    }

    private func addIgnoredApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = L10n.selectAppDialogTitle
        if panel.runModal() == .OK, let url = panel.url, let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier {
            let name = bundle.infoDictionary?["CFBundleName"] as? String ?? url.deletingPathExtension().lastPathComponent
            if !settings.ignoredApps.contains(where: { $0.bundleID == bundleID }) {
                settings.ignoredApps.append(AppSettings.IgnoredApp(bundleID: bundleID, name: name))
            }
        }
    }
}
