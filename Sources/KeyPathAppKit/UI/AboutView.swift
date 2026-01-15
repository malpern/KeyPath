import AppKit
import SwiftUI

/// About window for KeyPath - shows app info, version, attribution, and links
struct AboutView: View {
    @ObservedObject private var updateService = UpdateService.shared
    @Environment(\.dismiss) private var dismiss

    private let buildInfo = BuildInfo.current()

    var body: some View {
        VStack(spacing: 0) {
            // Header section with icon and title
            VStack(spacing: 12) {
                // App Icon
                if let image = NSImage(named: "AppIcon") {
                    Image(nsImage: image)
                        .resizable()
                        .frame(width: 128, height: 128)
                        .cornerRadius(16)
                        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
                }

                // App Name
                Text("KeyPath")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.primary)

                // Version Info
                VStack(spacing: 4) {
                    Text("Version \(buildInfo.version) (Build \(buildInfo.build))")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)

                    if let kanataVersion = buildInfo.kanataVersion {
                        Text("Kanata \(kanataVersion)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.top, 32)
            .padding(.bottom, 24)

            Divider()
                .padding(.horizontal, 32)

            // Update Button Section
            VStack(spacing: 12) {
                Button(action: {
                    updateService.checkForUpdates()
                }) {
                    Label("Check for Updates", systemImage: "arrow.down.circle")
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!updateService.canCheckForUpdates)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 20)

            Divider()
                .padding(.horizontal, 32)

            // Links Section
            VStack(spacing: 12) {
                Text("Links")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 8) {
                    LinkButton(
                        title: "Website",
                        url: "http://keypath-app.com",
                        icon: "safari"
                    )

                    LinkButton(
                        title: "GitHub",
                        url: "https://github.com/malpern/KeyPath",
                        icon: "chevron.left.forwardslash.chevron.right"
                    )

                    LinkButton(
                        title: "Twitter / X",
                        url: "http://x.com/malpern",
                        icon: "at"
                    )
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()
                .padding(.horizontal, 32)

            // Attribution Section
            VStack(spacing: 12) {
                Text("Built With")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 8) {
                    AttributionRow(
                        name: "Kanata",
                        description: "Advanced keyboard remapping engine",
                        license: "LGPL v3",
                        url: "https://github.com/jtroo/kanata"
                    )
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()
                .padding(.horizontal, 32)

            // Footer with copyright and author
            VStack(spacing: 8) {
                Text("© 2026 Micah Alpern")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Text("MIT License")
                    .font(.system(size: 10))
                    .foregroundColor(Color.secondary.opacity(0.6))
            }
            .padding(.vertical, 20)
        }
        .frame(width: 440)
        .background(
            // Liquid Glass effect for macOS 15+
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
        )
    }
}

// MARK: - Link Button Component

private struct LinkButton: View {
    let title: String
    let url: String
    let icon: String

    var body: some View {
        Button(action: {
            if let url = URL(string: url) {
                NSWorkspace.shared.open(url)
            }
        }) {
            HStack {
                Label(title, systemImage: icon)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

// MARK: - Attribution Row Component

private struct AttributionRow: View {
    let name: String
    let description: String
    let license: String
    let url: String

    var body: some View {
        Button(action: {
            if let url = URL(string: url) {
                NSWorkspace.shared.open(url)
            }
        }) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)

                        Text(license)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.secondary.opacity(0.15))
                            )
                    }

                    Text(description)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

// MARK: - Window Controller

@MainActor
class AboutWindowController {
    static let shared = AboutWindowController()
    private var window: NSWindow?

    private init() {}

    func show() {
        // If window already exists, just bring it to front
        if let existingWindow = window {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Create new window
        let contentView = AboutView()

        let hostingController = NSHostingController(rootView: contentView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 600),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.title = "About KeyPath"
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.contentViewController = hostingController
        window.center()
        window.isReleasedWhenClosed = false

        // Set appearance to match system
        window.appearance = NSAppearance.currentDrawing()

        // Clean up when window closes
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.window = nil
            }
        }

        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Preview

#Preview {
    AboutView()
        .frame(width: 440, height: 600)
}
