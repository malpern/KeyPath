/// Retains an actual AppKit launch event until application dependencies are wired.
/// Both the notification and delegate may deliver that event; startup runs once.
struct ApplicationLaunchGate {
    private var configured = false
    private var launchObserved = false
    private var consumed = false

    mutating func didConfigure() -> Bool {
        configured = true
        return consumeIfReady()
    }

    mutating func didFinishLaunching() -> Bool {
        launchObserved = true
        return consumeIfReady()
    }

    private mutating func consumeIfReady() -> Bool {
        guard configured, launchObserved, !consumed else { return false }
        consumed = true
        return true
    }
}
