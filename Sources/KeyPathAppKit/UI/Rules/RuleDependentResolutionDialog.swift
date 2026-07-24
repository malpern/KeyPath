import KeyPathRulesCore
import SwiftUI

struct RuleDependentDialogRowID: Hashable, Sendable {
    let dependentID: UUID
    let capability: RuleCapability
}

struct RuleDependentDialogRow: Equatable, Identifiable, Sendable {
    let id: RuleDependentDialogRowID
    let usageSummary: String
    let evidence: [String]
    let alternativeProviderNames: [String]
}

/// A prepared presentation snapshot for the reverse dependency dialog.
///
/// Collection lookup and evidence formatting happen once when the request
/// arrives rather than inside SwiftUI's repeatedly evaluated body.
struct RuleDependentResolutionDialogModel: Equatable, Sendable {
    let providerName: String
    let rows: [RuleDependentDialogRow]
    let dependentCount: Int
    let collapseDetails: Bool

    init(context: RuleDependentResolutionContext) {
        providerName = context.providerName

        let consumersByID = Dictionary(
            context.affectedConsumers.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let providersByID = Dictionary(
            context.availableProviders.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        rows = context.dependents.map { dependent in
            let consumerName = consumersByID[dependent.dependentCollectionID]?.name
                ?? "Another enabled rule"
            return RuleDependentDialogRow(
                id: RuleDependentDialogRowID(
                    dependentID: dependent.dependentCollectionID,
                    capability: dependent.newlyUnsatisfiedCapability
                ),
                usageSummary: Self.usageSummary(
                    consumerName: consumerName,
                    providerName: context.providerName,
                    capability: dependent.newlyUnsatisfiedCapability
                ),
                evidence: RulePrerequisiteDialogModel.evidenceDescriptions(
                    dependent.requirement.sortedEvidence
                ),
                alternativeProviderNames:
                dependent.remainingAvailableProviderCollectionIDs.compactMap {
                    providersByID[$0]?.name
                }
            )
        }

        dependentCount = Set(context.dependents.map(\.dependentCollectionID)).count
        collapseDetails = rows.count > 3
    }

    private static func usageSummary(
        consumerName: String,
        providerName: String,
        capability: RuleCapability
    ) -> String {
        switch capability {
        case let .layerContent(layer):
            "\(consumerName) uses \(providerName) for the \(RulePrerequisiteDialogModel.displayName(layer.rawValue)) layer."
        case let .layerActivation(layer):
            "\(consumerName) uses \(providerName) to enter the \(RulePrerequisiteDialogModel.displayName(layer.rawValue)) layer."
        case let .keyAlias(alias):
            switch alias {
            case .hyper:
                "\(consumerName) uses \(providerName) for the Hyper key."
            }
        }
    }
}

struct RuleDependentResolutionDialog: View {
    let model: RuleDependentResolutionDialogModel
    let onKeepEnabled: () -> Void
    let onDisableAnyway: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            RuleDependentDialogHeader(
                providerName: model.providerName,
                dependentCount: model.dependentCount,
                onKeepEnabled: onKeepEnabled
            )

            Divider()

            RuleDependentRulesSection(
                rows: model.rows,
                collapseDetails: model.collapseDetails
            )

            Divider()

            RuleDependentActionsSection(
                providerName: model.providerName,
                onKeepEnabled: onKeepEnabled,
                onDisableAnyway: onDisableAnyway
            )
        }
        .frame(width: 500)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

private struct RuleDependentDialogHeader: View {
    let providerName: String
    let dependentCount: Int
    let onKeepEnabled: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 8) {
                if dependentCount == 1 {
                    Text("\(providerName) is still used by another rule")
                        .font(.title2.weight(.semibold))
                } else {
                    Text("\(providerName) is still used by other rules")
                        .font(.title2.weight(.semibold))
                }

                if dependentCount == 1 {
                    Text("Disabling \(providerName) would leave one enabled rule without behavior it uses.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Disabling \(providerName) would leave \(dependentCount) enabled rules without behavior they use.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 24)

            Button(action: onKeepEnabled) {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.secondary.opacity(0.16)))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityIdentifier("rule-dependent-close-button")
            .accessibilityLabel("Keep \(providerName) enabled")
        }
        .padding(20)
    }
}

private struct RuleDependentRulesSection: View {
    let rows: [RuleDependentDialogRow]
    let collapseDetails: Bool

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(rows) { row in
                    RuleDependentRuleRow(
                        row: row,
                        collapseDetails: collapseDetails
                    )
                }
            }
            .padding(20)
        }
        .frame(maxHeight: 360)
    }
}

private struct RuleDependentRuleRow: View {
    let row: RuleDependentDialogRow
    let collapseDetails: Bool
    @State private var isExpanded = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.link")
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 5) {
                Text(row.usageSummary)
                    .font(.body.weight(.medium))

                Text("Its affected keys or actions may do nothing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if collapseDetails, !details.isEmpty {
                    DisclosureGroup(isExpanded: $isExpanded) {
                        RuleDependentDetailList(details: details)
                            .padding(.top, 4)
                    } label: {
                        Text("Show \(details.count) \(details.count == 1 ? "detail" : "details")")
                            .font(.caption)
                    }
                    .accessibilityIdentifier(
                        "rule-dependent-details-\(row.id.dependentID.uuidString)"
                    )
                } else {
                    RuleDependentDetailList(details: details)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var details: [String] {
        var values = row.evidence
        if !row.alternativeProviderNames.isEmpty {
            values.append(
                "Other matching rules are currently off: "
                    + row.alternativeProviderNames.joined(separator: ", ")
            )
        }
        return values
    }
}

private struct RuleDependentDetailList: View {
    let details: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(details, id: \.self) { detail in
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct RuleDependentActionsSection: View {
    let providerName: String
    let onKeepEnabled: () -> Void
    let onDisableAnyway: () -> Void

    var body: some View {
        ViewThatFits {
            HStack(spacing: 12) {
                RuleDependentActionButtons(
                    providerName: providerName,
                    onKeepEnabled: onKeepEnabled,
                    onDisableAnyway: onDisableAnyway
                )
            }

            VStack(spacing: 10) {
                RuleDependentActionButtons(
                    providerName: providerName,
                    onKeepEnabled: onKeepEnabled,
                    onDisableAnyway: onDisableAnyway
                )
            }
        }
        .padding(20)
    }
}

private struct RuleDependentActionButtons: View {
    let providerName: String
    let onKeepEnabled: () -> Void
    let onDisableAnyway: () -> Void

    var body: some View {
        Button(role: .destructive, action: onDisableAnyway) {
            Text("Disable Anyway")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("rule-dependent-disable-anyway-button")

        Button(action: onKeepEnabled) {
            Text("Keep \(providerName) Enabled")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
        .accessibilityIdentifier("rule-dependent-keep-enabled-button")
    }
}

#if DEBUG
    struct RuleDependentResolutionDialog_Previews: PreviewProvider {
        static var previews: some View {
            RuleDependentResolutionDialog(
                model: RuleDependentResolutionDialogModel(
                    context: RuleDependentResolutionContext(
                        providerID: UUID(),
                        providerName: "Function",
                        dependents: [],
                        affectedConsumers: [],
                        availableProviders: []
                    )
                ),
                onKeepEnabled: {},
                onDisableAnyway: {}
            )
        }
    }
#endif
