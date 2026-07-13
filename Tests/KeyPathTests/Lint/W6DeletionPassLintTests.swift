import Foundation
@preconcurrency import XCTest

final class W6DeletionPassLintTests: XCTestCase {
    func testKarabinerConflictSingleImplementationProtocolDoesNotRegrow() throws {
        let serviceFile = repositoryRoot()
            .appendingPathComponent("Sources/KeyPathAppKit/Services/Karabiner/KarabinerConflictService.swift")
        let runtimeCoordinator = repositoryRoot()
            .appendingPathComponent("Sources/KeyPathAppKit/Managers/RuntimeCoordinator.swift")
        let requirementsChecker = repositoryRoot()
            .appendingPathComponent("Sources/KeyPathAppKit/Services/System/SystemRequirementsChecker.swift")

        let violations = try [
            serviceFile,
            runtimeCoordinator,
            requirementsChecker,
        ].flatMap { file in
            try matchingLines(
                in: file,
                patterns: [
                    #"protocol\s+KarabinerConflictManaging\b"#,
                    #":\s*KarabinerConflictManaging\b"#,
                    #"\bKarabinerConflictManaging\b"#,
                ]
            )
        }

        XCTAssertTrue(
            violations.isEmpty,
            """
            W6 removes single-implementation protocols unless they provide \
            real injection value. KarabinerConflictService is the concrete \
            dependency; do not regrow KarabinerConflictManaging:
            \(violations.sorted().joined(separator: "\n"))
            """
        )
    }

    func testServiceHealthMonitorSingleImplementationProtocolDoesNotRegrow() throws {
        let monitorFile = repositoryRoot()
            .appendingPathComponent("Sources/KeyPathAppKit/Services/Monitoring/ServiceHealthMonitor.swift")
        let diagnosticsManager = repositoryRoot()
            .appendingPathComponent("Sources/KeyPathAppKit/Managers/Diagnostics/DiagnosticsManager.swift")

        let violations = try [
            monitorFile,
            diagnosticsManager,
        ].flatMap { file in
            try matchingLines(
                in: file,
                patterns: [
                    #"protocol\s+ServiceHealthMonitorProtocol\b"#,
                    #":\s*ServiceHealthMonitorProtocol\b"#,
                    #"\bServiceHealthMonitorProtocol\b"#,
                ]
            )
        }

        XCTAssertTrue(
            violations.isEmpty,
            """
            W6 removes single-implementation protocols unless they provide \
            real injection value. ServiceHealthMonitor is the concrete \
            dependency; do not regrow ServiceHealthMonitorProtocol:
            \(violations.sorted().joined(separator: "\n"))
            """
        )
    }

    func testConfigurationManagerSingleImplementationProtocolDoesNotRegrow() throws {
        let managerFile = repositoryRoot()
            .appendingPathComponent("Sources/KeyPathAppKit/Managers/Configuration/ConfigurationManager.swift")
        let runtimeCoordinator = repositoryRoot()
            .appendingPathComponent("Sources/KeyPathAppKit/Managers/RuntimeCoordinator.swift")

        let violations = try [
            managerFile,
            runtimeCoordinator,
        ].flatMap { file in
            try matchingLines(
                in: file,
                patterns: [
                    #"protocol\s+ConfigurationManaging\b"#,
                    #":\s*ConfigurationManaging\b"#,
                    #"\bConfigurationManaging\b"#,
                ]
            )
        }

        XCTAssertTrue(
            violations.isEmpty,
            """
            W6 removes single-implementation protocols unless they provide \
            real injection value. ConfigurationManager is the concrete \
            dependency; do not regrow ConfigurationManaging:
            \(violations.sorted().joined(separator: "\n"))
            """
        )
    }

    func testConfigurationManagerDoesNotRegrowSavePipeline() throws {
        let managerFile = repositoryRoot()
            .appendingPathComponent("Sources/KeyPathAppKit/Managers/Configuration/ConfigurationManager.swift")

        let violations = try matchingLines(
            in: managerFile,
            patterns: [
                #"func\s+writeGeneratedConfig\b"#,
                #"func\s+writeValidatedConfig\b"#,
                #"func\s+saveConfiguration\b"#,
            ]
        )

        XCTAssertTrue(
            violations.isEmpty,
            "ConfigurationManager owns startup and file utilities, not an alternate save/write pipeline:\n\(violations.sorted().joined(separator: "\n"))"
        )
    }

    func testDiagnosticsManagerSingleImplementationProtocolDoesNotRegrow() throws {
        let managerFile = repositoryRoot()
            .appendingPathComponent("Sources/KeyPathAppKit/Managers/Diagnostics/DiagnosticsManager.swift")
        let runtimeCoordinator = repositoryRoot()
            .appendingPathComponent("Sources/KeyPathAppKit/Managers/RuntimeCoordinator.swift")
        let reloadCoordinator = repositoryRoot()
            .appendingPathComponent("Sources/KeyPathAppKit/Managers/ConfigReloadCoordinator.swift")
        let reloadTests = repositoryRoot()
            .appendingPathComponent("Tests/KeyPathTests/Services/ConfigReloadCoordinatorTests.swift")

        let violations = try [
            managerFile,
            runtimeCoordinator,
            reloadCoordinator,
            reloadTests,
        ].flatMap { file in
            try matchingLines(
                in: file,
                patterns: [
                    #"protocol\s+DiagnosticsManaging\b"#,
                    #":\s*DiagnosticsManaging\b"#,
                    #"\bDiagnosticsManaging\b"#,
                ]
            )
        }

        XCTAssertTrue(
            violations.isEmpty,
            """
            W6 removes broad single-implementation protocols unless they \
            provide real injection value. DiagnosticsManager is concrete; \
            ConfigReloadCoordinator uses a narrow healthStatusProvider seam \
            instead of regrowing DiagnosticsManaging:
            \(violations.sorted().joined(separator: "\n"))
            """
        )
    }

    func testServiceLifecycleCoordinatorDoesNotRegrowSMAppServicePendingCache() throws {
        let coordinatorFile = repositoryRoot()
            .appendingPathComponent("Sources/KeyPathAppKit/Managers/ServiceLifecycleCoordinator.swift")

        let violations = try matchingLines(
            in: coordinatorFile,
            patterns: [
                #"\bsmAppServicePendingCache\b"#,
                #"\bsmAppServicePendingCacheTTL\b"#,
                #"\bsmAppServiceRefreshTask\b"#,
                #"\bisSMAppServicePendingCached\b"#,
            ]
        )

        XCTAssertTrue(
            violations.isEmpty,
            """
            W6 collapses duplicate service-state caches into the provider/manager \
            layer. ServiceLifecycleCoordinator should read \
            KanataDaemonManager.currentManagementState and refresh only unknown \
            state instead of regrowing a local SMAppService pending cache:
            \(violations.sorted().joined(separator: "\n"))
            """
        )
    }

    func testAsyncRepairGatesDoNotConsumeUnboundedManagementStateCache() throws {
        let lifecycleCoordinator = repositoryRoot()
            .appendingPathComponent("Sources/KeyPathAppKit/Managers/ServiceLifecycleCoordinator.swift")
        let reloadCoordinator = repositoryRoot()
            .appendingPathComponent("Sources/KeyPathAppKit/Managers/ConfigReloadCoordinator.swift")

        let violations = try [
            lifecycleCoordinator,
            reloadCoordinator,
        ].flatMap { file in
            try matchingLines(
                in: file,
                patterns: [
                    #"\bcurrentManagementState\b"#,
                ]
            )
        }

        XCTAssertTrue(
            violations.isEmpty,
            """
            W6 removes unbounded duplicate management-state reads from async \
            repair/start/reload gates. These paths should call \
            refreshManagementStateInternal(), leaving freshness and IPC \
            coalescing to the centralized provider-backed manager:
            \(violations.sorted().joined(separator: "\n"))
            """
        )
    }

    func testServiceLifecycleCoordinatorDoesNotRegrowDuplicateVHIDStartCheck() throws {
        let coordinatorFile = repositoryRoot()
            .appendingPathComponent("Sources/KeyPathAppKit/Managers/ServiceLifecycleCoordinator.swift")

        let violations = try matchingLines(
            in: coordinatorFile,
            patterns: [
                #"Second safety layer"#,
                #"serviceID:\s*ServiceHealthChecker\.vhidDaemonServiceID"#,
            ]
        )

        XCTAssertTrue(
            violations.isEmpty,
            """
            W6 removes duplicated in-path service checks. startKanata should \
            use the injected VirtualHID daemon health predicate once instead \
            of performing a second ServiceHealthChecker query in the start path:
            \(violations.sorted().joined(separator: "\n"))
            """
        )
    }

    func testCanonicalMatrixProjectionDoesNotTreatUnknownHelperVersionAsFresh() throws {
        let projections = [
            repositoryRoot().appendingPathComponent("Sources/KeyPathInstallationWizard/Core/InstallerStateMatrix.swift"),
        ]

        let violations = try projections.flatMap { file in
            try matchingLines(
                in: file,
                patterns: [
                    #"helper\.version\s*==\s*nil\s*\|\|"#,
                ]
            )
        }

        XCTAssertTrue(
            violations.isEmpty,
            """
            Helper responsiveness is not helper freshness. The matrix projection \
            must treat an unknown helper version as not fresh and route to \
            helper verification/refresh instead of reporting green:
            \(violations.sorted().joined(separator: "\n"))
            """
        )
    }

    func testHelperManagerDoesNotRegrowCachedHelperVersion() throws {
        let helperFiles = [
            repositoryRoot().appendingPathComponent("Sources/KeyPathAppKit/Core/HelperManager.swift"),
            repositoryRoot().appendingPathComponent("Sources/KeyPathAppKit/Core/HelperManager+Status.swift"),
            repositoryRoot().appendingPathComponent("Sources/KeyPathAppKit/Core/HelperManager+ConnectionLifecycle.swift"),
        ]

        let violations = try helperFiles.flatMap { file in
            try matchingLines(
                in: file,
                patterns: [
                    #"\bcachedHelperVersion\b"#,
                ]
            )
        }

        XCTAssertTrue(
            violations.isEmpty,
            """
            W6 collapses installer helper state into current provider/XPC \
            evidence instead of keeping an actor-local helper-version cache. \
            Do not regrow cachedHelperVersion:
            \(violations.sorted().joined(separator: "\n"))
            """
        )
    }

    func testInstallerCompatibilityBridgesDoNotRegrow() throws {
        let productionFiles = [
            "Sources/KeyPathWizardCore/RuntimeCoordinating.swift",
            "Sources/KeyPathAppKit/WizardProtocolConformances.swift",
            "Sources/KeyPathAppKit/Managers/RuntimeCoordinator.swift",
            "Sources/KeyPathAppKit/UI/ViewModels/KanataViewModel.swift",
            "Sources/KeyPathInstallationWizard/Core/WizardStateMachine.swift",
            "Sources/KeyPathInstallationWizard/Core/InstallerEngine.swift",
        ].map { repositoryRoot().appendingPathComponent($0) }

        let violations = try productionFiles.flatMap { file in
            try matchingLines(
                in: file,
                patterns: [
                    #"\bWizardRepairReport\b"#,
                    #"\brunFullRepair\b"#,
                    #"\brunFullInstall\b"#,
                    #"configure\(kanataManager"#,
                    #"InstallerEngine\(kanataManager"#,
                    #"\bSystemContextAdapter\b"#,
                ]
            )
        }

        XCTAssertTrue(
            violations.isEmpty,
            """
            Installer mutations belong directly to InstallerEngine. Do not \
            regrow unused RuntimeCoordinator/ViewModel forwarding methods, \
            lossy repair reports, or no-op wizard configuration bridges:
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

    return contents.components(separatedBy: .newlines).enumerated().compactMap { lineNumber, rawLine in
        let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
        guard !trimmed.hasPrefix("//"), !trimmed.hasPrefix("///") else { return nil }

        let range = NSRange(rawLine.startIndex..., in: rawLine)
        guard regexes.contains(where: { $0.firstMatch(in: rawLine, range: range) != nil }) else {
            return nil
        }
        return "\(fileURL.lastPathComponent):\(lineNumber + 1): \(trimmed)"
    }
}
