import XCTest
@testable import KeyPath

@MainActor
final class RecordingCoordinatorTests: XCTestCase {
    private var coordinator: RecordingCoordinator!
    private var permissionProvider: StubPermissionProvider!
    private var captureStub: StubRecordingCapture!
    private var kanataManager: KanataManager!
    private var statusMessages: [String] = []

    override func setUp() async throws {
        try await super.setUp()
        coordinator = RecordingCoordinator()
        permissionProvider = StubPermissionProvider(snapshot: RecordingCoordinatorTests.snapshot(accessibility: .unknown))
        captureStub = StubRecordingCapture()
        kanataManager = KanataManager()
        statusMessages = []

        coordinator.configure(
            kanataManager: kanataManager,
            statusHandler: { [weak self] message in self?.statusMessages.append(message) },
            permissionProvider: permissionProvider,
            keyboardCaptureFactory: { [unowned self] in self.captureStub }
        )
    }

    override func tearDown() async throws {
        coordinator.stopAllRecording()
        coordinator = nil
        captureStub = nil
        permissionProvider = nil
        kanataManager = nil
        statusMessages = []
        try await super.tearDown()
    }

    func testInputRecordingFailsWhenAccessibilityDenied() async throws {
        permissionProvider.snapshot = Self.snapshot(accessibility: .denied)

        coordinator.toggleInputRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertFalse(coordinator.isInputRecording())
        XCTAssertEqual(coordinator.inputDisplayText(), "⚠️ Accessibility permission required for recording")
        XCTAssertTrue(statusMessages.contains { $0.contains("Accessibility") })
    }

    func testInputRecordingCompletesWhenCaptureCallbackFires() async throws {
        permissionProvider.snapshot = Self.snapshot(accessibility: .granted)
        captureStub.autoFire = false

        coordinator.toggleInputRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(coordinator.isInputRecording())
        XCTAssertTrue(coordinator.inputDisplayText().hasPrefix("Press"))
        XCTAssertEqual(captureStub.startCalls, 1)

        let keyPress = KeyPress(baseKey: "k", modifiers: [], keyCode: 40)
        let sequence = KeySequence(keys: [keyPress], captureMode: .chord)
        captureStub.triggerCapture(with: sequence)
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertFalse(coordinator.isInputRecording())
        XCTAssertEqual(coordinator.inputDisplayText(), sequence.displayString)
        XCTAssertEqual(coordinator.capturedInputSequence(), sequence)
    }

    func testOutputRecordingFailsWhenAccessibilityDenied() async throws {
        permissionProvider.snapshot = Self.snapshot(accessibility: .denied)

        coordinator.toggleOutputRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertFalse(coordinator.isOutputRecording())
        XCTAssertEqual(coordinator.outputDisplayText(), "⚠️ Accessibility permission required for recording")
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
        return PermissionOracle.Snapshot(keyPath: permissionSet, kanata: permissionSet, timestamp: Date())
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

    func setEventRouter(_ router: EventRouter?, kanataManager: KanataManager?) {
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
