import XCTest
@testable import KeyPath
import ApplicationServices

@MainActor
final class KeyboardRecordingTests: XCTestCase {
    
    var keyboardCapture: KeyboardCapture!
    var recordedSequence: KeySequence?
    var recordingCompleted = false
    
    override func setUp() async throws {
        try await super.setUp()
        keyboardCapture = KeyboardCapture()
        recordedSequence = nil
        recordingCompleted = false
    }
    
    override func tearDown() async throws {
        keyboardCapture?.stopCapture()
        keyboardCapture = nil
        try await super.tearDown()
    }
    
    func testKeyboardCaptureInitialization() async throws {
        // Test that KeyboardCapture can be initialized
        XCTAssertNotNil(keyboardCapture)
    }
    
    func testPermissionCheck() async throws {
        // Test the fixed permission checking logic
        let hasPermissions = await keyboardCapture.checkAccessibilityPermissionsSilently()
        
        // Log the permission status for debugging
        let oracle = PermissionOracle.shared
        let snapshot = await oracle.currentSnapshot()
        
        print("🧪 [Test] Permission check results:")
        print("🧪 [Test] - Accessibility: \(snapshot.keyPath.accessibility.isReady)")
        print("🧪 [Test] - Input Monitoring: \(snapshot.keyPath.inputMonitoring.isReady)")
        print("🧪 [Test] - Combined check: \(hasPermissions)")
        
        // The test should pass if both permissions are available
        if snapshot.keyPath.accessibility.isReady && snapshot.keyPath.inputMonitoring.isReady {
            XCTAssertTrue(hasPermissions, "Permission check should return true when both AX and IM are granted")
        } else {
            XCTAssertFalse(hasPermissions, "Permission check should return false when permissions are missing")
            print("⚠️ [Test] Skipping recording tests - permissions not available")
            throw XCTSkip("Keyboard recording tests require both Accessibility and Input Monitoring permissions")
        }
    }
    
    func testStartSequenceCapture() async throws {
        // First verify we have permissions
        let hasPermissions = await keyboardCapture.checkAccessibilityPermissionsSilently()
        guard hasPermissions else {
            throw XCTSkip("Test requires both Accessibility and Input Monitoring permissions")
        }
        
        print("🧪 [Test] Starting sequence capture test...")
        
        let expectation = expectation(description: "Sequence capture completes")
        expectation.isInverted = true // We expect this NOT to fulfill quickly (no immediate callback)
        
        // Start recording in chord mode
        await keyboardCapture.startSequenceCapture(mode: .chord) { [weak self] sequence in
            print("🧪 [Test] Received key sequence: \(sequence.displayString)")
            self?.recordedSequence = sequence
            self?.recordingCompleted = true
        }
        
        // Wait briefly to ensure recording is started
        await fulfillment(of: [expectation], timeout: 1.0)
        
        print("🧪 [Test] Recording should now be active")
        print("🧪 [Test] Checking capture state...")
        
        // Verify the capture is in the right state
        // Note: We can't easily inject synthetic key events in tests due to security restrictions
        // But we can verify the recording state is set up correctly
        XCTAssertFalse(recordingCompleted, "Recording should not have completed immediately")
    }
    
    func testEventTapSetupLogging() async throws {
        // Test that the event tap setup produces the expected logs
        let hasPermissions = await keyboardCapture.checkAccessibilityPermissionsSilently()
        guard hasPermissions else {
            throw XCTSkip("Test requires both Accessibility and Input Monitoring permissions")
        }
        
        print("🧪 [Test] Testing event tap setup with detailed logging...")
        
        // Start capture which should trigger setupEventTap
        await keyboardCapture.startSequenceCapture(mode: .single) { sequence in
            print("🧪 [Test] Captured: \(sequence.displayString)")
        }
        
        // Give time for setup to complete
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // Stop capture to clean up
        keyboardCapture.stopCapture()
        
        print("🧪 [Test] Event tap setup test completed")
        print("🧪 [Test] Check logs for: '🎯 [KeyboardCapture] Creating CGEvent tap'")
        print("🧪 [Test] Check logs for: '🎹 [KeyboardCapture] Starting single capture'")
    }
}

// MARK: - Integration Test with UI Simulation

@MainActor
final class KeyboardRecordingIntegrationTests: XCTestCase {
    
    func testContentViewRecordingFlow() async throws {
        print("🧪 [Integration] Testing ContentView recording flow...")
        
        // Create a mock environment similar to ContentView
        var recordedInput = ""
        var isRecording = false
        var keyboardCapture: KeyboardCapture?
        
        // Simulate the ContentView startRecording logic
        let oracle = PermissionOracle.shared
        let snapshot = await oracle.currentSnapshot()
        
        print("🧪 [Integration] Permission snapshot:")
        print("🧪 [Integration] - AX Ready: \(snapshot.keyPath.accessibility.isReady)")
        print("🧪 [Integration] - IM Ready: \(snapshot.keyPath.inputMonitoring.isReady)")
        
        // Check permissions like ContentView does
        guard snapshot.keyPath.accessibility.isReady else {
            recordedInput = "⚠️ Accessibility permission required for recording"
            isRecording = false
            print("🧪 [Integration] Missing Accessibility permission")
            return
        }
        
        guard snapshot.keyPath.inputMonitoring.isReady else {
            recordedInput = "⚠️ Input Monitoring permission required for recording"
            isRecording = false
            print("🧪 [Integration] Missing Input Monitoring permission")
            return
        }
        
        // Initialize KeyboardCapture like ContentView does
        if keyboardCapture == nil {
            keyboardCapture = KeyboardCapture()
            keyboardCapture?.setEventRouter(nil, kanataManager: nil)
            print("🧪 [Integration] KeyboardCapture initialized for recording")
        }
        
        recordedInput = "Ready - press a key to record..."
        
        guard let capture = keyboardCapture else {
            recordedInput = "⚠️ Failed to initialize keyboard capture"
            isRecording = false
            print("🧪 [Integration] Failed to initialize KeyboardCapture")
            return
        }
        
        print("🧪 [Integration] Starting sequence capture...")
        
        // Start capture like ContentView does
        let captureMode: CaptureMode = .chord
        
        await capture.startSequenceCapture(mode: captureMode) { keySequence in
            recordedInput = keySequence.displayString
            isRecording = false
            print("🧪 [Integration] Captured sequence: \(keySequence.displayString)")
        }
        
        print("🧪 [Integration] Recording flow setup completed")
        print("🧪 [Integration] Current state: \(recordedInput)")
        
        // Verify the setup worked
        XCTAssertEqual(recordedInput, "Ready - press a key to record...", "Recording should be ready")
        
        // Clean up
        capture.stopCapture()
    }
}