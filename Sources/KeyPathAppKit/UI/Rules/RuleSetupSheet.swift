import KeyPathCore
import KeyPathRulesCore
import SwiftUI

typealias RuleSetupApply = @MainActor ([UUID]) async -> SaveResult

@MainActor
final class RuleSetupSession: Identifiable {
    let id = UUID()
    let context: RulePrerequisiteResolutionContext
    let apply: RuleSetupApply
    private var completion: ((SaveResult) -> Void)?

    init(context: RulePrerequisiteResolutionContext, apply: @escaping RuleSetupApply,
         completion: @escaping (SaveResult) -> Void)
    {
        self.context = context
        self.apply = apply
        self.completion = completion
    }

    func finish(_ result: SaveResult) {
        let callback = completion
        completion = nil
        callback?(result)
    }

    var initialSelections: [Int: UUID] {
        Dictionary(uniqueKeysWithValues: context.prerequisites.enumerated().compactMap { index, requirement in
            let ids = requirement.availableProviderCollectionIDs
            guard let selected = ids.first(where: { $0 == RuleCollectionIdentifier.leaderKey }) ?? ids.first else { return nil }
            return (index, selected)
        })
    }
}

struct RuleSetupSheet: View {
    let session: RuleSetupSession
    @State private var selections: [Int: UUID]
    @State private var saving = false
    @State private var error: String?

    init(session: RuleSetupSession) {
        self.session = session
        _selections = State(initialValue: session.initialSelections)
    }

    private var selectedIDs: [UUID] {
        Array(Set(selections.values)).sorted { $0.uuidString < $1.uuidString }
    }

    private var selectedNames: [String] {
        session.context.availableProviders.filter { selectedIDs.contains($0.id) }.map(\.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsDesign.sectionGap) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Set up \(session.context.candidate.name)").font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("Choose how to activate your shortcuts.").foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: SettingsDesign.sectionContentGap) {
                    ForEach(Array(session.context.prerequisites.enumerated()), id: \.offset) { index, requirement in
                        let providers = session.context.availableProviders.filter { requirement.availableProviderCollectionIDs.contains($0.id) }
                        SettingsCard {
                            VStack(alignment: .leading, spacing: SettingsDesign.rowGap) {
                                if providers.isEmpty {
                                    Label("No compatible supporting rule is available.", systemImage: "exclamationmark.triangle")
                                } else {
                                    let recommended = providers.first { $0.id == RuleCollectionIdentifier.leaderKey } ?? providers[0]
                                    providerChoice(recommended, index: index, recommended: true)
                                    if providers.count > 1 {
                                        DisclosureGroup("Another activation method") {
                                            VStack(spacing: SettingsDesign.optionGap) {
                                                ForEach(providers.filter { $0.id != recommended.id }) { provider in
                                                    providerChoice(provider, index: index, recommended: false)
                                                }
                                            }.padding(.top, SettingsDesign.rowGap)
                                        }
                                        .accessibilityIdentifier("rule-setup-alternatives-\(index)")
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 340)

            Label("Turns on \((selectedNames + [session.context.candidate.name]).joined(separator: " and ")).",
                  systemImage: "checklist")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("rule-setup-error")
            }
            Divider()
            HStack {
                if saving { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel") { session.finish(.failure(CancellationError())) }
                    .settingsAction().keyboardShortcut(.cancelAction)
                    .disabled(saving).accessibilityIdentifier("rule-setup-cancel")
                Button(saving ? "Enabling…" : "Enable \(session.context.candidate.name)") {
                    saving = true
                    error = nil
                    Task { @MainActor in
                        let result = await session.apply(selectedIDs)
                        saving = false
                        if result.success { session.finish(result) }
                        else { error = result.error?.localizedDescription ?? "Could not save. Your existing rules were kept. Try again." }
                    }
                }
                .settingsPrimaryAction().keyboardShortcut(.defaultAction)
                .disabled(saving || selections.count != session.context.prerequisites.count)
                .accessibilityIdentifier("rule-setup-enable")
            }
        }
        .padding(SettingsDesign.pageInset)
        .frame(width: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .onExitCommand { if !saving { session.finish(.failure(CancellationError())) } }
    }

    private func providerChoice(_ provider: RuleCollection, index: Int, recommended: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SettingsOptionCard(icon: provider.icon ?? "keyboard", title: provider.name,
                               subtitle: recommended ? "Recommended" : provider.summary,
                               isSelected: selections[index] == provider.id)
            {
                selections[index] = provider.id
                error = nil
            }
            .disabled(saving)
            .accessibilityIdentifier("rule-setup-provider-\(provider.id)")
            if selections[index] == provider.id {
                if provider.id == RuleCollectionIdentifier.leaderKey {
                    let key = provider.configuration.singleKeyPickerConfig?.selectedOutput ?? PreferencesService.shared.leaderKeyPreference.key
                    HStack(spacing: 6) {
                        Text(PreferencesService.shared.contextHUDTriggerMode == .holdToShow ? "Hold" : "Tap")
                        keycap(key == "space" || key == "spc" ? "Space" : key.uppercased())
                        if session.context.candidate.id == RuleCollectionIdentifier.windowSnapping {
                            Image(systemName: "arrow.right")
                            keycap("W")
                            Text("then a window shortcut")
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12)
                } else {
                    Text(provider.summary).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 12)
                }
            }
        }
    }

    private func keycap(_ label: String) -> some View {
        Text(label).font(.caption.monospaced().weight(.medium))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: SettingsDesign.optionRadius))
            .overlay(RoundedRectangle(cornerRadius: SettingsDesign.optionRadius).stroke(.secondary.opacity(0.3)))
    }
}
