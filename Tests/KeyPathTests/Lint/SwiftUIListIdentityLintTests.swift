import Foundation
@preconcurrency import XCTest

/// Guards SwiftUI list identities in editable/searchable collections.
///
/// These call sites used collection indices or enumerated offsets as row
/// identity even though rows can be searched, inserted, or removed. That makes
/// SwiftUI reuse the same identity for a different element after mutation,
/// risking focus/state loss and incorrect row animation.
final class SwiftUIListIdentityLintTests: XCTestCase {
    func testQMKSearchRowsUseKeyboardIdentity() throws {
        let file = LintScanner.path("Sources/KeyPathAppKit/UI/Overlay/QMKKeyboardSearchView.swift")
        let violations = try LintScanner.matchingLines(
            in: file,
            patterns: [#"ForEach\(keyboards\.indices,\s*id:\s*\\\.self\)"#]
        )

        XCTAssertTrue(
            violations.isEmpty,
            """
            QMK search rows must use `KeyboardMetadata.id`, not collection indices:
            \(violations.sorted().joined(separator: "\n"))
            """
        )
    }

    func testSequenceKeySlotsUseStableSessionIdentity() throws {
        let file = LintScanner.path("Sources/KeyPathAppKit/UI/Rules/SequencesModalView.swift")
        let violations = try LintScanner.matchingLines(
            in: file,
            patterns: [#"ForEach\(sequence\.keys\.wrappedValue\.indices,\s*id:\s*\\\.self\)"#]
        )

        XCTAssertTrue(
            violations.isEmpty,
            """
            Editable sequence key slots must use stable session IDs, not array indices:
            \(violations.sorted().joined(separator: "\n"))
            """
        )
    }

    func testChordEditorKeyChipsUseStableSessionIdentity() throws {
        let file = LintScanner.path("Sources/KeyPathAppKit/UI/Rules/ChordEditorDialog.swift")
        let violations = try LintScanner.matchingLines(
            in: file,
            patterns: [#"ForEach\(Array\(keys\.enumerated\(\)\),\s*id:\s*\\\.offset\)"#]
        )

        XCTAssertTrue(
            violations.isEmpty,
            """
            Editable chord key chips must use stable session IDs, not enumerated offsets:
            \(violations.sorted().joined(separator: "\n"))
            """
        )
    }
}
