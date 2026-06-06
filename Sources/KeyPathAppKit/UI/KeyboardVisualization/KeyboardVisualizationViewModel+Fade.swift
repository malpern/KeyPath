import Foundation
import KeyPathCore
import SwiftUI

@MainActor
extension KeyboardVisualizationViewModel {
    // MARK: - Timing Tunables

    enum OverlayTiming {
        /// Grace period to wait for a quick re-press before clearing hold state (seconds).
        /// Trade-off: higher = less flicker, lower = less linger.
        static var holdReleaseGrace: TimeInterval {
            0
        }
    }
}
