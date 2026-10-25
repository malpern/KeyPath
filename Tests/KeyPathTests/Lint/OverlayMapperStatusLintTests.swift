import Foundation
@preconcurrency import XCTest

/// The overlay Mapper autosaves and has no Save button. A status the view model
/// sets but no overlay view reads is a declined save nobody can see — which is
/// how a media-key mapping "vanished" on 2026-10-20. Keep the wiring explicit.
final class OverlayMapperStatusLintTests: XCTestCase {
    func testOverlayMapperRendersTheViewModelStatus() throws {
        let section = try String(contentsOf: LintScanner.path("Sources/KeyPathAppKit/UI/Overlay/OverlayMapperSection.swift"), encoding: .utf8)
        XCTAssertTrue(
            section.contains("MapperStatusLine(message: viewModel.statusMessage, isError: viewModel.statusIsError)"),
            "OverlayMapperSection must render MapperStatusLine from viewModel.statusMessage; the overlay has no Save button, so an unrendered status is an invisible refusal."
        )
        let line = try String(contentsOf: LintScanner.path("Sources/KeyPathAppKit/UI/Overlay/MapperStatusLine.swift"), encoding: .utf8)
        XCTAssertTrue(line.contains("Text(message)") && line.contains("\"overlay-mapper-status\""),
                      "MapperStatusLine must show the message as text under the overlay-mapper-status identifier.")
    }

    func testMapperSaveNeverReturnsSilently() throws {
        // Every early `return` in save() must be preceded by a status and a log line.
        let file = LintScanner.path("Sources/KeyPathAppKit/UI/Mapper/MapperViewModel+RuleManagement.swift")
        let contents = try String(contentsOf: file, encoding: .utf8)
        let saveBody = contents.components(separatedBy: "func save(kanataManager:")[1]
            .components(separatedBy: "\n    func ")[0]
        var silent: [Int] = []
        let lines = saveBody.components(separatedBy: "\n")
        for (index, text) in lines.enumerated() where text.trimmingCharacters(in: .whitespaces) == "return" {
            let window = lines[max(0, index - 6) ..< index].joined(separator: "\n")
            if !(window.contains("statusMessage =") && window.contains("AppLogger.shared.")) { silent.append(index) }
        }
        XCTAssertTrue(silent.isEmpty, "save() returns without a status and a log line at save-body lines \(silent)")
    }
}
