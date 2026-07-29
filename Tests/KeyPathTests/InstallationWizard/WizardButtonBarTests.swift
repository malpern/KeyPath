@testable import KeyPathInstallationWizard
import SwiftUI
@preconcurrency import XCTest

final class WizardButtonBarTests: XCTestCase {
    @MainActor
    func testCancelButtonUsesCancelShortcutByDefault() {
        let button = WizardButtonBar.CancelButton(action: {})

        XCTAssertTrue(button.usesCancelShortcut)
    }

    @MainActor
    func testCancelButtonCanOptOutOfKeyboardShortcut() {
        let button = WizardButtonBar.CancelButton(action: {}, usesCancelShortcut: false)

        XCTAssertFalse(button.usesCancelShortcut)
    }

    @MainActor
    func testSecondaryActionCanJoinThePrimaryAction() {
        let bar = WizardButtonBar(
            secondary: .init(title: "Back", action: {}),
            primary: .init(title: "Continue", action: {}),
            secondaryPlacement: .trailing
        )

        XCTAssertEqual(bar.secondaryPlacement, .trailing)
    }

    @MainActor
    func testSecondaryButtonsCanUseACompactWidth() {
        let bar = WizardButtonBar(
            secondary: .init(title: "Back", action: {}),
            primary: .init(title: "Continue", action: {}),
            secondaryMinimumWidth: 72
        )

        XCTAssertEqual(bar.secondaryMinimumWidth, 72)
    }
}
