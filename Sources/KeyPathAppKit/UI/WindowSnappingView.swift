import SwiftUI

// MARK: - Window Snapping View

/// A visual, interactive view for the Window Snapping rule collection.
/// Displays a monitor canvas with snap zones and floating action cards.
struct WindowSnappingView: View {
    let mappings: [KeyMapping]
    let convention: WindowKeyConvention
    let onConventionChange: (WindowKeyConvention) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Convention picker (leader key style)
            ConventionPicker(
                convention: convention,
                onConventionChange: onConventionChange
            )

            // Monitor canvas with snap zones
            MonitorCanvas(convention: convention)

            // Floating action cards row
            ActionCardsRow(convention: convention)

            // Tip
            HStack(spacing: 6) {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.yellow)
                    .font(.caption)
                Text("Activate via Leader → w, then press the action key")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Convention Picker

/// Native macOS segmented picker for key layout convention
private struct ConventionPicker: View {
    let convention: WindowKeyConvention
    let onConventionChange: (WindowKeyConvention) -> Void

    @State private var localConvention: WindowKeyConvention

    init(convention: WindowKeyConvention, onConventionChange: @escaping (WindowKeyConvention) -> Void) {
        self.convention = convention
        self.onConventionChange = onConventionChange
        _localConvention = State(initialValue: convention)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Native macOS segmented control
            Picker("Key Layout", selection: $localConvention) {
                Text("Standard").tag(WindowKeyConvention.standard)
                Text("Vim").tag(WindowKeyConvention.vim)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("window-snapping-convention-picker")
            .accessibilityLabel("Key layout convention")
            .onChange(of: localConvention) { _, newValue in
                onConventionChange(newValue)
            }
            .onChange(of: convention) { _, newValue in
                localConvention = newValue
            }

            // Description
            Text(convention.description)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Monitor Canvas

/// A stylized monitor showing window snap zones with embedded key badges.
private struct MonitorCanvas: View {
    let convention: WindowKeyConvention
    @State private var hoveredZone: SnapZone?

    var body: some View {
        VStack(spacing: 12) {
            // Quarter zones grid
            QuarterZonesGrid(convention: convention, hoveredZone: $hoveredZone)

            // Halves axis with maximize
            HalvesAxis(convention: convention, hoveredZone: $hoveredZone)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Quarter Zones Grid

private struct QuarterZonesGrid: View {
    let convention: WindowKeyConvention
    @Binding var hoveredZone: SnapZone?

    var body: some View {
        // Monitor frame
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ZoneCell(zone: .topLeft, convention: convention, hoveredZone: $hoveredZone)
                ZoneDivider(orientation: .vertical)
                ZoneCell(zone: .topRight, convention: convention, hoveredZone: $hoveredZone)
            }
            ZoneDivider(orientation: .horizontal)
            HStack(spacing: 0) {
                ZoneCell(zone: .bottomLeft, convention: convention, hoveredZone: $hoveredZone)
                ZoneDivider(orientation: .vertical)
                ZoneCell(zone: .bottomRight, convention: convention, hoveredZone: $hoveredZone)
            }
        }
        .frame(height: 140)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 2)
        )
        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
    }
}

// MARK: - Zone Cell

private struct ZoneCell: View {
    let zone: SnapZone
    let convention: WindowKeyConvention
    @Binding var hoveredZone: SnapZone?

    private var isHovered: Bool { hoveredZone == zone }

    var body: some View {
        ZStack {
            // Background fill on hover
            Rectangle()
                .fill(isHovered ? zone.color.opacity(0.3) : Color.clear)

            // Key badge
            SnapKeyBadge(
                key: zone.key(for: convention),
                color: zone.color,
                isHighlighted: isHovered
            )

            // Zone label (shown on hover)
            if isHovered {
                VStack {
                    Spacer()
                    Text(zone.label)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(zone.color)
                        .padding(.bottom, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                hoveredZone = hovering ? zone : nil
            }
        }
    }
}

// MARK: - Zone Divider

private struct ZoneDivider: View {
    enum Orientation { case horizontal, vertical }
    let orientation: Orientation

    var body: some View {
        switch orientation {
        case .horizontal:
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .frame(height: 1)
        case .vertical:
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .frame(width: 1)
        }
    }
}

// MARK: - Halves Axis

private struct HalvesAxis: View {
    let convention: WindowKeyConvention
    @Binding var hoveredZone: SnapZone?

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                // Left half
                HalfZoneButton(zone: .left, convention: convention, hoveredZone: $hoveredZone)

                // Visual connector
                Rectangle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(height: 2)

                // Maximize (center of axis)
                SnapKeyBadge(
                    key: SnapZone.maximize.key(for: convention),
                    color: SnapZone.maximize.color,
                    isHighlighted: hoveredZone == .maximize,
                    size: .large
                )
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.15)) {
                        hoveredZone = hovering ? .maximize : nil
                    }
                }

                // Visual connector
                Rectangle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(height: 2)

                // Right half
                HalfZoneButton(zone: .right, convention: convention, hoveredZone: $hoveredZone)
            }

            // Center button below
            HStack {
                Spacer()
                SnapKeyBadge(
                    key: SnapZone.center.key(for: convention),
                    color: SnapZone.center.color,
                    isHighlighted: hoveredZone == .center,
                    label: "Center"
                )
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.15)) {
                        hoveredZone = hovering ? .center : nil
                    }
                }
                Spacer()
            }
        }
    }
}

// MARK: - Half Zone Button

private struct HalfZoneButton: View {
    let zone: SnapZone
    let convention: WindowKeyConvention
    @Binding var hoveredZone: SnapZone?

    private var isHovered: Bool { hoveredZone == zone }

    var body: some View {
        HStack(spacing: 6) {
            if zone == .left {
                SnapKeyBadge(key: zone.key(for: convention), color: zone.color, isHighlighted: isHovered)
                Text(zone.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isHovered ? zone.color : .secondary)
            } else {
                Text(zone.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isHovered ? zone.color : .secondary)
                SnapKeyBadge(key: zone.key(for: convention), color: zone.color, isHighlighted: isHovered)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? zone.color.opacity(0.15) : Color.clear)
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                hoveredZone = hovering ? zone : nil
            }
        }
    }
}

// MARK: - Action Cards Row

private struct ActionCardsRow: View {
    let convention: WindowKeyConvention

    var body: some View {
        HStack(spacing: 12) {
            DisplaysCard(convention: convention)
            SpacesCard(convention: convention)
            UndoCard(convention: convention)
        }
    }
}

// MARK: - Displays Card

private struct DisplaysCard: View {
    let convention: WindowKeyConvention
    @State private var isHovered = false

    var body: some View {
        ActionCard(
            icon: "display.2",
            title: "Displays",
            isHovered: isHovered,
            accentColor: .orange
        ) {
            HStack(spacing: 8) {
                SnapKeyBadge(key: "[", color: .orange, isHighlighted: isHovered, size: .small)
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                SnapKeyBadge(key: "]", color: .orange, isHighlighted: isHovered, size: .small)
            }
        }
        .onHover { isHovered = $0 }
    }
}

// MARK: - Spaces Card

private struct SpacesCard: View {
    let convention: WindowKeyConvention
    @State private var isHovered = false

    private var prevKey: String {
        convention == .standard ? "," : "A"
    }

    private var nextKey: String {
        convention == .standard ? "." : "S"
    }

    var body: some View {
        ActionCard(
            icon: "square.stack.3d.up",
            title: "Spaces",
            isHovered: isHovered,
            accentColor: .cyan
        ) {
            HStack(spacing: 8) {
                SnapKeyBadge(key: prevKey, color: .cyan, isHighlighted: isHovered, size: .small)
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                SnapKeyBadge(key: nextKey, color: .cyan, isHighlighted: isHovered, size: .small)
            }
        }
        .onHover { isHovered = $0 }
    }
}

// MARK: - Undo Card

private struct UndoCard: View {
    let convention: WindowKeyConvention
    @State private var isHovered = false

    var body: some View {
        ActionCard(
            icon: "arrow.uturn.backward",
            title: "Undo",
            isHovered: isHovered,
            accentColor: .gray
        ) {
            SnapKeyBadge(key: "Z", color: .gray, isHighlighted: isHovered)
        }
        .onHover { isHovered = $0 }
    }
}

// MARK: - Action Card

private struct ActionCard<Content: View>: View {
    let icon: String
    let title: String
    let isHovered: Bool
    let accentColor: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 8) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isHovered ? .white : accentColor)
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(isHovered ? accentColor : accentColor.opacity(0.15))
                    )

                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primary)
            }

            // Content
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor).opacity(isHovered ? 0.9 : 0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(accentColor.opacity(isHovered ? 0.4 : 0.15), lineWidth: 1)
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
    }
}

// MARK: - Snap Key Badge

private struct SnapKeyBadge: View {
    let key: String
    let color: Color
    var isHighlighted: Bool = false
    var size: BadgeSize = .regular
    var label: String?

    /// Track displayed key and flip animation state
    @State private var displayedKey: String = ""
    @State private var flipAngle: Double = 0
    /// Randomized delay for this badge (0-0.15s)
    @State private var randomDelay: Double = 0
    /// Randomized duration multiplier (0.8-1.2x)
    @State private var durationMultiplier: Double = 1.0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum BadgeSize {
        case small, regular, large

        var dimension: CGFloat {
            switch self {
            case .small: 22
            case .regular: 28
            case .large: 34
            }
        }

        var fontSize: CGFloat {
            switch self {
            case .small: 11
            case .regular: 13
            case .large: 15
            }
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(displayedKey.uppercased())
                .font(.system(size: size.fontSize, weight: .semibold, design: .monospaced))
                .foregroundColor(isHighlighted ? .white : color)
                .frame(width: size.dimension, height: size.dimension)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHighlighted ? color : color.opacity(0.15))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(color.opacity(0.3), lineWidth: 1)
                )
                .scaleEffect(isHighlighted ? 1.1 : 1.0)
                .rotation3DEffect(
                    .degrees(flipAngle),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.5
                )
                .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isHighlighted)

            if let label {
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
            displayedKey = key
            // Generate random timing characteristics for this badge
            randomDelay = Double.random(in: 0 ... 0.12)
            durationMultiplier = Double.random(in: 0.8 ... 1.3)
        }
        .onChange(of: key) { oldKey, newKey in
            guard oldKey != newKey else { return }

            if reduceMotion {
                displayedKey = newKey
            } else {
                // Determine flip direction: Standard→Vim flips right (+90), Vim→Standard flips left (-90)
                // We detect direction by checking if we're going to a "vim-style" key
                let isGoingToVim = ["Y", "B", "N", "H"].contains(newKey.uppercased())
                let targetAngle: Double = isGoingToVim ? 90 : -90

                let baseDuration = 0.15 * durationMultiplier

                // Staggered start with random delay
                DispatchQueue.main.asyncAfter(deadline: .now() + randomDelay) {
                    // Flip out (to 90 or -90)
                    withAnimation(.easeIn(duration: baseDuration)) {
                        flipAngle = targetAngle
                    }
                    // Change key at midpoint and flip back in
                    DispatchQueue.main.asyncAfter(deadline: .now() + baseDuration) {
                        displayedKey = newKey
                        withAnimation(.easeOut(duration: baseDuration)) {
                            flipAngle = 0
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Snap Zone Model

private enum SnapZone: String, CaseIterable {
    // Corners
    case topLeft, topRight, bottomLeft, bottomRight
    // Halves
    case left, right
    // Full
    case maximize, center

    func key(for convention: WindowKeyConvention) -> String {
        switch convention {
        case .standard:
            switch self {
            case .topLeft: "U"
            case .topRight: "I"
            case .bottomLeft: "J"
            case .bottomRight: "K"
            case .left: "L"
            case .right: "R"
            case .maximize: "M"
            case .center: "C"
            }
        case .vim:
            switch self {
            case .topLeft: "Y"
            case .topRight: "U"
            case .bottomLeft: "B"
            case .bottomRight: "N"
            case .left: "H"
            case .right: "L"
            case .maximize: "M"
            case .center: "C"
            }
        }
    }

    var label: String {
        switch self {
        case .topLeft: "Top-Left"
        case .topRight: "Top-Right"
        case .bottomLeft: "Bottom-Left"
        case .bottomRight: "Bottom-Right"
        case .left: "Left"
        case .right: "Right"
        case .maximize: "Maximize"
        case .center: "Center"
        }
    }

    var color: Color {
        switch self {
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            .purple
        case .left, .right:
            .blue
        case .maximize, .center:
            .green
        }
    }
}

// MARK: - Preview

#Preview {
    WindowSnappingView(
        mappings: [],
        convention: .standard,
        onConventionChange: { _ in }
    )
    .frame(width: 400)
    .padding()
}
