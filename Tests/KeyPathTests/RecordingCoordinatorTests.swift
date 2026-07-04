@testable import KeyPathAppKit
import KeyPathPermissions
@preconcurrency import XCTest

@MainActor
final class RecordingCoordinatorTests: KeyPathTestCase {
    func testInputRecordingFailsWhenAccessibilityDenied() async {
        let fixture = RecordingCoordinatorFixture(accessibility: .denied)
        await fixture.drainStartupTasks()
        // Wait on the actual failure being applied (status banner posted from
        // failInputRecording), not just on the permission snapshot being queried.
        // StubPermissionProvider.currentSnapshot() invokes onSnapshot() and returns
        // synchronously, but the caller still needs a MainActor hop to evaluate the
        // guard and call failInputRecording(); fulfilling on "snapshot queried" let
        // fulfillment(of:) race ahead of that hop and observe pre-failure state,
        // which is the harness flake tracked in #922.
        let recordingFailed = expectation(description: "input recording failed")
        fixture.statusHandler = { message in
            if message.contains("Accessibility") { recordingFailed.fulfill() }
        }

        fixture.coordinator.toggleInputRecording()
        await fulfillment(of: [recordingFailed], timeout: 1.0)

        XCTAssertFalse(fixture.coordinator.isInputRecording())
        XCTAssertEqual(
            fixture.coordinator.inputDisplayText(), "⚠️ Accessibility permission required for recording"
        )
        XCTAssertTrue(fixture.statusMessages.contains { $0.contains("Accessibility") })
    }

    func testInputRecordingCompletesWhenCaptureCallbackFires() async {
        let fixture = RecordingCoordinatorFixture(accessibility: .granted)
        await fixture.drainStartupTasks()
        fixture.captureStub.autoFire = false
        let captureStarted = expectation(description: "capture started")
        fixture.captureStub.onStart = { captureStarted.fulfill() }

        fixture.coordinator.toggleInputRecording()
        await fulfillment(of: [captureStarted], timeout: 1.0)

        XCTAssertTrue(fixture.coordinator.isInputRecording())
        XCTAssertTrue(fixture.coordinator.inputDisplayText().hasPrefix("Press"))
        XCTAssertEqual(fixture.captureStub.startCalls, 1)

        let keyPress = KeyPress(baseKey: "k", modifiers: [], keyCode: 40)
        let sequence = KeySequence(keys: [keyPress], captureMode: .chord)
        fixture.captureStub.triggerCapture(with: sequence)
        await Task.yield()
        fixture.coordinator.finalizePendingCapturesForTesting()

        XCTAssertFalse(fixture.coordinator.isInputRecording())
        XCTAssertEqual(fixture.coordinator.inputDisplayText(), sequence.displayString)
        XCTAssertEqual(fixture.coordinator.capturedInputSequence(), sequence)
    }

    func testOutputRecordingFailsWhenAccessibilityDenied() async {
        let fixture = RecordingCoordinatorFixture(accessibility: .denied)
        await fixture.drainStartupTasks()
        // See testInputRecordingFailsWhenAccessibilityDenied for why we wait on the
        // applied failure rather than the permission snapshot being queried (#922).
        let recordingFailed = expectation(description: "output recording failed")
        fixture.statusHandler = { message in
            if message.contains("Accessibility") { recordingFailed.fulfill() }
        }

        fixture.coordinator.toggleOutputRecording()
        await fulfillment(of: [recordingFailed], timeout: 1.0)

        XCTAssertFalse(fixture.coordinator.isOutputRecording())
        XCTAssertEqual(
            fixture.coordinator.outputDisplayText(), "⚠️ Accessibility permission required for recording"
        )
        XCTAssertTrue(fixture.statusMessages.contains { $0.contains("Accessibility") })
    }

    fileprivate static func snapshot(accessibility: PermissionOracle.Status) -> PermissionOracle.Snapshot {
        let permissionSet = PermissionOracle.PermissionSet(
            accessibility: accessibility,
            inputMonitoring: .granted,
            source: "tests",
            confidence: .high,
            timestamp: Date()
        )
        return PermissionOracle.Snapshot(
            keyPath: permissionSet, kanata: permissionSet, timestamp: Date()
        )
    }
}

// MARK: - Test Doubles

@MainActor
private final class RecordingCoordinatorFixture {
    var statusMessages: [String] = []
    /// Optional extra hook for tests that need to synchronize on a status message
    /// being posted (e.g. via XCTestExpectation), in addition to the default
    /// accumulation into `statusMessages`.
    var statusHandler: ((String) -> Void)?
    let permissionProvider: StubPermissionProvider
    let captureStub = StubRecordingCapture()
    let kanataManager = RuntimeCoordinator()
    let coordinator = RecordingCoordinator()

    init(accessibility: PermissionOracle.Status) {
        permissionProvider = StubPermissionProvider(
            snapshot: RecordingCoordinatorTests.snapshot(accessibility: accessibility)
        )
        coordinator.configure(
            kanataManager: kanataManager,
            statusHandler: { [weak self] message in
                self?.statusMessages.append(message)
                self?.statusHandler?(message)
            },
            permissionProvider: permissionProvider,
            keyboardCaptureFactory: { [unowned self] in captureStub }
        )
    }

    func drainStartupTasks() async {
        // Best-effort drain for startup tasks kicked off by configure(); tests use
        // explicit expectations for correctness-sensitive capture and permission events.
        for _ in 0 ..< 20 {
            await Task.yield()
        }
    }
}

private final class StubPermissionProvider: PermissionSnapshotProviding, @unchecked Sendable {
    var snapshot: PermissionOracle.Snapshot
    var onSnapshot: (() -> Void)?

    init(snapshot: PermissionOracle.Snapshot) {
        self.snapshot = snapshot
    }

    func currentSnapshot() async -> PermissionOracle.Snapshot {
        onSnapshot?()
        return snapshot
    }
}

@MainActor
private final class StubRecordingCapture: RecordingCapture {
    private(set) var startCalls = 0
    private var callback: ((KeySequence) -> Void)?
    var autoFire = true
    var onStart: (() -> Void)?

    func setEventRouter(_: EventRouter?, kanataManager _: RuntimeCoordinator?) {
        // No-op in tests
    }

    func startSequenceCapture(mode: CaptureMode, callback: @escaping (KeySequence) -> Void) {
        startCalls += 1
        self.callback = callback
        onStart?()
        if autoFire {
            callback(Self.sampleSequence(for: mode))
        }
    }

    func stopCapture() {
        // No-op
    }

    func triggerCapture(with sequence: KeySequence) {
        callback?(sequence)
    }

    private static func sampleSequence(for mode: CaptureMode) -> KeySequence {
        let key = KeyPress(baseKey: "s", modifiers: [], keyCode: 1)
        return KeySequence(keys: [key], captureMode: mode)
    }
}
