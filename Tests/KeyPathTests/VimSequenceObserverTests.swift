@testable import KeyPathAppKit
import XCTest

/// State-machine tests for `VimSequenceObserver`. We don't drive real
/// `NSEvent` here — production reads the keystream from a global
/// monitor, but the observer exposes `ingest(character:)` as a test
/// seam and accepts a `modeProvider` closure so we can flip vim modes
/// deterministically without touching the kindaVim file watcher.
@MainActor
final class VimSequenceObserverTests: XCTestCase {
    private var mode: KindaVimStateAdapter.Mode = .unknown

    private func makeObserver() -> VimSequenceObserver {
        VimSequenceObserver(modeProvider: { [weak self] in
            self?.mode ?? .unknown
        })
    }

    // MARK: - Operator capture

    func testTypingDInNormalSetsCurrentOperator() {
        let observer = makeObserver()
        mode = .normal
        observer.ingest(character: "d")
        XCTAssertEqual(observer.currentOperator, "d")
    }

    func testNonOperatorClearsAnyPendingOperator() {
        let observer = makeObserver()
        mode = .normal
        observer.ingest(character: "d")
        // User immediately presses `j` — that's a motion, not an operator.
        // (In practice kindaVim would flip to op-pending after `d` and the
        // hard-reset path would clear state anyway. This covers the
        // single-mode happy path.)
        observer.ingest(character: "j")
        XCTAssertNil(observer.currentOperator)
    }

    // MARK: - Count buffer

    func testDigitsAccumulateInCountBuffer() {
        let observer = makeObserver()
        mode = .normal
        observer.ingest(character: "5")
        XCTAssertEqual(observer.countBuffer, "5")
        observer.ingest(character: "0")  // not a leading zero — ok mid-buffer
        XCTAssertEqual(observer.countBuffer, "50")
    }

    func testLeadingZeroIsIgnoredAsCount() {
        // `0` alone in vim is "go to line start", not a count prefix.
        let observer = makeObserver()
        mode = .normal
        observer.ingest(character: "0")
        XCTAssertEqual(observer.countBuffer, "")
    }

    func testMotionAfterCountClearsBuffer() {
        let observer = makeObserver()
        mode = .normal
        observer.ingest(character: "5")
        XCTAssertEqual(observer.countBuffer, "5")
        observer.ingest(character: "j")  // motion consumes the count
        XCTAssertEqual(observer.countBuffer, "")
    }

    // MARK: - Hard reset on mode transition

    func testModeTransitionClearsAllState() {
        let observer = makeObserver()
        mode = .normal
        observer.ingest(character: "5")
        observer.ingest(character: "d")
        XCTAssertEqual(observer.countBuffer, "5")
        XCTAssertEqual(observer.currentOperator, "d")

        // kindaVim flips to insert (e.g. user pressed Esc, then `i`).
        mode = .insert
        observer.ingest(character: "x")  // insert mode keystroke
        XCTAssertNil(observer.currentOperator)
        XCTAssertEqual(observer.countBuffer, "")
    }

    func testInsertModeIgnoresTrackedKeys() {
        let observer = makeObserver()
        mode = .insert
        observer.ingest(character: "d")
        observer.ingest(character: "5")
        XCTAssertNil(observer.currentOperator, "operators are not tracked in insert mode")
        XCTAssertEqual(observer.countBuffer, "", "counts are not tracked in insert mode")
    }

    func testUnknownModeIgnoresTrackedKeys() {
        // kindaVim hasn't published a mode yet (`.unknown`) — observer
        // should be inert, not eagerly populate state.
        let observer = makeObserver()
        mode = .unknown
        observer.ingest(character: "d")
        XCTAssertNil(observer.currentOperator)
    }

    // MARK: - Operator-pending sub-state

    func testCountInOpPendingAccumulates() {
        // After `d`, kindaVim flips to operator-pending. The user can
        // type `3w` for "delete 3 words". The count prefix in op-pending
        // should accumulate into the buffer for display.
        let observer = makeObserver()
        mode = .normal
        observer.ingest(character: "d")
        XCTAssertEqual(observer.currentOperator, "d")

        mode = .operatorPending
        observer.ingest(character: "3")
        XCTAssertEqual(observer.countBuffer, "3")
    }

    // MARK: - Visual mode tracks like normal

    func testVisualModeTracksOperatorsAndCounts() {
        let observer = makeObserver()
        mode = .visual
        observer.ingest(character: "5")
        observer.ingest(character: "y")
        XCTAssertEqual(observer.countBuffer, "5")
        XCTAssertEqual(observer.currentOperator, "y")
    }
}
