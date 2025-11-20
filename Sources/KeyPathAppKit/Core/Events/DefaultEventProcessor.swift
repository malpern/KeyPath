import CoreGraphics
import Foundation
import KeyPathCore

/// Default event processor that wraps existing KeyPath event handling logic
///
/// This processor serves as a bridge between the new EventProcessing architecture
/// and the existing event handling patterns in KeyPath. It ensures backward
/// compatibility while enabling the new processing chain architecture.
public final class DefaultEventProcessor: EventProcessing {
  /// Reference to the keyboard capture service for legacy event handling
  private weak var keyboardCapture: KeyboardCapture?

  /// Configuration for event processing behavior
  public struct Configuration: Sendable {
    public let suppressEvents: Bool
    public let logEvents: Bool
    public let enableKeyCodeMapping: Bool

    public init(
      suppressEvents: Bool = false,
      logEvents: Bool = false,
      enableKeyCodeMapping: Bool = true
    ) {
      self.suppressEvents = suppressEvents
      self.logEvents = logEvents
      self.enableKeyCodeMapping = enableKeyCodeMapping
    }

    public static let `default` = Configuration()
  }

  private let configuration: Configuration

  public init(
    keyboardCapture: KeyboardCapture? = nil,
    configuration: Configuration = .default
  ) {
    self.keyboardCapture = keyboardCapture
    self.configuration = configuration
  }

  // MARK: - EventProcessing Protocol

  public func process(
    event: CGEvent,
    location _: CGEventTapLocation,
    proxy _: CGEventTapProxy
  ) -> CGEvent? {
    // Skip non-keyboard events for now
    guard shouldProcess(event: event) else {
      return event
    }

    if configuration.logEvents {
      logEvent(event)
    }

    // For now, we primarily handle key events through the existing architecture
    // Future implementations can add more sophisticated processing here

    // Apply key code mapping if enabled
    if configuration.enableKeyCodeMapping {
      if let mappedEvent = applyKeyCodeMapping(event) {
        // Note: Logging removed from hot path for performance
        return mappedEvent
      }
    }

    // Default behavior: pass through unchanged or suppress based on configuration
    return configuration.suppressEvents ? nil : event
  }

  // MARK: - Legacy Integration Methods

  /// Process event through legacy KeyboardCapture logic
  private func processWithKeyboardCapture(_ event: CGEvent) -> CGEvent? {
    // This would integrate with existing keyboard capture logic
    // For now, we pass through to maintain existing behavior
    event
  }

  /// Apply key code mappings (placeholder for future Kanata integration)
  private func applyKeyCodeMapping(_ event: CGEvent) -> CGEvent? {
    // This is where we would integrate with Kanata's mapping logic
    // For now, we return the original event to maintain compatibility

    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    let eventType = event.type

    // Example: Convert caps lock to escape (this would come from configuration)
    if keyCode == 58, eventType == .keyDown {  // Caps Lock key code
      // Create a new event with escape key code (53)
      if let newEvent = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true) {
        newEvent.flags = event.flags
        newEvent.timestamp = event.timestamp

        // Note: Logging removed from hot path for performance

        return newEvent
      }
    }

    return event
  }

  /// Log event details for debugging
  private func logEvent(_ event: CGEvent) {
    let eventType = event.type
    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    let flags = event.flags

    AppLogger.shared.log(
      "⌨️ [DefaultEventProcessor] Event: type=\(eventType.rawValue), keyCode=\(keyCode), flags=\(flags.rawValue)"
    )
  }

  // MARK: - Configuration Updates

  /// Update the processor configuration
  public func updateConfiguration(_: Configuration) {
    // Note: This is a simple approach. In production, we might want to use atomic updates
    // or other thread-safe mechanisms depending on usage patterns.
  }
}

// MARK: - KeyboardEventProcessing Implementation

extension DefaultEventProcessor: KeyboardEventProcessing {
  public func processKeyboard(
    keyCode: Int,
    eventType: CGEventType,
    flags: CGEventFlags,
    originalEvent event: CGEvent
  ) -> CGEvent? {
    // High-level keyboard event processing
    // This provides a cleaner interface for keyboard-specific logic

    if configuration.logEvents {
      AppLogger.shared.log(
        "⌨️ [DefaultEventProcessor] Keyboard event: keyCode=\(keyCode), type=\(eventType.rawValue)"
      )
    }

    // Apply keyboard-specific transformations
    if let transformedEvent = transformKeyboardEvent(
      keyCode: keyCode,
      eventType: eventType,
      flags: flags,
      originalEvent: event
    ) {
      return transformedEvent
    }

    // Default behavior
    return configuration.suppressEvents ? nil : event
  }

  private func transformKeyboardEvent(
    keyCode: Int,
    eventType _: CGEventType,
    flags _: CGEventFlags,
    originalEvent: CGEvent
  ) -> CGEvent? {
    // Placeholder for keyboard-specific transformations
    // This could integrate with Kanata mapping logic in the future

    // Example transformation: F1 key could trigger a specific action
    if keyCode == 122 {  // F1 key
      AppLogger.shared.log(
        "🔧 [DefaultEventProcessor] F1 key pressed - could trigger special action")
    }

    return originalEvent
  }
}

// MARK: - Factory Methods

extension DefaultEventProcessor {
  /// Create a default event processor for standard KeyPath usage
  public static func standard() -> DefaultEventProcessor {
    DefaultEventProcessor(
      configuration: Configuration(
        suppressEvents: false,
        logEvents: false,
        enableKeyCodeMapping: true
      )
    )
  }

  /// Create an event processor for debugging with full logging
  public static func debugging() -> DefaultEventProcessor {
    DefaultEventProcessor(
      configuration: Configuration(
        suppressEvents: false,
        logEvents: true,
        enableKeyCodeMapping: true
      )
    )
  }

  /// Create an event processor that suppresses all events (for testing)
  public static func suppressing() -> DefaultEventProcessor {
    DefaultEventProcessor(
      configuration: Configuration(
        suppressEvents: true,
        logEvents: false,
        enableKeyCodeMapping: false
      )
    )
  }
}
