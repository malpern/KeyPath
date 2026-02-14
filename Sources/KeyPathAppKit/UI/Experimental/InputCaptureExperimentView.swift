import AppKit
import SwiftUI

// MARK: - Main View

struct InputCaptureExperimentView: View {
    @State private var viewModel = InputCaptureViewModel()
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
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button(action: { viewModel.clearAll() }) {
                Text("Clear")
                    .font(.subheadline)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .opacity(viewModel.capturedInputs.isEmpty ? 0.5 : 1)
            .disabled(viewModel.capturedInputs.isEmpty)
            .accessibilityIdentifier("input-capture-clear-button")
            .accessibilityLabel("Clear all captured inputs")
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
                    .font(.title2)
                    .foregroundColor(isRecording ? .accentColor : .secondary)
                    .symbolEffect(.pulse, isActive: isRecording)
            }

            Text(isRecording ? "Listening for keys..." : "Press keys or drag items here")
                .font(.subheadline)
                .foregroundColor(.secondary)

            if !isRecording {
                Text("⌘ ⇧ ⌥ ⌃ + any key")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.7))
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
                        .foregroundColor(isRecording ? .red : .primary)
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
                .foregroundColor(.secondary)

            Spacer()

            Button("Done") {
                NSApp.keyWindow?.close()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("input-capture-done-button")
            .accessibilityLabel("Done")
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
