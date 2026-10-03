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

        let capabilities = await PermissionOracle.shared.currentProcessCapabilities()
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
        CGEvent.tapEnable(tap: tap, enable: true)

        for number in [SIGTERM, SIGINT, SIGHUP] {
            signal(number, SIG_IGN)
            let signalSource = DispatchSource.makeSignalSource(signal: number, queue: .main)
            signalSource.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.finish(.stopped) }
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
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            finish(.failed, reason: "tap-disabled")
        }
        if IsSecureEventInputEnabled() { finish(.secureInput) }
        physicalPassthroughFlags = event.flags.rawValue & ((1 << 16) | (1 << 23)) // Caps Lock and Fn.
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
        if IsSecureEventInputEnabled() { finish(.secureInput) }
        if ownerPID > 0, kill(ownerPID, 0) != 0 { finish(.stopped, reason: "owner-exited") }
        guard let tap, CGEvent.tapIsEnabled(tap: tap) else { finish(.failed, reason: "tap-disabled") }
        guard let runtime else { finish(.failed, reason: "runtime-unavailable") }
        // Bound each drain so a runaway output queue cannot monopolize the tap.
        for _ in 0 ..< 256 {
            switch runtime.tryReceiveOutput() {
            case .success(nil):
                if Date().timeIntervalSince(lastReport) >= 0.5 { writeReport(.running) }
                return
            case let .success(event?):
                do {
                    let output = try outputs.translate(event)
                    // Publish cleanup state before posting a press. A parent that
                    // observes unexpected process death can release emitted keys.
                    writeReport(.running)
                    post(output)
                    outputCount += 1
                } catch {
                    finish(.failed, reason: "unsupported-output")
                }
            case .failure:
                finish(.failed, reason: "output-channel-unavailable")
            }
        }
        finish(.failed, reason: "output-queue-overrun")
    }

    private func post(_ output: SessionKeyOutput) {
        guard let source = CGEventSource(stateID: .privateState),
              let event = CGEvent(keyboardEventSource: source, virtualKey: output.keyCode, keyDown: output.isDown)
        else { finish(.failed, reason: "output-event-unavailable") }
        event.flags = CGEventFlags(rawValue: output.flags | physicalPassthroughFlags)
        event.setIntegerValueField(.keyboardEventAutorepeat, value: output.isRepeat ? 1 : 0)
        event.setIntegerValueField(.eventSourceUserData, value: Self.outputTag)
        event.post(tap: .cgSessionEventTap)
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

    private func finish(_ state: SessionRuntimeReport.State, reason: String? = nil) -> Never {
        finished = true
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        timer?.invalidate()
        for output in outputs.releaseAll() {
            post(output)
        }
        writeReport(state, failure: reason)
        // Process exit is the shutdown boundary for all detached bridge threads.
        exit(state == .failed ? 1 : 0)
    }
}
