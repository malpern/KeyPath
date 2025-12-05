import AppKit
import SwiftUI

// MARK: - Data Models

enum CapturedInput: Identifiable, Equatable {
    case key(KeyInput)
    case app(AppInput)
    case url(URLInput)

    var id: String {
        switch self {
        case let .key(k): "key-\(k.id)"
        case let .app(a): "app-\(a.id)"
        case let .url(u): "url-\(u.id)"
        }
    }

    struct KeyInput: Identifiable, Equatable {
        let id = UUID()
        let keyCode: UInt16
        let characters: String
        let modifiers: NSEvent.ModifierFlags

        var displayName: String {
            characters.uppercased()
        }

        var isModifier: Bool {
            ["⌘", "⇧", "⌥", "⌃", "fn"].contains(characters)
        }
    }

    struct AppInput: Identifiable, Equatable {
        let id = UUID()
        let name: String
        let bundleIdentifier: String
        let icon: NSImage?
    }

    struct URLInput: Identifiable, Equatable {
        let id = UUID()
        let url: URL
        let title: String
    }
}

// MARK: - Main View

struct InputCaptureExperimentView: View {
    @StateObject private var viewModel = InputCaptureViewModel()
    @State private var isRecording = false
    @State private var showingAppPicker = false
    @State private var dropTargetHighlight = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Main capture area
            VStack(spacing: 20) {
                // Captured inputs display
                capturedInputsArea

                // Action buttons
                actionButtons
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Footer with done/cancel
            footer
        }
        .frame(width: 480, height: 400)
        .onAppear {
            viewModel.setupKeyCapture()
        }
        .onDisappear {
            viewModel.stopKeyCapture()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Input Capture Experiment")
                    .font(.headline)
                Text("Press keys, drag apps, or drop files")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: { viewModel.clearAll() }) {
                Text("Clear")
                    .font(.subheadline)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .opacity(viewModel.capturedInputs.isEmpty ? 0.5 : 1)
            .disabled(viewModel.capturedInputs.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }

    // MARK: - Captured Inputs Area

    private var capturedInputsArea: some View {
        ZStack {
            // Drop zone background
            RoundedRectangle(cornerRadius: 16)
                .fill(dropTargetHighlight
                    ? Color.accentColor.opacity(0.1)
                    : Color(NSColor.controlBackgroundColor).opacity(0.3))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(
                            dropTargetHighlight ? Color.accentColor : Color.white.opacity(0.1),
                            style: StrokeStyle(lineWidth: 2, dash: viewModel.capturedInputs.isEmpty ? [8, 4] : [])
                        )
                )
                .animation(.easeInOut(duration: 0.2), value: dropTargetHighlight)

            if viewModel.capturedInputs.isEmpty {
                // Empty state
                emptyState
            } else {
                // Chips display
                chipsDisplay
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
        .onDrop(of: [.fileURL], isTargeted: $dropTargetHighlight) { providers in
            handleDrop(providers: providers)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            ZStack {
                // Animated circles
                Circle()
                    .stroke(Color.accentColor.opacity(0.2), lineWidth: 2)
                    .frame(width: 60, height: 60)

                Image(systemName: isRecording ? "waveform" : "keyboard")
                    .font(.system(size: 24))
                    .foregroundStyle(isRecording ? .accentColor : Color.secondary)
                    .symbolEffect(.pulse, isActive: isRecording)
            }

            Text(isRecording ? "Listening for keys..." : "Press keys or drag items here")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if !isRecording {
                Text("⌘ ⇧ ⌥ ⌃ + any key")
                    .font(.caption)
                    .foregroundStyle(Color.secondary.opacity(0.7))
            }
        }
    }

    private var chipsDisplay: some View {
        ScrollView {
            FlowLayout(spacing: 8) {
                ForEach(viewModel.capturedInputs) { input in
                    InputChipView(input: input) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            viewModel.remove(input)
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.5).combined(with: .opacity).combined(with: .move(edge: .bottom)),
                        removal: .scale(scale: 0.8).combined(with: .opacity)
                    ))
                }
            }
            .padding(16)
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 12) {
            // Record keys button
            Button {
                withAnimation {
                    isRecording.toggle()
                    if isRecording {
                        viewModel.startRecording()
                    } else {
                        viewModel.stopRecording()
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isRecording ? "stop.circle.fill" : "record.circle")
                        .foregroundStyle(isRecording ? .red : Color.primary)
                    Text(isRecording ? "Stop" : "Record Keys")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(isRecording ? .red : nil)

            // Add app button
            Button {
                showingAppPicker = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "app.badge.fill")
                    Text("Add App")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .popover(isPresented: $showingAppPicker) {
                AppPickerView { app in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        viewModel.addApp(app)
                    }
                    showingAppPicker = false
                }
            }

            // Add URL button
            Button {
                viewModel.addSampleURL()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "link")
                    Text("Add URL")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text("Experiment: Testing visual input capture")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Done") {
                NSApp.keyWindow?.close()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }

    // MARK: - Drop Handling

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }

                Task { @MainActor in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        if url.pathExtension == "app" {
                            // It's an app
                            let name = url.deletingPathExtension().lastPathComponent
                            let bundleID = Bundle(url: url)?.bundleIdentifier ?? ""
                            let icon = NSWorkspace.shared.icon(forFile: url.path)
                            viewModel.addApp(CapturedInput.AppInput(
                                name: name,
                                bundleIdentifier: bundleID,
                                icon: icon
                            ))
                        } else {
                            // It's a file/URL
                            viewModel.addURL(url)
                        }
                    }
                }
            }
        }
        return true
    }
}

// MARK: - Input Chip View

struct InputChipView: View {
    let input: CapturedInput
    let onDelete: () -> Void

    @State private var isHovered = false
    @State private var appearAnimation = false

    var body: some View {
        HStack(spacing: 6) {
            chipContent
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(chipBackground)
        .overlay(chipBorder)
        .clipShape(RoundedRectangle(cornerRadius: chipCornerRadius))
        .shadow(color: .black.opacity(0.1), radius: appearAnimation ? 4 : 0, y: appearAnimation ? 2 : 0)
        .scaleEffect(appearAnimation ? 1 : 0.8)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                appearAnimation = true
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .overlay(alignment: .topTrailing) {
            if isHovered {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .offset(x: 6, y: -6)
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel("Delete")
            }
        }
    }

    @ViewBuilder
    private var chipContent: some View {
        switch input {
        case let .key(keyInput):
            keyChipContent(keyInput)
        case let .app(appInput):
            appChipContent(appInput)
        case let .url(urlInput):
            urlChipContent(urlInput)
        }
    }

    private func keyChipContent(_ keyInput: CapturedInput.KeyInput) -> some View {
        HStack(spacing: 4) {
            // Modifier icons
            if keyInput.modifiers.contains(.command) {
                modifierBadge("⌘")
            }
            if keyInput.modifiers.contains(.shift) {
                modifierBadge("⇧")
            }
            if keyInput.modifiers.contains(.option) {
                modifierBadge("⌥")
            }
            if keyInput.modifiers.contains(.control) {
                modifierBadge("⌃")
            }

            // Key name
            Text(keyInput.displayName)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
        }
    }

    private func modifierBadge(_ symbol: String) -> some View {
        Text(symbol)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(4)
    }

    private func appChipContent(_ appInput: CapturedInput.AppInput) -> some View {
        HStack(spacing: 8) {
            if let icon = appInput.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.accentColor)
            }

            Text(appInput.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)

            Image(systemName: "arrow.up.forward.app")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    private func urlChipContent(_ urlInput: CapturedInput.URLInput) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "link")
                .font(.system(size: 14))
                .foregroundStyle(Color.accentColor)

            Text(urlInput.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }

    private var chipBackground: some View {
        Group {
            switch input {
            case .key:
                LinearGradient(
                    colors: [
                        Color(NSColor.controlBackgroundColor),
                        Color(NSColor.controlBackgroundColor).opacity(0.8)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            case .app:
                Color.accentColor.opacity(0.1)
            case .url:
                Color.orange.opacity(0.1)
            }
        }
    }

    private var chipBorder: some View {
        RoundedRectangle(cornerRadius: chipCornerRadius)
            .strokeBorder(borderColor, lineWidth: 1)
    }

    private var borderColor: Color {
        switch input {
        case .key:
            Color.white.opacity(isHovered ? 0.3 : 0.15)
        case .app:
            Color.accentColor.opacity(isHovered ? 0.5 : 0.3)
        case .url:
            Color.orange.opacity(isHovered ? 0.5 : 0.3)
        }
    }

    private var chipCornerRadius: CGFloat {
        switch input {
        case .key: 8
        case .app, .url: 10
        }
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: currentY + lineHeight), positions)
    }
}

// MARK: - App Picker View

struct AppPickerView: View {
    let onSelect: (CapturedInput.AppInput) -> Void

    @State private var searchText = ""

    private var apps: [CapturedInput.AppInput] {
        let workspace = NSWorkspace.shared
        var result: [CapturedInput.AppInput] = []

        // Add some common apps
        let commonApps = [
            "/Applications/Safari.app",
            "/Applications/Mail.app",
            "/Applications/Notes.app",
            "/Applications/Calendar.app",
            "/Applications/Messages.app",
            "/Applications/Music.app",
            "/Applications/Finder.app",
            "/System/Applications/Terminal.app",
            "/Applications/Slack.app",
            "/Applications/Visual Studio Code.app",
            "/Applications/Obsidian.app"
        ]

        for path in commonApps {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: path) {
                let name = url.deletingPathExtension().lastPathComponent
                let bundleID = Bundle(url: url)?.bundleIdentifier ?? ""
                let icon = workspace.icon(forFile: path)
                result.append(CapturedInput.AppInput(name: name, bundleIdentifier: bundleID, icon: icon))
            }
        }

        if searchText.isEmpty {
            return result
        }
        return result.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search apps...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // App list
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(apps) { app in
                        Button {
                            onSelect(app)
                        } label: {
                            HStack(spacing: 10) {
                                if let icon = app.icon {
                                    Image(nsImage: icon)
                                        .resizable()
                                        .frame(width: 24, height: 24)
                                }
                                Text(app.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(Color.clear)
                        .cornerRadius(6)
                    }
                }
                .padding(8)
            }
        }
        .frame(width: 250, height: 300)
    }
}

// MARK: - View Model

@MainActor
class InputCaptureViewModel: ObservableObject {
    @Published var capturedInputs: [CapturedInput] = []
    @Published var isRecording = false

    private var eventMonitor: Any?

    func setupKeyCapture() {
        // Monitor will be started when recording begins
    }

    func startRecording() {
        isRecording = true

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }

            // Ignore if it's just a modifier key
            let modifierOnlyKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63] // Command, Shift, etc.
            if modifierOnlyKeyCodes.contains(event.keyCode) {
                return event
            }

            let keyInput = CapturedInput.KeyInput(
                keyCode: event.keyCode,
                characters: event.charactersIgnoringModifiers ?? "?",
                modifiers: event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            )

            Task { @MainActor in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    self.capturedInputs.append(.key(keyInput))
                }
            }

            return nil // Consume the event
        }
    }

    func stopRecording() {
        isRecording = false
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    func stopKeyCapture() {
        stopRecording()
    }

    func remove(_ input: CapturedInput) {
        capturedInputs.removeAll { $0.id == input.id }
    }

    func clearAll() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            capturedInputs.removeAll()
        }
    }

    func addApp(_ app: CapturedInput.AppInput) {
        capturedInputs.append(.app(app))
    }

    func addURL(_ url: URL) {
        let urlInput = CapturedInput.URLInput(
            url: url,
            title: url.lastPathComponent
        )
        capturedInputs.append(.url(urlInput))
    }

    func addSampleURL() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            let urlInput = CapturedInput.URLInput(
                url: URL(string: "https://example.com")!,
                title: "example.com"
            )
            capturedInputs.append(.url(urlInput))
        }
    }
}

// MARK: - Window Controller

@MainActor
class InputCaptureExperimentWindowController {
    private var window: NSWindow?

    static let shared = InputCaptureExperimentWindowController()

    func showWindow() {
        if let existingWindow = window, existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }

        let contentView = InputCaptureExperimentView()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 400),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Input Capture Experiment"
        window.contentView = NSHostingView(rootView: contentView)
        window.isReleasedWhenClosed = false

        // Persistent window position
        window.setFrameAutosaveName("InputCaptureWindow")
        if !window.setFrameUsingName("InputCaptureWindow") {
            window.center()
        }

        window.makeKeyAndOrderFront(nil)

        self.window = window
    }
}
