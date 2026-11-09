import CoreGraphics

/// Creates a tap that observes keys without changing them.
///
/// A listen-only tap is preferred because it can never delay input, but macOS 27
/// grants one only with Input Monitoring, which KeyPath does not ask for. When it
/// is refused, a modifying tap that passes every event through is used instead:
/// Device Control and Data Access permits that. Its callback must return the event.
enum ObservingEventTap {
    static func create(
        location: CGEventTapLocation = .cgSessionEventTap,
        place: CGEventTapPlacement,
        events: CGEventMask,
        callback: CGEventTapCallBack,
        userInfo: UnsafeMutableRawPointer?
    ) -> (tap: CFMachPort, passThrough: Bool)? {
        for options in [CGEventTapOptions.listenOnly, .defaultTap] {
            if let tap = CGEvent.tapCreate(
                tap: location, place: place, options: options,
                eventsOfInterest: events, callback: callback, userInfo: userInfo
            ) {
                return (tap, options == .defaultTap)
            }
        }
        return nil
    }
}
