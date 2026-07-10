import Foundation
@preconcurrency import XCTest

/// Guards Phase 1's "one owner for OS/system evidence" rule.
///
/// This is a structural ratchet, not a claim that every remaining cache is ideal.
/// It prevents new runtime/installer state caches outside the known provider-style
/// owners while follow-up work shrinks the allowlist.
final class SnapshotConsumerLintTests: XCTestCase {
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
}
