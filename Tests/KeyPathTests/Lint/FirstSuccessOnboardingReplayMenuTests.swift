import Foundation
import XCTest

final class FirstSuccessOnboardingReplayMenuTests: XCTestCase {
    func testHelpMenuReplaysTourDirectlyWithoutInstallerOrDefaults() throws {
        let source = try String(
            contentsOf: onboardingReplayRepositoryRoot()
                .appendingPathComponent("Sources/KeyPathAppKit/Core/AppMenuCommands.swift"),
            encoding: .utf8
        )

        let helpMenu = try XCTUnwrap(source.range(of: "CommandGroup(replacing: .help)"))
        let privateHelpers = try XCTUnwrap(
            source.range(
                of: "// MARK: - Private Helpers",
                range: helpMenu.upperBound ..< source.endIndex
            )
        )
        let helpMenuSource = source[helpMenu.lowerBound ..< privateHelpers.lowerBound]

        XCTAssertTrue(helpMenuSource.contains("Replay KeyPath Tour…"))
        XCTAssertTrue(helpMenuSource.contains("replayFirstSuccessTour()"))
        XCTAssertTrue(helpMenuSource.contains("menu-replay-keypath-tour"))

        let replayMethod = try XCTUnwrap(
            source.range(of: "private func replayFirstSuccessTour()")
        )
        let nextMethod = try XCTUnwrap(
            source.range(
                of: "private func installCommandLineTool()",
                range: replayMethod.upperBound ..< source.endIndex
            )
        )
        let replaySource = source[replayMethod.lowerBound ..< nextMethod.lowerBound]

        XCTAssertTrue(
            replaySource.contains(
                "source: .replay"
            )
        )
        for forbiddenDependency in [
            "FirstSuccessOnboardingGate",
            "NotificationCenter",
            "UserDefaults",
            "WizardWindowController",
            ".showWizard",
        ] {
            XCTAssertFalse(
                replaySource.contains(forbiddenDependency),
                "Tour replay must not route through \(forbiddenDependency)."
            )
        }
    }
}

private func onboardingReplayRepositoryRoot(file: StaticString = #filePath) -> URL {
    URL(fileURLWithPath: file.description)
        .deletingLastPathComponent() // Lint
        .deletingLastPathComponent() // KeyPathTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repository root
}
