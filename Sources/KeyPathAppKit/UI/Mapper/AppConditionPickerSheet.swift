import AppKit
import SwiftUI

/// Sheet for picking an app condition (precondition) for a key mapping rule.
/// Lazy-loads running apps on appear — no preloading required.
struct AppConditionPickerSheet: View {
    let onSelect: (AppConditionInfo) -> Void
    let onBrowse: () -> Void

    @State private var apps: [NSRunningApplication] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    if apps.isEmpty {
                        Text("No apps running")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    } else {
                        ForEach(apps, id: \.processIdentifier) { app in
                            appRow(app)
                        }
                    }
                    Divider()
                    browseRow
                }
            }
        }
        .frame(minWidth: 280, idealWidth: 280, maxWidth: 280, minHeight: 200, maxHeight: 380)
        .onAppear {
            apps = NSWorkspace.shared.runningApplications
                .filter {
                    $0.activationPolicy == .regular &&
                        $0.bundleIdentifier != Bundle.main.bundleIdentifier &&
                        $0.localizedName != nil
                }
                .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
        }
    }

    private var headerRow: some View {
        HStack {
            Text("Choose App")
                .font(.headline)
            Spacer()
            Button("Cancel") { dismiss() }
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func appRow(_ app: NSRunningApplication) -> some View {
        Button {
            guard let bundleId = app.bundleIdentifier, let name = app.localizedName else { return }
            let rawIcon = app.icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
            let icon = rawIcon.copy() as? NSImage ?? rawIcon
            icon.size = NSSize(width: 24, height: 24)
            dismiss()
            onSelect(AppConditionInfo(bundleIdentifier: bundleId, displayName: name, icon: icon))
        } label: {
            HStack(spacing: 10) {
                if let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 24, height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                } else {
                    Image(systemName: "app")
                        .font(.title3)
                        .frame(width: 24, height: 24)
                        .foregroundStyle(.secondary)
                }
                Text(app.localizedName ?? "Unknown")
                    .font(.body)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("app-picker-row-\(app.bundleIdentifier ?? "pid-\(app.processIdentifier)")")
    }

    private var browseRow: some View {
        Button {
            dismiss()
            onBrowse()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "folder")
                    .font(.body)
                    .frame(width: 24)
                    .foregroundStyle(.secondary)
                Text("Browse Applications Folder...")
                    .font(.body)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("app-picker-browse")
    }
}
