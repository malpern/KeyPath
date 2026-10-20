import Foundation
@preconcurrency import XCTest

/// Validates that polling cannot navigate except after verified permission approval.
///
/// Polling should only update UI state (via onRefresh() or local state changes).
/// Permission pages may advance once after a fresh, ready snapshot.
///
/// This test catches regressions where someone accidentally adds navigation
/// calls to polling callbacks.
final class WizardPollingNoNavigationTests: XCTestCase {
    func testPollingMethodsDoNotCallNavigate() throws {
        let root = repositoryRoot()
        let pagesDir = root.appendingPathComponent("Sources/KeyPathInstallationWizard/UI/Pages")

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
            var pollingBody = ""

            for (lineNum, line) in lines.enumerated() {
                // Detect start of polling block
                if pollingPatterns.contains(where: { line.contains($0) }),
                   line.contains("{") || line.contains("Task {")
                {
                    inPollingBlock = true
                    braceDepth = 0
                    pollingBody = ""
                }

                if inPollingBlock {
                    pollingBody += line + "\n"
                    braceDepth += line.filter { $0 == "{" }.count
                    braceDepth -= line.filter { $0 == "}" }.count

                    // Check for navigation calls inside polling block
                    for navCall in navigationCalls {
                        if line.contains(navCall) {
                            // Clean installation intentionally advances after the user
                            // grants permission in System Settings. Keep this exception
                            // bound to the ready, one-shot, cancellation-checked branch.
                            let readyGuard: String? = switch fileName {
                            case "WizardAccessibilityPage.swift": "if accessibilityReady, !hasEverCelebrated {"
                            case "WizardInputMonitoringPage.swift": "if inputReady, !hasEverCelebrated {"
                            default: nil
                            }
                            if navCall == "navigateToNextStep()", let readyGuard,
                               pollingBody.contains(readyGuard),
                               pollingBody.contains("hasEverCelebrated = true"),
                               pollingBody.contains("await SystemStateProvider.shared.refreshPermissionSnapshot()"),
                               pollingBody.contains("await onRefresh()"),
                               pollingBody.contains("guard !Task.isCancelled else { return }")
                            {
                                continue
                            }
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
            Polling navigation must be user-initiated or follow verified permission approval.

            Polling should only update UI state (via onRefresh() or local @State).
            Only the guarded, one-shot permission-approval branches may advance automatically.

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
