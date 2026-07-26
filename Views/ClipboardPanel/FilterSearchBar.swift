import SwiftUI

// MARK: - FlowLayout

/// 自动换行的流式布局，用于 filter chip 的 grid 排列。
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var height: CGFloat = 0
        var x: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                height += lineHeight + spacing
                x = 0
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        height += lineHeight
        return CGSize(width: min(maxX, maxWidth), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxX = bounds.maxX
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxX && x > bounds.minX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

// MARK: - FilterSearchBar

/// 富搜索栏：支持 filter tag、/ 快捷指令、关键词 suggestion、filter grid popover。
struct FilterSearchBar: View {
    @Bindable var store: ClipboardStore
    @Bindable var panelState: PanelState
    @FocusState.Binding var searchFocused: Bool
    var isVertical: Bool

    @State private var l10nStore = L10nStore.shared
    /// suggestion 列表中当前高亮的索引。
    @State private var suggestionIndex: Int? = nil
    /// backspace 选中的 tag 索引（再次 backspace 删除）。
    @State private var selectedTagIndex: Int? = nil

    // MARK: - Display Tags

    /// 所有展示为 tag 的筛选项：activeFilters + board tag (from selectedBoardID)。
    private var displayTags: [SearchFilter] {
        var tags = store.activeFilters
        if let boardID = store.selectedBoardID {
            tags.append(.board(boardID))
        }
        return tags
    }

    // MARK: - Suggestions

    /// 基于当前 query 匹配的筛选候选（按精确 > 前缀 > 包含排序，排除已激活项）。
    private var currentSuggestions: [SearchFilter] {
        let q = store.query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }

        var exact: [SearchFilter] = []
        var startsWith: [SearchFilter] = []
        var contains: [SearchFilter] = []

        func check(_ filter: SearchFilter, label: String) {
            let lower = label.lowercased()
            if lower == q { exact.append(filter) }
            else if lower.hasPrefix(q) { startsWith.append(filter) }
            else if lower.contains(q) { contains.append(filter) }
        }

        for kind in ClipKind.allCases { check(.kind(kind), label: kind.title) }
        for app in store.distinctSourceApps { check(.app(app), label: app) }
        for board in store.boards { check(.board(board.id), label: board.name) }
        for range in DateRange.allCases { check(.dateRange(range), label: range.label) }

        return (exact + startsWith + contains).filter { !isActive($0) }
    }

    private var clampedSuggestionIndex: Int? {
        guard let idx = suggestionIndex else { return nil }
        let count = currentSuggestions.count
        guard count > 0 else { return nil }
        return min(max(idx, 0), count - 1)
    }

    private func isActive(_ filter: SearchFilter) -> Bool {
        switch filter {
        case .board(let id): return store.selectedBoardID == id
        default: return store.activeFilters.contains(filter)
        }
    }

    // MARK: - Body

    var body: some View {
        let _ = l10nStore.version
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            ForEach(Array(displayTags.enumerated()), id: \.element.id) { idx, tag in
                FilterTagView(
                    filter: tag,
                    boards: store.boards,
                    isSelected: selectedTagIndex == idx,
                    onRemove: { removeFilter(tag) }
                )
                .transition(.scale.combined(with: .opacity))
            }

            searchTextField

            clearButton

            filterIconButton
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.primary.opacity(0.09), in: Capsule())
        .overlay(alignment: .topLeading) { suggestionOverlayLayer }
        .onChange(of: store.query) { _, _ in
            suggestionIndex = nil
            selectedTagIndex = nil
        }
        .onChange(of: store.activeFilters.count) { _, _ in
            selectedTagIndex = nil
        }
        .onChange(of: store.selectedBoardID) { _, _ in
            selectedTagIndex = nil
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var searchTextField: some View {
        TextField(L10n.searchPlaceholder, text: $store.query)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .focused($searchFocused)
            .focusEffectDisabled()
            .frame(minWidth: 30)
            .onKeyPress("/") {
                withAnimation(.easeOut(duration: 0.2)) {
                    panelState.filterGridPresented.toggle()
                }
                return .handled
            }
            .onKeyPress(.delete) {
                if store.query.isEmpty {
                    handleBackspaceForTags()
                    return .handled
                }
                return .ignored
            }
            .onKeyPress(.upArrow) {
                if !currentSuggestions.isEmpty {
                    navigateSuggestion(direction: -1)
                    return .handled
                }
                return .ignored
            }
            .onKeyPress(.downArrow) {
                if !currentSuggestions.isEmpty {
                    navigateSuggestion(direction: 1)
                    return .handled
                }
                return .ignored
            }
            .onKeyPress(.return) {
                if let idx = clampedSuggestionIndex, idx < currentSuggestions.count {
                    applyFilter(currentSuggestions[idx])
                    store.query = ""
                    return .handled
                }
                return .ignored
            }
            .onKeyPress(.escape) {
                if panelState.filterGridPresented {
                    panelState.filterGridPresented = false
                } else if !store.query.isEmpty {
                    store.query = ""
                } else if !store.activeFilters.isEmpty || store.selectedBoardID != nil {
                    clearAll()
                } else {
                    return .ignored
                }
                return .handled
            }
    }

    @ViewBuilder
    private var clearButton: some View {
        if !store.query.isEmpty || !displayTags.isEmpty {
            Button {
                clearAll()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
        }
    }

    @ViewBuilder
    private var filterIconButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) {
                panelState.filterGridPresented.toggle()
            }
        } label: {
            Image(systemName: panelState.filterGridPresented
                   ? "line.3.horizontal.decrease.circle.fill"
                   : "line.3.horizontal.decrease")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(panelState.filterGridPresented ? .primary : .secondary)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
    }

    @ViewBuilder
    private var suggestionOverlayLayer: some View {
        if !panelState.filterGridPresented && !currentSuggestions.isEmpty {
            SuggestionOverlay(
                suggestions: currentSuggestions,
                selectedIndex: clampedSuggestionIndex,
                boards: store.boards,
                onSelect: { filter in
                    applyFilter(filter)
                    store.query = ""
                }
            )
            .offset(y: 34)
            .zIndex(10)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    // MARK: - Actions

    private func applyFilter(_ filter: SearchFilter) {
        switch filter {
        case .board(let id):
            store.selectedBoardID = (store.selectedBoardID == id) ? nil : id
        default:
            if let idx = store.activeFilters.firstIndex(of: filter) {
                store.activeFilters.remove(at: idx)
            } else {
                store.activeFilters.append(filter)
            }
        }
        selectedTagIndex = nil
    }

    private func removeFilter(_ filter: SearchFilter) {
        store.removeFilter(filter)
        selectedTagIndex = nil
    }

    private func clearAll() {
        store.query = ""
        store.clearAllFilters()
        selectedTagIndex = nil
    }

    /// 文本为空时按 backspace：首次选中最后一个 tag，再次删除。
    private func handleBackspaceForTags() {
        if let idx = selectedTagIndex, idx < displayTags.count {
            let tag = displayTags[idx]
            removeFilter(tag)
            selectedTagIndex = nil
        } else if !displayTags.isEmpty {
            withAnimation(.easeOut(duration: 0.12)) {
                selectedTagIndex = displayTags.count - 1
            }
        }
    }

    private func navigateSuggestion(direction: Int) {
        let count = currentSuggestions.count
        guard count > 0 else { return }
        if let idx = suggestionIndex {
            suggestionIndex = (idx + direction + count) % count
        } else {
            suggestionIndex = direction > 0 ? 0 : count - 1
        }
    }
}

// MARK: - Filter Tag View (搜索栏内的 chip)

private struct FilterTagView: View {
    let filter: SearchFilter
    let boards: [Pasteboard]
    let isSelected: Bool
    let onRemove: () -> Void

    @State private var isHovered = false

    private var label: String { filter.resolveLabel(boards: boards) }
    private var icon: String { filter.resolveIcon(boards: boards) }
    private var color: Color { filter.resolveColor(boards: boards) ?? .secondary }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
            Button(action: onRemove) {
                Image(systemName: isSelected ? "xmark.circle.fill" : "xmark")
                    .font(.system(size: isSelected ? 10 : 8, weight: .bold))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .frame(width: 12, height: 12)
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(color.opacity(isSelected ? 0.35 : (isHovered ? 0.25 : 0.18)))
        )
        .overlay(
            Capsule().stroke(color.opacity(isSelected ? 0.9 : 0.4), lineWidth: 0.8)
        )
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }
}

// MARK: - Suggestion Overlay (关键词推荐下拉)

private struct SuggestionOverlay: View {
    let suggestions: [SearchFilter]
    let selectedIndex: Int?
    let boards: [Pasteboard]
    let onSelect: (SearchFilter) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(suggestions.prefix(8).enumerated()), id: \.element.id) { idx, filter in
                HStack(spacing: 8) {
                    Image(systemName: filter.resolveIcon(boards: boards))
                        .font(.system(size: 11))
                        .foregroundStyle(filter.resolveColor(boards: boards) ?? .secondary)
                        .frame(width: 16)
                    Text(filter.resolveLabel(boards: boards))
                        .font(.system(size: 12))
                        .lineLimit(1)
                    Spacer()
                    Text(filter.categoryLabel)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(idx == selectedIndex ? Color.accentColor.opacity(0.2) : .clear)
                )
                .contentShape(Rectangle())
                .onTapGesture { onSelect(filter) }
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: 260)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.primary.opacity(0.12)))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
    }
}

// MARK: - Filter Grid Overlay (/ 或 filter icon 触发的分组面板)

struct FilterGridOverlay: View {
    @Bindable var store: ClipboardStore
    let onToggle: (SearchFilter) -> Void
    let onClear: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Clear all
                if !store.activeFilters.isEmpty || store.selectedBoardID != nil {
                    HStack {
                        Spacer()
                        Button(action: onClear) {
                            HStack(spacing: 3) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 10))
                                Text(L10n.tr("filter.clear_all"))
                                    .font(.system(size: 11))
                            }
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.bottom, 2)
                }

                // Type group
                FilterGroup(title: L10n.tr("filter.group.type")) {
                    FlowLayout(spacing: 6) {
                        ForEach(ClipKind.allCases) { kind in
                            FilterChipButton(
                                label: kind.title,
                                icon: kind.symbol,
                                color: kind.defaultColor,
                                isActive: store.activeFilters.contains(.kind(kind)),
                                action: { onToggle(.kind(kind)) }
                            )
                        }
                    }
                }

                // App group
                if !store.distinctSourceApps.isEmpty {
                    FilterGroup(title: L10n.tr("filter.group.app")) {
                        FlowLayout(spacing: 6) {
                            ForEach(store.distinctSourceApps, id: \.self) { app in
                                FilterChipButton(
                                    label: app,
                                    icon: "app",
                                    color: nil,
                                    isActive: store.activeFilters.contains(.app(app)),
                                    action: { onToggle(.app(app)) }
                                )
                            }
                        }
                    }
                }

                // Pinboard group
                if !store.boards.isEmpty {
                    FilterGroup(title: L10n.tr("filter.group.pinboard")) {
                        FlowLayout(spacing: 6) {
                            ForEach(store.boards) { board in
                                FilterChipButton(
                                    label: board.name,
                                    icon: "pin.fill",
                                    color: board.swiftUIColor,
                                    isActive: store.selectedBoardID == board.id,
                                    action: { onToggle(.board(board.id)) }
                                )
                            }
                        }
                    }
                }

                // Date group
                FilterGroup(title: L10n.tr("filter.group.date")) {
                    FlowLayout(spacing: 6) {
                        ForEach(DateRange.allCases) { range in
                            FilterChipButton(
                                label: range.label,
                                icon: "calendar",
                                color: nil,
                                isActive: store.activeFilters.contains(.dateRange(range)),
                                action: { onToggle(.dateRange(range)) }
                            )
                        }
                    }
                }
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.primary.opacity(0.12)))
        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
    }
}

// MARK: - Filter Chip Button (grid 内的单个筛选项)

private struct FilterChipButton: View {
    let label: String
    let icon: String
    let color: Color?
    let isActive: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let color {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                        .foregroundStyle(color)
                }
                Text(label)
                    .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                    .lineLimit(1)
                if isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(color ?? .accentColor)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(
                    isActive ? (color ?? Color.accentColor).opacity(0.22)
                    : (isHovered ? .primary.opacity(0.1) : .primary.opacity(0.06))
                )
            )
            .overlay(
                Capsule().stroke(
                    isActive ? (color ?? Color.accentColor).opacity(0.6) : .clear,
                    lineWidth: 1
                )
            )
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { isHovered = $0 }
    }
}

// MARK: - Filter Group (分组标题 + 内容)

private struct FilterGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content
        }
    }
}
