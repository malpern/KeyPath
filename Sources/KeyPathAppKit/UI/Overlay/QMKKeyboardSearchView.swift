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
    @State private var importToastMessage: String?
    @State private var importToastType: KanataViewModel.ToastType = .success

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()

            if isLoading {
                loadingView
            } else if let error = errorMessage {
                errorView(error)
            } else if keyboards.isEmpty {
                emptyStateView
            } else {
                keyboardListView
            }

            if !keyboards.isEmpty {
                statusBar
            }
        }
        .overlay(alignment: .bottom) {
            if let message = importToastMessage {
                ToastView(message: message, type: importToastType)
                    .padding(.bottom, 40)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: importToastMessage)
        .frame(width: 500, height: 450)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isSearchFocused = true
            }
            Task {
                await performSearch(query: "")
            }
        }
        .onChange(of: searchText) { _, newValue in
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(200))
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
                .font(.system(size: 14))

            TextField("Search 3,700+ keyboards...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .font(.body)
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
                        .font(.system(size: 14))
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
                .font(.callout)
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
                .font(.title2)
                .foregroundColor(.orange)
            Text(error)
                .font(.callout)
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
                .font(.system(size: 36))
                .foregroundColor(.secondary.opacity(0.4))
            Text(searchText.isEmpty ? "Start typing to search keyboards" : "No keyboards found matching '\(searchText)'")
                .font(.callout)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("qmk-search-empty-state")
        .accessibilityLabel(searchText.isEmpty ? "Start typing to search keyboards" : "No keyboards found matching '\(searchText)'")
    }

    // MARK: - Keyboard List

    private var keyboardListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(keyboards.indices, id: \.self) { index in
                    let keyboard = keyboards[index]
                    PopoverKeyboardRow(
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
                Text("↑↓ to navigate, Enter to import")
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
        isLoading = true
        errorMessage = nil

        do {
            let results = try await QMKKeyboardDatabase.shared.searchKeyboards(query)
            await MainActor.run {
                keyboards = results
                isLoading = false
                if query != searchText {
                    selectedIndex = nil
                } else if selectedIndex != nil, selectedIndex! >= results.count {
                    selectedIndex = results.isEmpty ? nil : 0
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
                keyboards = []
            }
        }
    }

    private func importKeyboard(_ keyboard: KeyboardMetadata) {
        // If this QMK keyboard has a built-in equivalent, select it directly
        if let builtInId = keyboard.builtInLayoutId,
           PhysicalLayout.find(id: builtInId) != nil
        {
            selectedLayoutId = builtInId
            onImportComplete?()
            dismiss()
            return
        }

        Task {
            do {
                // Fetch keyboard data (uses disk cache, handles QMK API unwrapping)
                let jsonData = try await QMKKeyboardDatabase.shared.fetchKeyboardData(keyboard)

                // Parse the layout from the fetched/cached data
                let info = try JSONDecoder().decode(QMKLayoutParser.QMKKeyboardInfo.self, from: jsonData)

                guard !info.layouts.isEmpty else {
                    throw QMKImportError.noLayoutFound("No layout definitions found for '\(keyboard.name)'")
                }

                let layoutId = "custom-\(UUID().uuidString)"

                // Strategy: try keymap-based parsing first (standard approach), fall back to row-based
                let result: QMKLayoutParser.ParseResult
                var cachedKeymapTokens: [String]?

                // Fetch default keymap from GitHub (best-effort, non-blocking)
                if let keymapTokens = await QMKKeyboardDatabase.shared.fetchDefaultKeymap(keyboardPath: keyboard.id),
                   let keymapResult = QMKLayoutParser.parseWithKeymap(
                       data: jsonData,
                       keymapTokens: keymapTokens,
                       idOverride: layoutId,
                       nameOverride: keyboard.name
                   )
                {
                    result = keymapResult
                    cachedKeymapTokens = keymapTokens
                }
                // Fallback: row-based position inference
                else if let positionResult = QMKLayoutParser.parseByPositionWithQuality(
                    data: jsonData,
                    idOverride: layoutId,
                    nameOverride: keyboard.name
                ) {
                    result = positionResult
                } else {
                    throw QMKImportError.parseError("Failed to parse layout for '\(keyboard.name)'")
                }

                // Generate a user-friendly name
                let layoutName = "\(keyboard.name)\(keyboard.manufacturer.map { " by \($0)" } ?? "")"

                // Replace any existing QMK import (at most 1 at a time)
                await QMKImportService.shared.replaceQMKImport(
                    layout: result.layout,
                    name: layoutName,
                    sourceURL: keyboard.infoJsonURL?.absoluteString,
                    layoutJSON: jsonData,
                    layoutVariant: nil,
                    defaultKeymap: cachedKeymapTokens
                )

                await MainActor.run {
                    selectedLayoutId = result.layout.id
                    onImportComplete?()

                    if !result.isUsable {
                        let pct = Int(result.matchRatio * 100)
                        showImportToast(
                            "Imported \(keyboard.name) — only \(pct)% of keys matched. Layout may not be usable.",
                            type: .error,
                            duration: 7.0
                        )
                    } else if !result.isHighQuality {
                        let pct = Int(result.matchRatio * 100)
                        showImportToast(
                            "Imported \(keyboard.name) — \(pct)% of keys matched. Some keys may not highlight correctly.",
                            type: .warning,
                            duration: 7.0
                        )
                    } else {
                        showImportToast("Imported \(keyboard.name)", type: .success)
                        dismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to import keyboard: \(error.localizedDescription)"
                }
            }
        }
    }

    private func showImportToast(_ message: String, type: KanataViewModel.ToastType, duration: TimeInterval = 3.0) {
        importToastType = type
        importToastMessage = message
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration))
            if importToastMessage == message {
                importToastMessage = nil
            }
        }
    }
}

// MARK: - Keyboard Row Component (Popover variant with selection highlight)

private struct PopoverKeyboardRow: View {
    let keyboard: KeyboardMetadata
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovering = false

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

    private var keyboardIcon: String {
        if keyboard.tags.contains("split") {
            return "rectangle.split.2x1"
        }
        return "keyboard"
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                // Keyboard icon
                Image(systemName: keyboardIcon)
                    .font(.system(size: 16))
                    .foregroundColor(.secondary.opacity(0.6))
                    .frame(width: 24, alignment: .center)

                // Name, manufacturer, and path
                VStack(alignment: .leading, spacing: 2) {
                    Text(keyboard.name)
                        .font(.callout)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        if let manufacturer = keyboard.manufacturer, !manufacturer.isEmpty {
                            Text(manufacturer)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        Text(keyboard.id)
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.5))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4)

                // Tags
                HStack(spacing: 4) {
                    if keyboard.builtInLayoutId != nil {
                        Text("Built-in")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15))
                            .foregroundColor(.green)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    ForEach(keyboard.tags.prefix(3), id: \.self) { tag in
                        TagBadge(tag: tag, keyboardId: keyboard.id)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.15) : (isHovering ? Color.accentColor.opacity(0.08) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovering = hovering
            }
        }
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
