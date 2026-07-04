import AppKit
import KeyPathCore
import SwiftUI

/// Observable state model driving the overlay's SwiftUI animations.
/// Separate from the controller to keep animation concerns isolated.
@MainActor
@Observable
final class DragToAuthorizeStateModel {
    let target: DragToAuthorizeController.PermissionTarget
    let subject: DragToAuthorizeController.PermissionSubject
    private weak var controller: DragToAuthorizeController?

    // Animation-driving state
    var overlayState: DragToAuthorizeController.OverlayState = .presenting
    var arrowPulsing = false
    var dragLifted = false
    var showSuccess = false
    var showRetryShake = false
    var retryShakeOffset: CGFloat = 0
    var dismissOpacity: Double = 1.0
    var dismissOffset: CGFloat = 0

    /// Icon for the subject being dragged (KeyPath.app or kanata-launcher).
    var subjectIcon: NSImage {
        let icon = NSWorkspace.shared.icon(forFile: subject.fileURL.path)
        icon.size = NSSize(width: 32, height: 32)
        return icon
    }

    init(
        target: DragToAuthorizeController.PermissionTarget,
        subject: DragToAuthorizeController.PermissionSubject,
        controller: DragToAuthorizeController
    ) {
        self.target = target
        self.subject = subject
        self.controller = controller
    }

    func transitionTo(_ newState: DragToAuthorizeController.OverlayState) {
        overlayState = newState

        switch newState {
        case .visible:
            arrowPulsing = true
            dragLifted = false
            showSuccess = false
            showRetryShake = false

        case .dragging:
            arrowPulsing = false
            dragLifted = true

        case .success:
            arrowPulsing = false
            dragLifted = false
            showSuccess = true

        case .retrying:
            dragLifted = false
            showRetryShake = true
            triggerShakeAnimation()

        case .dismissing:
            arrowPulsing = false
            withAnimation(.easeIn(duration: 0.25)) {
                self.dismissOpacity = 0
                self.dismissOffset = 20
            }

        default:
            break
        }
    }

    private func triggerShakeAnimation() {
        let keyframes: [(CGFloat, Double)] = [
            (-8, 0.06), (8, 0.06), (-4, 0.06), (4, 0.06), (0, 0.06)
        ]

        var delay: Double = 0
        for (offset, duration) in keyframes {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                withAnimation(.linear(duration: duration)) {
                    self?.retryShakeOffset = offset
                }
            }
            delay += duration
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.5) { [weak self] in
            self?.showRetryShake = false
            self?.retryShakeOffset = 0
        }
    }
}
