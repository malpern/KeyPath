import AppKit
import Carbon
import KeyPathCore
import KeyPathPermissions
#if KEYPATH_TAP_TIMEOUT_EXPERIMENT
    import CryptoKit
    import Darwin
#endif

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
    private var capsRecord: SessionCapsMappingPolicy.Record?
    private var capsOwner: SessionCapsMappingPolicy.Owner?
    private var capsDirectory: URL?
    private var capsInput = SessionCapsInputState()
    private var capsCheckInFlight = false
    private var lastCapsCheck = Date.distantPast
    private var inputCount: UInt64 = 0
    private var outputCount: UInt64 = 0
    private var lastReport = Date.distantPast
    private var finished = false
    private var physicalPassthroughFlags: UInt64 = 0
    private var physicalModifiers = SessionPhysicalModifierState()
    private var environmentObserver: SessionRuntimeEnvironmentObserver?
    #if KEYPATH_TAP_TIMEOUT_EXPERIMENT
        private var tapTimeoutExperiment: SessionTapTimeoutExperiment?
        private var tapTimeoutInitialization: SessionRuntimeReport.ExperimentalTapTimeoutDiagnostic.Initialization?
        private var rawTapCallbackCount: UInt64 = 0
        private var startupTapDiagnostics: SessionRuntimeReport.ExperimentalTapDiagnostics?
        private var experimentalRawCapabilities: PermissionOracle.PermissionSet?
        private var experimentalRawPosting: PermissionOracle.Status?
        private var registeredTapObservation: SessionRuntimeReport.RegisteredTapObservation?
    #endif

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
        #if KEYPATH_TAP_TIMEOUT_EXPERIMENT
            // Raw API facts remain separate from combined session readiness.
            // Both snapshots are obtained only through the canonical permission owner.
            worker.experimentalRawCapabilities = await PermissionOracle.shared.currentProcessCapabilities()
            worker.experimentalRawPosting = await PermissionOracle.shared.currentProcessEventPostingStatus()
        #endif
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
            finish(.failed, reason: reason.rawValue, acknowledge: acknowledge)
        }
        self.environmentObserver = environmentObserver
        guard environmentObserver.start() else {
            finish(.failed, reason: "environment-observer-registration-failed")
        }
        guard !IsSecureEventInputEnabled() else { finish(.secureInput) }
        let capsDigest: String?
        do {
            capsDigest = try SessionCapsRuntimeSupport.experimentalDevice() != nil
                ? SessionCapsRuntimeSupport.configSHA256(configPath) : nil
        } catch { finish(.failed, reason: "managed-caps-config-identity-unavailable") }
        let admission = SessionCapsRuntimeSupport.validate(configPath: configPath, runtimeHost: .current())
        guard case .valid = admission.result else {
            finish(.failed, reason: "config-requires-advanced-driver-backend-or-is-invalid")
        }
        if admission.managedCaps {
            do {
                guard let capsDigest, try SessionCapsRuntimeSupport.configSHA256(configPath) == capsDigest else {
                    throw SessionCapsRuntimeSupport.Refusal.configIdentity
                }
            } catch { finish(.failed, reason: "managed-caps-config-changed-during-validation") }
        }
        #if KEYPATH_TAP_TIMEOUT_EXPERIMENT
            do {
                tapTimeoutExperiment = try SessionTapTimeoutExperiment(
                    reportURL: reportURL, nonce: nonce, parentPID: ownerPID, configPath: configPath
                )
                tapTimeoutInitialization = .initialized
            } catch let failure as SessionTapTimeoutExperiment.InitializationFailure {
                switch failure {
                case .executableUnavailable: tapTimeoutInitialization = .executableUnavailable
                case .identityDigestUnavailable: tapTimeoutInitialization = .identityDigestUnavailable
                }
            } catch {
                tapTimeoutInitialization = .unexpectedFailure
            }
        #endif
        writeReport(.starting)
        let (_, handle) = KanataHostBridge.createPassthruRuntime(
            runtimeHost: .current(), configPath: configPath, tcpPort: port
        )
        guard let handle else { finish(.failed, reason: "runtime-creation-failed") }
        guard handle.hasSessionInputMap else { finish(.failed, reason: "runtime-input-map-unavailable") }
        runtime = handle
        #if KEYPATH_TAP_TIMEOUT_EXPERIMENT
            startupTapDiagnostics = .init(
                rawTapCallbackCount: 0,
                qMapped: handle.isInputMapped(usagePage: 7, usage: 20),
                aMapped: handle.isInputMapped(usagePage: 7, usage: 4),
                configSHA256: Self.experimentalConfigSHA256(configPath: configPath)
            )
        #endif
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
        CGEvent.tapEnable(tap: tap, enable: false)
        if admission.managedCaps {
            do {
                guard runtime?.isInputMapped(usagePage: 7, usage: 57) == true,
                      let device = try SessionCapsRuntimeSupport.experimentalDevice(), let capsDigest,
                      try SessionCapsRuntimeSupport.configSHA256(configPath) == capsDigest
                else {
                    throw SessionCapsRuntimeSupport.Refusal.configIdentity
                }
                try SessionCapsRuntimeSupport.requirePhysicalAllUp()
                let directory = SessionCapsRuntimeSupport.journalDirectory(configPath: configPath)
                let owner = try SessionCapsMappingPolicy.Owner(uid: getuid(), parentPID: ownerPID, workerPID: getpid(),
                                                               nonce: nonce, generation: nonce,
                                                               bootSessionUUID: SessionCapsRuntimeSupport.bootSessionUUID())
                capsOwner = owner
                capsDirectory = directory
                // The tap is disabled. Keep the main run loop out of startup
                // acquisition; environment shutdown cannot race this writer.
                // Ownership is retained even when write/readback throws.
                capsRecord = try DispatchQueue.global(qos: .userInitiated).sync {
                    let backend = SessionCapsHIDUtilTransport.backend()
                    guard try backend.enumerate() == [device] else { throw SessionCapsRuntimeSupport.Refusal.selection }
                    let lease = SessionCapsMappingLease(directory: directory, backend: backend)
                    return try lease.acquire(owner: owner, configSHA256: capsDigest, device: device)
                }
                try SessionCapsRuntimeSupport.requirePhysicalAllUp()
                capsInput.activate(generation: owner.generation)
            } catch { finish(.failed, reason: "managed-caps-activation-refused") }
        }
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        guard let source else { finish(.failed, reason: "tap-runloop-unavailable") }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        guard environmentObserver.check() else { finish(.failed, reason: "console-session-inactive") }
        CGEvent.tapEnable(tap: tap, enable: true)
        #if KEYPATH_TAP_TIMEOUT_EXPERIMENT
            if let raw = experimentalRawCapabilities {
                registeredTapObservation = Self.observeRegisteredTap(
                    requestedMask: UInt64(mask), accessibility: Self.fact(raw.accessibility),
                    posting: Self.fact(experimentalRawPosting ?? .unknown), listening: Self.fact(raw.inputMonitoring)
                )
            }
            if let failure = Self.registeredTapStartupFailure(registeredTapObservation) {
                finish(.failed, reason: failure)
            }
            guard CGEvent.tapIsEnabled(tap: tap) else {
                finish(.failed, reason: "modifying-tap-not-enabled")
            }
        #endif

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
        #if KEYPATH_TAP_TIMEOUT_EXPERIMENT
            // Includes tagged output, disabled notifications and unmapped input.
            // No event content is retained; saturation avoids counter wraparound.
            if rawTapCallbackCount < UInt64.max { rawTapCallbackCount += 1 }
        #endif
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
        guard let capturedUsage = SessionKeyMap.keyCodeToUsage[UInt16(event.getIntegerValueField(.keyboardEventKeycode))] else {
            return original
        }
        #if KEYPATH_TAP_TIMEOUT_EXPERIMENT
            tapTimeoutExperiment?.delayIfAdmitted(
                keyCode: Int(event.getIntegerValueField(.keyboardEventKeycode)), keyDown: type == .keyDown,
                repeatEvent: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
                mapped: runtime?.isInputMapped(usagePage: 7, usage: capturedUsage) != false,
                heldUsages: outputs.heldUsages.sorted(), reportAge: Date().timeIntervalSince(lastReport),
                now: Date().timeIntervalSince1970, environmentCurrent: environmentObserver?.check() == true,
                secureInput: IsSecureEventInputEnabled()
            )
            guard environmentObserver?.check() == true else {
                finish(.failed, reason: "environment-observer-unavailable")
            }
            if IsSecureEventInputEnabled() { finish(.secureInput) }
        #endif
        let value: UInt64
        if type == .flagsChanged {
            guard SessionKeyMap.isModifier(capturedUsage) else { return original }
            value = event.flags.rawValue & SessionKeyMap.deviceModifierFlag(for: capturedUsage) != 0 ? 1 : 0
        } else {
            value = type == .keyUp ? 0 : (event.getIntegerValueField(.keyboardEventAutorepeat) == 0 ? 1 : 2)
        }
        let usage: UInt32
        if capsRecord == nil {
            guard capturedUsage != 57 else { return original }
            usage = capturedUsage
        } else {
            guard let logical = capsInput.logicalUsage(capturedUsage: capturedUsage, value: value) else { return original }
            usage = logical
        }
        guard runtime?.isInputMapped(usagePage: 7, usage: usage) == true else {
            event.flags = CGEventFlags(rawValue: outputs.modifierFlags | physicalPassthroughFlags)
            return original
        }
        // Do not consume a release/repeat for a press that preceded this tap.
        if value != 1, !inputs.contains(usage) { return original }
        guard send(value: value, usage: usage) else { return original }
        if let owner = capsRecord?.owner {
            capsInput.didAdmit(capturedUsage: capturedUsage, value: value, generation: owner.generation)
        }
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
        #if KEYPATH_TAP_TIMEOUT_EXPERIMENT
            tapTimeoutExperiment?.prepare(now: Date().timeIntervalSince1970)
        #endif
        checkCapsOwnershipIfNeeded()
        // Bound each drain so a runaway output queue cannot monopolize the tap.
        for _ in 0 ..< 256 {
            switch runtime.tryReceiveOutput() {
            case .success(nil):
                if Date().timeIntervalSince(lastReport) >= 0.5 { writeReport(.running) }
                return
            case let .success(event?):
                if capsRecord != nil, event.usagePage == 7, event.usage == 109 {
                    finish(.failed, reason: "managed-caps-reserved-output")
                }
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

    private func checkCapsOwnershipIfNeeded() {
        guard let record = capsRecord, !capsCheckInFlight,
              Date().timeIntervalSince(lastCapsCheck) >= 0.5 else { return }
        capsCheckInFlight = true
        lastCapsCheck = Date()
        guard let directory = capsDirectory else { finish(.failed, reason: "managed-caps-directory-unavailable") }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let valid: Bool
            do { try SessionCapsRuntimeSupport.verifyActive(directory: directory, owner: record.owner); valid = true }
            catch { valid = false }
            CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, !self.finished, self.capsRecord?.owner == record.owner else { return }
                    self.capsCheckInFlight = false
                    if !valid { self.finish(.failed, reason: "managed-caps-ownership-lost") }
                }
            }
            CFRunLoopWakeUp(CFRunLoopGetMain())
        }
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

    #if KEYPATH_TAP_TIMEOUT_EXPERIMENT
        /// Native SDK layout checked before the experimental C API query.
        static var experimentalTapABIIsExpected: Bool {
            MemoryLayout<CGEventTapInformation>.size == 48 && MemoryLayout<CGEventTapInformation>.alignment == 8
                && MemoryLayout<CGEventTapInformation>.offset(of: \.eventTapID) == 0
                && MemoryLayout<CGEventTapInformation>.offset(of: \.tapPoint) == 4
                && MemoryLayout<CGEventTapInformation>.offset(of: \.options) == 8
                && MemoryLayout<CGEventTapInformation>.offset(of: \.eventsOfInterest) == 16
                && MemoryLayout<CGEventTapInformation>.offset(of: \.tappingProcess) == 24
                && MemoryLayout<CGEventTapInformation>.offset(of: \.processBeingTapped) == 28
                && MemoryLayout<CGEventTapInformation>.offset(of: \.enabled) == 32
                && MemoryLayout<CGEventTapInformation>.offset(of: \.minUsecLatency) == 36
                && MemoryLayout<CGEventTapInformation>.offset(of: \.avgUsecLatency) == 40
                && MemoryLayout<CGEventTapInformation>.offset(of: \.maxUsecLatency) == 44
        }

        static func fact(_ status: PermissionOracle.Status) -> String {
            switch status {
            case .granted: "granted"
            case .denied: "denied"
            case .unknown: "unknown"
            case .error: "error"
            }
        }

        /// One worker-self query, no input/prompt. Enumeration resets global tap latency extrema.
        /// Permission facts were sampled through the Oracle before starting this worker's tap.
        static func observeRegisteredTap(requestedMask: UInt64, accessibility: String, posting: String,
                                         listening: String) -> SessionRuntimeReport.RegisteredTapObservation
        {
            guard experimentalTapABIIsExpected else {
                return classifyRegisteredTaps(requestedMask: requestedMask, taps: [], count: 0, error: .success,
                                              abiIsExpected: false, ownPID: getpid(), accessibility: accessibility, posting: posting, listening: listening)
            }
            var taps = [CGEventTapInformation](repeating: CGEventTapInformation(), count: 128)
            var count: UInt32 = 0
            let error = taps.withUnsafeMutableBufferPointer { CGGetEventTapList(128, $0.baseAddress, &count) }
            return classifyRegisteredTaps(requestedMask: requestedMask, taps: taps, count: count, error: error,
                                          abiIsExpected: true, ownPID: getpid(), accessibility: accessibility, posting: posting, listening: listening)
        }

        /// Experimental admission uses registration evidence, not an unconditional permission rule.
        /// Full registered bits are necessary here; they do not prove physical delivery.
        static func registeredTapStartupFailure(_ observation: SessionRuntimeReport.RegisteredTapObservation?) -> String? {
            guard let observation else { return "modifying-tap-registration-unavailable" }
            guard observation.outcome == .observed, observation.rows.count == 1 else {
                return "modifying-tap-registration-unverified"
            }
            guard observation.requestedBitsPresent else { return "modifying-tap-missing-requested-events" }
            guard observation.rows[0].enabled else { return "modifying-tap-not-enabled" }
            return nil
        }

        /// Pure interpretation of the single bounded query; does not itself decide readiness.
        static func classifyRegisteredTaps(requestedMask: UInt64, taps: [CGEventTapInformation], count: UInt32,
                                           error: CGError, abiIsExpected: Bool, ownPID: pid_t, accessibility: String, posting: String,
                                           listening: String) -> SessionRuntimeReport.RegisteredTapObservation
        {
            typealias Observation = SessionRuntimeReport.RegisteredTapObservation
            func result(_ outcome: Observation.Outcome, _ rows: [Observation.Row] = []) -> Observation {
                Observation(outcome: outcome, requestedMask: requestedMask, rows: rows,
                            rawAccessibility: accessibility, rawPostEvent: posting, rawListenEvent: listening,
                            enumerationAttempted: abiIsExpected)
            }
            guard abiIsExpected else { return result(.unexpectedABI) }
            guard error == .success else { return result(.apiFailure) }
            guard count <= 128, Int(count) <= taps.count else { return result(.capacityExceeded) }
            let rows = taps.prefix(Int(count)).filter {
                $0.tappingProcess == ownPID && $0.tapPoint == .cgSessionEventTap && $0.options == .defaultTap
            }.map { Observation.Row(mask: $0.eventsOfInterest, enabled: $0.enabled) }
            return result(rows.isEmpty ? .absent : rows.count == 1 ? .observed : .multiple, rows)
        }

        nonisolated static func experimentalConfigSHA256(configPath: String) -> String? {
            let descriptor = Darwin.open(configPath, O_RDONLY | O_NONBLOCK | O_NOFOLLOW)
            guard descriptor >= 0 else { return nil }
            let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            defer { try? file.close() }
            var metadata = stat()
            guard fstat(file.fileDescriptor, &metadata) == 0,
                  metadata.st_mode & S_IFMT == S_IFREG,
                  metadata.st_size >= 0, metadata.st_size <= 65536,
                  let data = try? file.read(upToCount: 65537), data.count <= 65536
            else { return nil }
            return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
    #endif

    private func writeReport(_ state: SessionRuntimeReport.State, failure: String? = nil) {
        var diagnostics: SessionRuntimeReport.ExperimentalTapDiagnostics?
        var timeoutDiagnostic: SessionRuntimeReport.ExperimentalTapTimeoutDiagnostic?
        #if KEYPATH_TAP_TIMEOUT_EXPERIMENT
            if let tapTimeoutInitialization {
                timeoutDiagnostic = tapTimeoutExperiment?.reportDiagnostic
                    ?? .init(initialization: tapTimeoutInitialization, preparation: .notAttempted,
                             callbackFirstResult: .notObserved)
            }
            if let startupTapDiagnostics {
                diagnostics = .init(
                    rawTapCallbackCount: rawTapCallbackCount,
                    qMapped: startupTapDiagnostics.qMapped, aMapped: startupTapDiagnostics.aMapped,
                    configSHA256: startupTapDiagnostics.configSHA256, registeredTap: registeredTapObservation
                )
            }
        #endif
        let report = SessionRuntimeReport(
            nonce: nonce, pid: getpid(), uid: getuid(), state: state,
            accessibility: capabilities.accessibility.isReady,
            effectiveInputAccess: capabilities.inputMonitoring.isReady,
            tapActive: tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false,
            tcpPort: port, inputCount: inputCount, outputCount: outputCount, failure: failure,
            heldOutputUsages: outputs.heldUsages.sorted(), inputAccessSource: capabilities.source,
            experimentalTapDiagnostics: diagnostics, experimentalTapTimeout: timeoutDiagnostic,
            managedCapsGeneration: capsRecord?.owner.generation
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

    /// Failed event allocation retains exactly the unreleased owned ledger.
    /// The injected posting closure lets tests exercise this production loop
    /// without creating a CGEvent or terminating a host process.
    static func releaseOwnedOutputs(
        _ outputs: inout SessionOutputState, post: (SessionKeyOutput) -> Bool
    ) {
        var pending = outputs
        for output in pending.releaseAll() {
            if post(output), let usage = SessionKeyMap.keyCodeToUsage[output.keyCode] {
                _ = try? outputs.translate(.init(value: 0, usagePage: 7, usage: usage))
            }
        }
    }

    private func finish(
        _ state: SessionRuntimeReport.State, reason: String? = nil,
        acknowledge: (() -> Void)? = nil
    ) -> Never {
        finished = true
        capsInput.revoke()
        var terminalState = state
        var terminalReason = reason
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        timer?.invalidate()
        Self.completeTermination(releaseOutputs: {
            // Allocation failure during shutdown cannot recursively exit before
            // the power ACK. Preserve unposted releases in the crash ledger.
            var remaining = outputs
            Self.releaseOwnedOutputs(&remaining, post: post)
            outputs = remaining
            if let owner = capsOwner, let directory = capsDirectory {
                do {
                    try DispatchQueue.global(qos: .userInitiated).sync {
                        try SessionCapsRuntimeSupport.recoverPending(directory: directory, expectedOwner: owner)
                    }
                    capsRecord = nil
                    capsOwner = nil
                    capsDirectory = nil
                } catch {
                    terminalState = .failed
                    terminalReason = "managed-caps-restoration-pending"
                }
            }
        }, publishTerminalReport: {
            writeReport(terminalState, failure: terminalReason)
        }, acknowledge: acknowledge, unregisterObservers: {
            environmentObserver?.stop()
        })
        // Process exit is the shutdown boundary for all detached bridge threads.
        exit(terminalState == .failed ? 1 : 0)
    }
}
