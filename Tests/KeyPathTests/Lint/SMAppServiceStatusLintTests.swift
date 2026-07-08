import Foundation
@preconcurrency import XCTest

/// Guards the centralization of `SMAppService.status` access (issue #853).
///
/// `SMAppService.status` is a synchronous IPC into `launchservicesd` that can block
/// the calling thread 10–30s under load. When that happens on the MainActor (UI init,
/// state-refresh ticks) it stalls the whole app. `SMAppServiceStatusProvider` is the
/// single owner of that IPC: it caches per-plist, coalesces concurrent fetches, and
/// always runs the blocking call off the caller's actor.
///
/// This test fails the build if any source outside the provider reads `.status` off an
/// `SMAppService` instance (a `SMAppService.daemon(…)` value or a `SMAppServiceProtocol`
/// from `smServiceFactory`). To fix a new violation, route the read through
/// `SystemStateProvider` or, for the low-level cache/coalescer itself,
/// `SMAppServiceStatusProvider.shared.cachedStatus(for:)` / `.freshStatus(for:)`.
/// Do **not** extend the allowlist.
///
/// The allowlist is a shrinking ratchet of pre-existing **synchronous** call sites that
/// are not on a hot path and whose migration would require threading `async` through the
/// wizard state machine / diagnostics. It should only shrink.
final class SMAppServiceStatusLintTests: XCTestCase {
    /// Files permitted to read `.status` directly. Ratchet — never add entries.
    ///
    /// - `SMAppServiceStatusProvider.swift`: the sole intended owner of the IPC.
    /// - `HelperManager.swift`: defines the `SMAppServiceProtocol` seam whose `status`
    ///   getter forwards to Apple's `SMAppService` — the one legitimate declaration.
    /// - The remainder are synchronous, non-hot-path diagnostic readers still
    ///   awaiting an async migration.
    private static let allowList: Set<String> = [
        "SMAppServiceStatusProvider.swift",
        "HelperManager.swift",
        "BlessDiagnostics.swift"
    ]

    func testStatusAccessIsCentralized() throws {
        let sourcesDir = repositoryRoot().appendingPathComponent("Sources")

        // Matches a `.status` read off an SMAppService-shaped expression:
        //   smServiceFactory(…).status   SMAppService.daemon(…).status
        //   svc.status                    service.status
        // The factory/daemon arg groups tolerate one level of nested parentheses
        // (e.g. `smServiceFactory(plistName(x)).status`) so a nested call cannot
        // slip a violation past the guard.
        let argGroup = #"\((?:[^()]|\([^()]*\))*\)"#
        let pattern = try NSRegularExpression(
            pattern: #"(smServiceFactory\#(argGroup)|SMAppService\.daemon\#(argGroup)|\bsvc|\bservice)\.status\b"#
        )

        guard let enumerator = FileManager.default.enumerator(at: sourcesDir, includingPropertiesForKeys: nil) else {
            return XCTFail("Could not enumerate \(sourcesDir.path)")
        }

        var violations: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            if Self.allowList.contains(url.lastPathComponent) { continue }
            guard let contents = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for (idx, rawLine) in contents.components(separatedBy: .newlines).enumerated() {
                let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
                // Skip comment lines — the codebase discusses SMAppService.status a lot.
                if trimmed.hasPrefix("//") || trimmed.hasPrefix("///") || trimmed.hasPrefix("*") { continue }
                let range = NSRange(rawLine.startIndex..., in: rawLine)
                if pattern.firstMatch(in: rawLine, range: range) != nil {
                    violations.append("\(url.lastPathComponent):\(idx + 1): \(trimmed)")
                }
            }
        }

        XCTAssertTrue(
            violations.isEmpty,
            """
            Direct SMAppService `.status` reads found outside SMAppServiceStatusProvider \
            (issue #853). Route through SystemStateProvider or the low-level \
            SMAppServiceStatusProvider cache/coalescer instead of adding to the allowlist:
            \(violations.sorted().joined(separator: "\n"))
            """
        )
    }

    func testKanataDaemonManagerDelegatesStatusProviderAccessToSystemStateProvider() throws {
        let manager = repositoryRoot()
            .appendingPathComponent("Sources/KeyPathAppKit/Managers/KanataDaemonManager.swift")

        let violations = try matchingLines(
            in: manager,
            patterns: [#"SMAppServiceStatusProvider\.shared"#]
        )

        XCTAssertTrue(
            violations.isEmpty,
            """
            KanataDaemonManager must delegate SMAppService status/cache access \
            through SystemStateProvider:
            \(violations.sorted().joined(separator: "\n"))
            """
        )
    }

    func testHelperManagerAsyncStatusAccessDelegatesToSystemStateProvider() throws {
        let files = [
            repositoryRoot().appendingPathComponent("Sources/KeyPathAppKit/Core/HelperManager+Installation.swift"),
            repositoryRoot().appendingPathComponent("Sources/KeyPathAppKit/Core/HelperManager+Status.swift")
        ]

        let violations = try files.flatMap {
            try matchingLines(
                in: $0,
                patterns: [#"SMAppServiceStatusProvider\.shared"#]
            )
        }

        XCTAssertTrue(
            violations.isEmpty,
            """
            HelperManager SMAppService status/cache access must delegate \
            through SystemStateProvider:
            \(violations.sorted().joined(separator: "\n"))
            """
        )
    }

    func testWizardProtocolConformancesDelegateHelperApprovalToHelperManager() throws {
        let conformances = repositoryRoot()
            .appendingPathComponent("Sources/KeyPathAppKit/WizardProtocolConformances.swift")

        let violations = try matchingLines(
            in: conformances,
            patterns: [
                #"smServiceFactory\(.*\)\.status"#,
                #"SMAppServiceStatusProvider\.shared"#
            ]
        )

        XCTAssertTrue(
            violations.isEmpty,
            """
            Wizard dependency glue must not read SMAppService status directly. \
            Route helper approval checks through HelperManager/SystemStateProvider:
            \(violations.sorted().joined(separator: "\n"))
            """
        )
    }

    func testKanataDaemonServiceDelegatesStatusProviderAccessToSystemStateProvider() throws {
        let service = repositoryRoot()
            .appendingPathComponent("Sources/KeyPathAppKit/Services/Kanata/KanataDaemonService.swift")

        let violations = try matchingLines(
            in: service,
            patterns: [#"SMAppServiceStatusProvider\.shared"#]
        )

        XCTAssertTrue(
            violations.isEmpty,
            """
            KanataDaemonService must delegate SMAppService status/cache access \
            through SystemStateProvider:
            \(violations.sorted().joined(separator: "\n"))
            """
        )
    }

    func testHelperMaintenanceDelegatesStatusProviderAccessToSystemStateProvider() throws {
        let maintenance = repositoryRoot()
            .appendingPathComponent("Sources/KeyPathAppKit/Managers/HelperMaintenance.swift")

        let violations = try matchingLines(
            in: maintenance,
            patterns: [#"SMAppServiceStatusProvider\.shared"#]
        )

        XCTAssertTrue(
            violations.isEmpty,
            """
            HelperMaintenance must delegate SMAppService status/cache access \
            through SystemStateProvider:
            \(violations.sorted().joined(separator: "\n"))
            """
        )
    }

    func testUninstallCoordinatorDelegatesStatusProviderAccessToSystemStateProvider() throws {
        let coordinator = repositoryRoot()
            .appendingPathComponent("Sources/KeyPathAppKit/Managers/UninstallCoordinator.swift")

        let violations = try matchingLines(
            in: coordinator,
            patterns: [#"SMAppServiceStatusProvider\.shared"#]
        )

        XCTAssertTrue(
            violations.isEmpty,
            """
            UninstallCoordinator must delegate SMAppService status/cache access \
            through SystemStateProvider:
            \(violations.sorted().joined(separator: "\n"))
            """
        )
    }

    func testAppLifecycleDelegatesStatusProviderAccessToSystemStateProvider() throws {
        let app = repositoryRoot()
            .appendingPathComponent("Sources/KeyPathAppKit/App.swift")

        let violations = try matchingLines(
            in: app,
            patterns: [#"SMAppServiceStatusProvider\.shared"#]
        )

        XCTAssertTrue(
            violations.isEmpty,
            """
            App lifecycle code must delegate SMAppService status/cache access \
            through SystemStateProvider:
            \(violations.sorted().joined(separator: "\n"))
            """
        )
    }
}

private func repositoryRoot(file: StaticString = #filePath) -> URL {
    URL(fileURLWithPath: "\(file)")
        .deletingLastPathComponent() // Lint
        .deletingLastPathComponent() // KeyPathTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repo root
}

private func matchingLines(in fileURL: URL, patterns: [String]) throws -> [String] {
    let contents = try String(contentsOf: fileURL, encoding: .utf8)
    let regexes = try patterns.map { try NSRegularExpression(pattern: $0) }
    let relativePath = fileURL.path.replacingOccurrences(of: repositoryRoot().path + "/", with: "")

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
