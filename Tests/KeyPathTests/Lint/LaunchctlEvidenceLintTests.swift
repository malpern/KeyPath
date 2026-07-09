import Foundation
@preconcurrency import XCTest

/// Guards launchctl evidence-read migration slices.
///
/// Mutating launchctl operations still belong to installer/helper execution paths.
/// Read-only service-state evidence (`launchctl print`) belongs behind
/// `SystemStateProvider`, and this ratchet scans the whole production tree so new
/// files cannot reintroduce ad hoc launchd evidence reads.
final class LaunchctlEvidenceLintTests: XCTestCase {
    private static let allowList: Set<String> = [
        "Sources/KeyPathSystemProbes/SystemProbeClient.swift"
    ]

    func testProductionLaunchctlPrintEvidenceReadsDelegateToSystemStateProvider() throws {
        let violations = try LintScanner.matchingLines(
            under: LintScanner.path("Sources"),
            patterns: [
                #"SubprocessRunner\.shared\.launchctl\("print""#,
                #"subprocessRunner\.launchctl\("print""#,
                #"/bin/launchctl print"#
            ],
            allowList: Self.allowList
        )

        XCTAssertTrue(
            violations.isEmpty,
            """
            Production code must delegate launchctl print service-state evidence \
            to SystemStateProvider:
            \(violations.sorted().joined(separator: "\n"))
            """
        )
    }
}
