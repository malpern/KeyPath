import AppKit
import KeyPathCore
import SwiftUI

/// Proof-of-concept entry point for testing drag-to-authorize.
/// Call from a debug button to validate the mechanism works.
///
/// SUCCESS CRITERIA: Dragging the icon from the floating panel into the
/// System Settings privacy list actually adds kanata-launcher to the list.
@MainActor
public enum DragToAuthorizeProofOfConcept {
    /// Launch the test for accessibility permissions.
    public static func testAccessibility() {
        DragToAuthorizeController.shared.present(for: .accessibility)
    }

    /// Launch the test for input monitoring permissions.
    public static func testInputMonitoring() {
        DragToAuthorizeController.shared.present(for: .inputMonitoring)
    }

    /// Dismiss the overlay.
    public static func dismiss() {
        DragToAuthorizeController.shared.dismiss()
    }
}
