import KeyPathCore
import SwiftUI

/// Visual keyboard selection grid component with illustrations, organized by category
struct KeyboardSelectionGridView: View {
    @Binding var selectedLayoutId: String
    let isDark: Bool
    /// Optional category to scroll to when the view appears or changes
    @Binding var scrollToCategory: LayoutCategory?
    @State private var showImportSheet = false
    @State private var refreshTrigger = UUID() // Trigger refresh when custom layouts change

    /// Whether QMK keyboard search is enabled (off by default)
    @AppStorage(LayoutPreferences.qmkSearchEnabledKey) private var qmkSearchEnabled = false

    /// Track whether initial scroll has happened to prevent repeated scrolling
    @State private var hasScrolledToInitialSelection = false

    // Search state
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    @State private var searchKeyboards: [KeyboardMetadata] = []
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var searchTask: Task<Void, Never>?

    /// Grouped layouts by category (computed to reflect custom layout changes)
    private var groupedLayouts: [(category: LayoutCategory, layouts: [PhysicalLayout])] {
        PhysicalLayout.layoutsByCategory()
    }

    // Grid layout: 1 column for single-row keyboard previews
    private let columns = [
        GridItem(.flexible(), spacing: 12)
    ]

    /// Initialize with automatically grouped layouts
    init(selectedLayoutId: Binding<String>, isDark: Bool, scrollToCategory: Binding<LayoutCategory?> = .constant(nil)) {
        _selectedLayoutId = selectedLayoutId
        self.isDark = isDark
        _scrollToCategory = scrollToCategory
        _refreshTrigger = State(initialValue: UUID())
    }

    /// Initialize with a flat list of layouts (legacy, for previews)
    /// Note: This initializer is deprecated - use the main init instead
    init(layouts _: [PhysicalLayout], selectedLayoutId: Binding<String>, isDark: Bool) {
        _selectedLayoutId = selectedLayoutId
        self.isDark = isDark
        _scrollToCategory = .constant(nil)
        _refreshTrigger = State(initialValue: UUID())
        // Note: groupedLayouts is now computed, so layouts parameter is ignored
        // This init exists only for preview compatibility
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar at the top (only when QMK search is enabled in settings)
            if qmkSearchEnabled {
                searchBar
            }

            // Content: search results or layout grid
            if qmkSearchEnabled, !searchText.isEmpty {
                searchResultsView
                    .id(refreshTrigger) // Only refresh search results
            } else {
                layoutGridView
            }
        }
        .sheet(isPresented: $showImportSheet) {
            QMKImportSheet(
                selectedLayoutId: $selectedLayoutId,
                onImportComplete: {
                    // Refresh the view after import
                    refreshTrigger = UUID()
                }
            )
        }
        .onChange(of: searchText) { _, newValue in
            // Cancel previous search task
            searchTask?.cancel()

            // Debounce search
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
                if !Task.isCancelled {
                    await performSearch(query: newValue)
                }
            }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 11))

            TextField("Search keyboards...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .font(.caption)
                .focused($isSearchFocused)
                .accessibilityIdentifier("qmk-search-field")
                .accessibilityLabel("Search keyboards")
                .frame(maxWidth: .infinity) // Ensure TextField expands

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("qmk-search-clear-button")
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Search Results View

    private var searchResultsView: some View {
        Group {
            if isSearching {
                VStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Searching...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = searchError {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if searchKeyboards.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No keyboards found matching '\(searchText)'")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(searchKeyboards) { keyboard in
                            SearchKeyboardRow(
                                keyboard: keyboard,
                                onSelect: {
                                    importKeyboard(keyboard)
                                }
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - Layout Grid View

    private var layoutGridView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(groupedLayouts.filter { $0.category == .custom || !$0.layouts.isEmpty }, id: \.category.id) { group in
                        LayoutCategorySection(
                            category: group.category,
                            layouts: group.layouts,
                            selectedLayoutId: $selectedLayoutId,
                            isDark: isDark,
                            showImportSheet: $showImportSheet,
                            refreshTrigger: $refreshTrigger
                        )
                        .id(group.category.id)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
            .onChange(of: scrollToCategory) { _, newCategory in
                if let category = newCategory {
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(500))
                        withAnimation(.easeInOut(duration: 0.5)) {
                            proxy.scrollTo(category.id, anchor: .top)
                        }
                    }
                }
            }
            .onAppear {
                // Scroll to selected layout only on initial appear (not on re-renders)
                guard !hasScrolledToInitialSelection else { return }
                hasScrolledToInitialSelection = true

                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(100))
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo("layout-\(selectedLayoutId)", anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Search Actions

    private func performSearch(query: String) async {
        isSearching = true
        searchError = nil

        do {
            let results = try await QMKKeyboardDatabase.shared.searchKeyboards(query)
            await MainActor.run {
                searchKeyboards = results
                isSearching = false
            }
        } catch {
            await MainActor.run {
                searchError = error.localizedDescription
                isSearching = false
                searchKeyboards = []
            }
        }
    }

    private func importKeyboard(_ keyboard: KeyboardMetadata) {
        Task {
            do {
                // Fetch JSON data first
                let (jsonData, response) = try await URLSession.shared.data(from: keyboard.infoJsonURL)

                guard let httpResponse = response as? HTTPURLResponse,
                      (200 ... 299).contains(httpResponse.statusCode)
                else {
                    throw QMKImportError.networkError("Failed to fetch keyboard JSON")
                }

                // Import using QMKImportService
                let layout = try await QMKImportService.shared.importFromURL(
                    keyboard.infoJsonURL,
                    layoutVariant: nil,
                    keyMappingType: .ansi
                )

                // Generate a user-friendly name
                let layoutName = "\(keyboard.name)\(keyboard.manufacturer.map { " by \($0)" } ?? "")"

                // Save as custom layout
                await QMKImportService.shared.saveCustomLayout(
                    layout: layout,
                    name: layoutName,
                    sourceURL: keyboard.infoJsonURL.absoluteString,
                    layoutJSON: jsonData,
                    layoutVariant: nil
                )

                await MainActor.run {
                    // Select the imported layout
                    selectedLayoutId = layout.id
                    // Clear search
                    searchText = ""
                    // Refresh the view
                    refreshTrigger = UUID()
                }
            } catch {
                await MainActor.run {
                    searchError = "Failed to import keyboard: \(error.localizedDescription)"
                }
            }
        }
    }
}

/// A section with a category header and its layouts
private struct LayoutCategorySection: View {
    let category: LayoutCategory
    let layouts: [PhysicalLayout]
    @Binding var selectedLayoutId: String
    let isDark: Bool
    @Binding var showImportSheet: Bool
    @Binding var refreshTrigger: UUID

    private let columns = [
        GridItem(.flexible(), spacing: 12)
    ]

    /// Whether to show section header (US Standard has no header)
    private var showHeader: Bool {
        category != .usStandard
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header (hidden for US Standard)
            if showHeader {
                HStack {
                    Text(category.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.7))
                        .textCase(.uppercase)
                        .tracking(0.8)

                    Spacer()

                    // Import button for Custom section
                    if category == .custom {
                        Button {
                            showImportSheet = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 10))
                                Text("Import")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("import-custom-layout-button")
                    }
                }
                .padding(.leading, 4)
                .padding(.trailing, 4)
                .padding(.top, 8)
            }

            // Layout cards in grid
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(layouts) { layout in
                    KeyboardIllustrationCard(
                        layout: layout,
                        isSelected: selectedLayoutId == layout.id,
                        isDark: isDark,
                        isCustom: layout.id.hasPrefix("custom-")
                    ) {
                        // No animation on selection - keeps drawer stable
                        selectedLayoutId = layout.id
                    } onDelete: {
                        if layout.id.hasPrefix("custom-") {
                            Task {
                                let layoutId = String(layout.id.dropFirst(7))
                                await QMKImportService.shared.deleteCustomLayout(layoutId: layoutId)
                                // If deleted layout was selected, reset to default
                                if selectedLayoutId == layout.id {
                                    selectedLayoutId = LayoutPreferences.defaultLayoutId
                                }
                                // Trigger refresh to update UI
                                refreshTrigger = UUID()
                            }
                        }
                    }
                    .id("layout-\(layout.id)")
                }

                // Import button card for Custom section (if no layouts yet)
                if category == .custom, layouts.isEmpty {
                    ImportLayoutCard(isDark: isDark) {
                        showImportSheet = true
                    }
                }
            }
        }
    }
}

/// Individual keyboard illustration card with image and label
private struct KeyboardIllustrationCard: View {
    let layout: PhysicalLayout
    let isSelected: Bool
    let isDark: Bool
    let isCustom: Bool
    let onSelect: () -> Void
    let onDelete: (() -> Void)?

    @State private var isHovering = false
    @State private var showDeleteConfirmation = false

    // Image size - fairly big as requested
    private let imageHeight: CGFloat = 120

    init(
        layout: PhysicalLayout,
        isSelected: Bool,
        isDark: Bool,
        isCustom: Bool = false,
        onSelect: @escaping () -> Void,
        onDelete: (() -> Void)? = nil
    ) {
        self.layout = layout
        self.isSelected = isSelected
        self.isDark = isDark
        self.isCustom = isCustom
        self.onSelect = onSelect
        self.onDelete = onDelete
    }

    var body: some View {
        Button(action: {
            // Haptic feedback
            let generator = NSHapticFeedbackManager.defaultPerformer
            generator.perform(.alignment, performanceTime: .default)

            onSelect()
        }) {
            VStack(spacing: 8) {
                // Keyboard illustration - fixed height, horizontally centered
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(cardBackground)
                        .shadow(
                            color: shadowColor,
                            radius: shadowRadius,
                            x: 0,
                            y: shadowY
                        )

                    // Selection ring overlay
                    if isSelected {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 2)
                    }

                    keyboardImage
                        .frame(maxHeight: imageHeight)
                        .padding(12)
                }
                .frame(height: imageHeight + 24)

                // Label - centered below image, supports multi-line for long names
                Text(layout.name)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("overlay-keyboard-layout-button-\(layout.id)")
        .accessibilityLabel("Select keyboard layout \(layout.name)")
        .onHover { hovering in
            // Animate only hover state, not scale - avoids layout shifts
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        // No scale "pop" animation on selection - keeps drawer stable
        // Selection ring and shadow changes provide sufficient visual feedback
        .contextMenu {
            if isCustom, onDelete != nil {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete Layout", systemImage: "trash")
                }
                .accessibilityIdentifier("delete-custom-layout-button")
            }
        }
        .confirmationDialog(
            "Delete Layout",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                onDelete?()
            }
            .accessibilityIdentifier("overlay-keyboard-layout-delete-confirm")
            Button("Cancel", role: .cancel) {}
                .accessibilityIdentifier("overlay-keyboard-layout-delete-cancel")
        } message: {
            Text("Are you sure you want to delete \"\(layout.name)\"? This action cannot be undone.")
        }
    }

    // MARK: - Computed Animation Properties

    private var shadowColor: Color {
        if isSelected {
            Color.accentColor.opacity(0.4)
        } else if isHovering {
            Color.black.opacity(0.15)
        } else {
            Color.black.opacity(0.08)
        }
    }

    private var shadowRadius: CGFloat {
        if isSelected {
            10
        } else if isHovering {
            6
        } else {
            4
        }
    }

    private var shadowY: CGFloat {
        if isSelected {
            5
        } else if isHovering {
            3
        } else {
            2
        }
    }

    @ViewBuilder
    private var keyboardImage: some View {
        // Images are at bundle root (not in subdirectory) due to .process() flattening
        // Same pattern as SVG loading in LiveKeyboardOverlayView
        let imageURL = Bundle.module.url(
            forResource: layout.id,
            withExtension: "png"
        ) ?? Bundle.main.url(
            forResource: layout.id,
            withExtension: "png"
        )

        if let url = imageURL,
           let image = NSImage(contentsOf: url)
        {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        } else {
            // Fallback to SF Symbol
            Image(systemName: "keyboard")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
        }
    }

    private var cardBackground: some ShapeStyle {
        if isSelected {
            AnyShapeStyle(
                Color.accentColor.opacity(isDark ? 0.25 : 0.18)
            )
        } else if isHovering {
            AnyShapeStyle(
                Color.white.opacity(isDark ? 0.12 : 0.10)
            )
        } else {
            AnyShapeStyle(
                Color.white.opacity(isDark ? 0.06 : 0.05)
            )
        }
    }
}

/// Card for importing a custom layout (shown when Custom section is empty)
private struct ImportLayoutCard: View {
    let isDark: Bool
    let onImport: () -> Void

    @State private var isHovering = false

    private let imageHeight: CGFloat = 120

    var body: some View {
        Button(action: onImport) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(cardBackground)
                        .shadow(
                            color: shadowColor,
                            radius: shadowRadius,
                            x: 0,
                            y: shadowY
                        )

                    VStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                        Text("Import Layout")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(height: imageHeight)
                }
                .frame(height: imageHeight + 24)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("import-layout-card")
        .accessibilityLabel("Import custom keyboard layout")
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }

    private var shadowColor: Color {
        isHovering ? Color.black.opacity(0.15) : Color.black.opacity(0.08)
    }

    private var shadowRadius: CGFloat {
        isHovering ? 6 : 4
    }

    private var shadowY: CGFloat {
        isHovering ? 3 : 2
    }

    private var cardBackground: some ShapeStyle {
        AnyShapeStyle(
            Color.white.opacity(isDark ? (isHovering ? 0.12 : 0.06) : (isHovering ? 0.10 : 0.05))
        )
    }
}

#Preview("Grouped Layouts") {
    KeyboardSelectionGridView(
        selectedLayoutId: .constant(LayoutPreferences.defaultLayoutId),
        isDark: false
    )
    .frame(width: 400, height: 800)
}

// MARK: - Search Keyboard Row Component

private struct SearchKeyboardRow: View {
    let keyboard: KeyboardMetadata
    let onSelect: () -> Void

    private var accessibilityLabel: String {
        var parts: [String] = [keyboard.name, "keyboard"]
        if let manufacturer = keyboard.manufacturer {
            parts.append("by \(manufacturer)")
        }
        if !keyboard.tags.isEmpty {
            parts.append(keyboard.tags.prefix(3).joined(separator: " "))
        }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(keyboard.name)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)

                    if let manufacturer = keyboard.manufacturer {
                        Text(manufacturer)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Tags
                HStack(spacing: 4) {
                    ForEach(keyboard.tags.prefix(3), id: \.self) { tag in
                        SearchTagBadge(tag: tag, keyboardId: keyboard.id)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("qmk-search-keyboard-row-\(keyboard.id)")
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - Search Tag Badge Component

private struct SearchTagBadge: View {
    let tag: String
    let keyboardId: String

    var body: some View {
        Text(tag)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tagColor.opacity(0.15))
            .foregroundColor(tagColor)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .accessibilityIdentifier("qmk-search-tag-\(tag)-\(keyboardId)")
            .accessibilityLabel("\(tag) keyboard")
    }

    private var tagColor: Color {
        switch tag.lowercased() {
        case "split": .blue
        case "rgb", "rgb_matrix": .purple
        case "ortho": .green
        case "oled": .orange
        default: .secondary
        }
    }
}

#Preview("Dark Mode") {
    KeyboardSelectionGridView(
        selectedLayoutId: .constant("macbook-iso"),
        isDark: true
    )
    .frame(width: 400, height: 800)
    .background(Color.black.opacity(0.8))
}

#Preview("Legacy Initializer") {
    KeyboardSelectionGridView(
        layouts: Array(PhysicalLayout.all.prefix(6)),
        selectedLayoutId: .constant(LayoutPreferences.defaultLayoutId),
        isDark: false
    )
    .frame(width: 400, height: 600)
}
