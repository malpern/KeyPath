import Foundation
@preconcurrency import XCTest

final class MapperViewModelStructureLintTests: XCTestCase {
    func testMapperSelectionLogicLivesInDedicatedExtension() throws {
        let file = LintScanner.path("Sources/KeyPathAppKit/UI/Mapper/MapperViewModel+Selection.swift")
        let contents = try String(contentsOf: file, encoding: .utf8)

        for requiredText in [
            "extension MapperViewModel",
            "func setInputFromKeyClick(",
            "func loadBehaviorFromExistingRule(",
            "func applyPresets(",
            "func applyShiftedOutputPreset(",
        ] {
            XCTAssertTrue(contents.contains(requiredText), "Selection extension missing: \(requiredText)")
        }
    }

    func testMapperBaseFileDoesNotRegainSelectionMethods() throws {
        let file = LintScanner.path("Sources/KeyPathAppKit/UI/Mapper/MapperViewModel.swift")
        let violations = try LintScanner.matchingLines(
            in: file,
            patterns: [
                #"func\s+setInputFromKeyClick\("#,
                #"func\s+loadBehaviorFromExistingRule\("#,
                #"func\s+applyPresets\("#,
                #"func\s+applyShiftedOutputPreset\("#,
            ]
        )

        XCTAssertTrue(
            violations.isEmpty,
            """
            MapperViewModel.swift should keep selection/preset logic in MapperViewModel+Selection.swift:
            \(violations.sorted().joined(separator: "\n"))
            """
        )
    }
}
