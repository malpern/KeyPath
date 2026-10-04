/// Selected public Quartz-session evidence, never input or window contents.
public struct SessionRuntimeConsoleObservation: Equatable, Sendable {
    public let uid: UInt32
    public let onConsole: Bool
    public let loginDone: Bool

    public init(uid: UInt32, onConsole: Bool, loginDone: Bool) {
        self.uid = uid
        self.onConsole = onConsole
        self.loginDone = loginDone
    }
}

/// An inactive boundary retires this worker permanently. Wake/session return
/// cannot resurrect its queued input or output; recovery needs a new launch.
public struct SessionRuntimeEnvironmentState: Sendable {
    public enum Boundary: String, Equatable, Sendable {
        case systemWillSleep = "system-will-sleep"
        case systemWakeObserved = "system-wake-observed"
        case sessionResignedActive = "session-resigned-active"
        case consoleSessionChangeObserved = "console-session-change-observed"
        case consoleObservationUnavailable = "console-observation-unavailable"
        case consoleSessionInactive = "console-session-inactive"
    }

    public let expectedUID: UInt32
    public private(set) var boundary: Boundary?

    public init(expectedUID: UInt32) { self.expectedUID = expectedUID }

    @discardableResult
    public mutating func retire(_ reason: Boundary) -> Boundary {
        if boundary == nil { boundary = reason }
        return boundary!
    }

    @discardableResult
    public mutating func observe(_ observation: SessionRuntimeConsoleObservation?) -> Boundary? {
        if let boundary { return boundary }
        guard let observation else { return retire(.consoleObservationUnavailable) }
        guard expectedUID != 0, observation.uid == expectedUID,
              observation.onConsole, observation.loginDone else {
            return retire(.consoleSessionInactive)
        }
        return nil
    }
}
