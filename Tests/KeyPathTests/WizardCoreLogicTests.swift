import XCTest
@testable import KeyPath

/// Tests for core wizard logic (IssueGenerator, SystemSnapshotAdapter, WizardStateInterpreter)
/// Critical for wizard refactoring - protects state machine and issue generation logic
final class WizardCoreLogicTests: XCTestCase {

    // MARK: - Test Setup

    var issueGenerator: IssueGenerator!
    var stateInterpreter: WizardStateInterpreter!

    override func setUp() {
        super.setUp()
        issueGenerator = IssueGenerator()
        stateInterpreter = WizardStateInterpreter()
    }

    override func tearDown() {
        issueGenerator = nil
        stateInterpreter = nil
        super.tearDown()
    }

    // MARK: - IssueGenerator Tests

    func testConflictIssueGrouping() {
        // Given: Multiple kanata conflicts
        let conflicts: [SystemConflict] = [
            .kanataProcessRunning(pid: 1234, command: "/usr/local/bin/kanata"),
            .kanataProcessRunning(pid: 5678, command: "/usr/local/bin/kanata -c config.kbd")
        ]
        let result = ConflictDetectionResult(
            conflicts: conflicts,
            timestamp: Date()
        )

        // When: Creating conflict issues
        let issues = issueGenerator.createConflictIssues(from: result)

        // Then: Should group into single issue with both PIDs
        XCTAssertEqual(issues.count, 1, "Should group conflicts by type")
        let issue = issues[0]
        XCTAssertTrue(issue.description.contains("1234"), "Should include first PID")
        XCTAssertTrue(issue.description.contains("5678"), "Should include second PID")
        XCTAssertTrue(issue.description.contains("(2 instances)"), "Should show count")
    }

    func testConflictIssueNoGroupingForDifferentTypes() {
        // Given: Different conflict types
        let conflicts: [SystemConflict] = [
            .kanataProcessRunning(pid: 1234, command: "/usr/local/bin/kanata"),
            .karabinerGrabberRunning(pid: 5678)
        ]
        let result = ConflictDetectionResult(
            conflicts: conflicts,
            timestamp: Date()
        )

        // When: Creating conflict issues
        let issues = issueGenerator.createConflictIssues(from: result)

        // Then: Should create separate issues for different types
        XCTAssertEqual(issues.count, 2, "Different conflict types should not be grouped")
    }

    func testNoConflictIssuesWhenNoConflicts() {
        // Given: No conflicts
        let result = ConflictDetectionResult(
            conflicts: [],
            timestamp: Date()
        )

        // When: Creating conflict issues
        let issues = issueGenerator.createConflictIssues(from: result)

        // Then: Should return empty array
        XCTAssertTrue(issues.isEmpty, "No conflicts should produce no issues")
    }

    func testPermissionIssueCreation() {
        // Given: Missing permissions
        let result = PermissionCheckResult(
            missing: [.kanataInputMonitoring, .kanataAccessibility],
            granted: [],
            timestamp: Date()
        )

        // When: Creating permission issues
        let issues = issueGenerator.createPermissionIssues(from: result)

        // Then: Should create issue for each missing permission
        XCTAssertEqual(issues.count, 2, "Should create one issue per missing permission")
        XCTAssertTrue(issues.allSatisfy { $0.severity == .warning }, "Permission issues should be warnings")
        XCTAssertTrue(issues.allSatisfy { $0.category == .permissions }, "Should be permission category")
    }

    func testBackgroundServicesPermissionUsesSeparateCategory() {
        // Given: Background services permission missing
        let result = PermissionCheckResult(
            missing: [.backgroundServicesEnabled],
            granted: [],
            timestamp: Date()
        )

        // When: Creating permission issues
        let issues = issueGenerator.createPermissionIssues(from: result)

        // Then: Should use backgroundServices category
        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues[0].category, .backgroundServices, "Background services should have separate category")
    }

    func testComponentIssueAutoFixActions() {
        // Given: Missing components with auto-fix capability
        let result = ComponentCheckResult(
            missing: [.kanataBinaryMissing, .vhidDriverVersionMismatch],
            installed: [],
            timestamp: Date()
        )

        // When: Creating component issues
        let issues = issueGenerator.createComponentIssues(from: result)

        // Then: Should include appropriate auto-fix actions
        XCTAssertEqual(issues.count, 2)

        let binaryIssue = issues.first { $0.identifier == .component(.kanataBinaryMissing) }
        XCTAssertEqual(binaryIssue?.autoFixAction, .installBundledKanata)

        let versionIssue = issues.first { $0.identifier == .component(.vhidDriverVersionMismatch) }
        XCTAssertEqual(versionIssue?.autoFixAction, .fixDriverVersionMismatch)
    }

    func testDaemonIssueCreation() {
        // When: Creating daemon issue
        let issue = issueGenerator.createDaemonIssue()

        // Then: Should have correct properties
        XCTAssertEqual(issue.identifier, .daemon)
        XCTAssertEqual(issue.severity, .warning)
        XCTAssertEqual(issue.category, .daemon)
        XCTAssertEqual(issue.autoFixAction, .startKarabinerDaemon)
    }

    func testLogRotationIssueCreation() {
        // When: Creating log rotation issue
        let issue = issueGenerator.createLogRotationIssue()

        // Then: Should be informational with auto-fix
        XCTAssertEqual(issue.severity, .info)
        XCTAssertEqual(issue.autoFixAction, .installLogRotation)
    }

    func testConfigPathMismatchIssueCreation() {
        // Given: Config path mismatch
        let mismatch = ConfigPathMismatch(
            processPID: 1234,
            actualConfigPath: "/tmp/config.kbd",
            expectedConfigPath: "/Users/test/Library/Application Support/KeyPath/keypath.kbd"
        )
        let result = ConfigPathMismatchResult(
            mismatches: [mismatch],
            timestamp: Date()
        )

        // When: Creating config path issues
        let issues = issueGenerator.createConfigPathIssues(from: result)

        // Then: Should include both paths in description
        XCTAssertEqual(issues.count, 1)
        let issue = issues[0]
        XCTAssertTrue(issue.description.contains("/tmp/config.kbd"), "Should show actual path")
        XCTAssertTrue(issue.description.contains("Library/Application Support"), "Should show expected path")
        XCTAssertTrue(issue.description.contains("1234"), "Should show PID")
        XCTAssertEqual(issue.autoFixAction, .synchronizeConfigPaths)
    }

    // MARK: - WizardStateInterpreter Tests

    func testPermissionStatusDetection() {
        // Given: Permission issues
        let issues = [
            WizardIssue(
                identifier: .permission(.kanataInputMonitoring),
                severity: .warning,
                category: .permissions,
                title: "Input Monitoring",
                description: "Required",
                autoFixAction: nil,
                userAction: nil
            )
        ]

        // When/Then: Checking permission status
        XCTAssertEqual(
            stateInterpreter.getPermissionStatus(.kanataInputMonitoring, in: issues),
            .failed,
            "Issue present should show failed"
        )
        XCTAssertEqual(
            stateInterpreter.getPermissionStatus(.kanataAccessibility, in: issues),
            .completed,
            "No issue should show completed"
        )
    }

    func testComponentStatusDetection() {
        // Given: Component issues
        let issues = [
            WizardIssue(
                identifier: .component(.kanataBinaryMissing),
                severity: .error,
                category: .installation,
                title: "Kanata Binary Missing",
                description: "Install required",
                autoFixAction: .installBundledKanata,
                userAction: nil
            )
        ]

        // When/Then: Checking component status
        XCTAssertEqual(
            stateInterpreter.getComponentStatus(.kanataBinaryMissing, in: issues),
            .failed
        )
        XCTAssertEqual(
            stateInterpreter.getComponentStatus(.karabinerDriver, in: issues),
            .completed
        )
    }

    func testConflictDetection() {
        // Given: Conflict issue
        let issues = [
            WizardIssue(
                identifier: .conflict(.karabinerGrabberRunning(pid: 1234)),
                severity: .error,
                category: .conflicts,
                title: "Karabiner Conflict",
                description: "Terminate required",
                autoFixAction: .terminateConflictingProcesses,
                userAction: nil
            )
        ]

        // When/Then: Checking conflict status
        XCTAssertTrue(stateInterpreter.hasAnyConflicts(in: issues))
        XCTAssertTrue(stateInterpreter.hasKarabinerConflict(in: issues))
        XCTAssertEqual(stateInterpreter.getConflictIssues(in: issues).count, 1)
    }

    func testDaemonStatusDetection() {
        // Given: Daemon issue
        let issues = [
            WizardIssue(
                identifier: .daemon,
                severity: .warning,
                category: .daemon,
                title: "Daemon Not Running",
                description: "Start required",
                autoFixAction: .startKarabinerDaemon,
                userAction: nil
            )
        ]

        // When/Then: Checking daemon status
        XCTAssertFalse(stateInterpreter.isDaemonRunning(in: issues))
        XCTAssertEqual(stateInterpreter.getDaemonIssues(in: issues).count, 1)
    }

    func testBackgroundServicesDetection() {
        // Given: Background services issue
        let issues = [
            WizardIssue(
                identifier: .permission(.backgroundServicesEnabled),
                severity: .warning,
                category: .backgroundServices,
                title: "Background Services",
                description: "Enable required",
                autoFixAction: nil,
                userAction: nil
            )
        ]

        // When/Then: Checking background services status
        XCTAssertFalse(stateInterpreter.areBackgroundServicesEnabled(in: issues))
        XCTAssertEqual(stateInterpreter.getBackgroundServiceIssues(in: issues).count, 1)
    }

    func testAllRequirementsMet() {
        // When/Then: Empty issues means all requirements met
        XCTAssertTrue(stateInterpreter.areAllRequirementsMet(in: []))
        XCTAssertFalse(stateInterpreter.areAllRequirementsMet(in: [
            WizardIssue(
                identifier: .daemon,
                severity: .info,
                category: .daemon,
                title: "Info",
                description: "Info",
                autoFixAction: nil,
                userAction: nil
            )
        ]))
    }

    func testBlockingIssuesDetection() {
        // Given: Mix of severities
        let issues = [
            WizardIssue(
                identifier: .daemon,
                severity: .info,
                category: .daemon,
                title: "Info",
                description: "Info",
                autoFixAction: nil,
                userAction: nil
            ),
            WizardIssue(
                identifier: .component(.kanataBinaryMissing),
                severity: .error,
                category: .installation,
                title: "Error",
                description: "Error",
                autoFixAction: nil,
                userAction: nil
            )
        ]

        // When/Then: Error should be blocking
        XCTAssertTrue(stateInterpreter.hasBlockingIssues(in: issues))
    }

    func testMostCriticalSeverity() {
        // Given: Mix of severities
        let issues = [
            WizardIssue(
                identifier: .daemon,
                severity: .info,
                category: .daemon,
                title: "Info",
                description: "Info",
                autoFixAction: nil,
                userAction: nil
            ),
            WizardIssue(
                identifier: .component(.kanataBinaryMissing),
                severity: .warning,
                category: .installation,
                title: "Warning",
                description: "Warning",
                autoFixAction: nil,
                userAction: nil
            ),
            WizardIssue(
                identifier: .component(.karabinerDriver),
                severity: .error,
                category: .installation,
                title: "Error",
                description: "Error",
                autoFixAction: nil,
                userAction: nil
            )
        ]

        // When/Then: Should find most critical
        XCTAssertEqual(stateInterpreter.getMostCriticalSeverity(in: issues), .error)
        XCTAssertNil(stateInterpreter.getMostCriticalSeverity(in: []))
    }

    func testPageSpecificIssueFiltering() {
        // Given: Various issues
        let issues = [
            WizardIssue(
                identifier: .permission(.kanataInputMonitoring),
                severity: .warning,
                category: .permissions,
                title: "Kanata IM",
                description: "Required",
                autoFixAction: nil,
                userAction: nil
            ),
            WizardIssue(
                identifier: .permission(.kanataAccessibility),
                severity: .warning,
                category: .permissions,
                title: "Kanata AX",
                description: "Required",
                autoFixAction: nil,
                userAction: nil
            ),
            WizardIssue(
                identifier: .component(.kanataBinaryMissing),
                severity: .error,
                category: .installation,
                title: "Kanata Binary",
                description: "Missing",
                autoFixAction: .installBundledKanata,
                userAction: nil
            ),
            WizardIssue(
                identifier: .component(.karabinerDriver),
                severity: .error,
                category: .installation,
                title: "Karabiner Driver",
                description: "Missing",
                autoFixAction: nil,
                userAction: nil
            ),
            WizardIssue(
                identifier: .conflict(.karabinerGrabberRunning(pid: 1234)),
                severity: .error,
                category: .conflicts,
                title: "Conflict",
                description: "Terminate",
                autoFixAction: .terminateConflictingProcesses,
                userAction: nil
            )
        ]

        // When/Then: Filter by page
        let inputMonitoringIssues = stateInterpreter.getRelevantIssues(for: .inputMonitoring, in: issues)
        XCTAssertEqual(inputMonitoringIssues.count, 1, "Input Monitoring page should show only IM permission")

        let accessibilityIssues = stateInterpreter.getRelevantIssues(for: .accessibility, in: issues)
        XCTAssertEqual(accessibilityIssues.count, 1, "Accessibility page should show only AX permission")

        let kanataComponentIssues = stateInterpreter.getRelevantIssues(for: .kanataComponents, in: issues)
        XCTAssertEqual(kanataComponentIssues.count, 1, "Kanata components page should show only kanata binary")

        let karabinerComponentIssues = stateInterpreter.getRelevantIssues(for: .karabinerComponents, in: issues)
        XCTAssertEqual(karabinerComponentIssues.count, 1, "Karabiner components page should show only karabiner driver")

        let conflictIssues = stateInterpreter.getRelevantIssues(for: .conflicts, in: issues)
        XCTAssertEqual(conflictIssues.count, 1, "Conflicts page should show only conflicts")

        let summaryIssues = stateInterpreter.getRelevantIssues(for: .summary, in: issues)
        XCTAssertEqual(summaryIssues.count, 5, "Summary page should show all issues")
    }

    func testPageStatusDetermination() {
        // Given: Issues for specific page
        let issues = [
            WizardIssue(
                identifier: .permission(.kanataInputMonitoring),
                severity: .error,
                category: .permissions,
                title: "Input Monitoring",
                description: "Required",
                autoFixAction: nil,
                userAction: nil
            )
        ]

        // When/Then: Page status
        XCTAssertEqual(
            stateInterpreter.getPageStatus(for: .inputMonitoring, in: issues),
            .failed,
            "Page with error should be failed"
        )
        XCTAssertEqual(
            stateInterpreter.getPageStatus(for: .accessibility, in: issues),
            .completed,
            "Page without issues should be completed"
        )
    }

    func testStatusColorMapping() {
        // When/Then: Color mapping
        XCTAssertEqual(stateInterpreter.getStatusColor(.notStarted).description, "secondary")
        XCTAssertEqual(stateInterpreter.getStatusColor(.inProgress).description, "blue")
        XCTAssertEqual(stateInterpreter.getStatusColor(.completed).description, "green")
        XCTAssertEqual(stateInterpreter.getStatusColor(.failed).description, "red")
    }

    func testStatusIconMapping() {
        // When/Then: Icon mapping
        XCTAssertEqual(stateInterpreter.getStatusIcon(.notStarted), "circle")
        XCTAssertEqual(stateInterpreter.getStatusIcon(.inProgress), "clock")
        XCTAssertEqual(stateInterpreter.getStatusIcon(.completed), "checkmark.circle.fill")
        XCTAssertEqual(stateInterpreter.getStatusIcon(.failed), "xmark.circle.fill")
    }

    // MARK: - Edge Cases

    func testEmptyConflictGrouping() {
        // Given: Empty conflicts array
        let result = ConflictDetectionResult(
            conflicts: [],
            timestamp: Date()
        )

        // When: Creating conflict issues
        let issues = issueGenerator.createConflictIssues(from: result)

        // Then: Should return empty
        XCTAssertTrue(issues.isEmpty)
    }

    func testMultipleConflictTypesGrouping() {
        // Given: Multiple types with multiple instances each
        let conflicts: [SystemConflict] = [
            .kanataProcessRunning(pid: 1234, command: "kanata"),
            .kanataProcessRunning(pid: 5678, command: "kanata"),
            .karabinerGrabberRunning(pid: 9012),
            .karabinerGrabberRunning(pid: 3456)
        ]
        let result = ConflictDetectionResult(
            conflicts: conflicts,
            timestamp: Date()
        )

        // When: Creating conflict issues
        let issues = issueGenerator.createConflictIssues(from: result)

        // Then: Should create 2 grouped issues
        XCTAssertEqual(issues.count, 2, "Should create one issue per conflict type")
    }

    func testIssueFilteringPreservesOrder() {
        // Given: Issues in specific order
        let issues = [
            WizardIssue(
                identifier: .permission(.kanataInputMonitoring),
                severity: .warning,
                category: .permissions,
                title: "First",
                description: "First",
                autoFixAction: nil,
                userAction: nil
            ),
            WizardIssue(
                identifier: .permission(.kanataAccessibility),
                severity: .warning,
                category: .permissions,
                title: "Second",
                description: "Second",
                autoFixAction: nil,
                userAction: nil
            )
        ]

        // When: Getting permission issues
        let permissionIssues = stateInterpreter.getPermissionIssues(in: issues)

        // Then: Order should be preserved
        XCTAssertEqual(permissionIssues.count, 2)
        XCTAssertEqual(permissionIssues[0].title, "First")
        XCTAssertEqual(permissionIssues[1].title, "Second")
    }
}
