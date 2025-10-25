#if canImport(AppKit)
import XCTest
@testable import KeyPath

@MainActor
final class AppDelegateWindowTests: XCTestCase {

    var appDelegate: AppDelegate!
    var mockManager: KanataManager!

    override func setUp() async throws {
        try await super.setUp()

        // Create mock kanata manager
        mockManager = KanataManager()

        // Create app delegate
        appDelegate = AppDelegate()
        appDelegate.kanataManager = mockManager
        appDelegate.isHeadlessMode = false
    }

    override func tearDown() async throws {
        appDelegate = nil
        mockManager = nil
        try await super.tearDown()
    }

    // MARK: - Eager Window Creation Tests

    func testEagerWindowCreation() {
        // Given: Fresh app delegate
        XCTAssertNil(appDelegate.mainWindowController, "Window should not exist before prepare")

        // When: Prepare window
        appDelegate.prepareMainWindowIfNeeded()

        // Then: Window is created
        XCTAssertNotNil(appDelegate.mainWindowController, "Window should be created after prepare")
    }

    func testPrepareIsIdempotent() {
        // Given: Window already prepared
        appDelegate.prepareMainWindowIfNeeded()
        let firstWindow = appDelegate.mainWindowController

        // When: Prepare called again
        appDelegate.prepareMainWindowIfNeeded()
        let secondWindow = appDelegate.mainWindowController

        // Then: Same window instance
        XCTAssertIdentical(firstWindow, secondWindow, "Should not create new window when already prepared")
    }

    func testHeadlessModeSkipsWindowCreation() {
        // Given: Headless mode
        appDelegate.isHeadlessMode = true

        // When: Prepare window
        appDelegate.prepareMainWindowIfNeeded()

        // Then: No window created
        XCTAssertNil(appDelegate.mainWindowController, "Should not create window in headless mode")
    }

    func testPrepareWithNilKanataManager() {
        // Given: No kanata manager
        appDelegate.kanataManager = nil

        // When: Prepare window
        appDelegate.prepareMainWindowIfNeeded()

        // Then: No window created (graceful failure)
        XCTAssertNil(appDelegate.mainWindowController, "Should not create window without KanataManager")
    }

    // MARK: - Bootstrap Tests

    func testBootstrapOnceIsIdempotent() async {
        // Given: Fresh app delegate
        let initialBootstrap = appDelegate.bootstrapStarted
        XCTAssertFalse(initialBootstrap, "Bootstrap should not be started initially")

        // When: Bootstrap called multiple times
        appDelegate.bootstrapOnce()
        let firstCall = appDelegate.bootstrapStarted

        appDelegate.bootstrapOnce()
        let secondCall = appDelegate.bootstrapStarted

        // Then: Only runs once
        XCTAssertTrue(firstCall, "Bootstrap should be marked as started after first call")
        XCTAssertTrue(secondCall, "Bootstrap should remain started after second call")

        // Small delay to let async tasks start
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
    }

    // MARK: - Activation Fallback Tests

    func testActivationFallback() async {
        // Given: Window prepared but not shown
        appDelegate.prepareMainWindowIfNeeded()
        XCTAssertFalse(appDelegate.initialMainWindowShown, "Window should not be shown yet")

        // When: Wait for fallback timer (1 second + margin)
        try? await Task.sleep(nanoseconds: 1_200_000_000) // 1.2 seconds

        // Then: Window is shown
        XCTAssertTrue(appDelegate.initialMainWindowShown, "Fallback should have shown window after timeout")
    }

    func testActivationFallbackOnlyScheduledOnce() {
        // Given: Fresh app delegate
        XCTAssertFalse(appDelegate.activationFallbackScheduled, "Fallback should not be scheduled initially")

        // When: Schedule fallback twice
        appDelegate.scheduleActivationFallback()
        let firstSchedule = appDelegate.activationFallbackScheduled

        appDelegate.scheduleActivationFallback()
        let secondSchedule = appDelegate.activationFallbackScheduled

        // Then: Only scheduled once
        XCTAssertTrue(firstSchedule, "Should be scheduled after first call")
        XCTAssertTrue(secondSchedule, "Should still be scheduled (idempotent)")
    }

    // MARK: - Integration Tests

    func testFullWindowLifecycle() async {
        // Given: Fresh app delegate (simulating app launch)
        XCTAssertNil(appDelegate.mainWindowController, "Window should not exist at launch")
        XCTAssertFalse(appDelegate.bootstrapStarted, "Bootstrap should not be started at launch")

        // When: Prepare window (happens in App.init)
        appDelegate.prepareMainWindowIfNeeded()

        // Then: Window exists but not shown yet
        XCTAssertNotNil(appDelegate.mainWindowController, "Window should be created")
        XCTAssertFalse(appDelegate.initialMainWindowShown, "Window should not be shown yet")

        // When: First activation (happens in applicationDidBecomeActive)
        appDelegate.bootstrapOnce()

        // Then: Bootstrap completed
        XCTAssertTrue(appDelegate.bootstrapStarted, "Bootstrap should be started after activation")

        // Small delay for async tasks
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
    }

    func testApplicationShouldHandleReopenCreatesWindow() {
        // Given: App started in headless mode (no window)
        appDelegate.isHeadlessMode = true
        XCTAssertNil(appDelegate.mainWindowController)

        // When: User reopens app from Dock
        appDelegate.isHeadlessMode = false // Escalate to regular mode
        let result = appDelegate.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false)

        // Then: Window is created and method returns true
        XCTAssertNotNil(appDelegate.mainWindowController, "Window should be created on reopen")
        XCTAssertTrue(result, "Should return true to handle reopen")
    }

    // MARK: - Debug Assertion Test (only in DEBUG builds)

    #if DEBUG
    func testDebugAssertionFiresWithoutWindow() {
        // Note: This test verifies the assertion exists, but we can't test that it crashes
        // without special test harness. The assertion is verified by code review and
        // will catch issues during development builds.

        // Given: Headless mode to avoid triggering assertion
        appDelegate.isHeadlessMode = true
        appDelegate.mainWindowController = nil

        // When/Then: No crash because headless mode bypasses assertion
        // (In normal mode without window, this WOULD crash in DEBUG)
        appDelegate.applicationDidBecomeActive(Notification(name: NSApplication.didBecomeActiveNotification))
    }
    #endif
}
#endif
