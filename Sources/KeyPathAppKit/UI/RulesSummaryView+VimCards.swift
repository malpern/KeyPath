import KeyPathCore
import SwiftUI

#if os(macOS)
    import AppKit
#endif

// MARK: - Vim Command Cards View

/// An animated, educational view for Vim navigation commands organized by category.
/// Uses a 2-column layout with equal-height rows and hover effects.
struct VimCommandCardsView: View {
    let mappings: [KeyMapping]

    @State private var hasAppeared = false

    private var categories: [VimCategory] {
        VimCategory.allCases.filter { !commandsFor($0).isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Row 1: Navigation + Editing
            HStack(alignment: .top, spacing: 12) {
                if let nav = categories.first(where: { $0 == .navigation }) {
                    cardView(for: nav, index: 0)
                }
                if let edit = categories.first(where: { $0 == .editing }) {
                    cardView(for: edit, index: 1)
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            // Row 2: Search + Clipboard
            HStack(alignment: .top, spacing: 12) {
                if let search = categories.first(where: { $0 == .search }) {
                    cardView(for: search, index: 2)
                }
                if let clip = categories.first(where: { $0 == .clipboard }) {
                    cardView(for: clip, index: 3)
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            // Shift tip
            HStack(spacing: 6) {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.yellow)
                    .font(.caption)
                Text("Hold ⇧ Shift while navigating to select text")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 4)
            .opacity(hasAppeared ? 1 : 0)
            .animation(.easeOut.delay(0.5), value: hasAppeared)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                hasAppeared = true
            }
        }
    }

    private func cardView(for category: VimCategory, index: Int) -> some View {
        VimCategoryCard(
            category: category,
            commands: commandsFor(category)
        )
        .scaleEffect(hasAppeared ? 1 : 0.8)
        .opacity(hasAppeared ? 1 : 0)
        .animation(
            .spring(response: 0.5, dampingFraction: 0.7)
                .delay(Double(index) * 0.1),
            value: hasAppeared
        )
    }

    private func commandsFor(_ category: VimCategory) -> [KeyMapping] {
        let inputs = category.commandInputs
        return mappings.filter { inputs.contains($0.input.lowercased()) }
    }
}

// MARK: - Vim Category Enum

enum VimCategory: String, CaseIterable, Identifiable {
    case navigation
    case editing
    case search
    case clipboard

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .navigation: "Navigation"
        case .editing: "Editing"
        case .search: "Search"
        case .clipboard: "Clipboard"
        }
    }

    var icon: String {
        switch self {
        case .navigation: "arrow.up.arrow.down"
        case .editing: "scissors"
        case .search: "magnifyingglass"
        case .clipboard: "doc.on.clipboard"
        }
    }

    var commandInputs: [String] {
        switch self {
        case .navigation: ["h", "j", "k", "l", "0", "4", "a", "g"]
        case .editing: ["x", "r", "d", "u", "o"]
        case .search: ["/", "n"]
        case .clipboard: ["y", "p"]
        }
    }

    var accentColor: Color {
        switch self {
        case .navigation: .blue
        case .editing: .orange
        case .search: .purple
        case .clipboard: .green
        }
    }
}

// MARK: - Vim Category Card

struct VimCategoryCard: View {
    let category: VimCategory
    let commands: [KeyMapping]

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with icon and title
            HStack(spacing: 8) {
                Image(systemName: category.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isHovered ? .white : category.accentColor)
                    .symbolEffect(.bounce, value: isHovered)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isHovered ? category.accentColor : category.accentColor.opacity(0.15))
                    )

                Text(category.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)

                Spacer()
            }

            // Special HJKL cluster for navigation
            if category == .navigation {
                VimArrowKeysCompact()
                    .padding(.vertical, 4)
            }

            // Command list
            VStack(alignment: .leading, spacing: 2) {
                ForEach(commands, id: \.id) { command in
                    VimCommandRowCompact(command: command, accentColor: category.accentColor)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor).opacity(isHovered ? 0.9 : 0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(category.accentColor.opacity(isHovered ? 0.5 : 0.2), lineWidth: isHovered ? 2 : 1)
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .shadow(color: category.accentColor.opacity(isHovered ? 0.2 : 0), radius: 8, x: 0, y: 4)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Vim Arrow Keys View (HJKL with directional pulse)

struct VimArrowKeysView: View {
    var body: some View {
        VStack(spacing: 8) {
            // Arrow key cluster
            HStack(spacing: 20) {
                // Left side labels
                VStack(alignment: .trailing, spacing: 4) {
                    Text("← H")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                    Text("Move left")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                // Center cluster (J K)
                VStack(spacing: 4) {
                    VimArrowKey(key: "K", direction: .up)
                    HStack(spacing: 4) {
                        VimArrowKey(key: "H", direction: .left)
                        VimArrowKey(key: "J", direction: .down)
                        VimArrowKey(key: "L", direction: .right)
                    }
                }

                // Right side labels
                VStack(alignment: .leading, spacing: 4) {
                    Text("L →")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                    Text("Move right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

// MARK: - Vim Arrow Key (with directional pulse)

struct VimArrowKey: View {
    let key: String
    let direction: ArrowDirection

    @State private var isHovered = false
    @State private var pulseOffset: CGSize = .zero
    @State private var pulseOpacity: Double = 0

    enum ArrowDirection {
        case up, down, left, right

        var arrow: String {
            switch self {
            case .up: "↑"
            case .down: "↓"
            case .left: "←"
            case .right: "→"
            }
        }

        var offset: CGSize {
            switch self {
            case .up: CGSize(width: 0, height: -12)
            case .down: CGSize(width: 0, height: 12)
            case .left: CGSize(width: -12, height: 0)
            case .right: CGSize(width: 12, height: 0)
            }
        }
    }

    var body: some View {
        ZStack {
            // Pulse arrow (animated)
            Text(direction.arrow)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.blue)
                .offset(pulseOffset)
                .opacity(pulseOpacity)

            // Key label
            Text(key)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(isHovered ? .blue : .primary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isHovered ? Color.blue.opacity(0.5) : Color.secondary.opacity(0.2), lineWidth: 1)
                )
        }
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                triggerPulse()
            }
        }
    }

    private func triggerPulse() {
        // Reset
        pulseOffset = .zero
        pulseOpacity = 0.8

        // Animate outward
        withAnimation(.easeOut(duration: 0.4)) {
            pulseOffset = direction.offset
            pulseOpacity = 0
        }
    }
}

// MARK: - Vim Command Row

struct VimCommandRow: View {
    let command: KeyMapping
    let accentColor: Color

    var body: some View {
        HStack(spacing: 12) {
            // Key
            StandardKeyBadge(key: command.input, color: accentColor)

            // Description
            if let desc = command.description {
                Text(desc)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
            }

            Spacer()

            // Shift variant indicator
            if command.shiftedOutput != nil {
                HStack(spacing: 2) {
                    Text("+⇧")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.orange)
                }
            }

            // Ctrl variant indicator
            if command.ctrlOutput != nil {
                HStack(spacing: 2) {
                    Text("+⌃")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.cyan)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

// MARK: - Vim Arrow Keys Compact (for 2-column layout)

struct VimArrowKeysCompact: View {
    var body: some View {
        HStack(spacing: 4) {
            ForEach(["H", "J", "K", "L"], id: \.self) { key in
                VimKeyBadge(key: key, color: .blue)
            }
            Text("= Arrow keys")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Vim Key Badge

struct VimKeyBadge: View {
    let key: String
    let color: Color

    @State private var isHovered = false

    var body: some View {
        Text(key)
            .font(.system(size: 14, weight: .semibold, design: .monospaced))
            .foregroundColor(isHovered ? .white : color)
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isHovered ? color : color.opacity(0.15))
            )
            .scaleEffect(isHovered ? 1.1 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isHovered)
            .onHover { isHovered = $0 }
    }
}

// MARK: - Standard Key Badge

/// Consistent key badge styling used across all rule displays
struct StandardKeyBadge: View {
    let key: String
    var color: Color = .blue

    var body: some View {
        Text(key.uppercased())
            .font(.system(size: 14, weight: .semibold, design: .monospaced))
            .foregroundColor(color)
            .frame(minWidth: 26, minHeight: 26)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(color.opacity(0.1))
            )
    }
}

// MARK: - Vim Command Row Compact

struct VimCommandRowCompact: View {
    let command: KeyMapping
    let accentColor: Color

    var body: some View {
        HStack(spacing: 8) {
            // Key
            StandardKeyBadge(key: command.input, color: accentColor)

            // Description
            if let desc = command.description {
                Text(desc)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            // Modifier indicators
            if command.shiftedOutput != nil {
                Text("⇧")
                    .font(.system(size: 9))
                    .foregroundColor(.orange)
            }
            if command.ctrlOutput != nil {
                Text("⌃")
                    .font(.system(size: 9))
                    .foregroundColor(.cyan)
            }
        }
        .padding(.vertical, 2)
    }
}
