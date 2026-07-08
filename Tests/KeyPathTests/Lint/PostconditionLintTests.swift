import Foundation
@preconcurrency import XCTest

/// Guards ADR-031's postcondition enforcement boundary.
///
/// This ratchet pins the load-bearing mutating router verbs that already verify
/// postconditions. The explicit exemption list names remaining mutating verbs so
/// new public privileged operations cannot bypass the review surface by default.
/// Follow-up postcondition PRs should shrink the exemption list.
final class PostconditionLintTests: XCTestCase {
    private let router = LintScanner.path("Sources/KeyPathAppKit/Core/PrivilegedOperationsRouter.swift")

    func testRuntimeMutatingRouterVerbsEnforceRuntimePostcondition() throws {
        try assertFunctions(
            [
                "installRequiredRuntimeServices",
                "recoverRequiredRuntimeServices",
                "regenerateServiceConfiguration"
            ],
            contain: "enforceKanataRuntimePostcondition"
        )
    }

    func testVHIDServiceRepairEnforcesVHIDPostcondition() throws {
        try assertFunctions(
            [
                "installRequiredRuntimeServices",
                "repairVHIDDaemonServices"
            ],
            contain: "enforceVHIDServicesPostcondition"
        )
    }

    func testPublicRouterOperationsAreClassifiedForPostconditionReview() throws {
        let contents = try String(contentsOf: router, encoding: .utf8)
        let regex = try NSRegularExpression(pattern: #"public func ([A-Za-z0-9_]+)"#)
        let range = NSRange(contents.startIndex..., in: contents)
        let publicFunctions = Set(regex.matches(in: contents, range: range).compactMap { match -> String? in
            guard let nameRange = Range(match.range(at: 1), in: contents) else { return nil }
            return String(contents[nameRange])
        })

        let postconditionEnforced: Set = [
            "installRequiredRuntimeServices",
            "recoverRequiredRuntimeServices",
            "regenerateServiceConfiguration",
            "repairVHIDDaemonServices"
        ]
        let postconditionDelegatedOrVerified: Set = [
            "installServicesIfUninstalled",
            "restartKarabinerDaemonVerified"
        ]
        let explicitFollowUpExemptions: Set = [
            "cleanupPrivilegedHelper",
            "installNewsyslogConfig",
            "activateVirtualHIDManager",
            "uninstallVirtualHIDDrivers",
            "downloadAndInstallCorrectVHIDDriver",
            "terminateProcess",
            "killAllKanataProcesses",
            "disableKarabinerGrabber",
            "sudoExecuteCommand"
        ]

        XCTAssertEqual(
            publicFunctions,
            postconditionEnforced
                .union(postconditionDelegatedOrVerified)
                .union(explicitFollowUpExemptions),
            """
            Every public PrivilegedOperationsRouter operation must be classified \
            for postcondition review. New mutating verbs should enforce a \
            postcondition before returning success; do not expand the exemption \
            list without documenting the reason in the PR:
            \(publicFunctions.sorted().joined(separator: "\n"))
            """
        )
    }

    private func assertFunctions(_ functionNames: [String], contain needle: String) throws {
        var violations: [String] = []
        for functionName in functionNames {
            let body = try LintScanner.functionBody(named: functionName, in: router)
            if !body.contains(needle) {
                violations.append("\(functionName) does not call \(needle)")
            }
        }

        XCTAssertTrue(
            violations.isEmpty,
            """
            Router mutating operations must prove postconditions before returning \
            success:
            \(violations.sorted().joined(separator: "\n"))
            """
        )
    }
}
