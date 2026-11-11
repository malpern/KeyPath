import Foundation
@preconcurrency import XCTest

/// Guards on the installer engine and its callers (formerly
/// InstallerDecisionPipelineLintTests; the pipeline was folded into the engine).
final class InstallerEngineLintTests: KeyPathTestCase {
    func testRetiredPlanningLayersStayDeleted() {
        let root = repositoryRoot()
        for retired in ["ActionDeterminer.swift", "InstallerDecisionPipeline.swift", "InstallerEngine+Recipes.swift"] {
            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: root.appendingPathComponent("Sources/KeyPathInstallationWizard/Core/\(retired)").path
                ),
                "\(retired) was folded into InstallerEngine; planning has one place"
            )
        }
    }

    func testEarlyInstallerExitsPreserveCorrelationEvidence() throws {
        // Every AutoFixAction has a session recipe, so runSingleAction has no
        // early no-recipe exit; the CLI's user-action exit is the one left.
        let root = repositoryRoot()
        let cliSource = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/KeyPathAppKit/CLI/SystemFacade.swift"
            ),
            encoding: .utf8
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
            Production planning must go through InstallerEngine.actions(for:context:)
            so the matrix assessment and executable plan share one captured context:
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
                  of: "/// Execute the planned operations",
                  range: planningStart.lowerBound ..< source.endIndex
              )
        else {
            return XCTFail("Could not locate the InstallerEngine planning section")
        }

        var planningSource = String(source[planningStart.lowerBound ..< planningEnd.lowerBound])
        // The intent-to-action mapping is part of planning too.
        guard let actionsStart = source.range(of: "// MARK: - Actions and recipes"),
              let actionsEnd = source.range(of: "// MARK: - Installer Errors")
        else {
            return XCTFail("Could not locate the InstallerEngine actions section")
        }
        planningSource += source[actionsStart.lowerBound ..< actionsEnd.lowerBound]
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

    func testDriverlessEngineHasNoPrivilegedExecution() throws {
        let source = try String(contentsOf: repositoryRoot().appendingPathComponent(
            "Sources/KeyPathInstallationWizard/Core/InstallerEngine.swift"
        ), encoding: .utf8)
        for forbidden in ["try await broker.", "helperMaintenance.installOrRefresh"] {
            XCTAssertFalse(source.contains(forbidden), "Privileged execution must be deleted: \(forbidden)")
        }
        XCTAssertTrue(source.contains("guard isSupportedSessionRecipe(recipe)"))
        let wiring = try String(contentsOf: repositoryRoot().appendingPathComponent(
            "Sources/KeyPathAppKit/WizardProtocolConformances.swift"
        ), encoding: .utf8)
        XCTAssertFalse(wiring.contains("UninstallCoordinator()"), "Never register the legacy privileged uninstaller")
    }

    func testDriverlessMenusDoNotOfferSystemUninstall() throws {
        let file = repositoryRoot()
            .appendingPathComponent("Sources/KeyPathAppKit/Core/AppMenuCommands.swift")
        let source = try String(contentsOf: file, encoding: .utf8)

        for forbidden in ["InstallerEngine().uninstall(", "UninstallCoordinator()", ".showUninstall"] {
            XCTAssertFalse(
                source.contains(forbidden),
                "Driverless menus must not offer unsupported system uninstall: \(forbidden)"
            )
        }
    }

    func testExecutorDoesNotContainVHIDMutationBranches() throws {
        let source = try String(contentsOf: repositoryRoot().appendingPathComponent(
            "Sources/KeyPathInstallationWizard/Core/InstallerEngine.swift"
        ), encoding: .utf8)
        XCTAssertFalse(source.contains("case InstallerRecipeID.activateVHIDManager:"))
        XCTAssertFalse(source.contains("activateVirtualHIDManager()"))
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
        .deletingLastPathComponent() // InstallerEngineLintTests.swift
        .deletingLastPathComponent() // Lint
        .deletingLastPathComponent() // KeyPathTests
        .deletingLastPathComponent() // Tests
}
