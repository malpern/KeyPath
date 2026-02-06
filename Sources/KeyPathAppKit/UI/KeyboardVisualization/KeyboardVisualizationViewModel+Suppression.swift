import Foundation
import KeyPathCore

@MainActor
extension KeyboardVisualizationViewModel {
    // MARK: - Tap-Hold Output Suppression

    /// Fallback static map for common tap-hold patterns (used when TapActivated not available).
    /// Will be phased out once TapActivated is fully deployed.
    static let fallbackTapHoldOutputMap: [UInt16: Set<UInt16>] = [
        57: [53] // capslock -> esc (common tap-hold: caps = tap:esc, hold:hyper)
    ]

    /// All output keyCodes that should be suppressed (computed from active sources)
    var suppressedOutputKeyCodes: Set<UInt16> {
        activeTapHoldSources.reduce(into: Set<UInt16>()) { result, source in
            // Try dynamic map first (from TapActivated events)
            if let outputs = dynamicTapHoldOutputMap[source] {
                result.formUnion(outputs)
            }
            // Fall back to static map
            if let outputs = Self.fallbackTapHoldOutputMap[source] {
                result.formUnion(outputs)
            }
        }
    }

    // MARK: - Remap Output Suppression

    /// Output keyCodes to suppress from currently-pressed remapped keys.
    /// When A->B is mapped and A is pressed, B should not light up separately.
    var suppressedRemapOutputKeyCodes: Set<UInt16> {
        activeRemapSourceKeyCodes.reduce(into: Set<UInt16>()) { result, inputKeyCode in
            if let outputKeyCode = remapOutputMap[inputKeyCode] {
                result.insert(outputKeyCode)
            }
        }
    }

    /// Remap sources that should participate in suppression (pressed + recent releases).
    var activeRemapSourceKeyCodes: Set<UInt16> {
        pressedKeyCodes.union(recentRemapSourceKeyCodes)
    }

    func shouldSuppressKeyHighlight(_ keyCode: UInt16, source: String = "unknown") -> Bool {
        let tapHoldSuppressed = suppressedOutputKeyCodes.contains(keyCode)
        let remapSuppressed = suppressedRemapOutputKeyCodes.contains(keyCode)
        let recentTapSuppressed = recentTapOutputs.contains(keyCode)
        let shouldSuppress = tapHoldSuppressed || remapSuppressed || recentTapSuppressed

        if FeatureFlags.keyboardSuppressionDebugEnabled, shouldSuppress {
            AppLogger.shared.debug(
                """
                🧯 [KeyboardViz] Suppressed keyCode=\(keyCode) source=\(source) \
                tapHold=\(tapHoldSuppressed) remap=\(remapSuppressed) \
                recentTap=\(recentTapSuppressed) remapSources=\(activeRemapSourceKeyCodes)
                """
            )
        }

        return shouldSuppress
    }
}
