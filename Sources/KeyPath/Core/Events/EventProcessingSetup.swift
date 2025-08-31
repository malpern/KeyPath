import Foundation

/// Helper for setting up the event processing chain in KeyPath
public enum EventProcessingSetup {
    /// Configure the default event router with standard KeyPath processors
    public static func setupDefaultProcessors() {
        // Clear any existing processors
        defaultEventRouter.clearProcessors()

        // Add the default processor (wraps legacy behavior)
        let defaultProcessor = DefaultEventProcessor.standard()
        defaultEventRouter.addProcessor(defaultProcessor, name: "DefaultProcessor")

        AppLogger.shared.log("📋 [EventProcessingSetup] Default processors configured")
    }

    /// Configure event router for debugging with full logging
    public static func setupDebuggingProcessors() {
        // Clear any existing processors
        defaultEventRouter.clearProcessors()

        // Add debugging processor with logging
        let debugProcessor = DefaultEventProcessor.debugging()
        defaultEventRouter.addProcessor(debugProcessor, name: "DebuggingProcessor")

        AppLogger.shared.log("📋 [EventProcessingSetup] Debugging processors configured")
    }

    /// Configure KeyboardCapture to use the event router
    static func enableEventProcessingFor(
        _ keyboardCapture: KeyboardCapture,
        kanataManager: KanataManager? = nil
    ) {
        keyboardCapture.setEventRouter(defaultEventRouter, kanataManager: kanataManager)
        keyboardCapture.enableEventRouter()

        AppLogger.shared.log("📋 [EventProcessingSetup] Event processing enabled for KeyboardCapture")
    }

    /// Disable event processing for KeyboardCapture (fallback to legacy behavior)
    static func disableEventProcessingFor(_ keyboardCapture: KeyboardCapture) {
        keyboardCapture.disableEventRouter()
        keyboardCapture.setEventRouter(nil)

        AppLogger.shared.log("📋 [EventProcessingSetup] Event processing disabled for KeyboardCapture")
    }

    /// Get current processor configuration (for debugging)
    public static func getCurrentProcessors() -> [String] {
        defaultEventRouter.getProcessorNames()
    }
}
