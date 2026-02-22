import AppKit
import SwiftUI

// MARK: - Environment Key for Pressed Key Codes

private struct PressedKeyCodesKey: EnvironmentKey {
    static let defaultValue: Set<UInt16> = []
}

extension EnvironmentValues {
    var pressedKeyCodes: Set<UInt16> {
        get { self[PressedKeyCodesKey.self] }
        set { self[PressedKeyCodesKey.self] = newValue }
    }
}

/// Default list view for the Context HUD showing keycap + action pairs in columns
struct ContextHUDDefaultListView: View {
    let groups: [HUDKeyGroup]

    var body: some View {
        HStack(alignment: .top, spacing: 64) {
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 10) {
                    // Collection header
                    Text(group.name.uppercased())
                        .font(.caption.monospaced().weight(.semibold))
                        .foregroundStyle(group.color.opacity(0.8))
                        .tracking(1.5)

                    // Key entries in columns (max 4 per column)
                    ColumnarKeyLayout(entries: group.entries)
                }
            }
        }
    }
}

/// Lays out key entries in a wrapping grid
private struct ColumnarKeyLayout: View {
    let entries: [HUDKeyEntry]

    private let maxRowsPerColumn = 4

    private var columns: [[HUDKeyEntry]] {
        guard !entries.isEmpty else { return [] }
        let columnCount = (entries.count + maxRowsPerColumn - 1) / maxRowsPerColumn
        var result: [[HUDKeyEntry]] = []
        for col in 0 ..< columnCount {
            let start = col * maxRowsPerColumn
            let end = min(start + maxRowsPerColumn, entries.count)
            result.append(Array(entries[start ..< end]))
        }
        return result
    }

    var body: some View {
        HStack(alignment: .top, spacing: 34) {
            ForEach(columns.indices, id: \.self) { columnIndex in
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(columns[columnIndex]) { entry in
                        HUDKeycapChip(entry: entry)
                    }
                }
            }
        }
    }
}

/// A keycap chip showing the key and its action.
/// Launcher entries (with icons) hide text until hover; other entries always show labels inline.
struct HUDKeycapChip: View {
    let entry: HUDKeyEntry
    @Environment(\.pressedKeyCodes) private var pressedKeyCodes
    @State private var faviconImage: NSImage?
    @State private var isHovered = false

    private var isPressed: Bool {
        pressedKeyCodes.contains(entry.keyCode)
    }

    /// Resolved app icon (synchronous lookup)
    private var appIcon: NSImage? {
        guard let appId = entry.appIdentifier else { return nil }
        return IconResolverService.shared.resolveAppIcon(for: appId)
    }

    /// Whether this entry is a launcher (app or URL) — decides layout before icons load
    private var isLauncherEntry: Bool {
        entry.appIdentifier != nil || entry.urlIdentifier != nil
    }

    /// The resolved icon (app icon or async favicon)
    private var resolvedIcon: NSImage? {
        appIcon ?? faviconImage
    }

    /// Label text combining action + hold action
    private var labelText: String {
        if let holdAction = entry.holdAction {
            return "\(entry.action) \u{00B7} \(holdAction)"
        }
        return entry.action
    }

    var body: some View {
        if isLauncherEntry {
            // Launcher entry: compact keycap + icon, label on hover above
            launcherChip
        } else {
            // Non-launcher entry: keycap + inline label (original layout)
            inlineChip
        }
    }

    /// Launcher chip — key + icon, text label floats to the right on hover
    private var launcherChip: some View {
        HStack(spacing: 4) {
            // Subdued key label — compact width to reduce gap
            Text(entry.keycap)
                .font(.system(.headline, design: .monospaced).weight(.bold))
                .foregroundStyle(.white.opacity(isPressed ? 0.9 : 0.45))
                .frame(width: 22, alignment: .center)

            // App icon — always reserve space so columns stay aligned
            Group {
                if let icon = resolvedIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.white.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
                        )
                }
            }
            .frame(width: 42, height: 42)
            .scaleEffect(isPressed ? 1.08 : 1.0)
        }
        .overlay(alignment: .trailing) {
            if isHovered {
                Text(labelText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(.black.opacity(0.8))
                    )
                    .offset(x: 8)
                    .alignmentGuide(.trailing) { d in d[.leading] }
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .animation(.easeOut(duration: 0.1), value: isPressed)
        .onHover { isHovered = $0 }
        .task(id: entry.urlIdentifier) {
            guard let url = entry.urlIdentifier, appIcon == nil else { return }
            faviconImage = await IconResolverService.shared.resolveFavicon(for: url)
        }
    }

    /// Inline chip for non-launcher entries — keycap + text label always visible
    private var inlineChip: some View {
        HStack(spacing: 10) {
            keycapBadge

            if let sfSymbol = entry.sfSymbol {
                Image(systemName: sfSymbol)
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.8))
            } else {
                Text(entry.action)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
            }

            if let holdAction = entry.holdAction {
                Text("\u{00B7}")
                    .foregroundStyle(.white.opacity(0.35))
                Text(holdAction)
                    .font(.system(size: 15, weight: .medium).italic())
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
        }
        .animation(.easeOut(duration: 0.1), value: isPressed)
    }

    private var keycapBadge: some View {
        Text(entry.keycap)
            .font(.system(.headline, design: .monospaced).weight(.bold))
            .foregroundStyle(.white)
            .frame(minWidth: 32, minHeight: 32)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(entry.color.opacity(isPressed ? 0.65 : 0.35))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(entry.color.opacity(isPressed ? 0.9 : 0.5), lineWidth: isPressed ? 1.0 : 0.5)
            )
            .scaleEffect(isPressed ? 1.08 : 1.0)
    }
}

// FlowLayout is defined in FlowLayout.swift and reused here
