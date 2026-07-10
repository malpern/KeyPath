import Foundation
import KeyPathInstallationWizard

public struct CLIStatusResult: Codable, Sendable {
    public let isOperational: Bool
    public let helperInstalled: Bool
    public let helperWorking: Bool
    public let helperVersion: String?
    public let keyPathAccessibility: Bool
    public let keyPathInputMonitoring: Bool
    public let kanataAccessibility: Bool
    public let kanataInputMonitoring: Bool
    public let kanataBinaryInstalled: Bool
    public let karabinerDriverInstalled: Bool
    public let vhidDeviceHealthy: Bool
    public let kanataRunning: Bool
    public let karabinerDaemonRunning: Bool
    public let vhidHealthy: Bool
    public let activeRuntimePathTitle: String?
    public let activeRuntimePathDetail: String?
    public let hasConflicts: Bool
    public let timestamp: Date

    public init(
        isOperational: Bool,
        helperInstalled: Bool,
        helperWorking: Bool,
        helperVersion: String?,
        keyPathAccessibility: Bool,
        keyPathInputMonitoring: Bool,
        kanataAccessibility: Bool,
        kanataInputMonitoring: Bool,
        kanataBinaryInstalled: Bool,
        karabinerDriverInstalled: Bool,
        vhidDeviceHealthy: Bool,
        kanataRunning: Bool,
        karabinerDaemonRunning: Bool,
        vhidHealthy: Bool,
        activeRuntimePathTitle: String?,
        activeRuntimePathDetail: String?,
        hasConflicts: Bool,
        timestamp: Date
    ) {
        self.isOperational = isOperational
        self.helperInstalled = helperInstalled
        self.helperWorking = helperWorking
        self.helperVersion = helperVersion
        self.keyPathAccessibility = keyPathAccessibility
        self.keyPathInputMonitoring = keyPathInputMonitoring
        self.kanataAccessibility = kanataAccessibility
        self.kanataInputMonitoring = kanataInputMonitoring
        self.kanataBinaryInstalled = kanataBinaryInstalled
        self.karabinerDriverInstalled = karabinerDriverInstalled
        self.vhidDeviceHealthy = vhidDeviceHealthy
        self.kanataRunning = kanataRunning
        self.karabinerDaemonRunning = karabinerDaemonRunning
        self.vhidHealthy = vhidHealthy
        self.activeRuntimePathTitle = activeRuntimePathTitle
        self.activeRuntimePathDetail = activeRuntimePathDetail
        self.hasConflicts = hasConflicts
        self.timestamp = timestamp
    }
}

public struct CLIInstallerReport: Codable, Sendable {
    public let runID: String?
    public let planID: String?
    public let beforeSnapshotID: String?
    public let afterSnapshotID: String?
    public let completionState: String?
    public let success: Bool
    public let failureReason: String?
    public let steps: [CLIInstallerStep]
    public let fastRepair: Bool
    public let dryRun: Bool?
    public let userActionRequired: Bool?
    public let issues: [CLISystemIssue]?
    public let plannedRecipes: [String]?
    public let unmetRequirements: [String]?
    public let logs: [String]?
    public let repairTelemetry: [CLIRepairTelemetryEvent]?
    public let recommendedRecovery: String?
    public let recoveryPlanRecipes: [String]?
    public let failedPostconditions: [String]?

    public init(from report: InstallerReport) {
        runID = report.runID.uuidString
        planID = report.planID?.uuidString
        beforeSnapshotID = report.beforeSnapshotID?.uuidString
        afterSnapshotID = report.afterSnapshotID?.uuidString
        completionState = report.completionState.rawValue
        success = report.success
        failureReason = report.failureReason
        steps = report.executedRecipes.map {
            CLIInstallerStep(name: $0.recipeID, success: $0.success, error: $0.error)
        }
        fastRepair = false
        dryRun = nil
        let requiresUserAction = report.completionState == .awaitingApproval
            || report.completionState == .recoveryRequired
            || report.recommendedRecovery != nil
        userActionRequired = requiresUserAction ? true : nil
        issues = nil
        plannedRecipes = nil
        unmetRequirements = nil
        logs = report.logs.isEmpty ? nil : report.logs
        repairTelemetry = CLIRepairTelemetryEvent.from(report.repairTelemetry)
        recommendedRecovery = report.recommendedRecovery?.rawValue
        recoveryPlanRecipes = report.recoveryPlan?.recipes.map(\.id)
        failedPostconditions = report.failedPostconditions.isEmpty
            ? nil
            : report.failedPostconditions.map(\.rawValue)
    }

    public init(success: Bool, failureReason: String?, steps: [CLIInstallerStep], fastRepair: Bool) {
        runID = nil
        planID = nil
        beforeSnapshotID = nil
        afterSnapshotID = nil
        completionState = nil
        self.success = success
        self.failureReason = failureReason
        self.steps = steps
        self.fastRepair = fastRepair
        dryRun = nil
        userActionRequired = nil
        issues = nil
        plannedRecipes = nil
        unmetRequirements = nil
        logs = nil
        repairTelemetry = nil
        recommendedRecovery = nil
        recoveryPlanRecipes = nil
        failedPostconditions = nil
    }

    public init(bundleIssue: CLISystemIssue, dryRun: Bool, title: String) {
        runID = nil
        planID = nil
        beforeSnapshotID = nil
        afterSnapshotID = nil
        completionState = InstallerCompletionState.blocked.rawValue
        success = false
        failureReason = "\(title) requires the signed KeyPath.app bundle. \(bundleIssue.action)"
        steps = []
        fastRepair = false
        self.dryRun = dryRun
        userActionRequired = true
        issues = [bundleIssue]
        plannedRecipes = []
        unmetRequirements = ["Valid KeyPath.app bundle"]
        logs = nil
        repairTelemetry = nil
        recommendedRecovery = nil
        recoveryPlanRecipes = nil
        failedPostconditions = nil
    }

    public init(
        success: Bool,
        failureReason: String?,
        steps: [CLIInstallerStep],
        fastRepair: Bool,
        dryRun: Bool?,
        userActionRequired: Bool?,
        issues: [CLISystemIssue]?,
        plannedRecipes: [String]?,
        unmetRequirements: [String]?,
        logs: [String]?,
        repairTelemetry: [CLIRepairTelemetryEvent]? = nil,
        recommendedRecovery: String? = nil,
        runID: String? = nil,
        planID: String? = nil,
        beforeSnapshotID: String? = nil,
        afterSnapshotID: String? = nil,
        completionState: String? = nil,
        recoveryPlanRecipes: [String]? = nil,
        failedPostconditions: [String]? = nil
    ) {
        self.runID = runID
        self.planID = planID
        self.beforeSnapshotID = beforeSnapshotID
        self.afterSnapshotID = afterSnapshotID
        self.completionState = completionState
        self.success = success
        self.failureReason = failureReason
        self.steps = steps
        self.fastRepair = fastRepair
        self.dryRun = dryRun
        self.userActionRequired = userActionRequired
        self.issues = issues
        self.plannedRecipes = plannedRecipes
        self.unmetRequirements = unmetRequirements
        self.logs = logs
        self.repairTelemetry = repairTelemetry
        self.recommendedRecovery = recommendedRecovery
        self.recoveryPlanRecipes = recoveryPlanRecipes
        self.failedPostconditions = failedPostconditions
    }
}

public struct CLIInstallerStep: Codable, Sendable {
    public let name: String
    public let success: Bool
    public let error: String?

    public init(name: String, success: Bool, error: String?) {
        self.name = name
        self.success = success
        self.error = error
    }
}

public struct CLIRepairTelemetryEvent: Codable, Sendable {
    public let runID: String?
    public let planID: String?
    public let beforeSnapshotID: String?
    public let afterSnapshotID: String?
    public let trigger: String
    public let intent: String
    public let stateMatrixRow: String?
    public let stateMatrixPlan: [String]
    public let action: String?
    public let recipeID: String?
    public let recipeType: String?
    public let postconditionResult: String
    public let error: String?

    public init(_ event: InstallerRepairTelemetryEvent) {
        runID = event.runID?.uuidString
        planID = event.planID?.uuidString
        beforeSnapshotID = event.beforeSnapshotID?.uuidString
        afterSnapshotID = event.afterSnapshotID?.uuidString
        trigger = event.trigger.rawValue
        intent = event.intent
        stateMatrixRow = event.stateMatrixRow
        stateMatrixPlan = event.stateMatrixPlan
        action = event.action
        recipeID = event.recipeID
        recipeType = event.recipeType
        postconditionResult = event.postconditionResult.rawValue
        error = event.error
    }

    public static func from(_ events: [InstallerRepairTelemetryEvent]) -> [CLIRepairTelemetryEvent]? {
        guard !events.isEmpty else { return nil }
        return events.map(CLIRepairTelemetryEvent.init)
    }
}

public struct CLIInspectResult: Codable, Sendable {
    public let macOSVersion: String
    public let driverCompatible: Bool
    public let planStatus: String
    public let blockedBy: String?
    public let plannedRecipes: [String]
    public let planIntent: String?
    public let isOperational: Bool?
    public let userActionRequired: Bool?
    public let promptsNeeded: Bool?
    public let issues: [CLISystemIssue]?
    public let stateMatrixRow: String?
    public let stateMatrixPlan: [String]?

    public init(
        macOSVersion: String,
        driverCompatible: Bool,
        planStatus: String,
        blockedBy: String?,
        plannedRecipes: [String],
        planIntent: String? = nil,
        isOperational: Bool? = nil,
        userActionRequired: Bool? = nil,
        promptsNeeded: Bool? = nil,
        issues: [CLISystemIssue]? = nil,
        stateMatrixRow: String? = nil,
        stateMatrixPlan: [String]? = nil
    ) {
        self.macOSVersion = macOSVersion
        self.driverCompatible = driverCompatible
        self.planStatus = planStatus
        self.blockedBy = blockedBy
        self.plannedRecipes = plannedRecipes
        self.planIntent = planIntent
        self.isOperational = isOperational
        self.userActionRequired = userActionRequired
        self.promptsNeeded = promptsNeeded
        self.issues = issues
        self.stateMatrixRow = stateMatrixRow
        self.stateMatrixPlan = stateMatrixPlan
    }
}

public struct CLISystemIssue: Codable, Sendable {
    public let title: String
    public let category: String
    public let action: String
    public let canAutoFix: Bool
    public let remediationURL: String?

    public init(
        title: String,
        category: String,
        action: String,
        canAutoFix: Bool,
        remediationURL: String? = nil
    ) {
        self.title = title
        self.category = category
        self.action = action
        self.canAutoFix = canAutoFix
        self.remediationURL = remediationURL
    }
}
