import AppKit
import Carbon
import Combine
import Foundation
import KeyPathCore
import SwiftUI

extension KeyboardVisualizationViewModel {
    // MARK: - Private Event Handling

    func startIdleMonitor() {
        idleMonitorTask?.cancel()
        lastInteraction = Date()

        idleMonitorTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(idlePollInterval))

                // Check TCP connection state (detects disconnection via timeout)
                checkTcpConnectionState()

                // Don't fade while holding a momentary layer key (non-base layer active)
                let isOnMomentaryLayer = currentLayerName.lowercased() != "base"
                if isOnMomentaryLayer {
                    // Keep overlay fully visible while on a non-base layer
                    if fadeAmount != 0 { fadeAmount = 0 }
                    if deepFadeAmount != 0 { deepFadeAmount = 0 }
                    continue
                }

                let elapsed = Date().timeIntervalSince(lastInteraction)

                // Stage 1: outline fade begins after idleTimeout, completes over 5s
                // Use pow(x, 0.7) easing so changes are faster initially and gentler at the end,
                // avoiding the perceptual "cliff" when linear formulas hit their endpoints together.
                let linearProgress = max(0, min(1, (elapsed - idleTimeout) / 5))
                let fadeProgress = pow(linearProgress, 0.7)
                if fadeProgress != fadeAmount {
                    fadeAmount = fadeProgress
                }

                // Stage 2: deep fade to 5% after deepFadeTimeout over deepFadeRamp seconds
                let deepProgress = max(0, min(1, (elapsed - deepFadeTimeout) / deepFadeRamp))
                if deepProgress != deepFadeAmount {
                    deepFadeAmount = deepProgress
                }
            }
        }
    }

    /// Reset idle timer and un-fade if necessary.
    func noteInteraction() {
        lastInteraction = Date()
        if fadeAmount != 0 { fadeAmount = 0 }
        if deepFadeAmount != 0 { deepFadeAmount = 0 }
    }

    /// Track that we received a TCP event (for connection state indicator)
    func noteTcpEventReceived() {
        lastTcpEventTime = Date()
        if !isKanataConnected {
            isKanataConnected = true
            AppLogger.shared.log("🌐 [KeyboardViz] Kanata TCP connected (received event)")
        }
    }

    /// Check TCP connection timeout (called from idle monitor)
    func checkTcpConnectionState() {
        guard let lastEvent = lastTcpEventTime else {
            // No events ever received - not connected
            if isKanataConnected {
                isKanataConnected = false
                AppLogger.shared.log("🌐 [KeyboardViz] Kanata TCP disconnected (no events)")
            }
            return
        }

        let elapsed = Date().timeIntervalSince(lastEvent)
        if elapsed > tcpConnectionTimeout, isKanataConnected {
            isKanataConnected = false
            AppLogger.shared.log("🌐 [KeyboardViz] Kanata TCP disconnected (timeout after \(String(format: "%.1f", elapsed))s)")
        }
    }

}
