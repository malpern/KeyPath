import KeyPathRulesCore
import SwiftUI

/// The pack install preview (ADR-039 §5, decision 4): shown only when the
/// admission engine found a choice to make or something that blocks.
struct PackInstallPreviewState: Identifiable {
    let id = UUID()
    let pack: Pack
    let preview: PackInstallPreview
}

struct PackInstallPreviewSheet: View {
    let state: PackInstallPreviewState
    /// Called with what the user chose to turn off or remove.
    let onInstall: (_ disablingCollections: Set<UUID>, _ disablingRules: Set<UUID>, _ removingPacks: Set<String>) -> Void
    let onCancel: () -> Void

    @State private var chosenDisable: Set<UUID>
    @State private var chosenRemove: Set<String>

    init(state: PackInstallPreviewState,
         onInstall: @escaping (Set<UUID>, Set<UUID>, Set<String>) -> Void,
         onCancel: @escaping () -> Void)
    {
        self.state = state
        self.onInstall = onInstall
        self.onCancel = onCancel
        // Default to every offered resolution on, so one click installs.
        _chosenDisable = State(initialValue: Set(state.preview.disableOptions.map(\.id)))
        _chosenRemove = State(initialValue: Set(state.preview.removeOptions.map(\.packID)))
    }

    private var canInstall: Bool {
        // A block with no resolution offered here (a missing app) stays a block.
        !state.preview.blockingItems.contains { item in
            item.presentation.options.isEmpty || item.presentation.options.allSatisfy {
                if case .installApp = $0.fix { return true }
                return false
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(state.preview.isBlocked ? "\(state.pack.name) can't be installed yet" : "Install \(state.pack.name)?")
                    .font(.title2.weight(.semibold))
                Text(state.preview.isBlocked
                    ? "Something it needs isn't available."
                    : "Installing it changes what you already have. Choose what to turn off.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(state.preview.items) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Label(item.presentation.title, systemImage: icon(for: item.severity))
                                .font(.body.weight(.semibold))
                            Text(item.presentation.explanation)
                                .font(.callout)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            ForEach(item.presentation.options) { option in
                                optionRow(option)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .frame(maxHeight: 360)

            Divider()

            HStack {
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("pack-install-preview-cancel")
                Spacer()
                Button(state.preview.isBlocked && !canInstall ? "OK" : "Install") {
                    if canInstall {
                        onInstall(chosenDisable, Set(chosenDisableRules), chosenRemove)
                    } else {
                        onCancel()
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(state.preview.needsChoice && chosenDisable.isEmpty && chosenRemove.isEmpty && canInstall)
                .accessibilityIdentifier("pack-install-preview-confirm")
            }
            .padding(20)
        }
        .frame(width: 460)
        .background(Color(NSColor.windowBackgroundColor))
    }

    /// Collections are toggled by `additionalCollectionIDsToDisable`; custom rules
    /// are turned off in memory before the install. Both are chosen by id here.
    private var chosenDisableRules: [UUID] {
        state.preview.disableOptions
            .filter { if case .customRule = $0.subject { return chosenDisable.contains($0.id) }; return false }
            .map(\.id)
    }

    @ViewBuilder
    private func optionRow(_ option: AdmissionPresentation.Option) -> some View {
        switch option.fix {
        case let .disable(subject):
            if case let .pack(id) = subject {
                Toggle(option.label, isOn: binding(forPack: id))
                    .accessibilityIdentifier("pack-install-preview-remove-\(id)")
            } else if let entry = state.preview.disableOptions.first(where: { $0.subject == subject }) {
                Toggle(option.label, isOn: binding(forID: entry.id))
                    .accessibilityIdentifier("pack-install-preview-disable-\(entry.id.uuidString)")
            }
        case let .installApp(name, _):
            Link("Get \(name)", destination: URL(string: "https://kindavim.app")!)
                .font(.callout)
        case .moveCapsIntermediate:
            EmptyView()
        }
    }

    private func binding(forID id: UUID) -> Binding<Bool> {
        Binding(get: { chosenDisable.contains(id) },
                set: { on in if on { chosenDisable.insert(id) } else { chosenDisable.remove(id) } })
    }

    private func binding(forPack id: String) -> Binding<Bool> {
        Binding(get: { chosenRemove.contains(id) },
                set: { on in if on { chosenRemove.insert(id) } else { chosenRemove.remove(id) } })
    }

    private func icon(for severity: AdmissionVerdict.Severity) -> String {
        switch severity {
        case .blocking: "xmark.octagon"
        case .needsChoice: "exclamationmark.triangle"
        case .advisory: "info.circle"
        case .automatic: "checkmark.circle"
        }
    }
}
