import Foundation
@preconcurrency import XCTest

/// Keeps the experimental report capture ahead of the cleanup that removes it.
final class SessionTerminalDiagnosticPlacementTests: XCTestCase {
    func testTerminalLogUsesTheSingleFailureReadBeforeUnconditionalCleanup() throws {
        let source = try String(
            contentsOf: LintScanner.path("Sources/KeyPathAppKit/Managers/ServiceLifecycleCoordinator+SessionRuntime.swift"),
            encoding: .utf8
        )
        let start = try XCTUnwrap(source.range(of: "let terminalReport = sessionReportURL.flatMap(Self.readSessionReport)"))
        let tail = String(source[start.lowerBound...])
        let failure = try XCTUnwrap(tail.range(of: "let failure = terminalReport?.failure"))
        let readSection = String(tail[..<failure.lowerBound])
        let gate = try XCTUnwrap(tail.range(of: "#if KEYPATH_TAP_TIMEOUT_EXPERIMENT"))
        let logger = try XCTUnwrap(tail.range(of: "AppLogger.shared.error(\"SESSION_TERMINAL_STARTUP "))
        let gateEnd = try XCTUnwrap(tail.range(of: "#endif"))
        let cleanup = try XCTUnwrap(tail.range(of: "_ = await stopSessionRuntime()"))
        let diagnosticSection = String(tail[failure.upperBound ..< cleanup.lowerBound])
        let cleanupSection = String(tail[cleanup.lowerBound...])
        let loggerSection = String(tail[logger.lowerBound ..< cleanup.lowerBound])

        XCTAssertLessThan(failure.lowerBound, logger.lowerBound)
        XCTAssertLessThan(gate.lowerBound, logger.lowerBound)
        XCTAssertLessThan(logger.lowerBound, gateEnd.lowerBound)
        XCTAssertLessThan(gateEnd.lowerBound, cleanup.lowerBound)
        XCTAssertLessThan(logger.lowerBound, cleanup.lowerBound)
        XCTAssertEqual(readSection.components(separatedBy: "readSessionReport").count - 1, 1)
        XCTAssertEqual(tail.components(separatedBy: "SESSION_TERMINAL_STARTUP ").count - 1, 1)
        XCTAssertTrue(diagnosticSection.contains("#if KEYPATH_TAP_TIMEOUT_EXPERIMENT"))
        XCTAssertTrue(loggerSection.contains("#endif"))
        XCTAssertTrue(diagnosticSection.contains("sessionStartIsCurrent(generation)"))
        XCTAssertTrue(diagnosticSection.contains("sessionApplication === application"))
        XCTAssertTrue(diagnosticSection.contains("sessionReportURL == url"))
        XCTAssertTrue(diagnosticSection.contains("sessionNonce == nonce"))
        XCTAssertTrue(cleanupSection.contains("if sessionStartIsCurrent(generation) { onError?"))
        XCTAssertTrue(tail.contains("failure ?? \"no current tap and TCP evidence\""))
    }
}
