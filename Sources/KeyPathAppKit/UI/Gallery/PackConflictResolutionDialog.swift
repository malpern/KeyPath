import SwiftUI

struct PackConflictState: Identifiable {
    let id = UUID()
    let packToInstall: Pack
    let conflictingPacks: [(id: String, name: String)]

    var conflictNames: String {
        conflictingPacks.map(\.name).joined(separator: ", ")
    }
}

enum PackConflictChoice: Sendable {
    case keepInstalled
    case switchToNew
}

struct PackConflictResolutionDialog: View {
    let state: PackConflictState
    let onChoice: (PackConflictChoice) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()
            actionButtons
        }
        .frame(width: 400)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var headerSection: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 8) {
                Text("Switch to \(state.packToInstall.name)?")
                    .font(.title2.weight(.semibold))

                Text("This will turn off \(state.conflictNames) since they conflict.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)

                Text("The disabled pack can be re-enabled later.")
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
            .accessibilityIdentifier("pack-conflict-close-button")
            .accessibilityLabel("Close")
            .padding(.top, 2)
            .padding(.trailing, 2)
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 20)
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                onChoice(.keepInstalled)
            } label: {
                HStack {
                    Spacer()
                    Text("Keep \(state.conflictNames)")
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("pack-conflict-keep-existing-button")
            .accessibilityLabel("Keep \(state.conflictNames)")

            Button {
                onChoice(.switchToNew)
            } label: {
                HStack {
                    Spacer()
                    Text("Switch to \(state.packToInstall.name)")
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("pack-conflict-switch-button")
            .accessibilityLabel("Switch to \(state.packToInstall.name)")
        }
        .padding(20)
    }
}

#if DEBUG
    struct PackConflictResolutionDialog_Previews: PreviewProvider {
        static var previews: some View {
            PackConflictResolutionDialog(
                state: PackConflictState(
                    packToInstall: PackRegistry.kindaVim,
                    conflictingPacks: [(id: "com.keypath.pack.vim-navigation", name: "Vim Navigation")]
                ),
                onChoice: { _ in },
                onCancel: {}
            )
        }
    }
#endif
