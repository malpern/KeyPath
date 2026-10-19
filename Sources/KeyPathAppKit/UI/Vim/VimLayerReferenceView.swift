import KeyPathCore
import KeyPathRulesCore
import SwiftUI

/// Vim Navigation layer reference: the layer drawn on the user's keyboard, with a
/// list of the same commands grouped by intent underneath. Hovering a key or a row
/// highlights the other, so the map answers "where" and the list answers "what".
///
/// Used by the Gallery pack detail and the Rules row, so both show the pack the same way.
struct VimLayerReferenceView: View {
    let mappings: [KeyMapping]
    var activationHint: String?

    @State private var highlighted: String?
    @State private var modifier: VimLayerModifier = .none

    private var entries: [VimLayerReferenceEntry] {
        VimLayerReference.entries(from: mappings)
    }

    private var availableModifiers: [VimLayerModifier] {
        var result: [VimLayerModifier] = [.none]
        if entries.contains(where: { $0.shift != nil }) { result.append(.shift) }
        if entries.contains(where: { $0.ctrl != nil }) { result.append(.control) }
        return result
    }

    var body: some View {
        if entries.isEmpty {
            Text("Enable this collection to load its shortcuts.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: SettingsDesign.sectionContentGap) {
                header
                VimLayerKeyboardMap(entries: entries, modifier: modifier, highlighted: $highlighted)
                detailStrip
                VimLayerCommandList(entries: entries, highlighted: $highlighted)
            }
            .accessibilityIdentifier("vim-layer-reference")
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(activationHint ?? "Hold Space, then press a key. Release Space to type normally.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if availableModifiers.count > 1 {
                Picker("Show keys with", selection: $modifier) {
                    ForEach(availableModifiers) { mod in
                        Text(Self.pickerTitle(mod)).tag(mod)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .accessibilityIdentifier("vim-layer-reference-modifier-picker")
                .accessibilityLabel("Show keys with modifier")
            }
        }
    }

    private static func pickerTitle(_ modifier: VimLayerModifier) -> String {
        switch modifier {
        case .none: "Space"
        case .shift: "Space + ⇧"
        case .control: "Space + ⌃"
        }
    }

    private var detailStrip: some View {
        HStack(spacing: 8) {
            if let input = highlighted,
               let entry = entries.first(where: { $0.input == input }),
               let variant = entry.variant(for: modifier) ?? entry.variant(for: .none)
            {
                VimReferenceCap(text: "Space")
                Text("+").foregroundStyle(.tertiary)
                VimReferenceCap(text: variant.label)
                Text(variant.title)
                    .font(.callout.weight(.semibold))
                Text("sends")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                VimReferenceCap(text: variant.sends)
                Spacer(minLength: 0)
                if let category = entry.category {
                    Text(category.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(category.accentColor)
                }
            } else {
                Text(modifierHint)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, SettingsDesign.cardInset)
        .frame(minHeight: 40)
        .settingsGroupBackground()
        .accessibilityElement(children: .combine)
    }

    private var modifierHint: String {
        switch modifier {
        case .none: "Point at a key to see what it does and which Mac shortcut it sends."
        case .shift: "Holding Shift changes \(entries.count(where: { $0.shift != nil })) keys. The rest are dimmed."
        case .control: "Holding Control changes \(entries.count(where: { $0.ctrl != nil })) keys. The rest are dimmed."
        }
    }
}

// MARK: - Keyboard map

/// The layer drawn on the selected physical layout (geometry) and keymap (legends).
struct VimLayerKeyboardMap: View {
    let entries: [VimLayerReferenceEntry]
    let modifier: VimLayerModifier
    @Binding var highlighted: String?

    @AppStorage(LayoutPreferences.layoutIdKey) private var selectedLayoutId: String = LayoutPreferences.defaultLayoutId
    @AppStorage(KeymapPreferences.keymapIdKey) private var selectedKeymapId: String = LogicalKeymap.defaultId

    private struct DrawnKey: Identifiable {
        let id: UUID
        let name: String
        let legend: String
        let x: Double
        let y: Double
        let width: Double
        let height: Double
    }

    /// Mapping inputs use typed characters; the layout uses kanata key names.
    nonisolated static func keyName(forInput input: String) -> String {
        let aliases = [
            "/": "slash", ";": "semicolon", ",": "comma", ".": "dot",
            "'": "apostrophe", "[": "leftbrace", "]": "rightbrace", "-": "minus", "=": "equal",
            "spc": "space"
        ]
        return aliases[input] ?? input
    }

    private var drawnKeys: [DrawnKey] {
        let layout = PhysicalLayout.find(id: selectedLayoutId) ?? .macBookUS
        let keymap = LogicalKeymap.resolve(id: selectedKeymapId)
        let usable = layout.keys.filter {
            $0.keyCode != PhysicalKey.unmappedKeyCode && $0.keyCode < PhysicalKey.placeholderKeyCodeBase
        }
        // Drop the function row: the layer never uses it and it costs a row of height.
        let numberRowY = usable.first { OverlayKeyboardView.keyCodeToKanataName($0.keyCode) == "1" }?.visualY
        let keys = usable.filter { numberRowY == nil || $0.visualY >= numberRowY! - 0.25 }
        let minX = keys.map(\.visualX).min() ?? 0
        let minY = keys.map(\.visualY).min() ?? 0
        return keys.map { key in
            let name = OverlayKeyboardView.keyCodeToKanataName(key.keyCode).lowercased()
            let legend = keymap.label(for: key.keyCode, includeExtraKeys: false) ?? key.label
            return DrawnKey(
                id: key.id, name: name, legend: legend,
                x: key.visualX - minX, y: key.visualY - minY, width: key.width, height: key.height
            )
        }
    }

    var body: some View {
        let keys = drawnKeys
        let totalWidth = keys.map { $0.x + $0.width }.max() ?? 15
        let totalHeight = keys.map { $0.y + $0.height }.max() ?? 5
        let byName = Dictionary(entries.map { (Self.keyName(forInput: $0.input), $0) }, uniquingKeysWith: { first, _ in first })

        GeometryReader { geo in
            let unit = geo.size.width / totalWidth
            let gap = max(2, unit * 0.08)
            ZStack(alignment: .topLeading) {
                ForEach(keys) { key in
                    keyView(key, entry: byName[key.name], unit: unit)
                        .frame(width: key.width * unit - gap, height: key.height * unit - gap)
                        .offset(x: key.x * unit, y: key.y * unit)
                }
            }
        }
        .aspectRatio(totalWidth / totalHeight, contentMode: .fit)
        .frame(maxWidth: 760)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("vim-layer-keyboard-map")
    }

    @ViewBuilder
    private func keyView(_ key: DrawnKey, entry: VimLayerReferenceEntry?, unit: CGFloat) -> some View {
        if key.name == "space" || key.name == "spc" {
            VimLayerActivatorKey(modifier: modifier, compact: unit < 34)
        } else if let entry, let variant = entry.variant(for: modifier) {
            VimLayerMappedKey(
                entry: entry,
                variant: variant,
                showsTitle: unit >= 34,
                isHighlighted: highlighted == entry.input
            )
            .onHover { hovering in
                if hovering { highlighted = entry.input } else if highlighted == entry.input { highlighted = nil }
            }
        } else {
            VimLayerPlainKey(legend: key.legend, dimmed: entry != nil)
        }
    }
}

private struct VimLayerMappedKey: View {
    let entry: VimLayerReferenceEntry
    let variant: VimLayerReferenceEntry.Variant
    let showsTitle: Bool
    let isHighlighted: Bool

    private var accent: Color {
        entry.category?.accentColor ?? .secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(entry.capLabel)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
            if showsTitle {
                Text(VimLayerReference.capTitle(for: variant.title))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SettingsDesign.chipFill, in: .rect(cornerRadius: 6))
        .overlay(alignment: .bottom) {
            UnevenRoundedRectangle(bottomLeadingRadius: 6, bottomTrailingRadius: 6)
                .fill(accent)
                .frame(height: 3)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isHighlighted ? accent : SettingsDesign.groupStroke, lineWidth: isHighlighted ? 2 : 0.5)
        )
        .scaleEffect(isHighlighted ? 1.06 : 1)
        .animation(.easeOut(duration: 0.12), value: isHighlighted)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(variant.label), \(variant.title)")
        .accessibilityValue("Sends \(variant.sends)")
        .accessibilityIdentifier("vim-layer-key-\(entry.input)")
    }
}

private struct VimLayerPlainKey: View {
    let legend: String
    /// A layer key with no binding for the current modifier.
    let dimmed: Bool

    var body: some View {
        Text(legend.count == 1 ? legend.lowercased() : legend)
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // Outline only: the map's job is showing which keys do something, so keys
            // outside the layer recede instead of matching the mapped keys' chip fill.
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(SettingsDesign.groupStroke, lineWidth: 1))
            .opacity(dimmed ? 0.5 : 0.8)
            .accessibilityHidden(true)
    }
}

private struct VimLayerActivatorKey: View {
    let modifier: VimLayerModifier
    let compact: Bool

    private var text: String {
        switch modifier {
        case .none: compact ? "Space" : "Hold Space"
        case .shift: compact ? "Space ⇧" : "Hold Space + ⇧"
        case .control: compact ? "Space ⌃" : "Hold Space + ⌃"
        }
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.accentColor)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.accentColor.opacity(0.12), in: .rect(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1))
            .accessibilityLabel("Hold Space to use this layer")
    }
}

// MARK: - Command list

/// The same commands grouped by intent, with Shift/Control variants on a line underneath.
struct VimLayerCommandList: View {
    let entries: [VimLayerReferenceEntry]
    @Binding var highlighted: String?

    private struct Group: Identifiable {
        let id: String
        let title: String
        let icon: String
        let color: Color
        let entries: [VimLayerReferenceEntry]
        let showsArrowCluster: Bool
    }

    private var groups: [Group] {
        var result: [Group] = VimCategory.allCases.compactMap { category in
            let members = entries.filter { $0.category == category }
            guard !members.isEmpty else { return nil }
            let arrows = Set(VimLayerReference.arrowCluster.map(\.input))
            let hasCluster = category == .navigation && arrows.isSubset(of: Set(members.map(\.input)))
            return Group(
                id: category.rawValue,
                title: category.title,
                icon: category.icon,
                color: category.accentColor,
                entries: hasCluster ? members.filter { !arrows.contains($0.input) } : members,
                showsArrowCluster: hasCluster
            )
        }
        let others = entries.filter { $0.category == nil }
        if !others.isEmpty {
            result.append(Group(id: "more", title: "More", icon: "ellipsis", color: .secondary, entries: others, showsArrowCluster: false))
        }
        return result
    }

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 260), spacing: SettingsDesign.optionGap, alignment: .top)],
            alignment: .leading,
            spacing: SettingsDesign.optionGap
        ) {
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 6) {
                    SettingsSectionHeader(title: group.title, icon: group.icon, color: group.color)
                        .padding(.bottom, 2)
                    if group.showsArrowCluster {
                        arrowCluster
                    }
                    ForEach(group.entries) { entry in
                        row(entry)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .settingsGroupBackground()
            }
        }
        .accessibilityIdentifier("vim-layer-command-list")
    }

    private var arrowCluster: some View {
        HStack(spacing: 4) {
            ForEach(VimLayerReference.arrowCluster, id: \.input) { item in
                VStack(spacing: 0) {
                    Text(item.input).font(.system(size: 12, weight: .semibold, design: .monospaced))
                    Text(item.arrow).font(.system(size: 9, weight: .semibold)).foregroundStyle(VimCategory.navigation.accentColor)
                }
                .frame(width: 30, height: 32)
                .background(highlighted == item.input ? SettingsDesign.hoverFill : SettingsDesign.chipFill, in: .rect(cornerRadius: 5))
                .onHover { hovering in
                    if hovering { highlighted = item.input } else if highlighted == item.input { highlighted = nil }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(item.input), \(VimLayerReference.entry(forArrow: item.input))")
                .accessibilityIdentifier("vim-layer-row-\(item.input)")
            }
        }
        .padding(.bottom, 2)
    }

    private func row(_ entry: VimLayerReferenceEntry) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                VimReferenceCap(text: entry.listLabel)
                Text(entry.title)
                    .font(.callout)
                Spacer(minLength: 4)
                Text(entry.sends)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            if let shift = entry.shift {
                variantLine(shift, color: .orange)
            }
            if let ctrl = entry.ctrl {
                variantLine(ctrl, color: .cyan)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(highlighted == entry.input ? SettingsDesign.hoverFill : .clear, in: .rect(cornerRadius: 6))
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering { highlighted = entry.input } else if highlighted == entry.input { highlighted = nil }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("vim-layer-row-\(entry.input)")
    }

    private func variantLine(_ variant: VimLayerReferenceEntry.Variant, color: Color) -> some View {
        HStack(spacing: 6) {
            Text(variant.label)
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
            Text(variant.title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(variant.sends)
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
        }
        .padding(.leading, 34)
    }
}

/// Small keycap chip used in the list and the detail strip.
struct VimReferenceCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6)
            .frame(minWidth: 24, minHeight: 22)
            .background(SettingsDesign.chipFill, in: .rect(cornerRadius: 5))
    }
}

extension VimLayerReference {
    /// Spoken name for an arrow-cluster key, used by VoiceOver.
    static func entry(forArrow input: String) -> String {
        ["h": "Left", "j": "Down", "k": "Up", "l": "Right"][input] ?? input
    }
}
