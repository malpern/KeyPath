import Foundation
import KeyPathCore
import KeyPathPermissions
import KeyPathWizardCore

/// Pure function that inspects a SystemContext and returns what's wrong.
/// No side effects, no async, no dependencies — just data in, data out.
public enum SystemInspector {
    /// Inspect the system and return the current state plus all detected issues.
    /// Only the unprivileged session runtime exists (ADR-045), so this describes that runtime alone.
    public static func inspect(context: SystemContext) -> (WizardSystemState, [WizardIssue]) {
        guard context.captureStatus.isComplete else { return (.serviceNotRunning, []) }
        var issues: [WizardIssue] = []
        var missing: [PermissionRequirement] = []
        if context.permissions.accessibility == .denied {
            missing.append(.keyPathAccessibility)
            issues.append(WizardIssue(
                identifier: .permission(.keyPathAccessibility), severity: .error, category: .permissions,
                title: "Allow KeyPath to remap keys",
                description: context.permissions.blockingIssue ?? "Enable KeyPath in \(AccessibilityPermissionPresentation.current.name), then quit and reopen KeyPath.",
                autoFixAction: nil, userAction: context.permissions.blockingIssue ?? "Open \(AccessibilityPermissionPresentation.current.name) in System Settings"
            ))
        } else if context.permissions.accessibility.isReady,
                  context.permissions.runtimeKeyAccess.status == .denied
        {
            missing.append(.runtimeKeyAccess)
            issues.append(WizardIssue(
                identifier: .permission(.runtimeKeyAccess), severity: .error, category: .permissions,
                title: "Keyboard access still needs approval",
                description: context.permissions.blockingIssue ?? "Quit and reopen KeyPath so it picks up \(AccessibilityPermissionPresentation.current.name).",
                autoFixAction: nil, userAction: context.permissions.blockingIssue ?? "Quit and reopen KeyPath"
            ))
        }
        if !missing.isEmpty { return (.missingPermissions(missing: missing), issues) }
        if !context.components.requiredRuntimePayloadPresent {
            return (.missingComponents(missing: [.bundledKanataMissing]), [WizardIssue(
                identifier: .component(.bundledKanataMissing), severity: .error, category: .installation,
                title: "Bundled runtime missing", description: "Reinstall this KeyPath build.", autoFixAction: nil, userAction: "Reinstall KeyPath"
            )])
        }
        if !context.permissions.isSystemReady {
            return sessionPermissionEvidenceUnavailable()
        }
        if context.services.kanataRuntimeReadiness.isReady { return (.active, []) }
        return (.serviceNotRunning, [WizardIssue(
            identifier: .daemon, severity: .error, category: .daemon,
            title: "Start driverless remapping", description: "The session keyboard runtime is stopped or not ready.",
            autoFixAction: .startSessionRuntime, userAction: "Start the keyboard service"
        )])
    }

    /// An absent or failed worker check is not proof that macOS refused consent.
    /// Retry through the canonical runtime lifecycle to obtain fresh evidence.
    private static func sessionPermissionEvidenceUnavailable() -> (WizardSystemState, [WizardIssue]) {
        (.serviceNotRunning, [WizardIssue(
            identifier: .daemon, severity: .error, category: .daemon,
            title: "Check keyboard access",
            description: "Keyboard access has not been verified by the session runtime. Start or retry the keyboard service to check access.",
            autoFixAction: .startSessionRuntime, userAction: "Start or retry the keyboard service"
        )])
    }
}
