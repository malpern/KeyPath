import SwiftUI

#if os(macOS)
    import AppKit
#endif

// MARK: - Vallack Zone Definitions

enum VallackZones {
    static let modifierKeyCodes: Set<UInt16> = [12, 13, 14, 32, 34, 31]
    static let activatorKeyCodes: Set<UInt16> = [3, 38]

    static let navMappingKeyCodes: Set<UInt16> = [
        4, 38, 40, 37, 32, 34, 16, 41,
        12, 13, 14, 15, 0, 1, 2, 5, 17, 9
    ]

    static let homeSubtitles: [UInt16: String] = [
        12: "⌃", 13: "⌥", 14: "⌘",
        32: "⌘", 34: "⌥", 31: "⌃",
        3: "NAV", 38: "NAV"
    ]

    static let navSubtitles: [UInt16: String] = [
        4: "←", 38: "↓", 40: "↑", 37: "→",
        32: "⌫", 34: "↵", 16: "⌘C", 41: "⌘V",
        12: "⇥", 13: "esc", 14: "◀Tab", 15: "Tab▶",
        0: "⌘⇥", 1: "Home", 2: "End", 5: "camera",
        17: "◀", 9: "▶"
    ]

    static func homeZones() -> [UInt16: KeyboardZone] {
        var zones: [UInt16: KeyboardZone] = [:]
        for code in modifierKeyCodes { zones[code] = .modifier }
        for code in activatorKeyCodes { zones[code] = .activator }
        return zones
    }

    static func navZones() -> [UInt16: KeyboardZone] {
        var zones: [UInt16: KeyboardZone] = [:]
        for code in navMappingKeyCodes { zones[code] = .navMapping }
        return zones
    }
}

// MARK: - Component Card

struct SystemPackComponentCard: View {
    let icon: String
    let title: String
    let summary: String
    let isExpanded: Bool
    let onToggle: () -> Void
    let content: AnyView

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(summary)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(isExpanded ? nil : 1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(.easeInOut(duration: 0.2), value: isExpanded)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                    .padding(.horizontal, 12)
                content
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
}

// MARK: - Main Content

struct VallackSystemPackContent: View {
    let navCollection: RuleCollection?
    let modsCollection: RuleCollection?
    let togglesCollection: RuleCollection?
    let isInstalled: Bool

    @State private var expandedComponent: String?
    @State private var selectedLayer: String = "home"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    layerTab(id: "home", icon: "keyboard", label: "Home")
                    layerTab(id: "nav", icon: "arrow.up.and.down.and.arrow.left.and.right", label: "Navigation")
                }

                VStack(spacing: 0) {
                    layerHint
                        .padding(.top, 16)
                        .padding(.horizontal, 12)

                    if selectedLayer == "home" {
                        ZonedKeyboardDiagram(
                            zones: VallackZones.homeZones(),
                            subtitles: VallackZones.homeSubtitles,
                            keycapSize: 35
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.top, 14)
                        .padding(.bottom, 20)
                        .padding(.horizontal, 12)
                    } else {
                        ZonedKeyboardDiagram(
                            zones: VallackZones.navZones(),
                            subtitles: VallackZones.navSubtitles,
                            keycapSize: 35
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.top, 14)
                        .padding(.bottom, 20)
                        .padding(.horizontal, 12)
                    }
                }
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.black.opacity(0.25))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                        )
                )
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: selectedLayer == "home" ? 0 : 8,
                        bottomLeadingRadius: 8,
                        bottomTrailingRadius: 8,
                        topTrailingRadius: selectedLayer == "nav" ? 0 : 8
                    )
                )
            }

            // How it works
            VStack(alignment: .leading, spacing: 6) {
                Text("How it works")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 4)

                SystemPackComponentCard(
                    icon: "hand.tap",
                    title: "Layer Activation",
                    summary: "Hold either index finger to enter nav",
                    isExpanded: expandedComponent == "toggles",
                    onToggle: { toggleExpanded("toggles") },
                    content: AnyView(activatorCardContent)
                )

                SystemPackComponentCard(
                    icon: "keyboard",
                    title: "Top Row Modifiers",
                    summary: "Tap for letters, hold for ⌃ ⌥ ⌘",
                    isExpanded: expandedComponent == "mods",
                    onToggle: { toggleExpanded("mods") },
                    content: AnyView(modsCardContent)
                )

                SystemPackComponentCard(
                    icon: "arrow.up.and.down.and.arrow.left.and.right",
                    title: "Navigation Mappings",
                    summary: "\(navCollection?.mappings.count ?? 0) keys — arrows, clipboard, tabs",
                    isExpanded: expandedComponent == "nav",
                    onToggle: { toggleExpanded("nav") },
                    content: AnyView(navCardContent)
                )
            }
        }
    }

    // MARK: - Layer Hint

    @ViewBuilder
    private var layerHint: some View {
        if selectedLayer == "nav" {
            HStack(spacing: 6) {
                Text("Hold")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                ZonedKeycap(label: "F", zone: .activator, size: 20)
                Text("or")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                ZonedKeycap(label: "J", zone: .activator, size: 20)
                Text("to enter  ·  release to exit")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        } else {
            HStack(spacing: 6) {
                Text("Normal typing with dual-role keys")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Layer Tab

    private func layerTab(id: String, icon: String, label: String) -> some View {
        let isSelected = selectedLayer == id
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { selectedLayer = id }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(isSelected ? .primary : .secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: 8,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 8
                )
                .fill(isSelected
                    ? Color.black.opacity(0.25)
                    : Color.clear)
                .overlay(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 8,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 8
                    )
                    .strokeBorder(isSelected
                        ? Color.white.opacity(0.08)
                        : Color.clear, lineWidth: 1)
                )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Card Content

    @ViewBuilder
    private var modsCardContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Modifiers move to the top row so the home row is free for layer toggles. Tap for the letter, hold for the modifier.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            MappingTableContent(
                mappings: [
                    ("q", "⌃", nil, nil, "Control", false, true, UUID(uuidString: "00000000-0000-0000-0000-000000000101")!, nil),
                    ("w", "⌥", nil, nil, "Option", false, true, UUID(uuidString: "00000000-0000-0000-0000-000000000102")!, nil),
                    ("e", "⌘", nil, nil, "Command", false, true, UUID(uuidString: "00000000-0000-0000-0000-000000000103")!, nil),
                    ("u", "⌘", nil, nil, "Command", true, true, UUID(uuidString: "00000000-0000-0000-0000-000000000104")!, nil),
                    ("i", "⌥", nil, nil, "Option", false, true, UUID(uuidString: "00000000-0000-0000-0000-000000000105")!, nil),
                    ("o", "⌃", nil, nil, "Control", false, true, UUID(uuidString: "00000000-0000-0000-0000-000000000106")!, nil),
                ]
            )
        }
    }

    @ViewBuilder
    private var activatorCardContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Hold either index finger to activate the navigation layer. Release to return to normal typing. Both activate the same layer — use whichever hand is free.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Text("Hold")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                StandardKeyBadge(key: "F", color: .orange)
                Text("or")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                StandardKeyBadge(key: "J", color: .orange)
                Text("→ navigation layer")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var navCardContent: some View {
        if let collection = navCollection {
            VStack(alignment: .leading, spacing: 8) {
                Text("Right hand navigates (HJKL arrows, backspace, enter). Left hand switches and edits (tabs, clipboard, escape).")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                MappingTableContent(
                    mappings: collection.mappings.map {
                        ($0.input, $0.action.displayName, $0.shiftedOutput, $0.ctrlOutput,
                         $0.description, $0.sectionBreak, isInstalled, $0.id, nil)
                    }
                )
            }
        }
    }

    private func toggleExpanded(_ id: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            expandedComponent = expandedComponent == id ? nil : id
        }
    }
}
