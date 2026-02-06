import AppKit
import SwiftUI

/// Individual keycap view for the launcher keyboard visualization.
///
/// Displays app/website icons for mapped keys, with a small letter label in the top-left corner.
/// Unmapped keys appear dimmed. Caps lock key shows the Hyper star indicator.
struct LauncherKeycapView: View {
    let key: PhysicalKey
    let displayLabel: String
    let accessibilityKey: String
    let mapping: LauncherMapping? // nil = unmapped
    let isSelected: Bool
    var onTap: () -> Void

    @State private var icon: NSImage?

    /// Corner radius for keycap
    private let cornerRadius: CGFloat = 8

    /// Corner radius for icon
    private let iconCornerRadius: CGFloat = 6

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let iconSize = size * 0.55
            let labelSize = size * 0.22

            ZStack {
                // Background
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(backgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(strokeColor, lineWidth: isSelected ? 2 : 1)
                    )

                // Special handling for caps lock (Hyper indicator)
                if isCapsLockKey {
                    capsLockContent(size: size)
                } else if mapping != nil {
                    // Mapped key: icon + letter label
                    mappedKeyContent(iconSize: iconSize, labelSize: labelSize)
                } else {
                    // Unmapped key: just show dimmed letter
                    unmappedKeyContent(labelSize: labelSize)
                }
            }
        }
        .aspectRatio(key.width / key.height, contentMode: .fit)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .task {
            await loadIcon()
        }
        .onChange(of: mapping?.target) { _, _ in
            Task {
                await loadIcon()
            }
        }
        .accessibilityIdentifier("launcher-keycap-\(accessibilityKey)")
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Key Type Checks

    private var isCapsLockKey: Bool {
        key.keyCode == 57 || key.label.lowercased() == "⇪" || key.label.lowercased() == "caps"
    }

    // MARK: - Content Views

    private func capsLockContent(size: CGFloat) -> some View {
        // Hyper star indicator on caps lock
        VStack(spacing: 2) {
            Text("✦")
                .font(.system(size: size * 0.35, weight: .bold))
                .foregroundColor(.white)
            Text("hyper")
                .font(.system(size: size * 0.15, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
        }
    }

    private func mappedKeyContent(iconSize: CGFloat, labelSize: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            // Centered icon
            if let icon {
                ZStack(alignment: .bottomTrailing) {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: iconSize, height: iconSize)
                        .clipShape(RoundedRectangle(cornerRadius: iconCornerRadius))
                        .shadow(color: .black.opacity(0.2), radius: 2, y: 1)

                    // Link badge for websites only
                    if mapping?.target.isURL == true {
                        linkBadge(size: iconSize * 0.35)
                    }
                }
            } else {
                // Fallback placeholder
                Image(systemName: fallbackIconName)
                    .font(.system(size: iconSize * 0.6))
                    .foregroundColor(.white.opacity(0.7))
            }

            // Letter label in top-left
            Text(displayLabel.uppercased())
                .font(.system(size: labelSize, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.7))
                .padding(4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Small link badge for website icons
    private func linkBadge(size: CGFloat) -> some View {
        Image(systemName: "link")
            .font(.system(size: size * 0.65, weight: .bold))
            .foregroundColor(.white)
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(Color.blue)
                    .shadow(color: .black.opacity(0.3), radius: 1, y: 0.5)
            )
            .offset(x: size * 0.15, y: size * 0.15)
    }

    private func unmappedKeyContent(labelSize: CGFloat) -> some View {
        // Just the letter, centered, dimmed
        Text(displayLabel.uppercased())
            .font(.system(size: labelSize * 1.2, weight: .medium))
            .foregroundColor(.secondary.opacity(0.4))
    }

    // MARK: - Styling

    private var backgroundColor: Color {
        if isCapsLockKey {
            // Caps lock is always "pressed" in launcher view
            .accentColor
        } else if mapping != nil {
            // Mapped key: accent color
            isSelected ? .accentColor : .accentColor.opacity(0.85)
        } else {
            // Unmapped key: dimmed
            Color(NSColor.controlBackgroundColor).opacity(0.5)
        }
    }

    private var strokeColor: Color {
        if isSelected {
            .white
        } else if mapping != nil {
            .white.opacity(0.2)
        } else {
            Color.secondary.opacity(0.2)
        }
    }

    private var accessibilityLabel: String {
        if isCapsLockKey {
            "Hyper key (Caps Lock)"
        } else if let mapping {
            "\(displayLabel.uppercased()): \(mapping.target.displayName)"
        } else {
            "\(displayLabel.uppercased()): Unmapped"
        }
    }

    // MARK: - Icon Loading

    private func loadIcon() async {
        guard let mapping else {
            icon = nil
            return
        }

        switch mapping.target {
        case .app, .folder, .script:
            icon = AppIconResolver.icon(for: mapping.target)
        case let .url(urlString):
            icon = await FaviconFetcher.shared.fetchFavicon(for: urlString)
        }
    }

    /// Fallback SF Symbol name based on target type
    private var fallbackIconName: String {
        guard let target = mapping?.target else { return "questionmark" }
        switch target {
        case .app: return "app.fill"
        case .url: return "globe"
        case .folder: return "folder.fill"
        case .script: return "terminal.fill"
        }
    }
}

// MARK: - Preview

#Preview("Launcher Keycaps") {
    HStack(spacing: 8) {
        // Caps lock (Hyper)
        LauncherKeycapView(
            key: PhysicalKey(keyCode: 57, label: "⇪", x: 0, y: 0, width: 1.8),
            displayLabel: "⇪",
            accessibilityKey: "caps",
            mapping: nil,
            isSelected: false,
            onTap: {}
        )
        .frame(width: 70, height: 50)

        // Mapped app key
        LauncherKeycapView(
            key: PhysicalKey(keyCode: 1, label: "s", x: 0, y: 0),
            displayLabel: "S",
            accessibilityKey: "s",
            mapping: LauncherMapping(
                key: "s",
                target: .app(name: "Safari", bundleId: "com.apple.Safari")
            ),
            isSelected: false,
            onTap: {}
        )
        .frame(width: 50, height: 50)

        // Selected key
        LauncherKeycapView(
            key: PhysicalKey(keyCode: 17, label: "t", x: 0, y: 0),
            displayLabel: "T",
            accessibilityKey: "t",
            mapping: LauncherMapping(
                key: "t",
                target: .app(name: "Terminal", bundleId: "com.apple.Terminal")
            ),
            isSelected: true,
            onTap: {}
        )
        .frame(width: 50, height: 50)

        // Website key
        LauncherKeycapView(
            key: PhysicalKey(keyCode: 18, label: "1", x: 0, y: 0),
            displayLabel: "1",
            accessibilityKey: "1",
            mapping: LauncherMapping(
                key: "1",
                target: .url("github.com")
            ),
            isSelected: false,
            onTap: {}
        )
        .frame(width: 50, height: 50)

        // Unmapped key
        LauncherKeycapView(
            key: PhysicalKey(keyCode: 4, label: "h", x: 0, y: 0),
            displayLabel: "H",
            accessibilityKey: "h",
            mapping: nil,
            isSelected: false,
            onTap: {}
        )
        .frame(width: 50, height: 50)
    }
    .padding()
    .background(Color(white: 0.15))
}

#Preview("Launcher Keycaps - Dark Unmapped") {
    HStack(spacing: 8) {
        LauncherKeycapView(
            key: PhysicalKey(keyCode: 4, label: "h", x: 0, y: 0),
            displayLabel: "H",
            accessibilityKey: "h",
            mapping: nil,
            isSelected: false,
            onTap: {}
        )
        .frame(width: 50, height: 50)

        LauncherKeycapView(
            key: PhysicalKey(keyCode: 37, label: "l", x: 0, y: 0),
            displayLabel: "L",
            accessibilityKey: "l",
            mapping: nil,
            isSelected: true,
            onTap: {}
        )
        .frame(width: 50, height: 50)
    }
    .padding()
    .background(Color.black)
}
