import Foundation
@preconcurrency import XCTest

/// Guards Phase 1's "one owner for OS/system evidence" rule.
///
/// This is a structural ratchet, not a claim that every remaining cache is ideal.
/// It prevents new runtime/installer state caches outside the known provider-style
/// owners while follow-up work shrinks the allowlist.
final class SnapshotConsumerLintTests: XCTestCase {
    func testCanonicalCaptureTimeoutIsOwnedBySystemValidator() throws {
        let validatorURL = LintScanner.path(
            "Sources/KeyPathAppKit/Services/System/SystemValidator.swift"
        )
        let validator = try String(contentsOf: validatorURL, encoding: .utf8)
        XCTAssertTrue(validator.contains("canonicalCaptureTimeout"))
        XCTAssertTrue(validator.contains("boundedCapture(timeout:"))

        let mainControllerURL = LintScanner.path(
            "Sources/KeyPathAppKit/Services/MainAppStateController.swift"
        )
        let mainController = try String(contentsOf: mainControllerURL, encoding: .utf8)
        XCTAssertFalse(mainController.contains("ValidationError.timeout"))
        XCTAssertFalse(mainController.contains("Validation run started (watchdog="))

        let wizardURL = LintScanner.path(
            "Sources/KeyPathInstallationWizard/Core/WizardOperationsUIExtension.swift"
        )
        let stateDetection = try LintScanner.functionBody(named: "stateDetection", in: wizardURL)
        XCTAssertFalse(
            stateDetection.contains("withThrowingTaskGroup"),
            "Wizard state detection must consume SystemValidator timeout evidence, not race a client watchdog."
        )
    }

    func testTCPConfigurationEvidenceComesFromCanonicalSnapshot() throws {
        let controllerURL = LintScanner.path(
            "Sources/KeyPathAppKit/Services/MainAppStateController.swift"
        )
        let controller = try String(contentsOf: controllerURL, encoding: .utf8)
        XCTAssertTrue(controller.contains("snapshot.health.kanataTCPConfigured"))
        XCTAssertFalse(controller.contains("func checkTCPConfiguration"))
        XCTAssertFalse(controller.contains("PropertyListSerialization.propertyList"))
    }

    func testFreshCaptureInvalidatesComponentFacts() throws {
        let validator = LintScanner.path(
            "Sources/KeyPathAppKit/Services/System/SystemValidator.swift"
        )
        let source = try String(contentsOf: validator, encoding: .utf8)

        XCTAssertTrue(
            source.contains("if freshness == .fresh {") && source.contains("invalidateCaches()"),
            "A canonical fresh capture must invalidate subordinate evidence caches."
        )
        XCTAssertTrue(
            source.contains("cachedComponentFacts = nil"),
            "SystemValidator.invalidateCaches() must clear component installation facts."
        )
        XCTAssertTrue(
            source.contains("cachedComponentFacts.isFresh(ttl: Self.canonicalSnapshotCacheTTL)"),
            "Component facts must use the canonical snapshot freshness window."
        )
    }

    func testSMAppServiceStatusProviderCacheIsOnlyConsumedThroughSystemStateProvider() throws {
        let violations = try LintScanner.matchingLines(
            under: LintScanner.path("Sources"),
            patterns: [#"SMAppServiceStatusProvider\.shared"#],
            allowList: [
                "Sources/KeyPathAppKit/Core/SMAppServiceStatusProvider.swift",
                "Sources/KeyPathAppKit/Core/SystemStateProvider+SMAppService.swift"
            ]
        )

        XCTAssertTrue(
            violations.isEmpty,
            """
            Production consumers must reach SMAppService status/cache evidence \
            through SystemStateProvider, not SMAppServiceStatusProvider.shared:
            \(violations.sorted().joined(separator: "\n"))
            """
        )
    }

    func testRuntimeAndInstallerStateCachesStayInKnownOwners() throws {
        let violations = try LintScanner.matchingLines(
            under: LintScanner.path("Sources"),
            patterns: [
                #"\bhealthCache\b"#,
                #"\bruntimeCache\b"#,
                #"\bserviceStatusCache\b"#,
                #"\bcachedManagementState\b"#,
                #"\bsmAppServicePendingCache\b"#,
                #"\bcachedHelperVersion\b"#
            ],
            allowList: [
                "Sources/KeyPathInstallationWizard/Core/ServiceHealthChecker.swift",
                "Sources/KeyPathAppKit/Managers/KanataDaemonManager.swift"
            ]
        )

        XCTAssertTrue(
            violations.isEmpty,
            """
            Runtime/installer state caches must stay in the known provider-style \
            owners while Phase 1 follow-ups shrink this allowlist. Do not add new \
            system-state caches in consumers:
            \(violations.sorted().joined(separator: "\n"))
            """
        )
    }

    func testInstallerEnginePreservesMatrixEvidenceThroughSystemSnapshotBridge() throws {
        let body = try LintScanner.functionBody(
            named: "inspectSystem",
            in: LintScanner.path("Sources/KeyPathInstallationWizard/Core/InstallerEngine.swift")
        )
        XCTAssertTrue(
            body.contains("SystemContext(snapshot: snapshot)"),
            "InstallerEngine.inspectSystem() must use the canonical SystemSnapshot projection."
        )

        let typesURL = LintScanner.path(
            "Sources/KeyPathInstallationWizard/Core/InstallerEngineTypes.swift"
        )
        let typesSource = try String(contentsOf: typesURL, encoding: .utf8)
        guard let projectionStart = typesSource.range(of: "public init(snapshot: SystemSnapshot)"),
              let projectionEnd = typesSource.range(
                  of: "/// Empty/fallback context",
                  range: projectionStart.lowerBound ..< typesSource.endIndex
              )
        else {
            return XCTFail("Could not locate the canonical SystemSnapshot projection")
        }
        let projection = typesSource[projectionStart.lowerBound ..< projectionEnd.lowerBound]

        for mapping in [
            "permissions: snapshot.permissions",
            "services: snapshot.health",
            "conflicts: snapshot.conflicts",
            "components: snapshot.components",
            "helper: snapshot.helper",
            "macOSVersion: snapshot.compatibility.macOSVersion",
            "driverCompatible: snapshot.compatibility.driverCompatible",
            "timestamp: snapshot.timestamp",
            "captureStatus: snapshot.captureStatus",
        ] {
            XCTAssertTrue(
                projection.contains(mapping),
                """
                SystemContext.init(snapshot:) must preserve `\(mapping)` when \
                projecting canonical snapshot evidence into compatibility state.
                """
            )
        }
    }

    func testInstallerStateMatrixSnapshotInitializerDoesNotDefaultEvidence() throws {
        let fileURL = LintScanner.path("Sources/KeyPathInstallationWizard/Core/InstallerStateMatrix.swift")
        let contents = try String(contentsOf: fileURL, encoding: .utf8)

        guard let initStart = contents.range(of: "public init(")?.lowerBound,
              let bodyStart = contents[initStart...].firstIndex(of: "{")
        else {
            XCTFail("Could not find InstallerStateMatrixSnapshot public initializer")
            return
        }

        let signature = String(contents[initStart ..< bodyStart])

        XCTAssertFalse(
            signature.contains(" = "),
            """
            InstallerStateMatrixSnapshot production construction must spell out \
            every evidence field. Defaulting omitted matrix evidence back to \
            healthy values reopens the false-green bug class.
            """
        )
    }

    func testCLIInstallerConsumesEngineOwnedFinalSnapshot() throws {
        let fileURL = LintScanner.path("Sources/KeyPathAppKit/CLI/SystemFacade.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertEqual(
            source.components(separatedBy: "finalContext: report.finalContext").count - 1,
            2,
            "CLI install and repair must consume the final context captured by InstallerEngine."
        )
        XCTAssertFalse(
            source.contains("report.success ? await engine.inspectSystem() : nil"),
            "CLI clients must not race the engine-owned post-execution snapshot with a second observer."
        )
    }
}
