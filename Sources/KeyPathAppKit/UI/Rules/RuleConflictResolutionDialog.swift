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

            // Action buttons
            actionButtons
        }
        .frame(width: 400)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Header Section

    private var headerSection: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 8) {
                Text("Switch to \(context.newRule.name)?")
                    .font(.title2.weight(.semibold))

                Text("This will disable \(context.existingRule.name) since both use the same keys.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)

                Text("The disabled rule can be re-enabled later.")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.6))
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

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                onChoice(.keepExisting)
            } label: {
                HStack {
                    Spacer()
                    Text("Keep \(context.existingRule.name)")
                        .font(.body.weight(.medium))
                    Spacer()
                }
                .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("rule-conflict-keep-existing-button")
            .accessibilityLabel("Keep \(context.existingRule.name)")

            Button {
                onChoice(.keepNew)
            } label: {
                HStack {
                    Spacer()
                    Text("Switch to \(context.newRule.name)")
                        .font(.body.weight(.medium))
                    Spacer()
                }
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("rule-conflict-enable-new-button")
            .accessibilityLabel("Switch to \(context.newRule.name)")
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
