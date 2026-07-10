import Foundation
@preconcurrency import XCTest

final class InstallerDecisionPipelineLintTests: KeyPathTestCase {
    func testProductionPlanningUsesCanonicalDecisionPipeline() throws {
        let root = repositoryRoot()
        let consumers = [
            root.appendingPathComponent("Sources/KeyPathInstallationWizard/Core/InstallerEngine.swift"),
            root.appendingPathComponent("Sources/KeyPathInstallationWizard/Core/InstallerEngine+Recipes.swift"),
            root.appendingPathComponent("Sources/KeyPathInstallationWizard/Core/SystemContextAdapter.swift"),
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
