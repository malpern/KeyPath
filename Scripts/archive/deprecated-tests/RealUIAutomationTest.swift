@testable import KeyPathAppKit
import XCTest

/// Real UI Automation Test that goes through the complete KeyPath save pipeline
/// This test uses the actual KanataManager.saveConfiguration method with full validation
@MainActor
final class RealUIAutomationTest: XCTestCase {
    var kanataManager: KanataManager!

    override func setUp() async throws {
        try await super.setUp()
        kanataManager = KanataManager()
        AppLogger.shared.log("🧪 [RealUIAutomation] Starting real UI automation test")
    }

    override func tearDown() async throws {
        kanataManager = nil
        try await super.tearDown()
    }

    func testFullUIWorkflowWithValidation() async throws {
        AppLogger.shared.log("🤖 [RealUIAutomation] ========== STARTING FULL UI WORKFLOW ==========")
        AppLogger.shared.log("🤖 [RealUIAutomation] Testing 1→2 mapping through complete KeyPath pipeline")

        let startTime = Date()

        // Step 1: Record the baseline timestamp
        AppLogger.shared.log("🤖 [RealUIAutomation] Step 1: Recording baseline timestamp")
        let baselineTime = Date()

        // Step 2: Simulate user clicking "Record Input" button
        AppLogger.shared.log("🤖 [RealUIAutomation] Step 2: User clicks 'Record Input' button")
        let inputRecordStartTime = Date()

        // Step 3: Simulate input key capture (1)
        AppLogger.shared.log("🤖 [RealUIAutomation] Step 3: Input key '1' captured")
        let inputKey = "1"
        let inputCaptureTime = Date()
        let inputCaptureDuration = inputCaptureTime.timeIntervalSince(inputRecordStartTime)
        AppLogger.shared.log("🕐 [RealUIAutomation] Input capture took: \(String(format: "%.3f", inputCaptureDuration))s")

        // Step 4: Simulate user clicking "Record Output" button
        AppLogger.shared.log("🤖 [RealUIAutomation] Step 4: User clicks 'Record Output' button")
        let outputRecordStartTime = Date()

        // Step 5: Simulate output key capture (2)
        AppLogger.shared.log("🤖 [RealUIAutomation] Step 5: Output key '2' captured")
        let outputKey = "2"
        let outputCaptureTime = Date()
        let outputCaptureDuration = outputCaptureTime.timeIntervalSince(outputRecordStartTime)
        AppLogger.shared.log("🕐 [RealUIAutomation] Output capture took: \(String(format: "%.3f", outputCaptureDuration))s")

        // Step 6: Simulate user clicking "Save" button - THIS IS THE CRITICAL PART
        AppLogger.shared.log("🤖 [RealUIAutomation] Step 6: User clicks 'Save' button")
        AppLogger.shared.log("🤖 [RealUIAutomation] ========== ENTERING KANATA MANAGER SAVE PIPELINE ==========")

        let saveStartTime = Date()

        do {
            // This is the actual KanataManager.saveConfiguration call that the UI would make
            // It includes all the validation, config generation, file writing, and hot reload
            AppLogger.shared.log("💾 [RealUIAutomation] Calling KanataManager.saveConfiguration(input: '\(inputKey)', output: '\(outputKey)')")

            try await kanataManager.saveConfiguration(input: inputKey, output: outputKey)

            let saveEndTime = Date()
            let saveDuration = saveEndTime.timeIntervalSince(saveStartTime)

            AppLogger.shared.log("✅ [RealUIAutomation] ========== SAVE PIPELINE COMPLETED ==========")
            AppLogger.shared.log("🕐 [RealUIAutomation] Total save duration: \(String(format: "%.3f", saveDuration))s")

            // Step 7: Verify the save was successful
            AppLogger.shared.log("🤖 [RealUIAutomation] Step 7: Verifying save results")

            let configExists = await kanataManager.verifyConfigExists()
            XCTAssertTrue(configExists, "Configuration file should exist after save")

            // Step 8: Check if service reloaded
            AppLogger.shared.log("🤖 [RealUIAutomation] Step 8: Checking service reload status")

            // Give the service a moment to reload
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

            await kanataManager.updateStatus()
            let isRunning = kanataManager.isRunning
            AppLogger.shared.log("🔍 [RealUIAutomation] Service running status: \(isRunning)")

            // Step 9: Calculate total workflow timing
            let totalEndTime = Date()
            let totalWorkflowDuration = totalEndTime.timeIntervalSince(startTime)

            AppLogger.shared.log("🤖 [RealUIAutomation] ========== WORKFLOW TIMING SUMMARY ==========")
            AppLogger.shared.log("🕐 [RealUIAutomation] Input capture: \(String(format: "%.3f", inputCaptureDuration))s")
            AppLogger.shared.log("🕐 [RealUIAutomation] Output capture: \(String(format: "%.3f", outputCaptureDuration))s")
            AppLogger.shared.log("🕐 [RealUIAutomation] Save pipeline: \(String(format: "%.3f", saveDuration))s")
            AppLogger.shared.log("🕐 [RealUIAutomation] Total workflow: \(String(format: "%.3f", totalWorkflowDuration))s")

            // Step 10: Success verification
            AppLogger.shared.log("🎉 [RealUIAutomation] ========== UI AUTOMATION SUCCESSFUL ==========")
            AppLogger.shared.log("🎉 [RealUIAutomation] Successfully added 1→2 mapping through full UI pipeline")

            // Test assertions
            XCTAssertTrue(configExists, "Config file should exist")
            XCTAssertLessThan(saveDuration, 10.0, "Save should complete within 10 seconds")
            XCTAssertLessThan(totalWorkflowDuration, 15.0, "Total workflow should complete within 15 seconds")

        } catch {
            let saveEndTime = Date()
            let saveDuration = saveEndTime.timeIntervalSince(saveStartTime)

            AppLogger.shared.log("❌ [RealUIAutomation] ========== SAVE PIPELINE FAILED ==========")
            AppLogger.shared.log("❌ [RealUIAutomation] Error after \(String(format: "%.3f", saveDuration))s: \(error)")
            AppLogger.shared.log("❌ [RealUIAutomation] Full error: \(String(describing: error))")

            XCTFail("Save pipeline failed: \(error)")
        }
    }
}

// End of file
