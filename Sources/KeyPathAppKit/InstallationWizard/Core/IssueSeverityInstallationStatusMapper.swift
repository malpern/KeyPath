import KeyPathWizardCore

enum IssueSeverityInstallationStatusMapper {
    /// Maps issue severity to the appropriate `InstallationStatus`.
    /// - Parameter issues: The Wizard issues that affect a single row.
    /// - Returns: `.failed` if any issue is `.error`/`.critical`, `.warning` if only warnings/infos are present, `.completed` if no issues.
    static func installationStatus(for issues: [WizardIssue]) -> InstallationStatus {
        guard !issues.isEmpty else { return .completed }

        if issues.contains(where: { $0.severity == .critical || $0.severity == .error }) {
            return .failed
        }

        return .warning
    }

    /// Returns the highest-severity issue, if any.
    static func highestSeverity(in issues: [WizardIssue]) -> WizardIssue.IssueSeverity? {
        if issues.contains(where: { $0.severity == .critical }) {
            return .critical
        }
        if issues.contains(where: { $0.severity == .error }) {
            return .error
        }
        if issues.contains(where: { $0.severity == .warning }) {
            return .warning
        }
        if issues.contains(where: { $0.severity == .info }) {
            return .info
        }
        return nil
    }
}
