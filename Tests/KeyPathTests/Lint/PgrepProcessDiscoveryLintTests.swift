import Foundation
@preconcurrency import XCTest

/// Guards W1/W2 process-discovery migration slices.
///
/// `pgrep` remains the low-level subprocess mechanism for now, but production
/// process-discovery consumers should call `SystemStateProvider` so Phase 1 can
/// collapse process, TCP, and later launchd/SMAppService evidence into one
/// executable snapshot.
final class PgrepProcessDiscoveryLintTests: XCTestCase {
    func testServiceLifecycleCoordinatorDelegatesPgrepDiscoveryToSystemStateProvider() throws {
        let coordinator = repositoryRoot()
            .appendingPathComponent("Sources/KeyPathAppKit/Managers/ServiceLifecycleCoordinator.swift")

        let violations = try matchingLines(
            in: coordinator,
            patterns: [
                #"SubprocessRunner\.shared\.pgrep"#,
                #"subprocessRunner\.pgrep"#,
                #"/usr/bin/pgrep"#
            ]
        )

        XCTAssertTrue(
            violations.isEmpty,
            """
            ServiceLifecycleCoordinator must delegate process discovery to \
            SystemStateProvider instead of calling pgrep directly:
            \(violations.sorted().joined(separator: "\n"))
            """
        )
    }

    func testKanataDaemonManagerDelegatesPgrepDiscoveryToSystemStateProvider() throws {
        let manager = repositoryRoot()
            .appendingPathComponent("Sources/KeyPathAppKit/Managers/KanataDaemonManager.swift")

        let violations = try matchingLines(
            in: manager,
            patterns: [
                #"SubprocessRunner\.shared\.pgrep"#,
                #"subprocessRunner\.pgrep"#,
                #"/usr/bin/pgrep"#
            ]
        )

        XCTAssertTrue(
            violations.isEmpty,
            """
            KanataDaemonManager must delegate process discovery to \
            SystemStateProvider instead of calling pgrep directly:
            \(violations.sorted().joined(separator: "\n"))
            """
        )
    }

    func testSystemValidatorDelegatesPgrepDiscoveryToSystemStateProvider() throws {
        let validator = repositoryRoot()
            .appendingPathComponent("Sources/KeyPathAppKit/Services/System/SystemValidator.swift")

        let violations = try matchingLines(
            in: validator,
            patterns: [
                #"SubprocessRunner\.shared\.pgrep"#,
                #"subprocessRunner\.pgrep"#,
                #"/usr/bin/pgrep"#
            ]
        )

        XCTAssertTrue(
            violations.isEmpty,
            """
            SystemValidator must delegate process discovery to \
            SystemStateProvider instead of calling pgrep directly:
            \(violations.sorted().joined(separator: "\n"))
            """
        )
    }

    func testKarabinerConflictServiceDelegatesPgrepDiscoveryToSystemStateProvider() throws {
        let service = repositoryRoot()
            .appendingPathComponent("Sources/KeyPathAppKit/Services/Karabiner/KarabinerConflictService.swift")

        let violations = try matchingLines(
            in: service,
            patterns: [
                #"SubprocessRunner\.shared\.pgrep"#,
                #"subprocessRunner\.pgrep"#,
                #"/usr/bin/pgrep"#
            ]
        )

        XCTAssertTrue(
            violations.isEmpty,
            """
            KarabinerConflictService must delegate process discovery to \
            SystemStateProvider instead of calling pgrep directly:
            \(violations.sorted().joined(separator: "\n"))
            """
        )
    }

    func testVHIDDeviceManagerDelegatesPgrepDiscoveryToSystemStateProvider() throws {
        let manager = repositoryRoot()
            .appendingPathComponent("Sources/KeyPathInstallationWizard/Core/VHIDDeviceManager.swift")

        let violations = try matchingLines(
            in: manager,
            patterns: [
                #"SubprocessRunner\.shared\.pgrep"#,
                #"subprocessRunner\.pgrep"#,
                #"/usr/bin/pgrep"#
            ]
        )

        XCTAssertTrue(
            violations.isEmpty,
            """
            VHIDDeviceManager must delegate process discovery to \
            SystemStateProvider instead of calling pgrep directly:
            \(violations.sorted().joined(separator: "\n"))
            """
        )
    }

    func testDiagnosticsServiceDelegatesPgrepDiscoveryToSystemStateProvider() throws {
        let service = repositoryRoot()
            .appendingPathComponent("Sources/KeyPathAppKit/Services/Monitoring/DiagnosticsService.swift")

        let violations = try matchingLines(
            in: service,
            patterns: [
                #"SubprocessRunner\.shared\.pgrep"#,
                #"subprocessRunner\.pgrep"#,
                #"/usr/bin/pgrep"#
            ]
        )

        XCTAssertTrue(
            violations.isEmpty,
            """
            DiagnosticsService must delegate process discovery to \
            SystemStateProvider instead of calling pgrep directly:
            \(violations.sorted().joined(separator: "\n"))
            """
        )
    }

    func testLauncherServiceDelegatesPgrepDiscoveryToSystemStateProvider() throws {
        let service = repositoryRoot()
            .appendingPathComponent("Sources/KeyPathKanataLauncher/LauncherService.swift")

        let violations = try matchingLines(
            in: service,
            patterns: [
                #"SubprocessRunner\.shared\.pgrep"#,
                #"subprocessRunner\.pgrep"#,
                #"/usr/bin/pgrep"#
            ]
        )

        XCTAssertTrue(
            violations.isEmpty,
            """
            LauncherService must delegate process discovery to \
            SystemStateProvider instead of calling pgrep directly:
            \(violations.sorted().joined(separator: "\n"))
            """
        )
    }

    func testProcessLifecycleManagerDelegatesPgrepDiscoveryToSystemStateProvider() throws {
        let manager = repositoryRoot()
            .appendingPathComponent("Sources/KeyPathDaemonLifecycle/ProcessLifecycleManager.swift")

        let violations = try matchingLines(
            in: manager,
            patterns: [
                #"SubprocessRunner\.shared\.pgrep"#,
                #"SubprocessRunner\.shared\.run\("/usr/bin/pgrep"#,
                #"subprocessRunner\.pgrep"#,
                #"/usr/bin/pgrep"#
            ]
        )

        XCTAssertTrue(
            violations.isEmpty,
            """
            ProcessLifecycleManager must delegate process discovery to \
            SystemStateProvider instead of calling pgrep directly:
            \(violations.sorted().joined(separator: "\n"))
            """
        )
    }
}

private func repositoryRoot(file: StaticString = #filePath) -> URL {
    URL(fileURLWithPath: "\(file)")
        .deletingLastPathComponent() // PgrepProcessDiscoveryLintTests.swift
        .deletingLastPathComponent() // Lint
        .deletingLastPathComponent() // KeyPathTests
        .deletingLastPathComponent() // Tests
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
