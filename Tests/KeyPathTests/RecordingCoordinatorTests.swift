import KeyPathPermissions
import XCTest

@testable import KeyPathAppKit

@MainActor
final class RecordingCoordinatorTests: XCTestCase {
    private var statusMessages: [String] = []
    private lazy var permissionProvider = StubPermissionProvider(
        snapshot: RecordingCoordinatorTests.snapshot(accessibility: .unknown)
    )
    private lazy var captureStub = StubRecordingCapture()
    private lazy var kanataManager = KanataManager()
    private lazy var coordinator: RecordingCoordinator = {
        let c = RecordingCoordinator()
        c.configure(
            kanataManager: kanataManager,
            statusHandler: { [weak self] message in self?.statusMessages.append(message) },
            permissionProvider: permissionProvider,
            keyboardCaptureFactory: { [unowned self] in captureStub }
        )
        return c
    }()

    func testInputRecordingFailsWhenAccessibilityDenied() async throws {
        statusMessages.removeAll()
        coordinator.stopAllRecording()
        coordinator.clearCapturedSequences()
        permissionProvider.snapshot = Self.snapshot(accessibility: .denied)

        coordinator.toggleInputRecording()
        // Wait for async permission check and state update
        try? await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertFalse(coordinator.isInputRecording())
        XCTAssertEqual(
            coordinator.inputDisplayText(), "⚠️ Accessibility permission required for recording"
        )
        XCTAssertTrue(statusMessages.contains { $0.contains("Accessibility") })
    }

    func testInputRecordingCompletesWhenCaptureCallbackFires() async throws {
        statusMessages.removeAll()
        coordinator.stopAllRecording()
        coordinator.clearCapturedSequences()
        permissionProvider.snapshot = Self.snapshot(accessibility: .granted)
        captureStub.autoFire = false

        coordinator.toggleInputRecording()
        // Wait for recording to start
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(coordinator.isInputRecording())
        XCTAssertTrue(coordinator.inputDisplayText().hasPrefix("Press"))
        XCTAssertEqual(captureStub.startCalls, 1)

        let keyPress = KeyPress(baseKey: "k", modifiers: [], keyCode: 40)
        let sequence = KeySequence(keys: [keyPress], captureMode: .chord)
        captureStub.triggerCapture(with: sequence)
        // Wait for callback to process and stop recording
        // Increase wait time to ensure async callback completes
        try? await Task.sleep(nanoseconds: 500_000_000) // 500ms

        // Recording should stop after capture callback fires
        // Add a small retry loop for async operations
        var recordingStopped = false
        for _ in 0 ..< 10 {
            if !coordinator.isInputRecording() {
                recordingStopped = true
                break
            }
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }

        XCTAssertTrue(
            recordingStopped || !coordinator.isInputRecording(),
            "Recording should stop after capture callback fires"
        )
        if recordingStopped || !coordinator.isInputRecording() {
            XCTAssertEqual(coordinator.inputDisplayText(), sequence.displayString)
            XCTAssertEqual(coordinator.capturedInputSequence(), sequence)
        }
    }

    func testOutputRecordingFailsWhenAccessibilityDenied() async throws {
        statusMessages.removeAll()
        coordinator.stopAllRecording()
        coordinator.clearCapturedSequences()
        permissionProvider.snapshot = Self.snapshot(accessibility: .denied)

        coordinator.toggleOutputRecording()
        // Wait for async permission check and state update
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertFalse(coordinator.isOutputRecording())
        XCTAssertEqual(
            coordinator.outputDisplayText(), "⚠️ Accessibility permission required for recording"
        )
        XCTAssertTrue(statusMessages.contains { $0.contains("Accessibility") })
    }

    private static func snapshot(accessibility: PermissionOracle.Status) -> PermissionOracle.Snapshot {
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

private final class StubPermissionProvider: PermissionSnapshotProviding {
    var snapshot: PermissionOracle.Snapshot

    init(snapshot: PermissionOracle.Snapshot) {
        self.snapshot = snapshot
    }

    func currentSnapshot() async -> PermissionOracle.Snapshot {
        snapshot
    }
}

@MainActor
private final class StubRecordingCapture: RecordingCapture {
    private(set) var startCalls = 0
    private var callback: ((KeySequence) -> Void)?
    var autoFire = true

    func setEventRouter(_: EventRouter?, kanataManager _: KanataManager?) {
        // No-op in tests
    }

    func startSequenceCapture(mode: CaptureMode, callback: @escaping (KeySequence) -> Void) {
        startCalls += 1
        self.callback = callback
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
