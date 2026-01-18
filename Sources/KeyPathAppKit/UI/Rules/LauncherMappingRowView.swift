import AppKit
import SwiftUI

/// Shared view for displaying a launcher mapping row.
///
/// Used in both the welcome dialog preview and the main launcher collection view.
struct LauncherMappingRowView: View {
    let mapping: LauncherMapping
    var showToggle: Bool = false
    var onToggle: (() -> Void)?
    var onEdit: (() -> Void)?
    var onDelete: (() -> Void)?

    @State private var icon: NSImage?

    var body: some View {
        HStack(spacing: 8) {
            // Icon
            Group {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: fallbackIconName)
                        .frame(width: 20, height: 20)
                        .foregroundColor(.secondary)
                }
            }

            // Key badge
            Text(mapping.key.uppercased())
                .font(.system(size: 11, weight: showToggle ? .semibold : .bold, design: .monospaced))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.accentColor.opacity(mapping.isEnabled || !showToggle ? 0.2 : 0.1))
                )
                .foregroundColor(mapping.isEnabled || !showToggle ? .accentColor : .secondary)

            // Target name
            Text(mapping.target.displayName)
                .font(.system(size: 12))
                .foregroundColor(mapping.isEnabled || !showToggle ? .primary : .secondary)

            Spacer()

            // Toggle (optional)
            if showToggle, let onToggle {
                Toggle("", isOn: Binding(
                    get: { mapping.isEnabled },
                    set: { _ in onToggle() }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
            }
        }
        .padding(.horizontal, showToggle ? 8 : 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .contentShape(Rectangle())
        .if(onEdit != nil && onDelete != nil) { view in
            view.contextMenu {
                if let onEdit {
                    Button("Edit") { onEdit() }
                }
                if onEdit != nil, onDelete != nil {
                    Divider()
                }
                if let onDelete {
                    Button("Delete", role: .destructive) { onDelete() }
                }
            }
        }
        .accessibilityIdentifier("launcher-mapping-row-\(mapping.key)")
        .accessibilityLabel("\(mapping.target.displayName), key \(mapping.key)")
        .task {
            await loadIcon()
        }
    }

    private func loadIcon() async {
        switch mapping.target {
        case .app, .folder, .script:
            icon = AppIconResolver.icon(for: mapping.target)
        case let .url(urlString):
            icon = await FaviconLoader.shared.favicon(for: urlString)
        }
    }

    /// Fallback SF Symbol name based on target type
    private var fallbackIconName: String {
        switch mapping.target {
        case .app: "app"
        case .url: "globe"
        case .folder: "folder"
        case .script: "terminal"
        }
    }
}
