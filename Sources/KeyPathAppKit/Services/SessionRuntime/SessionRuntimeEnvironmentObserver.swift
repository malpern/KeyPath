import AppKit
import Darwin
import IOKit
import IOKit.pwr_mgt
import KeyPathCore

/// Owned by one standalone worker; callbacks run on its main CFRunLoop.
/// Uses public SDK power/session APIs and never requests a permission.
@MainActor
final class SessionRuntimeEnvironmentObserver {
    typealias Boundary = SessionRuntimeEnvironmentState.Boundary
    enum PowerEvent { case canSleep, willSleep, willPowerOn, hasPoweredOn }
    private var state: SessionRuntimeEnvironmentState
    private let readConsole: () -> SessionRuntimeConsoleObservation?
    private let onBoundary: (Boundary, (() -> Void)?) -> Void
    private var powerConnection: io_connect_t = 0
    private var powerPort: IONotificationPortRef?
    private var powerNotifier: io_object_t = 0
    private var powerSource: CFRunLoopSource?
    private var notifyTokens: [Int32] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var boundaryReported = false

    init(expectedUID: UInt32,
         readConsole: (() -> SessionRuntimeConsoleObservation?)? = nil,
         onBoundary: @escaping (Boundary, (() -> Void)?) -> Void) {
        state = SessionRuntimeEnvironmentState(expectedUID: expectedUID)
        self.readConsole = readConsole ?? Self.currentConsole
        self.onBoundary = onBoundary
    }

    func start() -> Bool {
        guard powerConnection == 0, notifyTokens.isEmpty, workspaceObservers.isEmpty else { return false }
        powerConnection = IORegisterForSystemPower(
            Unmanaged.passUnretained(self).toOpaque(), &powerPort, { context, _, message, argument in
                guard let context else { return }
                MainActor.assumeIsolated {
                    let observer = Unmanaged<SessionRuntimeEnvironmentObserver>.fromOpaque(context).takeUnretainedValue()
                    observer.powerMessage(message, notificationID: Int(bitPattern: argument))
                }
            }, &powerNotifier
        )
        guard powerConnection != 0, let powerPort,
              let source = IONotificationPortGetRunLoopSource(powerPort)?.takeUnretainedValue() else {
            stop()
            return false
        }
        powerSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        // CGSession.h specifies notify_post names. Polling check tokens keeps
        // their handling on the same run loop as input/output (no actor hop).
        for name in ["com.apple.coregraphics.GUIConsoleSessionChanged",
                     "com.apple.coregraphics.GUISessionUserChanged"] {
            var token: Int32 = 0
            guard notify_register_check(name, &token) == NOTIFY_STATUS_OK else {
                stop()
                return false
            }
            notifyTokens.append(token)
        }
        let center = NSWorkspace.shared.notificationCenter
        for (name, reason) in [(NSWorkspace.willSleepNotification, Boundary.systemWillSleep),
                               (NSWorkspace.sessionDidResignActiveNotification, Boundary.sessionResignedActive)] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                // Workspace callbacks are not assumed to have main-thread delivery.
                if Thread.isMainThread {
                    MainActor.assumeIsolated { self?.retire(reason) }
                } else {
                    CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) { [weak self] in
                        MainActor.assumeIsolated { self?.retire(reason) }
                    }
                    CFRunLoopWakeUp(CFRunLoopGetMain())
                }
            })
        }
        return check()
    }

    func stop() {
        for token in notifyTokens { notify_cancel(token) }
        notifyTokens.removeAll()
        let center = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers { center.removeObserver(observer) }
        workspaceObservers.removeAll()
        if let powerSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .commonModes) }
        powerSource = nil
        if powerNotifier != 0 { IODeregisterForSystemPower(&powerNotifier) }
        powerNotifier = 0
        if let powerPort { IONotificationPortDestroy(powerPort) }
        powerPort = nil
        if powerConnection != 0 { IOServiceClose(powerConnection) }
        powerConnection = 0
    }

    /// Called before accepting input and before posting queued output, as well
    /// as at startup. A missing Quartz dictionary is unavailable, never active.
    @discardableResult
    func check() -> Bool {
        for token in notifyTokens {
            var changed: Int32 = 0
            if notify_check(token, &changed) != NOTIFY_STATUS_OK {
                retire(.consoleObservationUnavailable)
                return false
            }
        }
        if let reason = state.observe(readConsole()) {
            retire(reason)
            return false
        }
        return true
    }

    func retire(_ reason: Boundary, acknowledge: (() -> Void)? = nil) {
        let reason = state.retire(reason)
        guard !boundaryReported else { acknowledge?(); return }
        boundaryReported = true
        onBoundary(reason, acknowledge)
    }

    private func powerMessage(_ message: UInt32, notificationID: Int) {
        let connection = powerConnection
        switch message {
        case UInt32(kIOMessageCanSystemSleep):
            observePowerEvent(.canSleep) { IOAllowPowerChange(connection, notificationID) }
        case UInt32(kIOMessageSystemWillSleep):
            observePowerEvent(.willSleep) { IOAllowPowerChange(connection, notificationID) }
        case UInt32(kIOMessageSystemWillPowerOn):
            observePowerEvent(.willPowerOn)
        case UInt32(kIOMessageSystemHasPoweredOn):
            observePowerEvent(.hasPoweredOn)
        default:
            break
        }
    }

    /// Callback policy seam; tests pass fake acknowledgements and never register
    /// IOKit. Both real power callbacks and tests enter this same boundary.
    func observePowerEvent(_ event: PowerEvent, acknowledge: (() -> Void)? = nil) {
        switch event {
        case .canSleep:
            acknowledge?()
        case .willSleep:
            // finish releases/posts the ledger and publishes its terminal
            // report, then acknowledges using this still-live connection,
            // before unregistering observers and exiting. No veto or retry.
            retire(.systemWillSleep, acknowledge: acknowledge)
        case .willPowerOn:
            // Hardware/disk can still be unavailable in this early callback.
            // Latch retirement without I/O here; subsequent input/tick checks
            // or has-powered-on perform shutdown, never drain the old queues.
            state.retire(.systemWakeObserved)
        case .hasPoweredOn:
            // If will-sleep was missed, a surviving worker must still retire.
            retire(.systemWakeObserved)
        }
    }

    private static func currentConsole() -> SessionRuntimeConsoleObservation? {
        parseConsole(CGSessionCopyCurrentDictionary() as? [String: Any])
    }

    /// Decode the actual public SDK keys without coercing absent/string/bool
    /// user IDs or numeric substitutes for CFBoolean session-state evidence.
    static func parseConsole(_ value: [String: Any]?) -> SessionRuntimeConsoleObservation? {
        guard let dictionary = value,
              let uid = dictionary[kCGSessionUserIDKey as String] as? NSNumber,
              CFGetTypeID(uid) == CFNumberGetTypeID(), uid.doubleValue == Double(uid.uint32Value),
              let onConsole = dictionary[kCGSessionOnConsoleKey as String] as? NSNumber,
              CFGetTypeID(onConsole) == CFBooleanGetTypeID(),
              let loginDone = dictionary[kCGSessionLoginDoneKey as String] as? NSNumber,
              CFGetTypeID(loginDone) == CFBooleanGetTypeID() else { return nil }
        return .init(uid: uid.uint32Value, onConsole: onConsole.boolValue, loginDone: loginDone.boolValue)
    }
}
