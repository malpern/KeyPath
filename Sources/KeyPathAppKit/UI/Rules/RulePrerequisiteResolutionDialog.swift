import KeyPathRulesCore
import SwiftUI

struct RulePrerequisiteDialogRowID: Hashable, Sendable {
    let consumerID: UUID
    let capability: RuleCapability

    var accessibilityIdentifier: String {
        let capabilityComponent = switch capability {
        case let .layerContent(layer): "layer-content-\(layer.rawValue)"
        case let .layerActivation(layer): "layer-activation-\(layer.rawValue)"
        case let .keyAlias(alias): "key-alias-\(alias.rawValue)"
        }
        return "rule-prerequisite-requirement-\(consumerID.uuidString)-\(capabilityComponent)"
    }
}

enum RulePrerequisiteProviderState: Equatable, Sendable {
    case unavailable
    case automatic(providerName: String)
    case choices(providerNames: [String])
}

enum RulePrerequisiteDialogResolution: Equatable, Sendable {
    case automatic
    case unavailable
    case ambiguous
    case unavailableAndAmbiguous
}

struct RulePrerequisiteDialogRow: Equatable, Identifiable, Sendable {
    let id: RulePrerequisiteDialogRowID
    let consumerName: String
    let capabilityName: String
    let providerState: RulePrerequisiteProviderState
    let evidence: [String]

    var providerSummary: String {
        switch providerState {
        case .unavailable:
            "No available rule provides this."
        case let .automatic(providerName):
            "KeyPath will turn on \(providerName)."
        case let .choices(providerNames):
            "Turn on one first: \(RulePrerequisiteDialogModel.joinedAlternatives(providerNames))."
        }
    }
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
    let resolution: RulePrerequisiteDialogResolution

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
            let providerNames = prerequisite.availableProviderCollectionIDs.map {
                providersByID[$0]?.name ?? "Another rule"
            }
            return RulePrerequisiteDialogRow(
                id: RulePrerequisiteDialogRowID(
                    consumerID: prerequisite.consumerCollectionID,
                    capability: prerequisite.missingCapability
                ),
                consumerName: consumersByID[prerequisite.consumerCollectionID]?.name
                    ?? context.candidate.name,
                capabilityName: Self.capabilityName(prerequisite.missingCapability),
                providerState: Self.providerState(providerNames),
                evidence: Self.evidenceDescriptions(prerequisite.requirement.sortedEvidence)
            )
        }

        let hasUnavailable = rows.contains { $0.providerState == .unavailable }
        let hasAmbiguous = rows.contains {
            if case .choices = $0.providerState { return true }
            return false
        }
        switch (hasUnavailable, hasAmbiguous) {
        case (false, false):
            resolution = .automatic
        case (true, false):
            resolution = .unavailable
        case (false, true):
            resolution = .ambiguous
        case (true, true):
            resolution = .unavailableAndAmbiguous
        }

        if let providerIDs = context.recommendedProviderIDs {
            recommendedProviderNames = providerIDs.compactMap { providersByID[$0]?.name }
        } else {
            recommendedProviderNames = []
        }
    }

    var canEnableAll: Bool {
        resolution == .automatic
    }

    var title: String {
        switch resolution {
        case .automatic:
            "Turn on supporting rules?"
        case .unavailable:
            if rows.count == 1, let row = rows.first {
                "\(row.consumerName) would lose \(row.capabilityName)"
            } else {
                "Some rules would lose behavior they need"
            }
        case .ambiguous:
            "Choose a supporting rule first"
        case .unavailableAndAmbiguous:
            "This change needs attention first"
        }
    }

    var primaryActionTitle: String {
        switch operation {
        case .enable:
            "Turn On Required Rules"
        case .save:
            "Save & Turn On Required Rules"
        }
    }

    var secondaryActionTitle: String {
        switch operation {
        case .enable:
            "Turn On Anyway"
        case .save:
            "Save Anyway"
        }
    }

    var cancelActionTitle: String {
        switch operation {
        case .enable:
            "Keep Off"
        case .save:
            "Keep Editing"
        }
    }

    var consequenceSummary: String {
        let action = switch operation {
        case .enable: "Turning on \(candidateName)"
        case .save: "Saving changes to \(candidateName)"
        }

        switch resolution {
        case .automatic:
            return "\(action) also requires the supporting rules below."
        case .unavailable:
            if rows.count == 1, let row = rows.first {
                return "\(action) would remove behavior that \(row.consumerName) needs."
            }
            return "\(action) would remove behavior that other enabled rules need."
        case .ambiguous:
            return "\(action) would leave enabled rules without behavior they use, and more than one supporting rule could replace it."
        case .unavailableAndAmbiguous:
            return "\(action) would leave enabled rules without behavior they use. Some missing behavior has no automatic fix, while other behavior has more than one choice."
        }
    }

    var guidanceSummary: String {
        switch resolution {
        case .automatic:
            "KeyPath can turn on every required rule in the same change."
        case .unavailable:
            "Keep your current setup, or continue knowing the affected shortcuts may not work."
        case .ambiguous:
            "Turn on one of the listed rules first, or continue knowing the affected shortcuts may not work."
        case .unavailableAndAmbiguous:
            "Resolve the items below first, or continue knowing the affected shortcuts may not work."
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

    private static func providerState(
        _ providerNames: [String]
    ) -> RulePrerequisiteProviderState {
        switch providerNames.count {
        case 0:
            .unavailable
        case 1:
            .automatic(providerName: providerNames[0])
        default:
            .choices(providerNames: providerNames)
        }
    }

    static func evidenceDescriptions(
        _ evidence: [RuleDependencyEvidence]
    ) -> [String] {
        evidence.compactMap { item in
            switch item {
            case let .keys(keys):
                let noun = keys.count == 1 ? "key" : "keys"
                return "\(keys.count) affected \(noun): \(joinedList(keys.map(displayName)))"
            case .mappingIDs, .layerPath, .configuration:
                return nil
            }
        }
    }

    fileprivate static func joinedList(_ values: [String]) -> String {
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

    fileprivate static func joinedAlternatives(_ values: [String]) -> String {
        switch values.count {
        case 0:
            ""
        case 1:
            values[0]
        case 2:
            "\(values[0]) or \(values[1])"
        default:
            "\(values.dropLast().joined(separator: ", ")), or \(values.last ?? "")"
        }
    }

    static func displayName(_ rawValue: String) -> String {
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
        VStack(alignment: .leading, spacing: 20) {
            RulePrerequisiteDialogHeader(model: model)

            RulePrerequisiteRequirementsSection(rows: model.rows)

            Text(model.guidanceSummary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            RulePrerequisiteActionsSection(
                model: model,
                onChoice: onChoice,
                onCancel: onCancel
            )
        }
        .padding(24)
        .frame(width: 540)
        .background(Color(NSColor.windowBackgroundColor))
        .accessibilityIdentifier("rule-prerequisite-resolution-dialog")
        .onExitCommand(perform: onCancel)
    }
}

private struct RulePrerequisiteDialogHeader: View {
    let model: RulePrerequisiteDialogModel

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: headerIcon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(headerColor)
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(headerColor.opacity(0.12))
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 7) {
                Text(model.title)
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)

                Text(model.consequenceSummary)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var headerIcon: String {
        switch model.resolution {
        case .automatic: "link.badge.plus"
        case .unavailable, .unavailableAndAmbiguous: "exclamationmark.triangle.fill"
        case .ambiguous: "arrow.triangle.branch"
        }
    }

    private var headerColor: Color {
        switch model.resolution {
        case .automatic: .accentColor
        case .unavailable, .ambiguous, .unavailableAndAmbiguous: .orange
        }
    }
}

private struct RulePrerequisiteRequirementsSection: View {
    let rows: [RulePrerequisiteDialogRow]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(rows) { row in
                    RulePrerequisiteRequirementRow(row: row)
                }
            }
        }
        .frame(maxHeight: 280)
    }
}

private struct RulePrerequisiteRequirementRow: View {
    let row: RulePrerequisiteDialogRow

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: statusIcon)
                .font(.body.weight(.semibold))
                .foregroundStyle(statusColor)
                .frame(width: 20, height: 22)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(row.consumerName)
                    .font(.body.weight(.semibold))

                Text("Needs \(row.capabilityName)")
                    .foregroundStyle(.secondary)

                Text(row.providerSummary)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(statusColor)

                ForEach(row.evidence, id: \.self) { evidence in
                    Text(evidence)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(row.id.accessibilityIdentifier)
    }

    private var statusIcon: String {
        switch row.providerState {
        case .unavailable: "exclamationmark.circle.fill"
        case .automatic: "checkmark.circle.fill"
        case .choices: "arrow.triangle.branch"
        }
    }

    private var statusColor: Color {
        switch row.providerState {
        case .unavailable, .choices: .orange
        case .automatic: .accentColor
        }
    }
}

private struct RulePrerequisiteActionsSection: View {
    let model: RulePrerequisiteDialogModel
    let onChoice: (RulePrerequisiteResolutionChoice) -> Void
    let onCancel: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                actionButtons
            }

            VStack(alignment: .trailing, spacing: 10) {
                actionButtons
            }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        if model.canEnableAll {
            Button(model.cancelActionTitle, action: onCancel)
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("rule-prerequisite-cancel-button")
        }

        Button(role: .destructive) {
            onChoice(.applyWithoutProviders)
        } label: {
            Text(model.secondaryActionTitle)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("rule-prerequisite-apply-without-button")

        if model.canEnableAll {
            Button {
                onChoice(.enableRequiredProvidersAndApply)
            } label: {
                Text(model.primaryActionTitle)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("rule-prerequisite-enable-required-button")
        } else {
            Button(model.cancelActionTitle, action: onCancel)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("rule-prerequisite-cancel-button")
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
