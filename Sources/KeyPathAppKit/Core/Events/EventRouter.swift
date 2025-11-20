import CoreGraphics
import Foundation
import KeyPathCore

/// Scope-based filtering for event processing
public enum EventScope {
  case keyboard
  case mouse
  case all
}

/// Result of event routing through the processing chain
public struct EventRoutingResult {
  /// The processed event, or nil if suppressed
  public let processedEvent: CGEvent?

  /// Whether the event was modified during processing
  public let wasModified: Bool

  /// Which processor handled the event (for debugging)
  public let handledBy: String?

  /// Whether processing was terminated early
  public let terminatedEarly: Bool

  public init(
    processedEvent: CGEvent?,
    wasModified: Bool = false,
    handledBy: String? = nil,
    terminatedEarly: Bool = false
  ) {
    self.processedEvent = processedEvent
    self.wasModified = wasModified
    self.handledBy = handledBy
    self.terminatedEarly = terminatedEarly
  }
}

/// Central event router that manages a chain of event processors
@MainActor
public final class EventRouter {
  private var processors: [EventProcessing] = []
  private var processorNames: [String] = []
  private let queue = DispatchQueue(label: "com.keypath.eventrouter", qos: .userInteractive)

  public init() {}

  /// Add a processor to the end of the processing chain
  public func addProcessor(_ processor: EventProcessing, name: String) {
    queue.sync {
      processors.append(processor)
      processorNames.append(name)
    }
    AppLogger.shared.log("📋 [EventRouter] Added processor: \(name)")
  }

  /// Insert a processor at a specific position in the chain
  public func insertProcessor(_ processor: EventProcessing, name: String, at index: Int) {
    queue.sync {
      let safeIndex = max(0, min(index, processors.count))
      processors.insert(processor, at: safeIndex)
      processorNames.insert(name, at: safeIndex)
    }
    AppLogger.shared.log("📋 [EventRouter] Inserted processor: \(name) at index \(index)")
  }

  /// Remove a processor by name
  public func removeProcessor(named name: String) {
    queue.sync {
      if let index = processorNames.firstIndex(of: name) {
        processors.remove(at: index)
        processorNames.remove(at: index)
        AppLogger.shared.log("📋 [EventRouter] Removed processor: \(name)")
      }
    }
  }

  /// Remove all processors
  public func clearProcessors() {
    queue.sync {
      processors.removeAll()
      processorNames.removeAll()
    }
    AppLogger.shared.log("📋 [EventRouter] Cleared all processors")
  }

  /// Get current processor names (for debugging)
  public func getProcessorNames() -> [String] {
    queue.sync {
      processorNames
    }
  }

  /// Route an event through the processing chain
  public func route(
    event: CGEvent,
    location: CGEventTapLocation,
    proxy: CGEventTapProxy,
    scope: EventScope
  ) -> EventRoutingResult {
    // Check if the event matches the requested scope
    guard shouldProcessForScope(event: event, scope: scope) else {
      return EventRoutingResult(processedEvent: event, wasModified: false)
    }

    var currentEvent: CGEvent? = event
    var wasModified = false
    var handledBy: String?
    guard let originalEvent = event.copy() else {
      return EventRoutingResult(processedEvent: event, wasModified: false)
    }

    // Process through each processor in order
    let (currentProcessors, currentNames) = queue.sync { (processors, processorNames) }

    for (index, processor) in currentProcessors.enumerated() {
      guard let eventToProcess = currentEvent else {
        // Event was suppressed by a previous processor
        return EventRoutingResult(
          processedEvent: nil,
          wasModified: wasModified,
          handledBy: handledBy,
          terminatedEarly: true
        )
      }

      let processorName = currentNames[index]

      do {
        let result = processor.process(
          event: eventToProcess,
          location: location,
          proxy: proxy
        )

        if result == nil {
          // Event was suppressed (no logging in hot path for performance)
          return EventRoutingResult(
            processedEvent: nil,
            wasModified: true,
            handledBy: processorName,
            terminatedEarly: false
          )
        }

        // Check if the event was modified
        if !wasModified, let resultEvent = result, !eventsEqual(originalEvent, resultEvent) {
          wasModified = true
          handledBy = processorName
        }

        currentEvent = result
      }
    }

    return EventRoutingResult(
      processedEvent: currentEvent,
      wasModified: wasModified,
      handledBy: handledBy,
      terminatedEarly: false
    )
  }

  /// Convenience method for simplified event routing
  public func route(event: CGEvent, scope: EventScope = .all) -> CGEvent? {
    let dummyProxy = CGEventTapProxy(bitPattern: 0)!
    let result = route(
      event: event,
      location: .cgSessionEventTap,
      proxy: dummyProxy,
      scope: scope
    )
    return result.processedEvent
  }

  // MARK: - Private Methods

  private func shouldProcessForScope(event: CGEvent, scope: EventScope) -> Bool {
    let eventType = event.type

    switch scope {
    case .keyboard:
      return eventType == .keyDown || eventType == .keyUp || eventType == .flagsChanged
    case .mouse:
      return eventType == .leftMouseDown || eventType == .leftMouseUp
        || eventType == .rightMouseDown || eventType == .rightMouseUp || eventType == .mouseMoved
        || eventType == .leftMouseDragged || eventType == .rightMouseDragged
        || eventType == .scrollWheel
    case .all:
      return true
    }
  }

  private func eventsEqual(_ event1: CGEvent, _ event2: CGEvent) -> Bool {
    // Basic event comparison - this could be enhanced for more thorough comparison
    event1.type == event2.type
      && event1.getIntegerValueField(.keyboardEventKeycode)
        == event2.getIntegerValueField(.keyboardEventKeycode)
      && event1.flags == event2.flags
  }
}

/// Default event router instance for global access
@MainActor public let defaultEventRouter = EventRouter()

// MARK: - Convenience Extensions

@MainActor extension EventProcessing {
  /// Register this processor with the default event router
  public func register(as name: String) {
    defaultEventRouter.addProcessor(self, name: name)
  }

  /// Unregister this processor from the default event router
  public func unregister(name: String) {
    defaultEventRouter.removeProcessor(named: name)
  }
}
