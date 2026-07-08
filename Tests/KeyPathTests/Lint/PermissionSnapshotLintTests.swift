import Foundation
@preconcurrency import XCTest

/// Guards the Phase 1 migration of permission-state reads behind `SystemStateProvider`.
///
/// `PermissionOracle` remains the low-level authority for permissions, but installer
/// and wizard consumers should ask `SystemStateProvider` so the eventual immutable
/// system snapshot has one owner for OS evidence reads.
final class PermissionSnapshotLintTests: XCTestCase {
    func testPermissionRequestServiceDelegatesPermissionSnapshotsToSystemStateProvider() throws {
        let service = repositoryRootForPermissionSnapshotLint()
            .appendingPathComponent("Sources/KeyPathAppKit/Services/Permissions/PermissionRequestService.swift")

        let violations = try matchingPermissionSnapshotLines(
            in: service,
            patterns: [
                #"PermissionOracle\.shared\.currentSnapshot"#,
                #"PermissionOracle\.shared\.forceRefresh"#,
                #"PermissionOracle\.shared"#
            ]
        )

        XCTAssertTrue(
            violations.isEmpty,
            """
            PermissionRequestService must delegate permission snapshot reads \
            through SystemStateProvider:
            \(violations.sorted().joined(separator: "\n"))
            """
        )
    }

    func testPermissionGateDelegatesPermissionSnapshotsToSystemStateProvider() throws {
        let gate = repositoryRootForPermissionSnapshotLint()
            .appendingPathComponent("Sources/KeyPathAppKit/Services/Permissions/PermissionGate.swift")

        let violations = try matchingPermissionSnapshotLines(
            in: gate,
            patterns: [
                #"PermissionOracle\.shared\.currentSnapshot"#,
                #"PermissionOracle\.shared\.forceRefresh"#,
                #"PermissionOracle\.shared"#
            ]
        )

        XCTAssertTrue(
            violations.isEmpty,
            """
            PermissionGate must delegate permission snapshot reads \
            through SystemStateProvider:
            \(violations.sorted().joined(separator: "\n"))
            """
        )
    }

    func testSystemRequirementsCheckerDelegatesPermissionSnapshotsToSystemStateProvider() throws {
        let checker = repositoryRootForPermissionSnapshotLint()
            .appendingPathComponent("Sources/KeyPathAppKit/Services/System/SystemRequirementsChecker.swift")

        let violations = try matchingPermissionSnapshotLines(
            in: checker,
            patterns: [
                #"PermissionOracle\.shared\.currentSnapshot"#,
                #"PermissionOracle\.shared\.forceRefresh"#,
                #"PermissionOracle\.shared"#
            ]
        )

        XCTAssertTrue(
            violations.isEmpty,
            """
            SystemRequirementsChecker must delegate permission snapshot reads \
            through SystemStateProvider:
            \(violations.sorted().joined(separator: "\n"))
            """
        )
    }

    func testSystemValidatorDelegatesPermissionSnapshotsToSystemStateProvider() throws {
        let validator = repositoryRootForPermissionSnapshotLint()
            .appendingPathComponent("Sources/KeyPathAppKit/Services/System/SystemValidator.swift")

        let violations = try matchingPermissionSnapshotLines(
            in: validator,
            patterns: [
                #"PermissionOracle\.shared\.currentSnapshot"#,
                #"PermissionOracle\.shared\.forceRefresh"#,
                #"PermissionOracle\.shared"#
            ]
        )

        XCTAssertTrue(
            violations.isEmpty,
            """
            SystemValidator must delegate permission snapshot reads \
            through SystemStateProvider:
            \(violations.sorted().joined(separator: "\n"))
            """
        )
    }

    func testServiceLifecycleCoordinatorDelegatesPermissionSnapshotsToSystemStateProvider() throws {
        let coordinator = repositoryRootForPermissionSnapshotLint()
            .appendingPathComponent("Sources/KeyPathAppKit/Managers/ServiceLifecycleCoordinator.swift")

        let violations = try matchingPermissionSnapshotLines(
            in: coordinator,
            patterns: [
                #"PermissionOracle\.shared\.currentSnapshot"#,
                #"PermissionOracle\.shared\.forceRefresh"#,
                #"PermissionOracle\.shared"#
            ]
        )

        XCTAssertTrue(
            violations.isEmpty,
            """
            ServiceLifecycleCoordinator must delegate permission snapshot reads \
            through SystemStateProvider:
            \(violations.sorted().joined(separator: "\n"))
            """
        )
    }

    func testAppLifecycleDelegatesPermissionSnapshotsToSystemStateProvider() throws {
        let app = repositoryRootForPermissionSnapshotLint()
            .appendingPathComponent("Sources/KeyPathAppKit/App.swift")

        let violations = try matchingPermissionSnapshotLines(
            in: app,
            patterns: permissionSnapshotBypassPatterns()
        )

        XCTAssertTrue(
            violations.isEmpty,
            """
            App lifecycle code must delegate permission snapshot reads \
            through SystemStateProvider:
            \(violations.sorted().joined(separator: "\n"))
            """
        )
    }

    func testMainWindowControllerDelegatesPermissionSnapshotsToSystemStateProvider() throws {
        let controller = repositoryRootForPermissionSnapshotLint()
            .appendingPathComponent("Sources/KeyPathAppKit/UI/MainWindowController.swift")

        let violations = try matchingPermissionSnapshotLines(
            in: controller,
            patterns: permissionSnapshotBypassPatterns()
        )

        XCTAssertTrue(
            violations.isEmpty,
            """
            MainWindowController must delegate permission snapshot reads \
            through SystemStateProvider:
            \(violations.sorted().joined(separator: "\n"))
            """
        )
    }

    func testCompositionRootDelegatesPermissionSnapshotsToSystemStateProvider() throws {
        let compositionRoot = repositoryRootForPermissionSnapshotLint()
            .appendingPathComponent("Sources/KeyPathAppKit/Core/CompositionRoot.swift")

        let violations = try matchingPermissionSnapshotLines(
            in: compositionRoot,
            patterns: permissionSnapshotBypassPatterns()
        )

        XCTAssertTrue(
            violations.isEmpty,
            """
            CompositionRoot must delegate permission snapshot reads \
            through SystemStateProvider:
            \(violations.sorted().joined(separator: "\n"))
            """
        )
    }

    func testPermissionSnapshotEnvironmentDefaultDelegatesToSystemStateProvider() throws {
        let dependencyInjection = repositoryRootForPermissionSnapshotLint()
            .appendingPathComponent("Sources/KeyPathAppKit/Utilities/DependencyInjection.swift")

        let violations = try matchingPermissionSnapshotLines(
            in: dependencyInjection,
            patterns: permissionSnapshotBypassPatterns()
        )

        XCTAssertTrue(
            violations.isEmpty,
            """
            Permission snapshot environment defaults must delegate reads \
            through SystemStateProvider:
            \(violations.sorted().joined(separator: "\n"))
            """
        )
    }

    func testWizardAsyncOperationManagerDelegatesPermissionSnapshotsToSystemStateProvider() throws {
        let manager = repositoryRootForPermissionSnapshotLint()
            .appendingPathComponent(
                "Sources/KeyPathInstallationWizard/Core/WizardAsyncOperationManager.swift"
            )

        let violations = try matchingPermissionSnapshotLines(
            in: manager,
            patterns: permissionSnapshotBypassPatterns()
        )

        XCTAssertTrue(
            violations.isEmpty,
            """
            WizardAsyncOperationManager must delegate permission snapshot reads \
            through SystemStateProvider:
            \(violations.sorted().joined(separator: "\n"))
            """
        )
    }

    func testPermissionGrantCoordinatorDelegatesPermissionSnapshotsToSystemStateProvider() throws {
        let coordinator = repositoryRootForPermissionSnapshotLint()
            .appendingPathComponent(
                "Sources/KeyPathInstallationWizard/Core/PermissionGrantCoordinator.swift"
            )

        let violations = try matchingPermissionSnapshotLines(
            in: coordinator,
            patterns: permissionSnapshotBypassPatterns()
        )

        XCTAssertTrue(
            violations.isEmpty,
            """
            PermissionGrantCoordinator must delegate permission snapshot reads \
            through SystemStateProvider:
            \(violations.sorted().joined(separator: "\n"))
            """
        )
    }

    func testWizardAccessibilityPageDelegatesPermissionSnapshotsToSystemStateProvider() throws {
        let page = repositoryRootForPermissionSnapshotLint()
            .appendingPathComponent(
                "Sources/KeyPathInstallationWizard/UI/Pages/WizardAccessibilityPage.swift"
            )

        let violations = try matchingPermissionSnapshotLines(
            in: page,
            patterns: permissionSnapshotBypassPatterns()
        )

        XCTAssertTrue(
            violations.isEmpty,
            """
            WizardAccessibilityPage must delegate permission snapshot reads \
            through SystemStateProvider:
            \(violations.sorted().joined(separator: "\n"))
            """
        )
    }

    func testWizardInputMonitoringPageDelegatesPermissionSnapshotsToSystemStateProvider() throws {
        let page = repositoryRootForPermissionSnapshotLint()
            .appendingPathComponent(
                "Sources/KeyPathInstallationWizard/UI/Pages/WizardInputMonitoringPage.swift"
            )

        let violations = try matchingPermissionSnapshotLines(
            in: page,
            patterns: permissionSnapshotBypassPatterns()
        )

        XCTAssertTrue(
            violations.isEmpty,
            """
            WizardInputMonitoringPage must delegate permission snapshot reads \
            through SystemStateProvider:
            \(violations.sorted().joined(separator: "\n"))
            """
        )
    }

    func testInstallationWizardStateManagementDelegatesPermissionSnapshotsToSystemStateProvider() throws {
        let stateManagement = repositoryRootForPermissionSnapshotLint()
            .appendingPathComponent(
                "Sources/KeyPathInstallationWizard/UI/InstallationWizardView+StateManagement.swift"
            )

        let violations = try matchingPermissionSnapshotLines(
            in: stateManagement,
            patterns: permissionSnapshotBypassPatterns()
        )

        XCTAssertTrue(
            violations.isEmpty,
            """
            InstallationWizardView state management must delegate permission snapshot reads \
            through SystemStateProvider:
            \(violations.sorted().joined(separator: "\n"))
            """
        )
    }

    func testDragToAuthorizeControllerDelegatesPermissionSnapshotsToSystemStateProvider() throws {
        let controller = repositoryRootForPermissionSnapshotLint()
            .appendingPathComponent(
                "Sources/KeyPathInstallationWizard/UI/Helpers/DragToAuthorize/DragToAuthorizeController.swift"
            )

        let violations = try matchingPermissionSnapshotLines(
            in: controller,
            patterns: permissionSnapshotBypassPatterns()
        )

        XCTAssertTrue(
            violations.isEmpty,
            """
            DragToAuthorizeController must delegate permission snapshot reads \
            through SystemStateProvider:
            \(violations.sorted().joined(separator: "\n"))
            """
        )
    }

    func testKeyboardCaptureDelegatesSyncAccessibilityStatusToSystemStateProvider() throws {
        let capture = repositoryRootForPermissionSnapshotLint()
            .appendingPathComponent("Sources/KeyPathAppKit/Services/KeyboardCapture/KeyboardCapture.swift")

        let violations = try matchingPermissionSnapshotLines(
            in: capture,
            patterns: permissionSnapshotBypassPatterns()
        )

        XCTAssertTrue(
            violations.isEmpty,
            """
            KeyboardCapture must delegate synchronous Accessibility status reads \
            through SystemStateProvider:
            \(violations.sorted().joined(separator: "\n"))
            """
        )
    }

    func testWindowManagerDelegatesSyncAccessibilityStatusToSystemStateProvider() throws {
        let manager = repositoryRootForPermissionSnapshotLint()
            .appendingPathComponent("Sources/KeyPathAppKit/Services/System/WindowManager.swift")

        let violations = try matchingPermissionSnapshotLines(
            in: manager,
            patterns: permissionSnapshotBypassPatterns()
        )

        XCTAssertTrue(
            violations.isEmpty,
            """
            WindowManager must delegate synchronous Accessibility status reads \
            through SystemStateProvider:
            \(violations.sorted().joined(separator: "\n"))
            """
        )
    }
}

private func repositoryRootForPermissionSnapshotLint(file: StaticString = #filePath) -> URL {
    URL(fileURLWithPath: "\(file)")
        .deletingLastPathComponent() // Lint
        .deletingLastPathComponent() // KeyPathTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repo root
}

private func matchingPermissionSnapshotLines(in fileURL: URL, patterns: [String]) throws -> [String] {
    let contents = try String(contentsOf: fileURL, encoding: .utf8)
    let regexes = try patterns.map { try NSRegularExpression(pattern: $0) }
    let relativePath = fileURL.path.replacingOccurrences(
        of: repositoryRootForPermissionSnapshotLint().path + "/",
        with: ""
    )

    var violations: [String] = []
    for (idx, rawLine) in contents.components(separatedBy: .newlines).enumerated() {
        let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("//") || trimmed.hasPrefix("///") || trimmed.hasPrefix("*") { continue }
        let range = NSRange(rawLine.startIndex..., in: rawLine)
        if regexes.contains(where: { $0.firstMatch(in: rawLine, range: range) != nil }) {
            violations.append("\(relativePath):\(idx + 1): \(trimmed)")
        }
    }
    return violations
}

private func permissionSnapshotBypassPatterns() -> [String] {
    [
        #"PermissionOracle\.shared\.currentSnapshot"#,
        #"PermissionOracle\.shared\.forceRefresh"#,
        #"PermissionOracle\.shared"#
    ]
}
