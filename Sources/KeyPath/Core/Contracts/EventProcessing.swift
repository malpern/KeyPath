import CoreGraphics
import Foundation

/// Protocol defining event processing capabilities for CGEvent handling.
///
/// This protocol establishes a consistent interface for processing CGEvents
/// within KeyPath's event handling pipeline. It provides the foundation for
/// clean separation between event capture and event processing logic.
///
/// ## Usage
///
/// Event processors implement this protocol to handle specific types of
/// events or implement particular processing policies:
///
/// ```swift
/// class KeyboardProcessor: EventProcessing {
///     func process(
///         event: CGEvent,
///         location: CGEventTapLocation,
///         proxy: CGEventTapProxy
///     ) -> CGEvent? {
///         let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
///
///         // Process the event and decide whether to pass it through
///         if shouldSuppressKey(keyCode) {
///             return nil // Suppress the event
///         }
///
///         return event // Pass through unchanged
///     }
/// }
/// ```
///
/// ## Event Handling Contract
///
/// - Return `nil` to suppress the event (prevent it from reaching other applications)
/// - Return the original `event` to pass it through unchanged
/// - Return a modified event to transform it before passing through
/// - Processing should be efficient as it occurs in the event tap callback
///
/// ## Thread Safety
///
/// Event processing occurs on the event tap's thread. Implementations should
/// avoid blocking operations and ensure thread-safe access to shared state.
protocol EventProcessing {
    /// Processes a CGEvent from an event tap.
    ///
    /// This method is called for each event captured by an event tap. The processor
    /// can examine the event, perform transformations, and decide whether to
    /// pass the event through to other applications.
    ///
    /// - Parameters:
    ///   - event: The CGEvent to process.
    ///   - location: The tap location where the event was captured.
    ///   - proxy: The event tap proxy for this tap.
    ///
    /// - Returns: The processed event to pass through, or `nil` to suppress it.
    func process(
        event: CGEvent,
        location: CGEventTapLocation,
        proxy: CGEventTapProxy
    ) -> CGEvent?
}

/// Extension providing convenience methods and default behaviors.
extension EventProcessing {
    /// Processes an event with minimal context (for simpler use cases).
    ///
    /// This convenience method calls the full `process` method with default
    /// values for location and proxy.
    ///
    /// - Parameter event: The CGEvent to process.
    /// - Returns: The processed event or `nil` to suppress it.
    func process(event: CGEvent) -> CGEvent? {
        // Create a dummy proxy for the convenience method
        let dummyProxy = CGEventTapProxy(bitPattern: 0)!
        return process(
            event: event,
            location: .cgSessionEventTap,
            proxy: dummyProxy
        )
    }

    /// Checks if an event should be processed based on its type.
    ///
    /// - Parameter event: The CGEvent to examine.
    /// - Returns: `true` if the event should be processed, `false` otherwise.
    func shouldProcess(event: CGEvent) -> Bool {
        let eventType = event.type
        return eventType == .keyDown || eventType == .keyUp
    }
}

/// Specialized event processing for keyboard events.
protocol KeyboardEventProcessing: EventProcessing {
    /// Processes a keyboard-specific event with extracted key information.
    ///
    /// This method provides a higher-level interface for keyboard event processing,
    /// extracting common keyboard event properties for easier handling.
    ///
    /// - Parameters:
    ///   - keyCode: The virtual key code for the pressed key.
    ///   - eventType: The type of keyboard event (keyDown, keyUp, etc.).
    ///   - flags: The modifier flags associated with the event.
    ///   - event: The original CGEvent for advanced processing.
    ///
    /// - Returns: The processed event or `nil` to suppress it.
    func processKeyboard(
        keyCode: Int,
        eventType: CGEventType,
        flags: CGEventFlags,
        originalEvent event: CGEvent
    ) -> CGEvent?
}

/// Default implementation for keyboard event processing.
extension KeyboardEventProcessing {
    func process(
        event: CGEvent,
        location _: CGEventTapLocation,
        proxy _: CGEventTapProxy
    ) -> CGEvent? {
        guard shouldProcess(event: event) else {
            return event
        }

        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let eventType = event.type
        let flags = event.flags

        return processKeyboard(
            keyCode: keyCode,
            eventType: eventType,
            flags: flags,
            originalEvent: event
        )
    }
}

/// Errors related to event processing operations.
enum EventProcessingError: Error, LocalizedError {
    case invalidEvent
    case processingFailed(String)
    case unsupportedEventType(CGEventType)

    var errorDescription: String? {
        switch self {
        case .invalidEvent:
            "Invalid or malformed CGEvent"
        case let .processingFailed(reason):
            "Event processing failed: \(reason)"
        case let .unsupportedEventType(type):
            "Unsupported event type: \(type.rawValue)"
        }
    }
}
