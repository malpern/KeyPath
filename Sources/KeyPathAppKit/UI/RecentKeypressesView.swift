import KeyPathCore
import SwiftUI

/// A simple view showing recent keypresses from Kanata TCP events.
/// Useful for debugging and understanding what keys are being pressed.
struct RecentKeypressesView: View {
    @ObservedObject private var service = RecentKeypressesService.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header with controls
            HStack {
                Text("Recent Keypresses")
                    .font(.headline)

                Spacer()

                // Current layer indicator
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text(service.currentLayer)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Recording toggle
                Button {
                    service.toggleRecording()
                } label: {
                    Image(systemName: service.isRecording ? "pause.circle.fill" : "record.circle")
                        .foregroundColor(service.isRecording ? .red : .secondary)
                }
                .buttonStyle(.borderless)
                .help(service.isRecording ? "Pause recording" : "Resume recording")
                .accessibilityIdentifier("recent-keypresses-toggle-recording")
                .accessibilityLabel(service.isRecording ? "Pause recording" : "Resume recording")

                // Clear button
                Button {
                    service.clearEvents()
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Clear all events")
                .accessibilityIdentifier("recent-keypresses-clear")
                .accessibilityLabel("Clear all events")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Event list
            if service.events.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No keypresses recorded")
                        .foregroundColor(.secondary)
                    if !service.isRecording {
                        Text("Recording is paused")
                            .font(.caption)
                            .foregroundColor(.orange)
                    } else {
                        Text("Press any key to see it here")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(service.events) { event in
                            KeypressEventRow(event: event)
                            Divider()
                        }
                    }
                }
            }
        }
        .frame(minWidth: 300, minHeight: 200)
    }
}

/// A single row in the keypress event list
private struct KeypressEventRow: View {
    let event: RecentKeypressesService.KeypressEvent

    var body: some View {
        HStack(spacing: 12) {
            // Key name with action indicator
            HStack(spacing: 6) {
                // Action indicator
                Image(systemName: actionIcon)
                    .foregroundColor(actionColor)
                    .frame(width: 16)

                // Key name
                Text(event.displayKey)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
            }

            Spacer()

            // Layer badge (if not base)
            if let layer = event.layer, layer != "base" {
                Text(layer)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.2))
                    .foregroundColor(.blue)
                    .cornerRadius(4)
            }

            // Timestamp
            Text(event.timeAgo)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 50, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(event.isPress ? Color.accentColor.opacity(0.05) : Color.clear)
    }

    private var actionIcon: String {
        switch event.action {
        case "press":
            "arrow.down.circle.fill"
        case "release":
            "arrow.up.circle"
        case "repeat":
            "repeat.circle"
        default:
            "circle"
        }
    }

    private var actionColor: Color {
        switch event.action {
        case "press":
            .green
        case "release":
            .secondary
        case "repeat":
            .orange
        default:
            .secondary
        }
    }
}

// MARK: - Window Controller

/// Window controller for the Recent Keypresses panel
@MainActor
final class RecentKeypressesWindowController {
    static let shared = RecentKeypressesWindowController()

    private var window: NSWindow?

    private init() {}

    func showWindow() {
        if let existingWindow = window {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = RecentKeypressesView()
        let hostingController = NSHostingController(rootView: contentView)

        let newWindow = NSWindow(contentViewController: hostingController)
        newWindow.title = "Recent Keypresses"
        newWindow.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        newWindow.setContentSize(NSSize(width: 350, height: 400))
        newWindow.minSize = NSSize(width: 280, height: 200)
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        newWindow.setFrameAutosaveName("RecentKeypressesWindow")

        // Make it a floating utility panel
        newWindow.level = .floating
        newWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        AppLogger.shared.log("🔍 [RecentKeypresses] Window opened")
    }

    func toggle() {
        if let existingWindow = window, existingWindow.isVisible {
            existingWindow.close()
        } else {
            showWindow()
        }
    }
}
