import Foundation
@preconcurrency import XCTest

/// Validates that wizard page polling implementations never auto-navigate.
///
/// Polling should only update UI state (via onRefresh() or local state changes).
/// Navigation must be user-initiated (button clicks only).
///
/// This test catches regressions where someone accidentally adds navigation
/// calls to polling callbacks.
final class WizardPollingNoNavigationTests: XCTestCase {
    func testPollingMethodsDoNotCallNavigate() throws {
        let root = repositoryRoot()
        let pagesDir = root.appendingPathComponent("Sources/KeyPathAppKit/InstallationWizard/UI/Pages")

        let fm = FileManager.default
        let files = try fm.contentsOfDirectory(at: pagesDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }

        var violations: [String] = []

        for file in files {
            let content = try String(contentsOf: file, encoding: .utf8)
            let fileName = file.lastPathComponent

            // Find polling-related method bodies
            let pollingPatterns = [
                "checkApprovalStatus",
                "checkPermissionStatus",
                "permissionPollingTask",
                "detectionTimer",
                "approvalPollingTimer",
                "Timer.scheduledTimer"
            ]

            // Check if file has polling
            let hasPolling = pollingPatterns.contains { content.contains($0) }
            guard hasPolling else { continue }

            // Extract lines that are inside polling callbacks
            // Look for navigation calls that shouldn't be in polling
            let navigationCalls = [
                "navigateToNextStep()",
                "navigateToPage(",
                "navigationCoordinator.navigateToPage"
            ]

            // Simple heuristic: if file has polling AND navigation inside a polling method, flag it
            // We look for navigation calls inside Timer callbacks or polling task closures
            let lines = content.components(separatedBy: .newlines)

            var inPollingBlock = false
            var braceDepth = 0

            for (lineNum, line) in lines.enumerated() {
                // Detect start of polling block
                if pollingPatterns.contains(where: { line.contains($0) }),
                   line.contains("{") || line.contains("Task {") {
                    inPollingBlock = true
                    braceDepth = 0
                }

                if inPollingBlock {
                    braceDepth += line.filter { $0 == "{" }.count
                    braceDepth -= line.filter { $0 == "}" }.count

                    // Check for navigation calls inside polling block
                    for navCall in navigationCalls {
                        if line.contains(navCall) {
                            violations.append(
                                "\(fileName):\(lineNum + 1): Navigation call '\(navCall)' found inside polling block"
                            )
                        }
                    }

                    if braceDepth <= 0 {
                        inPollingBlock = false
                    }
                }
            }
        }

        XCTAssert(
            violations.isEmpty,
            """
            Polling methods must NOT auto-navigate!

            Polling should only update UI state (via onRefresh() or local @State).
            Navigation must be user-initiated via button clicks.

            Violations found:
            \(violations.joined(separator: "\n"))

            Fix: Remove navigation calls from polling callbacks.
            """
        )
    }
}

// MARK: - Helpers

private func repositoryRoot(file: StaticString = #filePath) -> URL {
    // …/KeyPath/Tests/KeyPathTests/Lint/WizardPollingNoNavigationTests.swift -> go up 4 levels
    URL(fileURLWithPath: file.description)
        .deletingLastPathComponent() // Lint
        .deletingLastPathComponent() // KeyPathTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repo root
}
