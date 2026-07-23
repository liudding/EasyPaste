import AppKit
@preconcurrency import ApplicationServices
import SwiftUI

struct ContentView: View {
    @Bindable var store: ClipboardStore
    let clipboard: ClipboardService
    @State private var selectedIDs = Set<UUID>()
    @FocusState private var focusedField: Field?
    private let columns = [GridItem(.adaptive(minimum: 180, maximum: 280), spacing: 14)]
    private enum Field: Hashable { case search }

    var body: some View {
        HStack(spacing: 0) {
            LibrarySidebar(store: store)
            VStack(spacing: 0) {
                header
                Divider().overlay(Color.white.opacity(0.08))
                ScrollView {
                    if store.filteredItems.isEmpty { emptyState }
                    else { LazyVGrid(columns: columns, spacing: 14) { ForEach(store.filteredItems) { item in ClipCard(item: item, selected: selectedIDs.contains(item.id), store: store, clipboard: clipboard).onTapGesture { toggleSelection(item.id) } } }.padding(22) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.09, green: 0.10, blue: 0.12))
        }
        .background(Color(red: 0.055, green: 0.06, blue: 0.075))
        .preferredColorScheme(.dark)
        .onAppear { focusSearch() }
        .onReceive(NotificationCenter.default.publisher(for: .easyPasteLibraryShown)) { _ in focusSearch() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.selectedBoardID.flatMap { id in store.boards.first(where: { $0.id == id })?.name } ?? (store.isFavoritesOnly ? "Favorites" : "Clipboard"))
                    .font(.title2.weight(.bold))
                Text("\(store.filteredItems.count) items saved locally").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            TextField("Search clipboard", text: $store.query)
                .textFieldStyle(.plain).padding(.horizontal, 12).padding(.vertical, 9)
                .frame(width: 240).background(.white.opacity(0.09), in: Capsule())
                .focused($focusedField, equals: .search)
            Button { if let item = store.filteredItems.first(where: { selectedIDs.contains($0.id) }) { clipboard.paste(item) } } label: { Label("Paste", systemImage: "arrow.down.doc.fill") }
                .buttonStyle(.borderedProminent).tint(.orange).disabled(selectedIDs.isEmpty)
            Menu { ForEach(store.boards) { board in Button(board.name) { selectedIDs.forEach { store.move($0, to: board.id) } } }; Divider(); Button("Remove from pinboard") { selectedIDs.forEach { store.move($0, to: nil) } } } label: { Image(systemName: "folder.badge.plus") }
                .disabled(selectedIDs.isEmpty)
        }
        .padding(.horizontal, 24).padding(.vertical, 18)
    }

    private var emptyState: some View { ContentUnavailableView("Your clipboard is ready", systemImage: "rectangle.on.rectangle", description: Text("Copy something in any app and it appears here instantly.")) .frame(maxWidth: .infinity).padding(.top, 180) }
    private func toggleSelection(_ id: UUID) { if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs = [id] } }
    private func focusSearch() { DispatchQueue.main.async { focusedField = .search } }
}

private struct LibrarySidebar: View {
    @Bindable var store: ClipboardStore
    @State private var newBoardName = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) { Image(systemName: "square.on.square").font(.title3.weight(.bold)).foregroundStyle(.orange); Text("EasyPaste").font(.headline.weight(.bold)) }.padding(.bottom, 20)
            SidebarButton("All clips", icon: "rectangle.stack", selected: store.selectedBoardID == nil && !store.isFavoritesOnly && store.selectedKind == nil) { store.selectedBoardID = nil; store.isFavoritesOnly = false; store.selectedKind = nil }
            SidebarButton("Favorites", icon: "star", selected: store.isFavoritesOnly) { store.selectedBoardID = nil; store.isFavoritesOnly = true; store.selectedKind = nil }
            Text("PINBOARDS").font(.caption2.weight(.bold)).foregroundStyle(.tertiary).padding(.top, 20).padding(.horizontal, 10)
            ForEach(store.boards) { board in SidebarButton(board.name, icon: "circle.fill", selected: store.selectedBoardID == board.id, tint: board.color == "blue" ? .blue : .orange) { store.selectedBoardID = board.id; store.isFavoritesOnly = false; store.selectedKind = nil } }
            Text("CONTENT TYPE").font(.caption2.weight(.bold)).foregroundStyle(.tertiary).padding(.top, 18).padding(.horizontal, 10)
            ForEach(ClipboardKind.allCases) { kind in SidebarButton(kind.title, icon: kind.symbol, selected: store.selectedKind == kind) { store.selectedKind = store.selectedKind == kind ? nil : kind; store.selectedBoardID = nil; store.isFavoritesOnly = false } }
            Spacer()
            HStack { TextField("New pinboard", text: $newBoardName).textFieldStyle(.plain); Button { guard !newBoardName.isEmpty else { return }; store.addBoard(named: newBoardName); newBoardName = "" } label: { Image(systemName: "plus.circle.fill") } }.padding(10).background(.white.opacity(0.07), in: .rect(cornerRadius: 8))
            Text("⌘⇧V  Open EasyPaste").font(.caption2).foregroundStyle(.tertiary).padding(.horizontal, 8)
        }
        .padding(18).frame(width: 205).background(Color(red: 0.055, green: 0.06, blue: 0.075))
    }
}

private struct SidebarButton: View {
    let title: String; let icon: String; let selected: Bool; var tint: Color = .secondary; let action: () -> Void
    init(_ title: String, icon: String, selected: Bool, tint: Color = .secondary, action: @escaping () -> Void) { self.title = title; self.icon = icon; self.selected = selected; self.tint = tint; self.action = action }
    var body: some View { Button(action: action) { Label(title, systemImage: icon).foregroundStyle(selected ? .white : .secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.vertical, 8).background(selected ? .white.opacity(0.12) : .clear, in: .rect(cornerRadius: 7)) }.buttonStyle(.plain).symbolRenderingMode(.hierarchical).tint(tint) }
}

private struct ClipCard: View {
    let item: ClipboardItem; let selected: Bool; let store: ClipboardStore; let clipboard: ClipboardService
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            preview.frame(maxWidth: .infinity, minHeight: 112)
            HStack { Label(item.kind.title, systemImage: item.kind.symbol).font(.caption.weight(.medium)).foregroundStyle(.secondary); Spacer(); Button { store.toggleFavorite(item.id) } label: { Image(systemName: item.isFavorite ? "star.fill" : "star") }.buttonStyle(.plain).foregroundStyle(item.isFavorite ? .yellow : .secondary) }
            Text(item.displayTitle).font(.subheadline.weight(.semibold)).lineLimit(2)
            HStack { Text(item.sourceApplication ?? "Clipboard").lineLimit(1); Spacer(); Text(item.createdAt, style: .relative) }.font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(12).background(selected ? Color.orange.opacity(0.28) : Color.white.opacity(0.07), in: .rect(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).stroke(selected ? .orange : .white.opacity(0.07), lineWidth: 1) }
        .contentShape(.rect).onTapGesture(count: 2) { clipboard.paste(item) }
        .contextMenu { Button("Copy") { clipboard.copy(item) }; Button("Paste") { clipboard.paste(item) }; Divider(); Button(item.isFavorite ? "Remove Favorite" : "Favorite") { store.toggleFavorite(item.id) }; Button("Delete", role: .destructive) { store.delete([item.id]) } }
    }
    @ViewBuilder private var preview: some View {
        if item.kind == .image, let data = item.imageData, let image = NSImage(data: data) { Image(nsImage: image).resizable().scaledToFill().clipShape(.rect(cornerRadius: 9)) }
        else if item.kind == .link { VStack(alignment: .leading, spacing: 7) { Image(systemName: "link").font(.title2).foregroundStyle(.orange); Text(item.url?.host ?? item.displayTitle).font(.caption.weight(.bold)); Text(item.url?.absoluteString ?? "").font(.caption2).foregroundStyle(.secondary).lineLimit(2) }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(.black.opacity(0.2), in: .rect(cornerRadius: 9)) }
        else { VStack(alignment: .leading) { Image(systemName: item.kind.symbol).foregroundStyle(.orange); Spacer(); Text(item.detail).font(.caption).lineLimit(4).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(.black.opacity(0.2), in: .rect(cornerRadius: 9)) }
    }
}

struct MenuBarView: View {
    let store: ClipboardStore; let clipboard: ClipboardService
    var body: some View { Button("Open EasyPaste") { AppDelegate.showLibrary() }; Divider(); ForEach(store.items.prefix(7)) { item in Button(String(item.displayTitle.prefix(30))) { clipboard.paste(item) } }; Divider(); Button("Quit EasyPaste") { NSApp.terminate(nil) } }
}

struct SettingsView: View {
    @Bindable var store: ClipboardStore
    @State private var name = ""; @State private var keyword = ""; @State private var app = ""; @State private var boardID: UUID?
    var body: some View {
        Form {
            Section("Clipboard") {
                Toggle("Save clipboard history", isOn: .constant(true)); Toggle("Capture images", isOn: .constant(true)); LabeledContent("Global shortcut") { Text("⌘⇧V").foregroundStyle(.secondary) }
                LabeledContent("Cross-app paste") { Text(AXIsProcessTrusted() ? "Permission granted" : "Permission required").foregroundStyle(AXIsProcessTrusted() ? .green : .orange) }
                if !AXIsProcessTrusted() { Button("Open Accessibility Settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!) } }
            }
            Section("Automatic classification") {
                Text("Matching clips are automatically placed in the chosen pinboard.").font(.caption).foregroundStyle(.secondary)
                ForEach(store.rules) { rule in HStack { Toggle(rule.name, isOn: Binding(get: { rule.enabled }, set: { _ in store.toggleRule(rule.id) })); Spacer(); Button(role: .destructive) { store.deleteRules([rule.id]) } label: { Image(systemName: "trash") } } }
                TextField("Rule name", text: $name); TextField("Contains keyword (optional)", text: $keyword); TextField("Source app (optional)", text: $app)
                Picker("Pinboard", selection: $boardID) { Text("No pinboard").tag(UUID?.none); ForEach(store.boards) { board in Text(board.name).tag(Optional(board.id)) } }
                Button("Add rule") { guard !name.isEmpty else { return }; store.addRule(AutomationRule(name: name, keyword: keyword, sourceApplication: app, targetBoardID: boardID)); name = ""; keyword = ""; app = ""; boardID = nil }
            }
        }.padding(24).frame(width: 480)
    }
}
