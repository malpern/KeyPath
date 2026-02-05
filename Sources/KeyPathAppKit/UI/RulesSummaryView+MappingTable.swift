import KeyPathCore
import SwiftUI

#if os(macOS)
import AppKit
#endif

// MARK: - Mapping Table Content

struct MappingTableContent: View {
    let mappings: [(input: String, output: String, shiftedOutput: String?, ctrlOutput: String?, description: String?, sectionBreak: Bool, enabled: Bool, id: UUID, behavior: MappingBehavior?)]

    private var hasShiftVariants: Bool {
        mappings.contains { $0.shiftedOutput != nil }
    }

    private var hasCtrlVariants: Bool {
        mappings.contains { $0.ctrlOutput != nil }
    }

    private var hasDescriptions: Bool {
        mappings.contains { $0.description != nil }
    }

    // Calculate column widths based on content
    private var keyColumnWidth: CGFloat {
        let maxInput = mappings.map { prettyKeyName($0.input) }.max(by: { $0.count < $1.count }) ?? ""
        return max(60, CGFloat(maxInput.count) * 10 + 20)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(spacing: 0) {
                headerCell("Key")
                    .frame(minWidth: 80, alignment: .leading)
                    .padding(.leading, 12)
                    .padding(.trailing, 24)
                if hasDescriptions {
                    headerCell("Description")
                        .frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
                }
                headerCell("Action")
                    .frame(width: 90)
                if hasShiftVariants {
                    headerCell("+ Shift ⇧", color: .orange)
                        .frame(width: 100)
                }
                if hasCtrlVariants {
                    headerCell("+ Ctrl ⌃", color: .cyan)
                        .frame(width: 100)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))

            // Data rows
            ForEach(Array(mappings.enumerated()), id: \.element.id) { _, mapping in
                // Section break separator (extra whitespace)
                if mapping.sectionBreak {
                    Spacer()
                        .frame(height: 12)
                }

                HStack(spacing: 0) {
                    keyCell(prettyKeyName(mapping.input))
                        .frame(minWidth: 80, alignment: .leading)
                        .padding(.leading, 12)
                        .padding(.trailing, 24)
                    if hasDescriptions {
                        descriptionCell(mapping.description)
                            .frame(minWidth: 150, maxWidth: .infinity)
                    }
                    actionCell(formatOutput(mapping.output))
                        .frame(width: 90)
                    if hasShiftVariants {
                        modifierCell(mapping.shiftedOutput.map { formatOutput($0) }, color: .orange)
                            .frame(width: 100)
                    }
                    if hasCtrlVariants {
                        modifierCell(mapping.ctrlOutput.map { formatOutput($0) }, color: .cyan)
                            .frame(width: 100)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
            }
            .padding(.vertical, 4)
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func headerCell(_ text: String, color: Color = .secondary) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundColor(color)
    }

    @ViewBuilder
    private func keyCell(_ text: String) -> some View {
        StandardKeyBadge(key: formatKeyForDisplay(text), color: .blue)
            .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private func descriptionCell(_ text: String?) -> some View {
        Text(text ?? "")
            .font(.body)
            .foregroundColor(.primary.opacity(0.8))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func actionCell(_ text: String) -> some View {
        Text(text)
            .font(.body.monospaced())
            .foregroundColor(.secondary)
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func modifierCell(_ text: String?, color: Color) -> some View {
        if let text {
            Text(text)
                .font(.body.monospaced())
                .foregroundColor(color.opacity(0.9))
                .fixedSize(horizontal: true, vertical: false)
                .frame(maxWidth: .infinity)
        } else {
            Text("—")
                .font(.body)
                .foregroundColor(.secondary.opacity(0.3))
                .frame(maxWidth: .infinity)
        }
    }

    private func prettyKeyName(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespaces)
            .capitalized
    }

    /// Format key name for display in Key column (show Mac modifier names & symbols)
    private func formatKeyForDisplay(_ key: String) -> String {
        let macModifiers: [String: String] = [
            // Command
            "Lmet": "⌘ Cmd",
            "Rmet": "⌘ Cmd",
            "Cmd": "⌘ Cmd",
            "Command": "⌘ Cmd",
            // Option/Alt
            "Lalt": "⌥ Opt",
            "Ralt": "⌥ Opt",
            "Alt": "⌥ Opt",
            "Option": "⌥ Opt",
            // Control
            "Lctl": "⌃ Ctrl",
            "Rctl": "⌃ Ctrl",
            "Ctrl": "⌃ Ctrl",
            "Control": "⌃ Ctrl",
            // Shift
            "Lsft": "⇧ Shift",
            "Rsft": "⇧ Shift",
            "Shift": "⇧ Shift",
            // Caps Lock
            "Caps": "⇪ Caps",
            "Capslock": "⇪ Caps",
            // Function keys stay as-is (F1, F2, etc.)
            // Special keys
            "Esc": "⎋ Esc",
            "Tab": "⇥ Tab",
            "Ret": "↩ Return",
            "Return": "↩ Return",
            "Enter": "↩ Return",
            "Spc": "␣ Space",
            "Space": "␣ Space",
            "Bspc": "⌫ Delete",
            "Backspace": "⌫ Delete",
            "Del": "⌦ Fwd Del",
            "Delete": "⌦ Fwd Del",
            // Arrow keys
            "Left": "←",
            "Right": "→",
            "Up": "↑",
            "Down": "↓",
            // Page navigation
            "Pgup": "Pg ↑",
            "Pgdn": "Pg ↓",
            "Home": "↖ Home",
            "End": "↘ End"
        ]

        // Check if we have a Mac-friendly name for this key
        if let macName = macModifiers[key] {
            return macName
        }

        // Handle modifier prefix notation (e.g., "C-M-A-up" -> "⌃⌘⌥↑")
        return formatModifierPrefixNotation(key, macModifiers: macModifiers)
    }

    /// Format modifier prefix notation (e.g., "C-M-A-up" -> "⌃⌘⌥↑")
    private func formatModifierPrefixNotation(_ key: String, macModifiers: [String: String]) -> String {
        // Modifier prefix symbols in Kanata notation
        let modifierPrefixes: [(prefix: String, symbol: String)] = [
            ("C-", "⌃"), // Control
            ("M-", "⌘"), // Meta/Command
            ("A-", "⌥"), // Alt/Option
            ("S-", "⇧") // Shift
        ]

        var remaining = key
        var symbols = ""

        // Extract modifier prefixes in order
        var foundModifier = true
        while foundModifier {
            foundModifier = false
            for (prefix, symbol) in modifierPrefixes {
                if remaining.hasPrefix(prefix) {
                    symbols += symbol
                    remaining = String(remaining.dropFirst(prefix.count))
                    foundModifier = true
                    break
                }
            }
        }

        // Format the base key
        let baseKey = remaining.isEmpty ? key : remaining
        let formattedBase: String = if let macName = macModifiers[baseKey.capitalized] {
            // Extract just the symbol part if it has a name (e.g., "↑" from "↑ Up")
            macName.components(separatedBy: " ").first ?? macName
        } else {
            baseKey.uppercased()
        }

        // Combine modifiers and base key
        if symbols.isEmpty {
            return formattedBase
        } else {
            return "\(symbols)\(formattedBase)"
        }
    }

    /// Format output for display (convert Kanata codes to readable symbols)
    private func formatOutput(_ output: String) -> String {
        // Split by space to handle multi-key sequences, format each part, rejoin with space
        output.split(separator: " ").map { part in
            String(part)
                // Multi-modifier combinations (order matters - longest first)
                .replacingOccurrences(of: "C-M-A-S-", with: "⌃⌘⌥⇧")
                .replacingOccurrences(of: "C-M-A-", with: "⌃⌘⌥")
                .replacingOccurrences(of: "M-S-", with: "⌘⇧")
                .replacingOccurrences(of: "C-S-", with: "⌃⇧")
                .replacingOccurrences(of: "A-S-", with: "⌥⇧")
                // Single modifiers
                .replacingOccurrences(of: "M-", with: "⌘")
                .replacingOccurrences(of: "A-", with: "⌥")
                .replacingOccurrences(of: "C-", with: "⌃")
                .replacingOccurrences(of: "S-", with: "⇧")
                // Arrow keys and special keys
                .replacingOccurrences(of: "left", with: "←")
                .replacingOccurrences(of: "right", with: "→")
                .replacingOccurrences(of: "up", with: "↑")
                .replacingOccurrences(of: "down", with: "↓")
                .replacingOccurrences(of: "ret", with: "↩")
                .replacingOccurrences(of: "bspc", with: "⌫")
                .replacingOccurrences(of: "del", with: "⌦")
                .replacingOccurrences(of: "pgup", with: "Pg↑")
                .replacingOccurrences(of: "pgdn", with: "Pg↓")
                .replacingOccurrences(of: "esc", with: "⎋")
        }.joined(separator: " ")
    }
}
