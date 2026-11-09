@preconcurrency import CoreFoundation
@preconcurrency import CoreGraphics
import Foundation

/// A tap that observes keys without changing them, on its own thread.
///
/// A listen-only tap needs Input Monitoring, which KeyPath does not ask for on
/// macOS 27. Without it this falls back to a modifying tap that passes every
/// event through, which Device Control and Data Access permits. A modifying tap
/// holds each event until its callback returns, so the tap runs on a dedicated
/// thread: a busy main thread can never delay typing. The handler is called on
/// that thread and must return quickly; callers hop to the main actor themselves.
/// If macOS disables the tap (timeout or user input), it is re-enabled.
final class ObservingEventTap: @unchecked Sendable {
    typealias Handler = @Sendable (CGEventType, CGEvent) -> Void

    let passThrough: Bool
    private let handler: Handler
    private var tap: CFMachPort?
    private var runLoop: CFRunLoop?
    private let lock = NSLock()

    private init(passThrough: Bool, handler: @escaping Handler) {
        self.passThrough = passThrough
        self.handler = handler
    }

    /// Only asks for listen-only when it is already allowed, so creating the tap
    /// never prompts for Input Monitoring.
    static func preferredOptions(listenAllowed: Bool) -> [CGEventTapOptions] {
        listenAllowed ? [.listenOnly, .defaultTap] : [.defaultTap]
    }

    static func start(
        place: CGEventTapPlacement,
        events: CGEventMask,
        threadName: String,
        handler: @escaping Handler
    ) -> ObservingEventTap? {
        for options in preferredOptions(listenAllowed: CGPreflightListenEventAccess()) {
            let observer = ObservingEventTap(passThrough: options == .defaultTap, handler: handler)
            let userInfo = Unmanaged.passUnretained(observer).toOpaque()
            guard let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap, place: place, options: options,
                eventsOfInterest: events, callback: ObservingEventTap.callback, userInfo: userInfo
            ) else { continue }
            observer.tap = tap
            observer.run(threadName: threadName)
            return observer
        }
        return nil
    }

    private static let callback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else { return Unmanaged.passUnretained(event) }
        let observer = Unmanaged<ObservingEventTap>.fromOpaque(refcon).takeUnretainedValue()
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            observer.lock.lock()
            let tap = observer.tap
            observer.lock.unlock()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        observer.handler(type, event)
        return Unmanaged.passUnretained(event)
    }

    private func run(threadName: String) {
        guard let machPort = tap,
              let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, machPort, 0)
        else { return }
        let ready = DispatchSemaphore(value: 0)
        // Handed to the tap's own thread once and only used there.
        nonisolated(unsafe) let source = runLoopSource
        nonisolated(unsafe) let tap = machPort
        let thread = Thread { [self] in
            let current = CFRunLoopGetCurrent()!
            lock.lock()
            runLoop = current
            lock.unlock()
            CFRunLoopAddSource(current, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            ready.signal()
            CFRunLoopRun()
            CFRunLoopRemoveSource(current, source, .commonModes)
        }
        thread.name = threadName
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
    }

    /// Stops the tap and its thread. Safe to call more than once.
    func stop() {
        lock.lock()
        let tap = tap
        let runLoop = runLoop
        self.tap = nil
        self.runLoop = nil
        lock.unlock()
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoop { CFRunLoopStop(runLoop) }
    }

    deinit { stop() }
}
