import KeyPathRulesCore
import SwiftUI

struct RulePrerequisiteDialogRowID: Hashable, Sendable {
    let consumerID: UUID
    let capability: RuleCapability
}

struct RulePrerequisiteDialogRow: Equatable, Identifiable, Sendable {
    let id: RulePrerequisiteDialogRowID
    let consumerName: String
    let capabilityName: String
    let providerSummary: String
    let evidence: [String]
}

/// A prepared, presentation-only snapshot for the prerequisite dialog.
///
/// Building this once when the request arrives keeps graph and collection
/// transformations out of SwiftUI's repeatedly evaluated view body.
struct RulePrerequisiteDialogModel: Equatable, Sendable {
    let operation: RulePrerequisiteOperation
    let candidateName: String
    let rows: [RulePrerequisiteDialogRow]
    let recommendedProviderNames: [String]
    let canEnableAll: Bool

    init(context: RulePrerequisiteResolutionContext) {
        operation = context.operation
        candidateName = context.candidate.name

        let consumersByID = Dictionary(
            context.affectedConsumers.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let providersByID = Dictionary(
            context.availableProviders.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        rows = context.prerequisites.map { prerequisite in
            let providerNames = prerequisite.availableProviderCollectionIDs.compactMap {
                providersByID[$0]?.name
            }
            return RulePrerequisiteDialogRow(
                id: RulePrerequisiteDialogRowID(
                    consumerID: prerequisite.consumerCollectionID,
                    capability: prerequisite.missingCapability
                ),
                consumerName: consumersByID[prerequisite.consumerCollectionID]?.name
                    ?? context.candidate.name,
                capabilityName: Self.capabilityName(prerequisite.missingCapability),
                providerSummary: Self.providerSummary(providerNames),
                evidence: Self.evidenceDescriptions(prerequisite.requirement.sortedEvidence)
            )
        }

        if let providerIDs = context.recommendedProviderIDs {
            canEnableAll = true
            recommendedProviderNames = providerIDs.compactMap { providersByID[$0]?.name }
        } else {
            canEnableAll = false
            recommendedProviderNames = []
        }
    }

    var primaryActionTitle: String {
        switch operation {
        case .enable:
            "Enable Required Rules & Turn On"
        case .save:
            "Enable Required Rules & Save"
        }
    }

    var secondaryActionTitle: String {
        switch operation {
        case .enable:
            "Turn On Without Them"
        case .save:
            "Save Without Them"
        }
    }

    var consequenceSummary: String {
        switch operation {
        case .enable:
            "Turning on \(candidateName) introduces requirements that are not active."
        case .save:
            "Saving \(candidateName) introduces requirements that are not active."
        }
    }

    private static func capabilityName(_ capability: RuleCapability) -> String {
        switch capability {
        case let .layerContent(layer):
            "\(displayName(layer.rawValue)) layer content"
        case let .layerActivation(layer):
            "a way to enter the \(displayName(layer.rawValue)) layer"
        case let .keyAlias(alias):
            switch alias {
            case .hyper:
                "the Hyper key"
            }
        }
    }

    private static func providerSummary(_ providerNames: [String]) -> String {
        switch providerNames.count {
        case 0:
            "No matching rule is currently available."
        case 1:
            "Provided by \(providerNames[0])."
        default:
            "Available from \(joinedList(providerNames))."
        }
    }

    private static func evidenceDescriptions(
        _ evidence: [RuleDependencyEvidence]
    ) -> [String] {
        evidence.map { item in
            switch item {
            case let .keys(keys):
                let noun = keys.count == 1 ? "key" : "keys"
                return "\(keys.count) affected \(noun): \(joinedList(keys.map(displayName)))"
            case let .mappingIDs(ids):
                let noun = ids.count == 1 ? "mapping" : "mappings"
                return "\(ids.count) affected \(noun)"
            case let .layerPath(source, target):
                return "Layer path: \(displayName(source.rawValue)) to \(displayName(target.rawValue))"
            case let .configuration(field, value):
                return "\(displayName(field)): \(displayName(value))"
            }
        }
    }

    private static func joinedList(_ values: [String]) -> String {
        switch values.count {
        case 0:
            ""
        case 1:
            values[0]
        case 2:
            "\(values[0]) and \(values[1])"
        default:
            "\(values.dropLast().joined(separator: ", ")), and \(values.last ?? "")"
        }
    }

    private static func displayName(_ rawValue: String) -> String {
        rawValue
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map(\.capitalized)
            .joined(separator: " ")
    }
}

struct RulePrerequisiteResolutionDialog: View {
    let model: RulePrerequisiteDialogModel
    let onChoice: (RulePrerequisiteResolutionChoice) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            RulePrerequisiteDialogHeader(
                consequenceSummary: model.consequenceSummary,
                onCancel: onCancel
            )

            Divider()

            RulePrerequisiteRequirementsSection(rows: model.rows)

            Divider()

            RulePrerequisiteActionsSection(
                model: model,
                onChoice: onChoice
            )
        }
        .frame(width: 500)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

private struct RulePrerequisiteDialogHeader: View {
    let consequenceSummary: String
    let onCancel: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 8) {
                Text("Enable the rules this change needs?")
                    .font(.title2.weight(.semibold))

                Text(consequenceSummary)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Without them, the affected keys or actions may do nothing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)

            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.secondary.opacity(0.16)))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityIdentifier("rule-prerequisite-close-button")
            .accessibilityLabel("Cancel")
        }
        .padding(20)
    }
}

private struct RulePrerequisiteRequirementsSection: View {
    let rows: [RulePrerequisiteDialogRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(rows) { row in
                RulePrerequisiteRequirementRow(row: row)
            }
        }
        .padding(20)
    }
}

private struct RulePrerequisiteRequirementRow: View {
    let row: RulePrerequisiteDialogRow

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "link")
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(row.consumerName) needs \(row.capabilityName).")
                    .font(.body.weight(.medium))

                Text(row.providerSummary)
                    .foregroundStyle(.secondary)

                ForEach(row.evidence, id: \.self) { evidence in
                    Text(evidence)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct RulePrerequisiteActionsSection: View {
    let model: RulePrerequisiteDialogModel
    let onChoice: (RulePrerequisiteResolutionChoice) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !model.canEnableAll {
                Text("KeyPath found more than one possible provider for at least one requirement. Choose one manually later, or continue without it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ViewThatFits {
                HStack(spacing: 12) {
                    actionButtons
                }

                VStack(spacing: 10) {
                    actionButtons
                }
            }
        }
        .padding(20)
    }

    @ViewBuilder
    private var actionButtons: some View {
        Button {
            onChoice(.applyWithoutProviders)
        } label: {
            Text(model.secondaryActionTitle)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("rule-prerequisite-apply-without-button")

        if model.canEnableAll {
            Button {
                onChoice(.enableRequiredProvidersAndApply)
            } label: {
                Text(model.primaryActionTitle)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("rule-prerequisite-enable-required-button")
        }
    }
}

#if DEBUG
    struct RulePrerequisiteResolutionDialog_Previews: PreviewProvider {
        static var previews: some View {
            RulePrerequisiteResolutionDialog(
                model: RulePrerequisiteDialogModel(
                    context: RulePrerequisiteResolutionContext(
                        operation: .save,
                        candidate: RuleCollection(
                            id: UUID(),
                            name: "Home Row Layer Toggles",
                            summary: "Hold a home-row key to enter a layer",
                            category: .layers,
                            mappings: [],
                            isEnabled: true
                        ),
                        prerequisites: [],
                        affectedConsumers: [],
                        availableProviders: []
                    )
                ),
                onChoice: { _ in },
                onCancel: {}
            )
        }
    }
#endif
