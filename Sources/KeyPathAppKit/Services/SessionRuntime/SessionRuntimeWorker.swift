import AppKit
import Carbon
import KeyPathCore
import KeyPathPermissions

/// Runs before SwiftUI/bootstrap in a separate instance of the same signed app.
/// Process isolation is intentional: the current Kanata TCP/processing APIs do
/// not expose a joinable shutdown, so their library must live until process exit.
@MainActor
public final class SessionRuntimeWorker {
    private static let outputTag: Int64 = 0x4B50_5345_5353_494F
    private let reportURL: URL
    private let nonce: String
    private let ownerPID: Int32
    private let port: UInt16
    private let capabilities: PermissionOracle.PermissionSet
    private var runtime: KanataHostBridgePassthruRuntimeHandle?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var timer: Timer?
    private var signals: [DispatchSourceSignal] = []
    private var outputs = SessionOutputState()
    private var inputs: Set<UInt32> = []
    private var inputCount: UInt64 = 0
    private var outputCount: UInt64 = 0
    private var lastReport = Date.distantPast
    private var finished = false
    private var physicalPassthroughFlags: UInt64 = 0
    private var physicalModifiers = SessionPhysicalModifierState()
    private var environmentObserver: SessionRuntimeEnvironmentObserver?

    private init(
        reportURL: URL, nonce: String, ownerPID: Int32, port: UInt16,
        capabilities: PermissionOracle.PermissionSet
    ) {
        self.reportURL = reportURL
        self.nonce = nonce
        self.ownerPID = ownerPID
        self.port = port
        self.capabilities = capabilities
    }

    /// Returns false for an ordinary app launch. Worker modes never initialize
    /// the UI, helper repair, service monitoring or the privileged installer.
    public static func runIfRequested() async -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--session-runtime") || arguments.contains("--session-capabilities") else {
            return false
        }
        func argument(_ name: String) -> String? {
            guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        }
        guard getuid() != 0,
              let path = argument("--session-report"),
              let nonce = argument("--session-nonce"), UUID(uuidString: nonce) != nil
        else { exit(64) }

        let capabilities = await SystemStateProvider.shared.currentProcessPermissionCapabilities()
        let worker = SessionRuntimeWorker(
            reportURL: URL(fileURLWithPath: path), nonce: nonce,
            ownerPID: argument("--session-owner").flatMap(Int32.init) ?? 0,
            port: argument("--session-port").flatMap(UInt16.init) ?? 0,
            capabilities: capabilities
        )
        if arguments.contains("--session-capabilities") {
            worker.writeReport(.capabilities)
            exit(0)
        }
        guard let config = argument("--session-config") else {
            worker.finish(.failed, reason: "missing-config")
        }
        worker.start(configPath: config)
        // Keep the worker and loaded bridge alive through process termination;
        // dropping a runtime cannot stop its detached TCP listener threads.
        worker.runLoop()
    }

    private func runLoop() -> Never {
        CFRunLoopRun()
        finish(.stopped)
    }

    private func start(configPath: String) {
        guard capabilities.hasAllPermissions else {
            finish(.failed, reason: "missing-current-process-permission")
        }
        let environmentObserver = SessionRuntimeEnvironmentObserver(expectedUID: getuid()) { [weak self] reason, acknowledge in
            guard let self else { acknowledge?(); return }
            self.finish(.failed, reason: reason.rawValue, acknowledge: acknowledge)
        }
        self.environmentObserver = environmentObserver
        guard environmentObserver.start() else {
            finish(.failed, reason: "environment-observer-registration-failed")
        }
        guard !IsSecureEventInputEnabled() else { finish(.secureInput) }
        let validation = KanataHostBridge.validateSessionConfig(
            runtimeHost: .current(), configPath: configPath,
            supportedUsages: SessionKeyMap.keyCodeToUsage.values.filter { $0 != 57 }.sorted()
        )
        guard case .valid = validation else {
            finish(.failed, reason: "config-requires-advanced-driver-backend-or-is-invalid")
        }
        writeReport(.starting)
        let (_, handle) = KanataHostBridge.createPassthruRuntime(
            runtimeHost: .current(), configPath: configPath, tcpPort: port
        )
        guard let handle else { finish(.failed, reason: "runtime-creation-failed") }
        guard handle.hasSessionInputMap else { finish(.failed, reason: "runtime-input-map-unavailable") }
        runtime = handle
        guard case .success = handle.start() else {
            finish(.failed, reason: "runtime-start-failed")
        }

        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: CGEventMask(mask), callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let consume = MainActor.assumeIsolated {
                    let worker = Unmanaged<SessionRuntimeWorker>.fromOpaque(context).takeUnretainedValue()
                    return worker.receive(type: type, event: event) == nil
                }
                return consume ? nil : Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        guard let tap else { finish(.failed, reason: "modifying-tap-unavailable") }
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        guard let source else { finish(.failed, reason: "tap-runloop-unavailable") }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        guard environmentObserver.check() else { finish(.failed, reason: "console-session-inactive") }
        CGEvent.tapEnable(tap: tap, enable: true)

        for number in [SIGTERM, SIGINT, SIGHUP] {
            signal(number, SIG_IGN)
            // The standalone worker drives CFRunLoop directly; it does not run
            // NSApplication's main-dispatch servicing. Deliver shutdown onto
            // that run loop rather than queueing a main-dispatch handler.
            let signalSource = DispatchSource.makeSignalSource(signal: number, queue: .global())
            signalSource.setEventHandler { @Sendable [weak self] in
                CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) { [weak self] in
                    MainActor.assumeIsolated { self?.finish(.stopped) }
                }
                CFRunLoopWakeUp(CFRunLoopGetMain())
            }
            signals.append(signalSource)
            signalSource.resume()
        }
        timer = Timer(timeInterval: 0.005, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer!, forMode: .common)
        writeReport(.running)
    }

    private func receive(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let original = Unmanaged.passUnretained(event)
        if finished || event.getIntegerValueField(.eventSourceUserData) == Self.outputTag { return original }
        if type == .tapDisabledByTimeout {
            finish(.failed, reason: "tap-disabled-by-timeout")
        }
        if type == .tapDisabledByUserInput {
            finish(.failed, reason: "tap-disabled-by-user-input")
        }
        guard environmentObserver?.check() == true else {
            finish(.failed, reason: "environment-observer-unavailable")
        }
        if IsSecureEventInputEnabled() { finish(.secureInput) }
        physicalPassthroughFlags = physicalModifiers.passthroughFlags(
            keyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)),
            isFlagsChanged: type == .flagsChanged, flags: event.flags.rawValue
        )
        for modifier: UInt32 in 224 ... 231 {
            if runtime?.isInputMapped(usagePage: 7, usage: modifier) == false,
               event.flags.rawValue & SessionKeyMap.deviceModifierFlag(for: modifier) != 0
            {
                physicalPassthroughFlags |= SessionKeyMap.modifierFlags(for: modifier)
            }
        }
        guard let usage = SessionKeyMap.keyCodeToUsage[UInt16(event.getIntegerValueField(.keyboardEventKeycode))] else {
            return original
        }
        // Caps Lock's WindowServer toggle is upstream of the session tap. Leave
        // it physical and reject configurations that try to remap it.
        if usage == 57 { return original }
        guard runtime?.isInputMapped(usagePage: 7, usage: usage) == true else {
            event.flags = CGEventFlags(rawValue: outputs.modifierFlags | physicalPassthroughFlags)
            return original
        }
        let value: UInt64
        if type == .flagsChanged {
            guard SessionKeyMap.isModifier(usage) else { return original }
            let deviceFlag = SessionKeyMap.deviceModifierFlag(for: usage)
            value = event.flags.rawValue & deviceFlag != 0 ? 1 : 0
        } else {
            value = type == .keyUp ? 0 : (event.getIntegerValueField(.keyboardEventAutorepeat) == 0 ? 1 : 2)
        }
        // Do not consume a release/repeat for a press that preceded this tap.
        if value != 1, !inputs.contains(usage) { return original }
        guard send(value: value, usage: usage) else { return original }
        if value == 0 { inputs.remove(usage) } else { inputs.insert(usage) }
        return nil
    }

    private func send(value: UInt64, usage: UInt32) -> Bool {
        guard let runtime, case .success = runtime.sendInput(value: value, usagePage: 7, usage: usage) else {
            finish(.failed, reason: "input-queue-unavailable")
        }
        inputCount += 1
        return true
    }

    private func tick() {
        guard !finished else { return }
        guard environmentObserver?.check() == true else {
            finish(.failed, reason: "environment-observer-unavailable")
        }
        if IsSecureEventInputEnabled() { finish(.secureInput) }
        if ownerPID > 0, !SystemStateProvider.shared.isProcessAlive(pid: ownerPID) { finish(.stopped, reason: "owner-exited") }
        guard let tap, CGEvent.tapIsEnabled(tap: tap) else { finish(.failed, reason: "tap-disabled-observed") }
        guard let runtime else { finish(.failed, reason: "runtime-unavailable") }
        // Bound each drain so a runaway output queue cannot monopolize the tap.
        for _ in 0 ..< 256 {
            switch runtime.tryReceiveOutput() {
            case .success(nil):
                if Date().timeIntervalSince(lastReport) >= 0.5 { writeReport(.running) }
                return
            case let .success(event?):
                do {
                    // Refresh immediately before each queued event as well as
                    // before the drain; a console change can race a long drain.
                    guard environmentObserver?.check() == true else {
                        finish(.failed, reason: "environment-observer-unavailable")
                    }
                    var nextOutputs = outputs
                    let output = try nextOutputs.translate(event)
                    // Publish a press before posting it, but retain a release in
                    // the durable ledger until its key-up has been posted. Death
                    // between these operations leaves a conservative cleanup set.
                    if output.isDown {
                        outputs = nextOutputs
                        writeReport(.running)
                    }
                    guard environmentObserver?.check() == true else {
                        finish(.failed, reason: "environment-observer-unavailable")
                    }
                    guard post(output) else { finish(.failed, reason: "output-event-unavailable") }
                    outputCount += 1
                    if !output.isDown {
                        outputs = nextOutputs
                        writeReport(.running)
                    }
                } catch {
                    finish(.failed, reason: "unsupported-output")
                }
            case .failure:
                finish(.failed, reason: "output-channel-unavailable")
            }
        }
        finish(.failed, reason: "output-queue-overrun")
    }

    private func post(_ output: SessionKeyOutput) -> Bool {
        guard let source = CGEventSource(stateID: .privateState),
              let event = CGEvent(keyboardEventSource: source, virtualKey: output.keyCode, keyDown: output.isDown)
        else { return false }
        event.flags = CGEventFlags(rawValue: output.flags | physicalPassthroughFlags)
        event.setIntegerValueField(.keyboardEventAutorepeat, value: output.isRepeat ? 1 : 0)
        event.setIntegerValueField(.eventSourceUserData, value: Self.outputTag)
        event.post(tap: .cgSessionEventTap)
        return true
    }

    private func writeReport(_ state: SessionRuntimeReport.State, failure: String? = nil) {
        let report = SessionRuntimeReport(
            nonce: nonce, pid: getpid(), uid: getuid(), state: state,
            accessibility: capabilities.accessibility.isReady,
            effectiveInputAccess: capabilities.inputMonitoring.isReady,
            tapActive: tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false,
            tcpPort: port, inputCount: inputCount, outputCount: outputCount, failure: failure,
            heldOutputUsages: outputs.heldUsages.sorted()
        )
        do {
            try JSONEncoder().encode(report).write(to: reportURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: reportURL.path)
            lastReport = report.timestamp
        } catch {
            if !finished { finish(.failed, reason: "report-write-failed") }
        }
    }

    /// The production shutdown ordering is also exercised without OS events or
    /// process exit in tests. A power acknowledgement must precede unregister.
    static func completeTermination(
        releaseOutputs: () -> Void, publishTerminalReport: () -> Void,
        acknowledge: (() -> Void)?, unregisterObservers: () -> Void
    ) {
        releaseOutputs()
        publishTerminalReport()
        acknowledge?()
        unregisterObservers()
    }

    private func finish(
        _ state: SessionRuntimeReport.State, reason: String? = nil,
        acknowledge: (() -> Void)? = nil
    ) -> Never {
        finished = true
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        timer?.invalidate()
        Self.completeTermination(releaseOutputs: {
            // Allocation failure during shutdown cannot recursively exit before
            // the power ACK. Preserve unposted releases in the crash ledger.
            var pending = outputs
            for output in pending.releaseAll() {
                if post(output), let usage = SessionKeyMap.keyCodeToUsage[output.keyCode] {
                    _ = try? outputs.translate(.init(value: 0, usagePage: 7, usage: usage))
                }
            }
        }, publishTerminalReport: {
            writeReport(state, failure: reason)
        }, acknowledge: acknowledge, unregisterObservers: {
            environmentObserver?.stop()
        })
        // Process exit is the shutdown boundary for all detached bridge threads.
        exit(state == .failed ? 1 : 0)
    }
}
