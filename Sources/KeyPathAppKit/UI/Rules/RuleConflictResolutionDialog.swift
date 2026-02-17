import SwiftUI

// MARK: - Rule Conflict Types

/// A single key mapping for display in conflict resolution
struct ConflictMapping: Sendable, Equatable, Identifiable {
    let input: String
    let output: String

    var id: String {
        input
    }
}

/// Snapshot of a rule source for conflict resolution UI (Sendable for state transfer)
struct RuleConflictSourceSnapshot: Sendable, Equatable {
    let name: String
    let icon: String
    let summary: String
    let mappings: [ConflictMapping]

    /// Memberwise initializer for direct construction
    init(name: String, icon: String, summary: String, mappings: [ConflictMapping]) {
        self.name = name
        self.icon = icon
        self.summary = summary
        self.mappings = mappings
    }

    /// Create a snapshot from a RuleConflictInfo.Source
    @MainActor
    init(from source: RuleConflictInfo.Source) {
        name = source.name
        icon = source.icon
        summary = source.summary
        // Copy all mappings for later filtering
        switch source {
        case let .collection(collection):
            mappings = collection.mappings.map { ConflictMapping(input: $0.input, output: $0.output) }
        case let .customRule(rule):
            mappings = [ConflictMapping(input: rule.input, output: rule.output)]
        }
    }
}

/// Represents a conflict between two rule sources for UI presentation (Sendable)
struct RuleConflictContext: Sendable, Equatable {
    let newRule: RuleConflictSourceSnapshot
    let existingRule: RuleConflictSourceSnapshot
    let conflictingKeys: [String]

    /// Memberwise initializer for direct construction (used by previews)
    init(newRule: RuleConflictSourceSnapshot, existingRule: RuleConflictSourceSnapshot, conflictingKeys: [String]) {
        self.newRule = newRule
        self.existingRule = existingRule
        self.conflictingKeys = conflictingKeys
    }

    /// Create a context from RuleConflictInfo sources
    @MainActor
    init(newRule: RuleConflictInfo.Source, existingRule: RuleConflictInfo.Source, conflictingKeys: [String]) {
        self.newRule = RuleConflictSourceSnapshot(from: newRule)
        self.existingRule = RuleConflictSourceSnapshot(from: existingRule)
        self.conflictingKeys = conflictingKeys
    }
}

/// User's choice when resolving a rule conflict
enum RuleConflictChoice: Sendable {
    case keepNew
    case keepExisting
}

// MARK: - Rule Conflict Resolution Dialog

/// A dialog that appears when enabling a rule that conflicts with an existing rule
struct RuleConflictResolutionDialog: View {
    let context: RuleConflictContext
    let onChoice: (RuleConflictChoice) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection

            Divider()

            // Conflicting keys display
            conflictingKeysSection

            Divider()

            // Side-by-side rule cards
            ruleCardsSection

            Divider()

            // Action buttons
            actionButtons
        }
        .frame(width: 520)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Header Section

    private var headerSection: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 12) {
                // Icons with VS
                HStack(spacing: 20) {
                    ruleIcon(for: context.newRule)
                        .foregroundColor(.blue)

                    Text("VS")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.secondary.opacity(0.15))
                        )

                    ruleIcon(for: context.existingRule)
                        .foregroundColor(.orange)
                }

                Text("Rule Conflict")
                    .font(.title2.weight(.semibold))

                Text("Both rules want to control the same keys. Choose which rule to keep enabled.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
            }

            Button {
                onCancel()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 22, height: 22)
                    .background(
                        Circle()
                            .fill(Color.secondary.opacity(0.16))
                    )
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityIdentifier("rule-conflict-close-button")
            .accessibilityLabel("Close")
            .padding(.top, 2)
            .padding(.trailing, 2)
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 20)
    }

    private func ruleIcon(for source: RuleConflictSourceSnapshot) -> some View {
        Image(systemName: source.icon)
            .font(.title)
    }

    // MARK: - Conflicting Keys Section

    private var conflictingKeysSection: some View {
        VStack(spacing: 8) {
            Text("Conflicting Keys")
                .font(.caption.weight(.medium))
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                ForEach(context.conflictingKeys.prefix(8), id: \.self) { key in
                    Text(KeyDisplayName.display(for: key))
                        .font(.system(.body, design: .monospaced).weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.red.opacity(0.1))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.red.opacity(0.3), lineWidth: 1)
                        )
                }

                if context.conflictingKeys.count > 8 {
                    Text("+\(context.conflictingKeys.count - 8) more")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 16)
    }

    // MARK: - Rule Cards Section

    private var ruleCardsSection: some View {
        HStack(alignment: .top, spacing: 16) {
            // New rule card (the one user is trying to enable)
            ruleCard(
                source: context.newRule,
                label: "Enable This",
                accentColor: .blue,
                isNew: true,
                isPrimaryAction: false
            ) {
                onChoice(.keepNew)
            }

            // Existing rule card (the one already enabled)
            ruleCard(
                source: context.existingRule,
                label: "Keep This",
                accentColor: .orange,
                isNew: false,
                isPrimaryAction: true
            ) {
                onChoice(.keepExisting)
            }
        }
        .padding(20)
    }

    private func ruleCard(
        source: RuleConflictSourceSnapshot,
        label: String,
        accentColor: Color,
        isNew: Bool,
        isPrimaryAction: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let mappings = relevantMappings(from: source, for: context.conflictingKeys)

        return VStack(alignment: .leading, spacing: 12) {
            ruleCardHeader(source: source, accentColor: accentColor, isNew: isNew)
            ruleCardSummary(source: source)

            if !mappings.isEmpty {
                ruleCardMappings(mappings: mappings, accentColor: accentColor)
            }

            Spacer()

            ruleCardActionButton(
                label: label,
                accentColor: accentColor,
                isNew: isNew,
                isPrimaryAction: isPrimaryAction,
                action: action
            )
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 200)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(accentColor.opacity(0.3), lineWidth: 1)
        )
    }

    private func ruleCardHeader(
        source: RuleConflictSourceSnapshot,
        accentColor: Color,
        isNew: Bool
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: source.icon)
                .font(.title3)
                .foregroundColor(accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(source.name)
                    .font(.headline)
                    .lineLimit(1)

                Text(isNew ? "New" : "Currently Enabled")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }

    private func ruleCardSummary(source: RuleConflictSourceSnapshot) -> some View {
        Text(source.summary)
            .font(.subheadline)
            .foregroundColor(.secondary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func ruleCardMappings(mappings: [ConflictMapping], accentColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(mappings.prefix(4))) { mapping in
                HStack(spacing: 4) {
                    Text(KeyDisplayName.display(for: mapping.input))
                        .font(.system(.caption, design: .monospaced))
                    Text("→")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(KeyDisplayName.display(for: mapping.output))
                        .font(.system(.caption, design: .monospaced))
                }
            }

            if mappings.count > 4 {
                Text("... and \(mappings.count - 4) more")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(accentColor.opacity(0.05))
        )
    }

    @ViewBuilder
    private func ruleCardActionButton(
        label: String,
        accentColor: Color,
        isNew: Bool,
        isPrimaryAction: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let button = Button(action: action) {
            HStack {
                Spacer()
                Text(label)
                    .font(.body.weight(.medium))
                Spacer()
            }
            .padding(.vertical, 8)
        }
        .tint(accentColor)
        .keyboardShortcut(isPrimaryAction ? .defaultAction : nil)
        .accessibilityIdentifier("rule-conflict-\(isNew ? "enable-new" : "keep-existing")-button")
        .accessibilityLabel(label)

        if isPrimaryAction {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }

    /// Get mappings that are relevant to the given conflicting keys
    private func relevantMappings(
        from source: RuleConflictSourceSnapshot,
        for conflictingKeys: [String]
    ) -> [ConflictMapping] {
        let conflictSet = Set(conflictingKeys)
        return source.mappings.filter { mapping in
            conflictSet.contains(KanataKeyConverter.convertToKanataKey(mapping.input))
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack {
            Spacer()
            Text("The disabled rule can be re-enabled later")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(20)
    }
}

// MARK: - RuleConflictInfo.Source Extensions

extension RuleConflictInfo.Source {
    /// SF Symbol icon for this rule source
    var icon: String {
        switch self {
        case let .collection(collection):
            collection.icon ?? "square.stack.3d.up"
        case .customRule:
            "pencil.circle"
        }
    }

    /// Summary description for this rule source
    var summary: String {
        switch self {
        case let .collection(collection):
            collection.summary
        case let .customRule(rule):
            rule.notes ?? "Custom key mapping"
        }
    }
}

// MARK: - Preview

#if DEBUG
    struct RuleConflictResolutionDialog_Previews: PreviewProvider {
        static var previews: some View {
            // Create sample snapshots for preview
            let vimSnapshot = RuleConflictSourceSnapshot(
                name: "Vim Navigation",
                icon: "keyboard",
                summary: "HJKL as arrow keys",
                mappings: [
                    ConflictMapping(input: "h", output: "left"),
                    ConflictMapping(input: "j", output: "down"),
                    ConflictMapping(input: "k", output: "up"),
                    ConflictMapping(input: "l", output: "right")
                ]
            )

            let colemakSnapshot = RuleConflictSourceSnapshot(
                name: "Colemak Layout",
                icon: "keyboard.badge.ellipsis",
                summary: "Alternative keyboard layout",
                mappings: [
                    ConflictMapping(input: "h", output: "d"),
                    ConflictMapping(input: "j", output: "n"),
                    ConflictMapping(input: "k", output: "e"),
                    ConflictMapping(input: "l", output: "i")
                ]
            )

            let context = RuleConflictContext(
                newRule: vimSnapshot,
                existingRule: colemakSnapshot,
                conflictingKeys: ["h", "j", "k", "l"]
            )

            RuleConflictResolutionDialog(
                context: context,
                onChoice: { _ in },
                onCancel: {}
            )
        }
    }
#endif
