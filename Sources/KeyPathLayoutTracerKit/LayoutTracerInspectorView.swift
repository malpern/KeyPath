import SwiftUI

struct LayoutTracerInspectorView: View {
    @Bindable var document: TracingDocument
    let onOpenImage: () -> Void
    let onClearImage: () -> Void
    let onOpenLayout: () -> Void
    let onAnalyzeImage: () -> Void
    let availableLayouts: [LayoutCatalogEntry]
    let onSelectLayout: (LayoutCatalogEntry) -> Void
    @State private var layoutSearch = ""
    @State private var highlightedLayoutID: LayoutCatalogEntry.ID?
    @FocusState private var isSearchFocused: Bool
    @AppStorage("layoutTracer.recentBuiltInLayoutPath") private var recentBuiltInLayoutPath = ""

    private var recentLayout: LayoutCatalogEntry? {
        guard !recentBuiltInLayoutPath.isEmpty else { return nil }
        return availableLayouts.first(where: { $0.fileURL.path == recentBuiltInLayoutPath })
    }

    private var filteredLayouts: [LayoutCatalogEntry] {
        let query = layoutSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return prioritizeRecentLayout(in: availableLayouts)
        }
        let matches = availableLayouts
            .filter {
                $0.displayName.localizedCaseInsensitiveContains(query) ||
                $0.layoutID.localizedCaseInsensitiveContains(query) ||
                $0.filename.localizedCaseInsensitiveContains(query)
            }
            .prefix(6)
            .map { $0 }
        return prioritizeRecentLayout(in: matches)
    }

    private var showsLayoutResults: Bool {
        isSearchFocused && !filteredLayouts.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                layoutSection
                documentSection
                selectionSection
            }
            .padding(16)
        }
        .frame(minWidth: 280, idealWidth: 320)
        .background(Color(nsColor: .controlBackgroundColor))
        .onChange(of: layoutSearch) { _, _ in
            highlightedLayoutID = filteredLayouts.first?.id
        }
        .onChange(of: isSearchFocused) { _, isFocused in
            if isFocused {
                highlightedLayoutID = filteredLayouts.first?.id
            }
        }
        .onChange(of: document.layoutFileURL) { _, newValue in
            guard let newValue else { return }
            if let matchingLayout = availableLayouts.first(where: { $0.fileURL.standardizedFileURL == newValue.standardizedFileURL }) {
                recentBuiltInLayoutPath = matchingLayout.fileURL.path
            }
        }
    }

    private var layoutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Document")
                .font(.headline)

            HStack {
                Button(action: document.backgroundImageURL == nil ? onOpenImage : onClearImage) {
                    Label(
                        document.backgroundImageURL == nil ? "Add Image" : "Remove Image",
                        systemImage: document.backgroundImageURL == nil ? "photo.badge.plus" : "photo.badge.minus"
                    )
                }
                .tracerGlassButtonStyle()
                .help(document.backgroundImageURL == nil ? "Add Image" : "Remove Image")
                .accessibilityIdentifier(document.backgroundImageURL == nil ? "layoutTracer.openImage" : "layoutTracer.clearImage")
                Button(action: onOpenLayout) {
                    Label("Open Layout", systemImage: "square.stack.badge.plus")
                        .labelStyle(.iconOnly)
                }
                .tracerGlassButtonStyle()
                .help("Open Layout")
                .accessibilityIdentifier("layoutTracer.openLayout")

                Button(action: onAnalyzeImage) {
                    Label("Analyze Image", systemImage: "sparkles.rectangle.stack")
                        .labelStyle(.iconOnly)
                }
                .tracerGlassButtonStyle()
                .help("Analyze Image")
                .disabled(document.backgroundImageURL == nil)
                .accessibilityIdentifier("layoutTracer.analyzeImage")
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search built-in layouts", text: $layoutSearch)
                        .textFieldStyle(.roundedBorder)
                        .focused($isSearchFocused)
                        .accessibilityIdentifier("layoutTracer.searchField")
                        .onMoveCommand(perform: handleSearchMoveCommand)
                        .onSubmit {
                            openHighlightedLayout()
                        }
                }

                if showsLayoutResults {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(filteredLayouts) { layout in
                            Button {
                                selectLayout(layout)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(layout.displayName)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(layout.filename)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                            .background(
                                (highlightedLayoutID == layout.id ? Color.accentColor.opacity(0.22) : Color.white.opacity(0.03))
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .accessibilityIdentifier("layoutTracer.search.result.\(layout.layoutID)")
                        }
                    }
                }
            }

            if let layoutFileURL = document.layoutFileURL {
                Text(layoutFileURL.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if document.backgroundImageURL != nil, (document.hasLayoutOverlay || document.hasAnalysisProposals) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        if document.hasLayoutOverlay {
                            Toggle(isOn: $document.showsLayoutLayer) {
                                Image(systemName: "square.stack.3d.up")
                            }
                            .toggleStyle(.button)
                            .help("Show Layout Overlay")
                            .accessibilityIdentifier("layoutTracer.layout.toggle")
                        }

                        if document.hasAnalysisProposals {
                            Toggle(isOn: $document.showsAnalysisLayer) {
                                Image(systemName: "sparkles.rectangle.stack")
                            }
                            .toggleStyle(.button)
                            .help("Show Analysis Overlay")
                            .accessibilityIdentifier("layoutTracer.analysis.toggle")
                        }
                    }

                    if document.hasAnalysisProposals {
                        HStack {
                            Button {
                                document.promoteAnalysisProposals()
                            } label: {
                                Image(systemName: "arrow.down.to.line.compact")
                            }
                            .tracerGlassButtonStyle()
                            .help("Promote Analysis")
                            .accessibilityIdentifier("layoutTracer.analysis.promote")

                            Button {
                                document.clearAnalysis()
                            } label: {
                                Image(systemName: "xmark.bin")
                            }
                            .tracerGlassButtonStyle()
                            .help("Clear Analysis")
                            .accessibilityIdentifier("layoutTracer.analysis.clear")
                        }

                        if let analysis = document.analysis {
                            Text("\(analysis.proposals.count) proposals via \(analysis.modelVersion)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            HStack {
                Button {
                    document.addKey()
                } label: {
                    Image(systemName: "plus.square")
                }
                .tracerGlassButtonStyle()
                .help("Add Key")
                .accessibilityIdentifier("layoutTracer.addKey")

                Button {
                    document.duplicateSelectedKey()
                } label: {
                    Image(systemName: "square.on.square")
                }
                .tracerGlassButtonStyle()
                .help("Duplicate Key")
                .disabled(document.selectedKey == nil)
                .accessibilityIdentifier("layoutTracer.duplicateKey")

                Button {
                    document.removeSelectedKey()
                } label: {
                    Image(systemName: "trash")
                }
                .tracerGlassButtonStyle()
                .help("Delete Key")
                .disabled(document.selectedKey == nil)
                .accessibilityIdentifier("layoutTracer.deleteKey")
            }
        }
        .tracerGlassCard()
    }

    private var documentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Canvas")
                .font(.headline)

            HStack(spacing: 8) {
                Image(systemName: "plus.magnifyingglass")
                    .foregroundStyle(.secondary)
                Slider(value: $document.zoom, in: 0.03...2.0)
                    .frame(width: 140)
                    .accessibilityIdentifier("layoutTracer.zoom")
                Button("Fit") {
                    document.fitCanvasToViewport()
                }
                .tracerGlassButtonStyle()
                .accessibilityIdentifier("layoutTracer.fitToCanvas")
            }

            HStack(spacing: 8) {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
                Slider(value: $document.imageOpacity, in: 0.1...1.0)
                    .frame(width: 200)
                    .accessibilityIdentifier("layoutTracer.imageOpacity")
            }

            HStack(spacing: 8) {
                Image(systemName: "roundedcorner")
                    .foregroundStyle(.secondary)
                Slider(value: $document.keyCornerRadius, in: 0...24)
                    .frame(width: 140)
                    .accessibilityIdentifier("layoutTracer.keyCornerRadius")
                Text("\(Int(document.keyCornerRadius.rounded()))")
                    .font(.body.monospacedDigit())
                    .frame(minWidth: 24, alignment: .trailing)
            }

        }
        .tracerGlassCard()
    }

    private var selectionSection: some View {
        Group {
            if let selected = document.selectedKey {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Selected Key")
                        .font(.headline)

                LabelComboBoxField(
                    title: "Label",
                    text: binding(for: \.label),
                    suggestions: KeySuggestionCatalog.commonLabelSuggestions,
                    accessibilityID: "layoutTracer.selected.label"
                )
                KeyCodeComboBoxField(
                    title: "Key Code",
                    value: bindingUInt16(for: \.keyCode),
                    suggestions: KeySuggestionCatalog.keyCodeSuggestions,
                    accessibilityID: "layoutTracer.selected.keyCode"
                )
                LabeledDoubleField(title: "X", value: bindingDouble(for: \.x), accessibilityID: "layoutTracer.selected.x")
                LabeledDoubleField(title: "Y", value: bindingDouble(for: \.y), accessibilityID: "layoutTracer.selected.y")
                LabeledDoubleField(title: "Width", value: bindingDouble(for: \.width), accessibilityID: "layoutTracer.selected.width")
                LabeledDoubleField(title: "Height", value: bindingDouble(for: \.height), accessibilityID: "layoutTracer.selected.height")

                HStack(spacing: 8) {
                    Text("Rotation")
                        .frame(width: 70, alignment: .leading)
                    Button {
                        document.rotateSelectedKey(by: -5)
                    } label: {
                        Image(systemName: "rotate.left")
                    }
                    .help("Rotate Counterclockwise")
                    .accessibilityIdentifier("layoutTracer.rotate.left")

                    Text("\(Int((selected.rotation ?? 0).rounded()))°")
                        .font(.body.monospacedDigit())
                        .frame(minWidth: 44)

                    Button {
                        document.rotateSelectedKey(by: 5)
                    } label: {
                        Image(systemName: "rotate.right")
                    }
                    .help("Rotate Clockwise")
                    .accessibilityIdentifier("layoutTracer.rotate.right")
                }

                HStack {
                    Button("←") { document.nudgeSelectedKey(dx: -1, dy: 0) }
                        .accessibilityIdentifier("layoutTracer.nudge.left")
                    Button("→") { document.nudgeSelectedKey(dx: 1, dy: 0) }
                        .accessibilityIdentifier("layoutTracer.nudge.right")
                    Button("↑") { document.nudgeSelectedKey(dx: 0, dy: -1) }
                        .accessibilityIdentifier("layoutTracer.nudge.up")
                    Button("↓") { document.nudgeSelectedKey(dx: 0, dy: 1) }
                        .accessibilityIdentifier("layoutTracer.nudge.down")
                }

                Text("Current frame: \(Int(selected.width))×\(Int(selected.height)) at (\(Int(selected.x)), \(Int(selected.y)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .tracerGlassCard()
            }
        }
    }

    private func binding(for keyPath: WritableKeyPath<TracingKey, String>) -> Binding<String> {
        Binding(
            get: { document.selectedKey?[keyPath: keyPath] ?? "" },
            set: { newValue in
                guard var selected = document.selectedKey else { return }
                document.beginInteractiveChange()
                selected[keyPath: keyPath] = newValue
                document.selectedKey = selected
                document.endInteractiveChange()
            }
        )
    }

    private func bindingDouble(for keyPath: WritableKeyPath<TracingKey, Double>) -> Binding<Double> {
        Binding(
            get: { document.selectedKey?[keyPath: keyPath] ?? 0 },
            set: { newValue in
                guard var selected = document.selectedKey else { return }
                document.beginInteractiveChange()
                selected[keyPath: keyPath] = newValue
                document.selectedKey = selected
                document.endInteractiveChange()
            }
        )
    }

    private func bindingUInt16(for keyPath: WritableKeyPath<TracingKey, UInt16>) -> Binding<UInt16> {
        Binding(
            get: { document.selectedKey?[keyPath: keyPath] ?? 0 },
            set: { newValue in
                guard var selected = document.selectedKey else { return }
                document.beginInteractiveChange()
                selected[keyPath: keyPath] = newValue
                document.selectedKey = selected
                document.endInteractiveChange()
            }
        )
    }

    private func handleSearchMoveCommand(_ direction: MoveCommandDirection) {
        guard !filteredLayouts.isEmpty else { return }
        let currentIndex = filteredLayouts.firstIndex(where: { $0.id == highlightedLayoutID }) ?? 0
        switch direction {
        case .down:
            let nextIndex = min(currentIndex + 1, filteredLayouts.count - 1)
            highlightedLayoutID = filteredLayouts[nextIndex].id
        case .up:
            let nextIndex = max(currentIndex - 1, 0)
            highlightedLayoutID = filteredLayouts[nextIndex].id
        default:
            break
        }
    }

    private func openHighlightedLayout() {
        guard let highlightedLayoutID,
              let layout = filteredLayouts.first(where: { $0.id == highlightedLayoutID })
        else { return }
        selectLayout(layout)
    }

    private func selectLayout(_ layout: LayoutCatalogEntry) {
        recentBuiltInLayoutPath = layout.fileURL.path
        onSelectLayout(layout)
        layoutSearch = ""
        highlightedLayoutID = nil
        isSearchFocused = false
    }

    private func prioritizeRecentLayout(in layouts: [LayoutCatalogEntry]) -> [LayoutCatalogEntry] {
        guard let recentLayout,
              let recentIndex = layouts.firstIndex(of: recentLayout)
        else { return layouts }

        var reordered = layouts
        let recent = reordered.remove(at: recentIndex)
        reordered.insert(recent, at: 0)
        return reordered
    }
}
