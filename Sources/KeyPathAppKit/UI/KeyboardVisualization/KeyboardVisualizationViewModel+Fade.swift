import Foundation
import KeyPathCore
import SwiftUI

@MainActor
extension KeyboardVisualizationViewModel {
    // MARK: - Timing Tunables

    enum OverlayTiming {
        /// Grace period to wait for a quick re-press before clearing hold state (seconds).
        /// Trade-off: higher = less flicker, lower = less linger.
        static var holdReleaseGrace: TimeInterval { 0 }

        /// Duration of fade-out animation when key is released (seconds).
        static var keyReleaseFadeDuration: TimeInterval { 0 }
    }

    /// Start fade-out animation for a released key
    func startKeyFadeOut(_ keyCode: UInt16) {
        // Cancel any existing fade-out for this key
        fadeOutTasks[keyCode]?.cancel()

        // Animate fade from 0 (visible) to 1 (faded) over the duration
        let duration = OverlayTiming.keyReleaseFadeDuration
        let steps = 20 // 20 steps for smooth animation
        let stepDuration = duration / Double(steps)

        let task = Task { @MainActor in
            for step in 1 ... steps {
                guard !Task.isCancelled else {
                    keyFadeAmounts.removeValue(forKey: keyCode)
                    return
                }

                let progress = CGFloat(step) / CGFloat(steps)
                keyFadeAmounts[keyCode] = progress

                try? await Task.sleep(for: .milliseconds(Int(stepDuration * 1000)))
            }

            // Fade complete - clean up
            keyFadeAmounts.removeValue(forKey: keyCode)
            fadeOutTasks.removeValue(forKey: keyCode)
            holdReleaseFadeKeyCodes.remove(keyCode)
        }

        fadeOutTasks[keyCode] = task
    }

    /// Cancel fade-out for a key that was re-pressed
    func cancelKeyFadeOut(_ keyCode: UInt16) {
        fadeOutTasks[keyCode]?.cancel()
        fadeOutTasks.removeValue(forKey: keyCode)
        keyFadeAmounts.removeValue(forKey: keyCode)
        holdReleaseFadeKeyCodes.remove(keyCode)
    }
}
