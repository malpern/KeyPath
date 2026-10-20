import AppKit
@testable import KeyPathAppKit
import XCTest

@MainActor
final class NonModalAlertPresenterTests: XCTestCase {
    func testAlertShowsWithoutBlockingAndButtonsWork() {
        _ = NSApplication.shared
        let alert = NSAlert()
        alert.messageText = "Test"
        alert.addButton(withTitle: "Copy Error")
        alert.addButton(withTitle: "Dismiss")
        var copied = 0

        NonModalAlertPresenter.present(alert, onFirstButton: { copied += 1 })

        // present() returned: nothing is waiting on a modal session.
        XCTAssertNil(NSApp.modalWindow)
        XCTAssertTrue(alert.window.isVisible)

        alert.buttons[0].performClick(nil)
        XCTAssertEqual(copied, 1)
        XCTAssertFalse(alert.window.isVisible)
    }

    func testSecondButtonOnlyCloses() {
        _ = NSApplication.shared
        let alert = NSAlert()
        alert.addButton(withTitle: "Copy Error")
        alert.addButton(withTitle: "Dismiss")
        var copied = 0
        NonModalAlertPresenter.present(alert, onFirstButton: { copied += 1 })

        alert.buttons[1].performClick(nil)
        XCTAssertEqual(copied, 0)
        XCTAssertFalse(alert.window.isVisible)
    }
}
