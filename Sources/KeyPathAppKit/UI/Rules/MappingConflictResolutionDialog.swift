import Foundation
import SwiftUI

// MARK: - Mapping Conflict Types

/// A collection the user can disable to resolve a save-time mapping conflict (#460).
struct MappingConflictOption: Sendable, Equatable, Identifiable {
    let id: UUID
    let name: String
    let icon: String
}

/// Context for a save-time mapping conflict that can be resolved by disabling a
/// collection. Sendable so it can cross the actor boundary from the save task to
/// the UI. Built only when every conflicting party is a real, toggleable collection
/// (see `RuleCollectionsManager.resolvableCollectionConflict`).
struct MappingConflictContext: Sendable, Equatable {
    /// Plain-English explanation of the conflict(s).
    let explanation: String
    /// The collections involved — disabling one resolves the conflict.
    let options: [MappingConflictOption]
}

// MARK: - Mapping Conflict Resolution Dialog

/// Shown when saving a configuration fails because two enabled collections claim
/// the same key. Lets the user disable one inline instead of hunting through the
/// Rules tab.
struct MappingConflictResolutionDialog: View {
    let context: MappingConflictContext
    /// Called with the collection id to disable, or invoked via `onCancel` to dismiss.
    let onChoice: (UUID) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()
            actionButtons
        }
        .frame(width: 420)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var headerSection: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 8) {
                Text("Rule Conflict")
                    .font(.title2.weight(.semibold))

                Text(context.explanation)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)

                Text("Disable one to resolve. It can be re-enabled later.")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.6))
            }

            Button {
                onCancel()
            } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.secondary.opacity(0.16)))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityIdentifier("mapping-conflict-close-button")
            .accessibilityLabel("Close")
            .padding(.top, 2)
            .padding(.trailing, 2)
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 20)
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            ForEach(context.options) { option in
                Button {
                    onChoice(option.id)
                } label: {
                    HStack {
                        Image(systemName: option.icon)
                        Spacer()
                        Text("Disable \(option.name)")
                            .font(.body.weight(.medium))
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("mapping-conflict-disable-\(option.id.uuidString)")
                .accessibilityLabel("Disable \(option.name)")
            }
        }
        .padding(20)
    }
}

// MARK: - Preview

#if DEBUG
    struct MappingConflictResolutionDialog_Previews: PreviewProvider {
        static var previews: some View {
            MappingConflictResolutionDialog(
                context: MappingConflictContext(
                    explanation: "Home Row Mods and Home Row Layer Toggles both configure the \";\" key with different behaviors. A key can only have one action assigned.",
                    options: [
                        MappingConflictOption(id: UUID(), name: "Home Row Mods", icon: "keyboard"),
                        MappingConflictOption(id: UUID(), name: "Home Row Layer Toggles", icon: "square.stack.3d.up")
                    ]
                ),
                onChoice: { _ in },
                onCancel: {}
            )
        }
    }
#endif
