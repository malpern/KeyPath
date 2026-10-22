import CoreGraphics

/// Remap hardware input, preserving shortcuts and text injected by other apps.
enum SessionInputEventPolicy {
    static func isSoftwareKeyboardEvent(type: CGEventType, event: CGEvent) -> Bool {
        switch type {
        case .keyDown, .keyUp, .flagsChanged:
            // Hardware events have no originating process. Software producers can
            // set aggregate modifiers without separate physical modifier events.
            event.getIntegerValueField(.eventSourceUnixProcessID) > 0
        default:
            // Tap-disabled notifications must still reach the worker's recovery.
            false
        }
    }
}
