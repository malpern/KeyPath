import Foundation
@preconcurrency import XCTest

final class OverlayMapperLifecycleLintTests: XCTestCase {
    func testOverlayMapperLifecycleLivesInDedicatedExtension() throws {
        let lifecycleFile = LintScanner.path("Sources/KeyPathAppKit/UI/Overlay/OverlayMapperSection+Lifecycle.swift")
        let contents = try String(contentsOf: lifecycleFile, encoding: .utf8)

        XCTAssertTrue(
            contents.contains("extension OverlayMapperSection"),
            "Overlay mapper lifecycle wiring should live in the dedicated lifecycle extension."
        )
        XCTAssertTrue(
            contents.contains("var bodyView: some View"),
            "Overlay mapper body/lifecycle composition should stay outside the large rendering file."
        )
        XCTAssertTrue(
            contents.contains("handleDrawerKeySelection"),
            "Drawer notification handling should remain extracted from the visual layout file."
        )
    }

    func testOverlayMapperRenderingFileDoesNotRegainLifecycleWiring() throws {
        let file = LintScanner.path("Sources/KeyPathAppKit/UI/Overlay/OverlayMapperSection.swift")
        let violations = try LintScanner.matchingLines(
            in: file,
            patterns: [
                #"NotificationCenter\.default\.publisher"#,
                #"onChange\(of:\s*viewModel\.isRecording"#,
                #""Clear Mapping""#,
            ]
        )

        XCTAssertTrue(
            violations.isEmpty,
            """
            OverlayMapperSection.swift should stay focused on rendering; lifecycle/event wiring belongs in OverlayMapperSection+Lifecycle.swift:
            \(violations.sorted().joined(separator: "\n"))
            """
        )
    }
}
