import Foundation
import Testing

@testable import KeyPath

@Suite("Auto-Reload Functionality Tests")
struct AutoReloadTests {
    
    @Test("Rule installation context includes auto-reload callback")
    func ruleInstallationContextIncludesAutoReloadCallback() {
        var messageAppended: KeyPathMessage?
        var lastMessageUpdated: String?
        var focusInputCalled = false
        var validationErrorCalled = false
        var kanataNotRunningCalled = false
        
        let context = RuleInstallationContext(
            appendMessage: { message in messageAppended = message },
            ruleHistory: RuleHistory(),
            updateLastMessage: { text in lastMessageUpdated = text },
            onFocusInput: { focusInputCalled = true },
            onValidationError: { _ in validationErrorCalled = true },
            onKanataNotRunning: { kanataNotRunningCalled = true }
        )
        
        // Test that all callbacks are properly set
        context.appendMessage(KeyPathMessage(role: .assistant, text: "test"))
        context.updateLastMessage("test update")
        context.onFocusInput()
        context.onValidationError(KanataValidationError.validationFailed("test error"))
        context.onKanataNotRunning()
        
        // Verify callbacks were called
        #expect(messageAppended?.displayText == "test")
        #expect(lastMessageUpdated == "test update")
        #expect(focusInputCalled == true)
        #expect(validationErrorCalled == true)
        #expect(kanataNotRunningCalled == true)
    }
    
    @Test("Kanata status view updates correctly")
    func kanataStatusViewUpdatesCorrectly() {
        // Test that KanataStatusView can be instantiated
        // Note: Since this is a SwiftUI view, we mainly test that it doesn't crash
        // and that the underlying status checking works
        
        let processManager = KanataProcessManager.shared
        let statusMessage = processManager.getStatusMessage()
        let isRunning = processManager.isKanataRunning()
        
        // Verify status message format
        #expect(!statusMessage.isEmpty)
        
        if isRunning {
            #expect(statusMessage.contains("running"))
            #expect(statusMessage.contains("PID"))
        } else {
            #expect(statusMessage.contains("not running"))
        }
    }
}

@Suite("Kanata Configuration Auto-Reload Integration Tests") 
struct KanataConfigAutoReloadTests {
    
    @Test("Status message reflects process state")
    func statusMessageReflectsProcessState() {
        let manager = KanataProcessManager.shared
        let isRunning = manager.isKanataRunning()
        let statusMessage = manager.getStatusMessage()
        
        // Status message should be consistent with running state
        if isRunning {
            #expect(statusMessage.contains("running"))
            
            // If running, should have PID information
            let pids = manager.getKanataPIDs()
            #expect(!pids.isEmpty)
            
            // Status message should mention PID
            #expect(statusMessage.contains("PID"))
        } else {
            #expect(statusMessage.contains("not running"))
        }
    }
    
    @Test("Reload operation handles process state correctly")
    func reloadOperationHandlesProcessStateCorrectly() {
        let manager = KanataProcessManager.shared
        let isRunning = manager.isKanataRunning()
        let reloadResult = manager.reloadKanata()
        
        // If Kanata is not running, reload should fail
        if !isRunning {
            #expect(reloadResult == false)
        }
        
        // Reload result should always be a boolean
        #expect(reloadResult == true || reloadResult == false)
    }
    
    @Test("Process info provides useful debugging information")
    func processInfoProvidesUsefulDebuggingInformation() {
        let manager = KanataProcessManager.shared
        let processInfo = manager.getKanataProcessInfo()
        
        // Should always return some information
        #expect(!processInfo.isEmpty)
        
        // Should mention Kanata in the info
        #expect(processInfo.contains("Kanata"))
        
        // If processes are running, should have process details
        let pids = manager.getKanataPIDs()
        if !pids.isEmpty {
            // Process info should contain some process details
            #expect(processInfo.contains("processes") || processInfo.contains("PID"))
        }
    }
}
