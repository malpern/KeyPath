// Lightweight observer over the user's keystream while kindaVim is in
// a vim-y mode. Maintains a tiny state machine — `currentOperator`
// (the operator key that put us into op-pending), `countBuffer` (digit
// prefix the user is building) — that the HUD and the overlay use to
// sharpen their feedback.
//
// Architecture invariant: `KindaVimStateAdapter.state.mode` is the
// authoritative signal for which mode we're in. This observer's
// derived state is informational sub-state. Every mode transition
// **hard-resets** the observer, so any desync (kindaVim cancels a
// sequence via Esc, an unsupported motion, or a timeout) is bounded
// to the next mode change.

import AppKit
import KeyPathCore
import Observation

@MainActor
@Observable
final class VimSequenceObserver {
    static let shared = VimSequenceObserver()

    /// The operator key the user pressed to enter operator-pending mode
    /// (`d`, `c`, `y`). Nil unless adapter mode is `.operatorPending`.
    private(set) var currentOperator: String?

    /// Numeric prefix being typed before a motion (`5j`, `3dw`). Empty
    /// when no count is in flight or when adapter mode isn't a vim mode.
    /// Stored as the raw digit string so the UI can render `5×` directly.
    private(set) var countBuffer: String = ""

    @ObservationIgnored
    private let modeProvider: @MainActor () -> KindaVimStateAdapter.Mode

    @ObservationIgnored
    private var monitoringCount = 0

    @ObservationIgnored
    private var globalMonitor: Any?

    @ObservationIgnored
    private var lastObservedMode: KindaVimStateAdapter.Mode = .unknown

    /// Production callers use the no-arg init which reads from the
    /// shared `KindaVimStateAdapter`. Tests inject a `modeProvider`
    /// closure so they can drive mode transitions deterministically
    /// without touching the file watcher.
    init(modeProvider: @MainActor @escaping () -> KindaVimStateAdapter.Mode = {
        KindaVimStateAdapter.shared.state.mode
    }) {
        self.modeProvider = modeProvider
    }

    /// Refcounted start. Idempotent across multiple callers.
    func startMonitoring() {
        monitoringCount += 1
        guard monitoringCount == 1 else { return }
        AppLogger.shared.log("👀 [VimSeq] Starting observer")

        lastObservedMode = modeProvider()

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                self?.handleKeyDown(event)
            }
        }

        // Mirror the mode signal as a dependency: `KindaVimStateAdapter`
        // is `@Observable`, but we also need a side-effect on every flip
        // (hard-reset). Polling on each keystroke is simpler than wiring
        // up a Combine subscription, so we just check before each event.
    }

    func stopMonitoring() {
        guard monitoringCount > 0 else { return }
        monitoringCount -= 1
        guard monitoringCount == 0 else { return }
        AppLogger.shared.log("🛑 [VimSeq] Stopping observer")

        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
        }
        globalMonitor = nil

        currentOperator = nil
        countBuffer = ""
        lastObservedMode = .unknown
    }

    // MARK: - Event handling

    /// Test seam — synthetic event injection so unit tests don't need to
    /// drive real `NSEvent`. Production path goes through `handleKeyDown`.
    func ingest(character: String) {
        ingestCore(character: character)
    }

    private func handleKeyDown(_ event: NSEvent) {
        guard let chars = event.charactersIgnoringModifiers, !chars.isEmpty else { return }
        ingestCore(character: chars)
    }

    private func ingestCore(character: String) {
        // Hard-reset on every adapter mode transition — see file header.
        let currentMode = modeProvider()
        if currentMode != lastObservedMode {
            currentOperator = nil
            countBuffer = ""
            lastObservedMode = currentMode
        }

        // Only track sub-state while in a vim-y mode.
        switch currentMode {
        case .normal, .visual:
            applyNormalOrVisual(character: character)
        case .operatorPending:
            applyOperatorPending(character: character)
        case .insert, .unknown:
            // No bookkeeping — user is typing or kindaVim isn't reporting.
            currentOperator = nil
            countBuffer = ""
        }
    }

    private func applyNormalOrVisual(character: String) {
        // Digit accumulating into a count prefix (`5`, `12`, `100`).
        if Self.isDigit(character) {
            // Avoid leading zero: `0` alone is "line start", not a count.
            if countBuffer.isEmpty, character == "0" { return }
            countBuffer.append(character)
            return
        }

        // An operator key starts an op-pending sequence (the actual mode
        // flip will follow from kindaVim's environment.json signal).
        if Self.isOperator(character) {
            currentOperator = character
            return
        }

        // Anything else (motion, edit, escape, ...) consumes the count
        // prefix and clears it.
        countBuffer = ""
        currentOperator = nil
    }

    private func applyOperatorPending(character: String) {
        // Inside op-pending the user picks a motion or text-object; once
        // they do, kindaVim flips back to normal/visual and our hard-reset
        // path clears state. We don't try to model individual motions;
        // currentOperator is the only useful sub-state here.
        if Self.isDigit(character) {
            // Some operators allow counts before the motion: `d3w`.
            countBuffer.append(character)
        }
    }

    // MARK: - Helpers

    private static func isDigit(_ s: String) -> Bool {
        s.count == 1 && s.allSatisfy(\.isNumber)
    }

    private static let operatorChars: Set<String> = ["d", "c", "y"]

    private static func isOperator(_ s: String) -> Bool {
        operatorChars.contains(s.lowercased())
    }
}
