import CoreGraphics
import Foundation

/// Protocol defining output event synthesis capabilities.
///
/// This protocol establishes a consistent interface for generating and posting
/// synthetic events within KeyPath. It provides the foundation for clean separation
/// between event synthesis and input processing logic.
///
/// ## Usage
///
/// Output synthesizers implement this protocol to provide different methods
/// of generating system events:
///
/// ```swift
/// class CGEventSynthesizer: OutputSynthesizing {
///     func synthesizeKey(_ keyCode: Int, pressed: Bool) async throws {
///         let event = CGEvent(keyboardEventSource: nil,
///                           virtualKey: CGKeyCode(keyCode),
///                           keyDown: pressed)
///         guard let event else { throw OutputError.creationFailed }
///         event.post(tap: .cghidEventTap)
///     }
/// }
/// ```
///
/// ## Thread Safety
///
/// All methods are async and implementations should ensure thread-safe
/// event synthesis and posting operations.
protocol OutputSynthesizing {
    /// Synthesizes a keyboard event.
    ///
    /// Creates and posts a keyboard event with the specified parameters.
    /// The event will be delivered to the system input queue.
    ///
    /// - Parameters:
    ///   - keyCode: The virtual key code to synthesize.
    ///   - pressed: Whether this is a key press (true) or release (false).
    ///   - modifiers: Optional modifier keys to include with the event.
    ///
    /// - Throws: `OutputError` if event creation or posting fails.
    func synthesizeKey(_ keyCode: Int, pressed: Bool, modifiers: EventModifiers?) async throws

    /// Synthesizes a sequence of keyboard events.
    ///
    /// Creates and posts multiple keyboard events in sequence, useful for
    /// implementing complex key combinations or text input.
    ///
    /// - Parameter sequence: The sequence of keyboard events to synthesize.
    /// - Throws: `OutputError` if any event in the sequence fails.
    func synthesizeKeySequence(_ sequence: [KeyEvent]) async throws

    /// Synthesizes a mouse event.
    ///
    /// Creates and posts a mouse event at the specified location with the
    /// given button state.
    ///
    /// - Parameters:
    ///   - location: The screen coordinates for the mouse event.
    ///   - button: The mouse button involved in the event.
    ///   - eventType: The type of mouse event (click, drag, etc.).
    ///
    /// - Throws: `OutputError` if event creation or posting fails.
    func synthesizeMouse(at location: CGPoint, button: MouseButton, eventType: MouseEventType) async throws

    /// Posts a pre-created CGEvent to the system.
    ///
    /// This method provides low-level access for posting custom CGEvents
    /// that have been created elsewhere.
    ///
    /// - Parameters:
    ///   - event: The CGEvent to post.
    ///   - location: The tap location where the event should be posted.
    ///
    /// - Throws: `OutputError` if posting fails.
    func postEvent(_ event: CGEvent, at location: CGEventTapLocation) async throws
}

/// Extension providing convenience methods and common patterns.
extension OutputSynthesizing {
    /// Synthesizes a key press followed by a key release.
    ///
    /// This convenience method simulates a complete key press by generating
    /// both press and release events with appropriate timing.
    ///
    /// - Parameters:
    ///   - keyCode: The virtual key code to press.
    ///   - modifiers: Optional modifier keys to include.
    ///   - duration: Time between press and release (default: 10ms).
    ///
    /// - Throws: `OutputError` if event synthesis fails.
    func pressKey(_ keyCode: Int, modifiers: EventModifiers? = nil, duration: TimeInterval = 0.01) async throws {
        try await synthesizeKey(keyCode, pressed: true, modifiers: modifiers)
        try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
        try await synthesizeKey(keyCode, pressed: false, modifiers: modifiers)
    }

    /// Synthesizes typing of a text string.
    ///
    /// Converts a text string into a sequence of keyboard events and posts them.
    /// This method handles character-to-keycode mapping and modifier requirements.
    ///
    /// - Parameter text: The text string to type.
    /// - Throws: `OutputError` if text conversion or event synthesis fails.
    func typeText(_ text: String) async throws {
        let events = try textToKeyEvents(text)
        try await synthesizeKeySequence(events)
    }

    /// Synthesizes a mouse click at the specified location.
    ///
    /// This convenience method generates a complete mouse click (press + release).
    ///
    /// - Parameters:
    ///   - location: The screen coordinates to click.
    ///   - button: The mouse button to click (default: left).
    ///
    /// - Throws: `OutputError` if event synthesis fails.
    func clickMouse(at location: CGPoint, button: MouseButton = .left) async throws {
        try await synthesizeMouse(at: location, button: button, eventType: .buttonPress)
        try await synthesizeMouse(at: location, button: button, eventType: .buttonRelease)
    }

    /// Converts text to a sequence of key events (internal helper).
    private func textToKeyEvents(_: String) throws -> [KeyEvent] {
        // This would contain the actual text-to-keycode conversion logic
        // For now, this is a placeholder that would need platform-specific implementation
        throw OutputError.unsupportedOperation("Text typing not yet implemented")
    }
}

/// Represents a keyboard event in a synthesis sequence.
struct KeyEvent: Sendable {
    let keyCode: Int
    let pressed: Bool
    let modifiers: EventModifiers?
    let timing: EventTiming

    init(keyCode: Int, pressed: Bool, modifiers: EventModifiers? = nil, timing: EventTiming = .immediate) {
        self.keyCode = keyCode
        self.pressed = pressed
        self.modifiers = modifiers
        self.timing = timing
    }
}

/// Timing information for event synthesis.
enum EventTiming: Sendable {
    case immediate
    case delayed(TimeInterval)
    case after(TimeInterval)
}

/// Modifier key flags for events.
struct EventModifiers: OptionSet, Sendable {
    let rawValue: UInt32

    static let command = EventModifiers(rawValue: 1 << 0)
    static let shift = EventModifiers(rawValue: 1 << 1)
    static let option = EventModifiers(rawValue: 1 << 2)
    static let control = EventModifiers(rawValue: 1 << 3)
    static let capsLock = EventModifiers(rawValue: 1 << 4)
    static let function = EventModifiers(rawValue: 1 << 5)

    /// Convert to CGEventFlags for CGEvent creation.
    var cgEventFlags: CGEventFlags {
        var flags: CGEventFlags = []
        if contains(.command) { flags.insert(.maskCommand) }
        if contains(.shift) { flags.insert(.maskShift) }
        if contains(.option) { flags.insert(.maskAlternate) }
        if contains(.control) { flags.insert(.maskControl) }
        if contains(.capsLock) { flags.insert(.maskAlphaShift) }
        if contains(.function) { flags.insert(.maskSecondaryFn) }
        return flags
    }
}

/// Mouse button identifiers.
enum MouseButton: Sendable {
    case left
    case right
    case middle
    case other(Int)

    var cgMouseButton: CGMouseButton {
        switch self {
        case .left: .left
        case .right: .right
        case .middle: .center
        case let .other(buttonNumber): CGMouseButton(rawValue: UInt32(buttonNumber))!
        }
    }
}

/// Mouse event types.
enum MouseEventType: Sendable {
    case buttonPress
    case buttonRelease
    case moved
    case dragged

    func cgEventType(for button: MouseButton) -> CGEventType {
        switch (self, button) {
        case (.buttonPress, .left): .leftMouseDown
        case (.buttonRelease, .left): .leftMouseUp
        case (.buttonPress, .right): .rightMouseDown
        case (.buttonRelease, .right): .rightMouseUp
        case (.buttonPress, .middle): .otherMouseDown
        case (.buttonRelease, .middle): .otherMouseUp
        case (.moved, _): .mouseMoved
        case (.dragged, .left): .leftMouseDragged
        case (.dragged, .right): .rightMouseDragged
        case (.dragged, _): .otherMouseDragged
        default: .mouseMoved
        }
    }
}

/// Errors related to output synthesis operations.
enum OutputError: Error, LocalizedError {
    case creationFailed
    case postingFailed(String)
    case permissionDenied
    case invalidEvent
    case unsupportedOperation(String)
    case sequenceError(String)

    var errorDescription: String? {
        switch self {
        case .creationFailed:
            "Failed to create output event"
        case let .postingFailed(reason):
            "Failed to post output event: \(reason)"
        case .permissionDenied:
            "Insufficient permissions for output synthesis"
        case .invalidEvent:
            "Invalid event parameters"
        case let .unsupportedOperation(operation):
            "Unsupported output operation: \(operation)"
        case let .sequenceError(reason):
            "Event sequence error: \(reason)"
        }
    }
}
