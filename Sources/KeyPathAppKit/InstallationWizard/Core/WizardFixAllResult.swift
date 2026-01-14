import Foundation
import KeyPathWizardCore

enum FixAllStatus: Equatable, Sendable {
    case success
    case partial
    case failed
}

enum FixAllStep: String, Sendable {
    case fastRestart = "Restart Service"
    case autoFixActions = "Auto-Fix Actions"
    case fullRepair = "Full Repair"
    case refreshState = "Refresh State"
}

struct FixStepResult: Equatable, Sendable {
    let step: FixAllStep
    let success: Bool
    let detail: String?
}

struct FixAllResult: Equatable, Sendable {
    let status: FixAllStatus
    let steps: [FixStepResult]
    let resolvedIssueIDs: [IssueIdentifier]
    let remainingIssueIDs: [IssueIdentifier]
    let finalState: WizardSystemState

    var successfulSteps: [FixAllStep] {
        steps.filter { $0.success }.map(\.step)
    }

    var failedSteps: [FixAllStep] {
        steps.filter { !$0.success }.map(\.step)
    }

    static func evaluate(
        initialIssues: [WizardIssue],
        finalIssues: [WizardIssue],
        finalState: WizardSystemState,
        steps: [FixStepResult]
    ) -> FixAllResult {
        let initialIDs = initialIssues.map(\.identifier)
        let finalIDs = finalIssues.map(\.identifier)

        let resolved = initialIDs.filter { id in !finalIDs.contains(id) }
        let remaining = finalIDs

        let hasRemainingIssues = !remaining.isEmpty
        let anyStepSucceeded = steps.contains(where: { $0.success })

        let status: FixAllStatus
        if finalState == .active, !hasRemainingIssues {
            status = .success
        } else if anyStepSucceeded || !resolved.isEmpty {
            status = .partial
        } else {
            status = .failed
        }

        return FixAllResult(
            status: status,
            steps: steps,
            resolvedIssueIDs: resolved,
            remainingIssueIDs: remaining,
            finalState: finalState
        )
    }
}
