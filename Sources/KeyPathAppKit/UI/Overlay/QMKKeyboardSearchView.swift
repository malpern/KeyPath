import KeyPathCore
import SwiftUI

/// Popover view for searching and importing QMK keyboards
struct QMKKeyboardSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedLayoutId: String
    var onImportComplete: (() -> Void)?

    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    @State private var keyboards: [KeyboardMetadata] = []
    @State private var isLoading = false
    @State private var selectedIndex: Int?
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            searchField

            Divider()

            // Results list
            if isLoading {
                loadingView
            } else if let error = errorMessage {
                errorView(error)
            } else if keyboards.isEmpty {
                emptyStateView
            } else {
                keyboardListView
            }

            // Status bar
            if !keyboards.isEmpty {
                statusBar
            }
        }
        .frame(width: 500, height: 450)
        .onAppear {
            AppLogger.shared.info("🔍 [QMKSearch] Popover appeared, starting initial load...")
            // Auto-focus search field
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isSearchFocused = true
            }
            // Load initial list
            Task {
                AppLogger.shared.info("🔍 [QMKSearch] Task started for initial load")
                await performSearch(query: "")
            }
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
        .onKeyPress(.upArrow) {
            if let current = selectedIndex, current > 0 {
                selectedIndex = current - 1
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.downArrow) {
            if let current = selectedIndex {
                if current < keyboards.count - 1 {
                    selectedIndex = current + 1
                }
            } else if !keyboards.isEmpty {
                selectedIndex = 0
            }
            return .handled
        }
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
        .onKeyPress(.return) {
            if let index = selectedIndex, index < keyboards.count {
                importKeyboard(keyboards[index])
            }
            return .handled
        }
        .focusable()
    }

    // MARK: - Search Field

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 13))

            TextField("Search keyboards...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .focused($isSearchFocused)
                .onSubmit {
                    if let index = selectedIndex, index < keyboards.count {
                        importKeyboard(keyboards[index])
                    }
                }
                .accessibilityIdentifier("qmk-search-field")
                .accessibilityLabel("Search keyboards")

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("qmk-search-clear-button")
                .accessibilityLabel("Clear search")
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack {
            ProgressView()
                .scaleEffect(0.8)
                .accessibilityIdentifier("qmk-search-loading-indicator")
            Text("Loading keyboards...")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Loading keyboards")
    }

    // MARK: - Error View

    private func errorView(_ error: String) -> some View {
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
        .accessibilityIdentifier("qmk-search-error-message")
        .accessibilityLabel("Error loading keyboards: \(error)")
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "keyboard")
                .font(.system(size: 32))
                .foregroundColor(.secondary.opacity(0.5))
            Text(searchText.isEmpty ? "Start typing to search keyboards" : "No keyboards found matching '\(searchText)'")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("qmk-search-empty-state")
        .accessibilityLabel(searchText.isEmpty ? "Start typing to search keyboards" : "No keyboards found matching '\(searchText)'")
    }

    // MARK: - Keyboard List

    private var keyboardListView: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(Array(keyboards.enumerated()), id: \.element.id) { index, keyboard in
                    KeyboardRow(
                        keyboard: keyboard,
                        isSelected: selectedIndex == index,
                        onSelect: {
                            importKeyboard(keyboard)
                        }
                    )
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Text("\(keyboards.count) keyboard\(keyboards.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("Press ⌘F to search, ↑↓ to navigate, Enter to import")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.7))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .accessibilityIdentifier("qmk-search-status-bar")
        .accessibilityLabel("\(keyboards.count) keyboard\(keyboards.count == 1 ? "" : "s") found")
    }

    // MARK: - Actions

    private func performSearch(query: String) async {
        AppLogger.shared.info("🔍 [QMKSearch] Performing search with query: '\(query)'")
        isLoading = true
        errorMessage = nil

        do {
            AppLogger.shared.info("🔍 [QMKSearch] Calling QMKKeyboardDatabase.searchKeyboards...")
            let results = try await QMKKeyboardDatabase.shared.searchKeyboards(query)
            AppLogger.shared.info("✅ [QMKSearch] Got \(results.count) results")
            await MainActor.run {
                keyboards = results
                isLoading = false
                // Reset selection when search changes
                if query != searchText {
                    selectedIndex = nil
                } else if selectedIndex != nil, selectedIndex! >= results.count {
                    selectedIndex = results.isEmpty ? nil : 0
                }
                AppLogger.shared.info("✅ [QMKSearch] Updated UI with \(results.count) keyboards")
            }
        } catch {
            AppLogger.shared.error("❌ [QMKSearch] Search failed: \(error.localizedDescription)")
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
                keyboards = []
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
                    onImportComplete?()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to import keyboard: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Keyboard Row Component

private struct KeyboardRow: View {
    let keyboard: KeyboardMetadata
    let isSelected: Bool
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
                        TagBadge(tag: tag, keyboardId: keyboard.id)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("qmk-search-keyboard-row-\(keyboard.id)")
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - Tag Badge Component

private struct TagBadge: View {
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
