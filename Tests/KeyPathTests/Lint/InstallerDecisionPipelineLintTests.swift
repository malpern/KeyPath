import Foundation
@preconcurrency import XCTest

final class InstallerDecisionPipelineLintTests: KeyPathTestCase {
    func testDeprecatedActionDeterminerFacadeIsDeleted() throws {
        let root = repositoryRoot()
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(
                    "Sources/KeyPathInstallationWizard/Core/ActionDeterminer.swift"
                ).path
            )
        )
        let pipeline = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/KeyPathInstallationWizard/Core/InstallerDecisionPipeline.swift"
            ),
            encoding: .utf8
        )
        XCTAssertFalse(pipeline.contains("enum ActionDeterminer"))
    }

    func testEarlyInstallerExitsPreserveCorrelationEvidence() throws {
        let root = repositoryRoot()
        let engineSource = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/KeyPathInstallationWizard/Core/InstallerEngine.swift"
            ),
            encoding: .utf8
        )
        let cliSource = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/KeyPathAppKit/CLI/SystemFacade.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(
            engineSource.contains("planID: basePlan.id")
                && engineSource.contains("beforeSnapshotID: context.snapshotID"),
            "runSingleAction no-recipe failures must preserve plan and snapshot IDs."
        )
        XCTAssertTrue(
            cliSource.contains("planID: plan.id.uuidString")
                && cliSource.contains("beforeSnapshotID: context.snapshotID.uuidString"),
            "CLI user-action early returns must preserve plan and snapshot IDs."
        )
    }

    func testProductionPlanningUsesCanonicalDecisionPipeline() throws {
        let root = repositoryRoot()
        let consumers = [
            root.appendingPathComponent("Sources/KeyPathInstallationWizard/Core/InstallerEngine.swift"),
            root.appendingPathComponent("Sources/KeyPathInstallationWizard/Core/InstallerEngine+Recipes.swift"),
            root.appendingPathComponent("Sources/KeyPathInstallationWizard/Core/SystemStateResult+SystemContext.swift"),
        ]
        var violations: [String] = []

        for file in consumers {
            let source = try String(contentsOf: file, encoding: .utf8)
            for (index, line) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
                where line.contains("ActionDeterminer")
            {
                violations.append("\(file.lastPathComponent):\(index + 1): \(line)")
            }
        }

        XCTAssertTrue(
            violations.isEmpty,
            """
            Production planning must consume InstallerDecisionPipeline so the
            matrix assessment and executable plan share one captured context:
            \(violations.joined(separator: "\n"))
            """
        )
    }

    func testCompatibilityIsProjectedFromCanonicalSnapshot() throws {
        let root = repositoryRoot()
        let consumers = [
            root.appendingPathComponent("Sources/KeyPathInstallationWizard/Core/InstallerEngine.swift"),
            root.appendingPathComponent("Sources/KeyPathAppKit/Services/MainAppStateController.swift"),
        ]
        var violations: [String] = []

        for file in consumers {
            let source = try String(contentsOf: file, encoding: .utf8)
            for (index, line) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
                where line.contains("SystemRequirements(")
            {
                violations.append("\(file.lastPathComponent):\(index + 1): \(line)")
            }
        }

        XCTAssertTrue(
            violations.isEmpty,
            """
            Installer and main-app projections must consume compatibility from
            SystemSnapshot instead of performing another system read:
            \(violations.joined(separator: "\n"))
            """
        )
    }

    func testClientsDoNotRecaptureInstallerMatrixEvidence() throws {
        let root = repositoryRoot()
        let consumers = [
            root.appendingPathComponent("Sources/KeyPathAppKit/CLI/SystemFacade.swift"),
            root.appendingPathComponent("Sources/KeyPathAppKit/Services/MainAppStateController.swift"),
        ]
        let forbidden = [
            "currentInstallerStateMatrixSnapshot",
            "SystemStateProvider.installerStateMatrixSnapshot",
        ]
        var violations: [String] = []

        for file in consumers {
            let source = try String(contentsOf: file, encoding: .utf8)
            for symbol in forbidden where source.contains(symbol) {
                violations.append("\(file.lastPathComponent): \(symbol)")
            }
        }

        XCTAssertTrue(
            violations.isEmpty,
            "Clients must render the assessment attached to their captured context or plan: \(violations)"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(
                    "Sources/KeyPathAppKit/Core/SystemStateProvider+InstallerStateMatrix.swift"
                ).path
            ),
            "Do not restore the duplicate system-probe-to-matrix compatibility path"
        )
    }

    func testPlanningPerformsNoSystemIO() throws {
        let file = repositoryRoot()
            .appendingPathComponent("Sources/KeyPathInstallationWizard/Core/InstallerEngine.swift")
        let source = try String(contentsOf: file, encoding: .utf8)
        guard let planningStart = source.range(of: "public func makePlan("),
              let planningEnd = source.range(
                  of: "// MARK: - Action Determination",
                  range: planningStart.lowerBound ..< source.endIndex
              )
        else {
            return XCTFail("Could not locate the InstallerEngine planning section")
        }

        let planningSource = source[planningStart.lowerBound ..< planningEnd.lowerBound]
        let forbiddenReads = [
            "FileManager",
            "SystemRequirements",
            "checkSystem(",
            "inspectSystem(",
            "ServiceHealthChecker",
            "SMAppService",
            "Process(",
            "URLSession",
        ]
        let violations = forbiddenReads.filter { planningSource.contains($0) }

        XCTAssertTrue(
            violations.isEmpty,
            "Planning must be a pure projection of captured context; found: \(violations)"
        )
    }

    func testBootstrapperDoesNotRecursivelyInvokeInstallerEngine() throws {
        let file = repositoryRoot()
            .appendingPathComponent("Sources/KeyPathInstallationWizard/Core/ServiceBootstrapper.swift")
        let source = try String(contentsOf: file, encoding: .utf8)
        let forbiddenCalls = ["InstallerEngine(", ".runSingleAction("]
        let violations = forbiddenCalls.filter { source.contains($0) }

        XCTAssertTrue(
            violations.isEmpty,
            """
            ServiceBootstrapper executes inside an InstallerEngine transaction. \
            It must execute declared operations without creating another plan or \
            reacquiring the transaction gate; found: \(violations)
            """
        )
    }

    func testUninstallCoordinatorDoesNotStartInstallerTransactions() throws {
        let file = repositoryRoot()
            .appendingPathComponent("Sources/KeyPathAppKit/Managers/UninstallCoordinator.swift")
        let source = try String(contentsOf: file, encoding: .utf8)
        let forbiddenCalls = [".run(intent:", ".runSingleAction(", ".uninstall("]
        let violations = forbiddenCalls.filter { source.contains($0) }

        XCTAssertTrue(
            violations.isEmpty,
            "UninstallCoordinator executes inside the InstallerEngine-owned transaction: \(violations)"
        )
    }

    func testEveryPublicPrivilegedRouteUsesSharedTransactionWrapper() throws {
        let file = repositoryRoot()
            .appendingPathComponent("Sources/KeyPathInstallationWizard/Core/InstallerEngine.swift")
        let source = try String(contentsOf: file, encoding: .utf8)
        let routeNames = [
            "uninstallVirtualHIDDrivers",
            "disableKarabinerGrabber",
            "restartKarabinerDaemon",
        ]

        for routeName in routeNames {
            guard let start = source.range(of: "public func \(routeName)("),
                  let end = source.range(of: "\n    }", range: start.lowerBound ..< source.endIndex)
            else {
                XCTFail("Could not locate public privileged route \(routeName)")
                continue
            }
            let body = source[start.lowerBound ..< end.upperBound]
            XCTAssertTrue(
                body.contains("withInstallerTransaction"),
                "\(routeName) must participate in the shared installer transaction"
            )
        }
    }

    func testInstantUninstallRoutesThroughInstallerEngine() throws {
        let file = repositoryRoot()
            .appendingPathComponent("Sources/KeyPathAppKit/Core/AppMenuCommands.swift")
        let source = try String(contentsOf: file, encoding: .utf8)

        XCTAssertTrue(source.contains("InstallerEngine().uninstall("))
        XCTAssertFalse(
            source.contains("UninstallCoordinator()"),
            "The hidden uninstall shortcut must not bypass the shared transaction gate"
        )
    }

    func testExecutorDoesNotMakeUndeclaredVHIDActivationDecisions() throws {
        let file = repositoryRoot()
            .appendingPathComponent("Sources/KeyPathInstallationWizard/Core/InstallerEngine.swift")
        let source = try String(contentsOf: file, encoding: .utf8)
        guard let executionStart = source.range(of: "private func executeRecipeWithDetails("),
              let explicitActivation = source.range(
                  of: "case InstallerRecipeID.activateVHIDManager:",
                  range: executionStart.lowerBound ..< source.endIndex
              )
        else {
            return XCTFail("Could not locate installer execution boundaries")
        }

        let genericExecution = source[executionStart.lowerBound ..< explicitActivation.lowerBound]
        let forbiddenDecisions = [
            "VHIDDeviceManager(",
            "detectActivation(",
            "activateVirtualHIDManager()"
        ]
        let violations = forbiddenDecisions.filter { genericExecution.contains($0) }

        XCTAssertTrue(
            violations.isEmpty,
            "Generic recipe execution may only run declared plan steps; found: \(violations)"
        )
    }

    func testWizardActionsConsumeOwnedRunFinalEvidence() throws {
        let file = repositoryRoot()
            .appendingPathComponent(
                "Sources/KeyPathInstallationWizard/UI/InstallationWizardView+Actions.swift"
            )
        let source = try String(contentsOf: file, encoding: .utf8)
        let forbiddenSecondObservers = [
            "refreshManagementState(",
            "performPostFixHealthCheck(",
            "detectCurrentState(",
            "refreshSystemState(",
            "VHIDDeviceManager(",
            "wizardStartupRevalidate",
            "getDetailedErrorMessage("
        ]
        let violations = forbiddenSecondObservers.filter { source.contains($0) }

        XCTAssertTrue(
            violations.isEmpty,
            "Wizard actions must render the owned run result without a second observer: \(violations)"
        )
        XCTAssertTrue(source.contains("applyOwnedRunResult(report)"))
        XCTAssertTrue(source.contains("report.finalContext"))
        XCTAssertTrue(source.contains("evidenceApplied"))
    }
}

private func repositoryRoot(file: StaticString = #filePath) -> URL {
    URL(fileURLWithPath: "\(file)")
        .deletingLastPathComponent() // InstallerDecisionPipelineLintTests.swift
        .deletingLastPathComponent() // Lint
        .deletingLastPathComponent() // KeyPathTests
        .deletingLastPathComponent() // Tests
}
