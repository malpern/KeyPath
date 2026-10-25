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
    private enum CapsInventoryFailure: Error { case unavailable }
    private static let outputTag: Int64 = 0x4B50_5345_5353_494F
    private let reportURL: URL
    private let nonce: String
    private let ownerPID: Int32
    private let port: UInt16
    private let capabilities: PermissionOracle.PermissionSet
    private let rawPermissions: SessionRuntimeReport.RawPermissions?
    private var runtime: KanataHostBridgePassthruRuntimeHandle?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var timer: Timer?
    private var signals: [DispatchSourceSignal] = []
    private var outputs = SessionOutputState()
    private var inputs: Set<UInt32> = []
    /// Consumer-page media keys held into Kanata. Kept apart from `inputs`:
    /// usage numbers overlap across pages (0xE2 is Mute here, Left Alt on page 7).
    private var mediaInputs: Set<UInt32> = []
    private var capsRecord: SessionCapsMappingPolicy.Record?
    private var capsFleetEnabled = false
    private var capsFleetRecords: [SessionCapsMappingPolicy.Record] = []
    private var capsFleetCoverage: SessionRuntimeReport.CapsCoverage?
    private var capsFleetRetryAfter: [UInt64: Date] = [:]
    private var capsFleetReadFailures = 0
    private var capsCheckSchedule = SessionCapsCheckSchedule()
    private var capsArrivalMonitor: SessionCapsKeyboardArrivalMonitor?
    /// Tracked arrivals not yet mapped, each with when it arrived.
    private var capsTimedArrivals: [SessionCapsArrivedService: Date] = [:]
    private var capsOwner: SessionCapsMappingPolicy.Owner?
    private var capsDirectory: URL?
    private var capsInput = SessionCapsInputState()
    private let capsOutput = SessionCapsLockOutput()
    private var capsCheckInFlight = false
    /// The profile and its digest as last admitted under the leased key.
    private var capsConfigPath: String?
    private var capsAdmittedDigest: String?
    private var lastCapsCheck = Date.distantPast
    /// When the last fleet check finished; fast arrival checks are spaced from it.
    private var lastCapsCheckEnd = Date.distantPast
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
        private var rawTimeoutCallbackCount: UInt64 = 0
        private var rawUserInputDisabledCallbackCount: UInt64 = 0
        private var postDelayRegisteredTap: SessionRuntimeReport.RegisteredTapObservation?
        private var postDelayQueryUptimeNanos: UInt64?
        private var startupTapDiagnostics: SessionRuntimeReport.ExperimentalTapDiagnostics?
        private var experimentalRawCapabilities: PermissionOracle.PermissionSet?
        private var experimentalRawPosting: PermissionOracle.Status?
        private var registeredTapObservation: SessionRuntimeReport.RegisteredTapObservation?
    #endif

    private init(
        reportURL: URL, nonce: String, ownerPID: Int32, port: UInt16,
        capabilities: PermissionOracle.PermissionSet,
        rawPermissions: SessionRuntimeReport.RawPermissions? = nil
    ) {
        self.reportURL = reportURL
        self.nonce = nonce
        self.ownerPID = ownerPID
        self.port = port
        self.capabilities = capabilities
        self.rawPermissions = rawPermissions
    }

    /// Returns false for an ordinary app launch. Worker modes never initialize
    /// the UI, helper repair, service monitoring or the privileged installer.
    public static func runIfRequested() async -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--session-runtime") || arguments.contains("--session-capabilities") else {
            return false
        }
        // Capability probes and the runtime are background processes, not a
        // second foreground KeyPath app. Keep them out of the Dock.
        await MainActor.run { _ = NSApplication.shared.setActivationPolicy(.prohibited) }
        func argument(_ name: String) -> String? {
            guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        }
        guard getuid() != 0,
              let path = argument("--session-report"),
              let nonce = argument("--session-nonce"), UUID(uuidString: nonce) != nil
        else { exit(64) }

        if arguments.contains("--session-capabilities") {
            await writeCapabilityReport(
                reportURL: URL(fileURLWithPath: path), nonce: nonce,
                ownerPID: argument("--session-owner").flatMap(Int32.init) ?? 0,
                port: argument("--session-port").flatMap(UInt16.init) ?? 0,
                snapshotProvider: {
                    await SystemStateProvider.shared.currentProcessSessionCapabilitySnapshot()
                }
            )
            exit(0)
        }
        let capabilities = await SystemStateProvider.shared.currentProcessPermissionCapabilities()
        let worker = SessionRuntimeWorker(
            reportURL: URL(fileURLWithPath: path), nonce: nonce,
            ownerPID: argument("--session-owner").flatMap(Int32.init) ?? 0,
            port: argument("--session-port").flatMap(UInt16.init) ?? 0,
            capabilities: capabilities
        )
        guard let config = argument("--session-config") else {
            worker.finish(.failed, reason: "missing-config")
        }
        #if KEYPATH_TAP_TIMEOUT_EXPERIMENT
            // Raw API facts remain separate from combined session readiness.
            // Both snapshots are obtained only through the canonical permission owner.
            worker.experimentalRawCapabilities = SystemStateProvider.shared.currentProcessRawPermissionCapabilities()
            worker.experimentalRawPosting = await SystemStateProvider.shared.currentProcessRawEventPostingStatus()
        #endif
        worker.start(configPath: config)
        // Keep the worker and loaded bridge alive through process termination;
        // dropping a runtime cannot stop its detached TCP listener threads.
        worker.runLoop()
    }

    /// Capability mode samples passive APIs and writes evidence only. In particular,
    /// this path never enters start(), creates an event tap, or loads configuration.
    static func writeCapabilityReport(
        reportURL: URL, nonce: String, ownerPID: Int32, port: UInt16,
        snapshotProvider: () async -> PermissionOracle.SessionCapabilitySnapshot
    ) async {
        let snapshot = await snapshotProvider()
        let worker = SessionRuntimeWorker(
            reportURL: reportURL, nonce: nonce, ownerPID: ownerPID, port: port,
            capabilities: snapshot.effective, rawPermissions: snapshot.rawPermissions
        )
        worker.writeReport(.capabilities)
    }

    private func runLoop() -> Never {
        CFRunLoopRun()
        AppLogger.shared.log("🛑 [SessionWorker] Run loop exited; retiring")
        finish(.stopped)
    }

    private func start(configPath: String) {
        // Install before any HID mutation. Shutdown waits for the synchronous
        // acquisition to finish, then restores the owned mapping on this run loop.
        installTerminationHandlers()
        guard capabilities.hasAllPermissions else {
            finish(.failed, reason: "missing-current-process-permission")
        }
        let environmentObserver = SessionRuntimeEnvironmentObserver(expectedUID: getuid()) { [weak self] reason, acknowledge in
            guard let self, !self.finished else { acknowledge?(); return }
            finish(.failed, reason: reason.rawValue, acknowledge: acknowledge)
        }
        self.environmentObserver = environmentObserver
        guard environmentObserver.start() else {
            finish(.failed, reason: "environment-observer-registration-failed")
        }
        guard !IsSecureEventInputEnabled() else { finish(.secureInput) }
        // Capture before engine validation; stale consent must not block ordinary
        // profiles, but managed admission must validate these exact bytes.
        let capsDigest = try? SessionCapsRuntimeSupport.configSHA256(configPath)
        // The parent chose the intermediate; run exactly that one.
        let admission = SessionCapsRuntimeSupport.admit(configPath: configPath, runtimeHost: .current(), rechoose: false)
        guard case .valid = admission.result else {
            finish(.failed, reason: "config-requires-advanced-driver-backend-or-is-invalid")
        }
        if admission.managedCaps {
            do {
                guard let capsDigest, try SessionCapsRuntimeSupport.validatedConfigDigest(configPath, beforeValidation: capsDigest) == capsDigest else {
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

        // 14 = NX_SYSDEFINED: the media keys (volume, brightness, playback) on
        // Apple keyboards arrive as system-defined events, not key events.
        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
            | (1 << Self.systemDefinedEventType)
        tap = createModifyingTap(eventsOfInterest: CGEventMask(mask))
        guard let startupTap = tap else { finish(.failed, reason: "modifying-tap-unavailable") }
        if admission.managedCaps {
            CGEvent.tapEnable(tap: startupTap, enable: false)
            do {
                let allUsage = SessionCapsRuntimeSupport.allKeyboardIntermediate()
                guard runtime?.isInputMapped(usagePage: 7, usage: 57) == true,
                      let capsDigest,
                      try SessionCapsRuntimeSupport.configSHA256(configPath) == capsDigest
                else {
                    throw SessionCapsRuntimeSupport.Refusal.configIdentity
                }
                let selection = allUsage == nil ? try SessionCapsRuntimeSupport.selected() : nil
                guard (allUsage ?? selection?.intermediateUsage) == admission.intermediateUsage else {
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
                // Before any HID work: the transport's diagnostics go to the log.
                SessionCapsHIDUtilTransport.warn = { AppLogger.shared.warn($0) }
                if let allUsage {
                    let result = try Self.performHIDWork {
                        let backend = SessionCapsHIDUtilTransport.backend()
                        let excluded = SessionCapsRuntimeSupport.excludedKeyboardIDs()
                        let inventory = try SessionCapsHIDUtilTransport.keyboards()
                        let devices = inventory.keyboards.map(\.device)
                            .filter { !excluded.contains(SessionCapsRuntimeSupport.preferenceID($0)) }
                        let coverage = try SessionCapsMappingFleet(directory: directory, backend: backend)
                            .acquire(owner: owner, configSHA256: capsDigest, devices: devices,
                                     intermediate: SessionCapsMappingPolicy.packed(allUsage))
                        return (coverage, devices.count, inventory.withheld)
                    }
                    capsFleetEnabled = true
                    startCapsArrivalMonitor()
                    capsFleetRecords = result.0.records
                    capsRecord = result.0.records.first
                    capsFleetCoverage = .init(eligible: result.1, covered: result.0.records.count, withheld: result.2)
                    for (id, reason) in result.0.failures {
                        AppLogger.shared.warn("[SessionCaps] Keyboard \(id) left uncovered: \(reason)")
                    }
                } else if let selection {
                    let device = selection.device
                    let intermediate = SessionCapsMappingPolicy.packed(selection.intermediateUsage)
                    capsRecord = try Self.performHIDWork {
                        let backend = SessionCapsHIDUtilTransport.backend()
                        do { try SessionCapsMappingPolicy.requireUnique(device, among: backend.enumerate()) } catch {
                            throw SessionCapsRuntimeSupport.Refusal.selection
                        }
                        let lease = SessionCapsMappingLease(directory: directory, backend: backend)
                        return try lease.acquire(owner: owner, configSHA256: capsDigest, device: device,
                                                 intermediate: intermediate)
                    }
                }
                try SessionCapsRuntimeSupport.requirePhysicalAllUp()
                if capsRecord != nil {
                    capsInput.activate(generation: owner.generation, intermediateUsage: admission.intermediateUsage)
                }
                capsConfigPath = configPath
                capsAdmittedDigest = capsDigest
            } catch {
                AppLogger.shared.warn("Managed Caps activation refused: \(error)")
                finish(.failed, reason: "managed-caps-activation-refused: \(error)")
            }
            // Explicitly disabling the preflight tap can queue a user-disable
            // notification. Retire its port before installing a fresh live tap;
            // every disable notification from the live port remains fatal.
            CFMachPortInvalidate(startupTap)
            tap = nil
            tap = createModifyingTap(eventsOfInterest: CGEventMask(mask))
        }
        guard let tap else { finish(.failed, reason: "modifying-tap-unavailable") }
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

        timer = Timer(timeInterval: 0.005, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer!, forMode: .common)
        writeReport(.running)
    }

    private func installTerminationHandlers() {
        for number in [SIGTERM, SIGINT, SIGHUP] {
            signal(number, SIG_IGN)
            // The standalone worker drives CFRunLoop directly; it does not run
            // NSApplication's main-dispatch servicing. Deliver shutdown onto
            // that run loop rather than queueing a main-dispatch handler.
            let signalSource = DispatchSource.makeSignalSource(signal: number, queue: .global())
            signalSource.setEventHandler { @Sendable [weak self] in
                CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) { [weak self] in
                    MainActor.assumeIsolated {
                        guard let self, !self.finished else { return }
                        AppLogger.shared.log("🛑 [SessionWorker] Received signal \(number); retiring")
                        self.finish(.stopped)
                    }
                }
                CFRunLoopWakeUp(CFRunLoopGetMain())
            }
            signals.append(signalSource)
            signalSource.resume()
        }
    }

    /// DispatchQueue.sync can execute on the caller, where Process.waitUntilExit
    /// may pump the main run loop and reenter shutdown inside a lease mutation.
    /// An async dispatch guarantees background execution; the semaphore joins
    /// without servicing main-loop callbacks. Do not bound this join: the HID
    /// transport must finish joining its child before lease exclusion can end.
    /// A reloaded profile keeps this session only if it is still managed Caps
    /// under the key the lease reserved.
    /// The periodic profile check: only a profile whose digest changed since
    /// admission is re-admitted (parsing is not free), and an unreadable file
    /// keeps the admitted digest, so the next tick looks again.
    nonisolated static func profileCheck(configPath: String?, admittedDigest: String?, record: SessionCapsMappingPolicy.Record,
                                         digestOf: (String) throws -> String,
                                         admit: (String) -> SessionCapsRuntimeSupport.Admission) -> (digest: String?, fits: Bool)
    {
        guard let configPath, let current = try? digestOf(configPath), current != admittedDigest else {
            return (admittedDigest, true)
        }
        return (current, profileFitsLease(admit(configPath), record: record))
    }

    nonisolated static func profileFitsLease(_ admission: SessionCapsRuntimeSupport.Admission,
                                             record: SessionCapsMappingPolicy.Record) -> Bool
    {
        guard case .valid = admission.result, admission.managedCaps else { return false }
        return SessionCapsMappingPolicy.packed(admission.intermediateUsage) == record.intermediate
    }

    /// Backstop to admission: the runtime must never emit the key this
    /// lease reserved. Any other key, F18 included, is ordinary output.
    nonisolated static func emitsReservedKey(usagePage: UInt32, usage: UInt32,
                                             record: SessionCapsMappingPolicy.Record?) -> Bool
    {
        guard let record else { return false }
        return SessionCapsMappingPolicy.packed(usage) == record.intermediate && usagePage == 7
    }

    nonisolated static func performHIDWork<Value: Sendable>(
        _ operation: @escaping @Sendable () throws -> Value
    ) throws -> Value {
        let result = SessionRuntimeBackgroundResult<Value>()
        let completion = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            result.store(Result { try operation() })
            completion.signal()
        }
        completion.wait()
        return try result.load().get()
    }

    private func createModifyingTap(eventsOfInterest: CGEventMask) -> CFMachPort? {
        CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: eventsOfInterest, callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let consume = MainActor.assumeIsolated {
                    let worker = Unmanaged<SessionRuntimeWorker>.fromOpaque(context).takeUnretainedValue()
                    return worker.receive(type: type, event: event) == nil
                }
                return consume ? nil : Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
    }

    private func receive(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        #if KEYPATH_TAP_TIMEOUT_EXPERIMENT
            // Includes tagged output, disabled notifications and unmapped input.
            // No event content is retained; saturation avoids counter wraparound.
            if rawTapCallbackCount < UInt64.max { rawTapCallbackCount += 1 }
            // Observe before tagged-output filtering without changing the existing fatal policy.
            if type == .tapDisabledByTimeout, rawTimeoutCallbackCount < UInt64.max { rawTimeoutCallbackCount += 1 }
            if type == .tapDisabledByUserInput, rawUserInputDisabledCallbackCount < UInt64.max { rawUserInputDisabledCallbackCount += 1 }
        #endif
        let original = Unmanaged.passUnretained(event)
        if finished || event.getIntegerValueField(.eventSourceUserData) == Self.outputTag { return original }
        // Aqua Voice and other software inject complete shortcuts. Sending their
        // keys through Kanata loses aggregate-only modifiers (Cmd+V becomes v)
        // and can contaminate the physical key/held-output state.
        if SessionInputEventPolicy.isSoftwareKeyboardEvent(type: type, event: event) { return original }
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
        if type.rawValue == Self.systemDefinedEventType { return receiveMedia(event) }
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
            event.flags = CGEventFlags(rawValue: outputs.modifierFlags | physicalPassthroughFlags | event.flags.intersection(.maskAlphaShift).rawValue)
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

    static let systemDefinedEventType: UInt32 = 14

    /// A media key from the built-in or an Apple keyboard. Mapped ones go to
    /// Kanata and are consumed; everything else passes through untouched.
    /// Hardware repeats of a held mapped key are swallowed, since Kanata (and,
    /// for posted media outputs, macOS) repeat on their own.
    private func receiveMedia(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let original = Unmanaged.passUnretained(event)
        guard let nsEvent = NSEvent(cgEvent: event), nsEvent.type == .systemDefined,
              let input = SessionKeyMap.mediaInput(subtype: nsEvent.subtype.rawValue, data1: nsEvent.data1),
              runtime?.isInputMapped(usagePage: SessionKeyMap.consumerPage, usage: input.usage) == true
        else { return original }
        switch input.value {
        case 2: return mediaInputs.contains(input.usage) ? nil : original
        case 0: guard mediaInputs.contains(input.usage) else { return original } // press predates this tap
        default: break
        }
        guard send(value: input.value, usage: input.usage, usagePage: SessionKeyMap.consumerPage) else { return original }
        if input.value == 0 { mediaInputs.remove(input.usage) } else { mediaInputs.insert(input.usage) }
        return nil
    }

    private func send(value: UInt64, usage: UInt32, usagePage: UInt32 = SessionKeyMap.keyboardPage) -> Bool {
        guard let runtime, case .success = runtime.sendInput(value: value, usagePage: usagePage, usage: usage) else {
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
        #if KEYPATH_TAP_TIMEOUT_EXPERIMENT
            // Same run loop: the delayed callback has returned. Sample once before
            // the existing disabled-tap guard can retire it; never re-enable a tap.
            if tapTimeoutExperiment?.takePostReturnObservationRequest() == true,
               let startup = registeredTapObservation, let tapID = startup.rows.first?.timing?.eventTapID
            {
                postDelayQueryUptimeNanos = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
                postDelayRegisteredTap = Self.observeRegisteredTap(
                    requestedMask: startup.requestedMask, accessibility: startup.rawAccessibility,
                    posting: startup.rawPostEvent, listening: startup.rawListenEvent, expectedTapID: tapID
                )
            }
        #endif
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
                if Self.emitsReservedKey(usagePage: event.usagePage, usage: event.usage, record: capsRecord) {
                    finish(.failed, reason: "managed-caps-reserved-output")
                }
                do {
                    // Refresh immediately before each queued event as well as
                    // before the drain; a console change can race a long drain.
                    guard environmentObserver?.check() == true else {
                        finish(.failed, reason: "environment-observer-unavailable")
                    }
                    if event.usagePage == 7, event.usage == 57 {
                        do {
                            try capsOutput.receive(value: event.value)
                            outputCount += 1
                            writeReport(.running)
                        } catch {
                            finish(.failed, reason: "caps-lock-output-failed")
                        }
                        continue
                    }
                    if event.usagePage == SessionKeyMap.consumerPage {
                        // Media keys: posted as system-defined events, held in
                        // their own ledger so a stop releases them too.
                        var nextOutputs = outputs
                        guard let media = try nextOutputs.translateMedia(event) else { continue }
                        if media.isDown { outputs = nextOutputs; writeReport(.running) }
                        guard environmentObserver?.check() == true else {
                            finish(.failed, reason: "environment-observer-unavailable")
                        }
                        guard postMedia(media) else { finish(.failed, reason: "output-event-unavailable") }
                        outputCount += 1
                        if !media.isDown { outputs = nextOutputs; writeReport(.running) }
                        continue
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

    /// How long an arrival waits to be attributed. Long enough for a keyboard
    /// plugged in with keys held to be mapped once they are released.
    static let arrivalAttributionLimit: TimeInterval = 30

    /// Keyboards whose failure backoff can be dropped: gone from the registry,
    /// not merely missing from one listing.
    static func departedBackoffs(_ backingOff: Set<UInt64>, listed: Set<UInt64>,
                                 exists: (UInt64) -> Bool?) -> Set<UInt64>
    {
        backingOff.filter { !listed.contains($0) && exists($0) == false }
    }

    /// Times each newly covered keyboard from the arrival of its own service (by
    /// registry ID, or another interface at its LocationID). A keyboard covered
    /// for any other reason, such as an exclusion removed, is not an arrival.
    static func arrivalLog(_ timed: [SessionCapsArrivedService: Date], now: Date,
                           covered: [(id: UInt64, location: UInt32?)])
        -> (lines: [String], remaining: [SessionCapsArrivedService: Date])
    {
        var remaining = timed.filter { now.timeIntervalSince($0.value) < arrivalAttributionLimit }
        var lines: [String] = []
        for keyboard in covered.sorted(by: { $0.id < $1.id }) {
            let matches = remaining.filter { service, _ in
                service.registryEntryID == keyboard.id
                    || (service.locationID != nil && service.locationID == keyboard.location)
            }
            guard let arrivedAt = matches.values.min() else { continue }
            let elapsed = Int((now.timeIntervalSince(arrivedAt) * 1000).rounded())
            lines.append("[SessionCaps] Keyboard arrival mapped in \(elapsed) ms: [\(keyboard.id)]")
            for service in matches.keys {
                remaining.removeValue(forKey: service)
            }
        }
        return (lines, remaining)
    }

    /// Without the monitor the backstop check still finds arrivals, only later.
    private func startCapsArrivalMonitor() {
        let monitor = SessionCapsKeyboardArrivalMonitor { [weak self] keyboards in
            guard let self, !self.finished else { return }
            let now = Date()
            for service in capsCheckSchedule.keyboardArrived(keyboards: keyboards)
                where capsTimedArrivals[service].map({ now.timeIntervalSince($0) >= Self.arrivalAttributionLimit }) ?? true
            {
                capsTimedArrivals[service] = now
            }
        }
        if monitor.start() {
            capsArrivalMonitor = monitor
        } else {
            AppLogger.shared.warn("[SessionCaps] Keyboard arrival notifications unavailable; relying on the 2 s check")
        }
    }

    private func checkCapsOwnershipIfNeeded() {
        guard !capsCheckInFlight else { return }
        if capsFleetEnabled {
            guard capsCheckSchedule.isDue(now: Date(), lastStart: lastCapsCheck, lastEnd: lastCapsCheckEnd) else { return }
            checkCapsFleetIfNeeded()
            return
        }
        guard Date().timeIntervalSince(lastCapsCheck) >= 0.5 else { return }
        guard let record = capsRecord else { return }
        capsCheckInFlight = true
        lastCapsCheck = Date()
        guard let directory = capsDirectory else { finish(.failed, reason: "managed-caps-directory-unavailable") }
        let configPath = capsConfigPath, admittedDigest = capsAdmittedDigest
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let lost = SessionCapsRuntimeSupport.leaseCheckFailure(
                registryEntryID: record.device.registryEntryID,
                verify: { try SessionCapsRuntimeSupport.verifyActive(directory: directory, owner: record.owner) },
                registryEntryExists: SessionCapsHIDUtilTransport.registryEntryExists
            )
            // Any reload path (the app, the CLI, a raw TCP client) can load a
            // profile that now uses the leased key. Re-admit a changed profile
            // under that key; the app restarts the session to choose another.
            let (digest, fits) = Self.profileCheck(configPath: configPath, admittedDigest: admittedDigest, record: record,
                                                   digestOf: SessionCapsRuntimeSupport.configSHA256,
                                                   admit: { SessionCapsRuntimeSupport.admit(configPath: $0, runtimeHost: .current(), rechoose: false) })
            CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, !self.finished, self.capsRecord?.owner == record.owner else { return }
                    self.capsCheckInFlight = false
                    if let lost { self.finish(.failed, reason: lost) }
                    if !fits { self.finish(.failed, reason: SessionCapsRuntimeSupport.profileChangedReason) }
                    self.capsAdmittedDigest = digest
                }
            }
            CFRunLoopWakeUp(CFRunLoopGetMain())
        }
    }

    private func checkCapsFleetIfNeeded() {
        let now = Date()
        let arrived = capsCheckSchedule.checkStarted(at: now, lastStart: lastCapsCheck)
        lastCapsCheck = now
        guard let owner = capsOwner, let directory = capsDirectory,
              let configPath = capsConfigPath, let admittedDigest = capsAdmittedDigest
        else {
            // Unreachable today (all four are set before the tick timer starts).
            // Counted as a failed check so a pending arrival can't spin the tick.
            lastCapsCheckEnd = now
            capsCheckSchedule.checkFailed()
            return
        }
        capsCheckInFlight = true
        let previous = Set(capsFleetRecords.map(\.device.registryEntryID))
        let retryAfter = capsFleetRetryAfter
        let usage = SessionCapsRuntimeSupport.preferredIntermediate()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let digest = try? SessionCapsRuntimeSupport.configSHA256(configPath)
            let result: Result<(records: [SessionCapsMappingPolicy.Record], failures: [UInt64: String],
                                eligible: Int, withheld: Int, departed: Set<UInt64>,
                                resolved: Set<SessionCapsArrivedService>), Error>
            do {
                guard digest == nil || digest == admittedDigest else {
                    throw SessionCapsRuntimeSupport.Refusal.configIdentity
                }
                let excluded = SessionCapsRuntimeSupport.excludedKeyboardIDs()
                let inventory: (keyboards: [SessionCapsHIDUtilTransport.Keyboard], withheld: Int)
                var listing = ""
                do {
                    inventory = try SessionCapsHIDUtilTransport.keyboards(run: {
                        listing = try SessionCapsHIDUtilTransport.runHIDUtil($0)
                        return listing
                    })
                } catch { throw CapsInventoryFailure.unavailable }
                let devices = inventory.keyboards.map(\.device)
                    .filter { !excluded.contains(SessionCapsRuntimeSupport.preferenceID($0)) }
                let now = Date()
                let retryable = devices.filter { device in
                    previous.contains(device.registryEntryID)
                        || now >= (retryAfter[device.registryEntryID] ?? .distantPast)
                }
                let fleet = SessionCapsMappingFleet(directory: directory, backend: SessionCapsHIDUtilTransport.backend())
                let coverage = try fleet.reconcile(
                    owner: owner, configSHA256: admittedDigest, devices: retryable,
                    intermediate: SessionCapsMappingPolicy.packed(usage),
                    bootSessionUUID: owner.bootSessionUUID,
                    allowNewDevices: SessionCapsRuntimeSupport.heldKeys().isEmpty
                )
                // A registry walk can be slow; ask once per keyboard per check.
                var existence: [UInt64: Bool?] = [:]
                let exists = { (id: UInt64) -> Bool? in
                    if let known = existence[id] { return known }
                    let answer = try? SessionCapsHIDUtilTransport.registryEntryExists(id)
                    existence[id] = answer
                    return answer
                }
                let resolved = SessionCapsCheckSchedule.resolved(
                    arrived, listed: (try? SessionCapsHIDUtilTransport.parseServiceRows(listing)) ?? [], exists: exists
                )
                // A backoff is dropped only once its keyboard is gone, not when one
                // listing happens to miss it.
                let departed = Self.departedBackoffs(
                    Set(retryAfter.keys), listed: Set(inventory.keyboards.map(\.device.registryEntryID)), exists: exists
                )
                result = .success((coverage.records, coverage.failures, devices.count, inventory.withheld,
                                   departed, resolved))
            } catch {
                result = .failure(error)
            }
            CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, !self.finished, self.capsOwner == owner else { return }
                    self.capsCheckInFlight = false
                    self.lastCapsCheckEnd = Date()
                    guard digest == nil || digest == admittedDigest else {
                        self.finish(.failed, reason: SessionCapsRuntimeSupport.profileChangedReason)
                    }
                    switch result {
                    case let .success(coverage):
                        self.capsFleetReadFailures = 0
                        let current = Set(coverage.records.map(\.device.registryEntryID))
                        if previous.isEmpty, !current.isEmpty {
                            self.capsInput.activate(generation: owner.generation, intermediateUsage: usage)
                        }
                        self.capsFleetRecords = coverage.records
                        self.capsRecord = coverage.records.first
                        if current.isEmpty { self.capsInput.revoke() }
                        for id in current {
                            self.capsFleetRetryAfter.removeValue(forKey: id)
                        }
                        for id in coverage.failures.keys {
                            self.capsFleetRetryAfter[id] = Date().addingTimeInterval(30)
                        }
                        // A departed keyboard's backoff would otherwise linger forever.
                        for id in coverage.departed where coverage.failures[id] == nil {
                            self.capsFleetRetryAfter.removeValue(forKey: id)
                        }
                        self.capsCheckSchedule.checkFinished(resolved: coverage.resolved)
                        let nextCoverage = SessionRuntimeReport.CapsCoverage(
                            eligible: coverage.eligible, covered: coverage.records.count, withheld: coverage.withheld
                        )
                        let coverageChanged = self.capsFleetCoverage != nextCoverage
                        self.capsFleetCoverage = nextCoverage
                        if current != previous || coverageChanged { self.writeReport(.running) }
                        for (id, reason) in coverage.failures where !previous.contains(id) {
                            AppLogger.shared.warn("[SessionCaps] Keyboard \(id) left uncovered: \(reason)")
                        }
                        let added = current.subtracting(previous)
                        if !added.isEmpty {
                            AppLogger.shared.log("[SessionCaps] Keyboard covered: \(added.sorted())")
                        }
                        let arrival = Self.arrivalLog(
                            self.capsTimedArrivals, now: Date(),
                            covered: coverage.records.filter { added.contains($0.device.registryEntryID) }
                                .map { ($0.device.registryEntryID, $0.device.locationID) }
                        )
                        arrival.lines.forEach { AppLogger.shared.log($0) }
                        self.capsTimedArrivals = arrival.remaining
                    case let .failure(error):
                        self.capsTimedArrivals = self.capsTimedArrivals.filter {
                            Date().timeIntervalSince($0.value) < Self.arrivalAttributionLimit
                        }
                        // Lease contention clears in moments; keep the arrival's fast checks.
                        if case SessionCapsMappingLease.Refusal.busy = error { return }
                        self.capsCheckSchedule.checkFailed()
                        if error is CapsInventoryFailure {
                            self.capsFleetReadFailures += 1
                            if self.capsFleetReadFailures == 3 {
                                self.capsFleetCoverage = .init(
                                    eligible: self.capsFleetCoverage?.eligible ?? self.capsFleetRecords.count,
                                    covered: self.capsFleetRecords.count,
                                    withheld: self.capsFleetCoverage?.withheld ?? 0,
                                    inventoryUnavailable: true
                                )
                                self.writeReport(.running)
                            }
                            return
                        }
                        AppLogger.shared.warn("[SessionCaps] Fleet verification failed: \(error)")
                        self.finish(.failed, reason: SessionCapsRuntimeSupport.ownershipLostReason)
                    }
                }
            }
            CFRunLoopWakeUp(CFRunLoopGetMain())
        }
    }

    /// `NSEvent.otherEvent(.systemDefined, subtype 8)`: data1 carries the
    /// NX key type in the high word and 0xA (down) / 0xB (up) in the next
    /// byte. Tagged like a key event so this worker's own tap ignores it.
    private func postMedia(_ output: SessionMediaOutput) -> Bool {
        guard let event = Self.mediaEvent(keyType: output.keyType, isDown: output.isDown)?.cgEvent else { return false }
        event.setIntegerValueField(.eventSourceUserData, value: Self.outputTag)
        event.post(tap: .cgSessionEventTap)
        return true
    }

    nonisolated static func mediaEvent(keyType: Int, isDown: Bool) -> NSEvent? {
        NSEvent.otherEvent(
            with: .systemDefined, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0, context: nil,
            subtype: 8, data1: (keyType << 16) | ((isDown ? 0xA : 0xB) << 8), data2: -1
        )
    }

    private func post(_ output: SessionKeyOutput) -> Bool {
        guard let source = CGEventSource(stateID: .privateState),
              let event = CGEvent(keyboardEventSource: source, virtualKey: output.keyCode, keyDown: output.isDown)
        else { return false }
        let capsFlag = CGEventSource.flagsState(.combinedSessionState).intersection(.maskAlphaShift).rawValue
        event.flags = CGEventFlags(rawValue: output.flags | (physicalPassthroughFlags & ~CGEventFlags.maskAlphaShift.rawValue) | capsFlag)
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
                                         listening: String, expectedTapID: UInt32? = nil) -> SessionRuntimeReport.RegisteredTapObservation
        {
            guard experimentalTapABIIsExpected else {
                return classifyRegisteredTaps(requestedMask: requestedMask, taps: [], count: 0, error: .success,
                                              abiIsExpected: false, ownPID: getpid(), accessibility: accessibility, posting: posting, listening: listening, expectedTapID: expectedTapID)
            }
            var taps = [CGEventTapInformation](repeating: CGEventTapInformation(), count: 128)
            var count: UInt32 = 0
            let error = taps.withUnsafeMutableBufferPointer { CGGetEventTapList(128, $0.baseAddress, &count) }
            return classifyRegisteredTaps(requestedMask: requestedMask, taps: taps, count: count, error: error,
                                          abiIsExpected: true, ownPID: getpid(), accessibility: accessibility, posting: posting, listening: listening, expectedTapID: expectedTapID)
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
                                           listening: String, expectedTapID: UInt32? = nil) -> SessionRuntimeReport.RegisteredTapObservation
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
            let rows = taps.prefix(Int(count)).filter { tap in
                tap.tappingProcess == ownPID && tap.tapPoint == .cgSessionEventTap
                    && (expectedTapID.map { tap.eventTapID == $0 } ?? (tap.options == .defaultTap))
            }.map { tap in
                // Unexpected OS floats must not make JSON publication fail or
                // affect startup admission. Keep registration, omit invalid timing.
                let finite = [tap.minUsecLatency, tap.avgUsecLatency, tap.maxUsecLatency].allSatisfy { $0.isFinite && $0 >= 0 }
                return Observation.Row(mask: tap.eventsOfInterest, enabled: tap.enabled, timing: finite ? .init(
                    eventTapID: tap.eventTapID, options: tap.options.rawValue,
                    minUsecLatency: tap.minUsecLatency, avgUsecLatency: tap.avgUsecLatency,
                    maxUsecLatency: tap.maxUsecLatency
                ) : nil)
            }
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

    private func writeReport(_ state: SessionRuntimeReport.State, failure: String? = nil, retirementReason: String? = nil) {
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
                    configSHA256: startupTapDiagnostics.configSHA256, registeredTap: registeredTapObservation,
                    postDelayRegisteredTap: postDelayRegisteredTap, postDelayQueryUptimeNanos: postDelayQueryUptimeNanos,
                    rawTimeoutCallbackCount: rawTimeoutCallbackCount,
                    rawUserInputDisabledCallbackCount: rawUserInputDisabledCallbackCount
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
            managedCapsGeneration: capsRecord?.owner.generation, capsCoverage: capsFleetCoverage,
            rawPermissions: rawPermissions,
            retirementReason: retirementReason
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
        _ outputs: inout SessionOutputState, post: (SessionKeyOutput) -> Bool,
        postMedia: (SessionMediaOutput) -> Bool = { _ in true }
    ) {
        var pending = outputs
        for output in pending.releaseAll() {
            if post(output), let usage = SessionKeyMap.keyCodeToUsage[output.keyCode] {
                _ = try? outputs.translate(.init(value: 0, usagePage: 7, usage: usage))
            }
        }
        for media in pending.releaseAllMedia() where postMedia(media) {
            _ = try? outputs.translateMedia(.init(value: 0, usagePage: SessionKeyMap.consumerPage, usage: media.usage))
        }
    }

    private func finish(
        _ state: SessionRuntimeReport.State, reason: String? = nil,
        acknowledge: (() -> Void)? = nil
    ) -> Never {
        finished = true
        // Every exit records why, so a stop with no failure is still explainable.
        AppLogger.shared.log("🛑 [SessionWorker] Finishing: state=\(state) reason=\(reason ?? "none")")
        AppLogger.shared.flushBuffer()
        capsInput.revoke()
        capsArrivalMonitor?.stop()
        capsArrivalMonitor = nil
        var terminalState = state
        var terminalReason = reason
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        timer?.invalidate()
        Self.completeTermination(releaseOutputs: {
            // Allocation failure during shutdown cannot recursively exit before
            // the power ACK. Preserve unposted releases in the crash ledger.
            var remaining = outputs
            Self.releaseOwnedOutputs(&remaining, post: post, postMedia: postMedia)
            outputs = remaining
            if let owner = capsOwner, let directory = capsDirectory {
                do {
                    try Self.performHIDWork {
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
            writeReport(terminalState, failure: terminalReason, retirementReason: reason)
        }, acknowledge: acknowledge, unregisterObservers: {
            environmentObserver?.stop()
        })
        // Process exit is the shutdown boundary for all detached bridge threads.
        exit(terminalState == .failed ? 1 : 0)
    }
}

/// One result passes from the HID queue to its synchronously waiting caller.
/// Every access is protected; Value and Error can cross concurrency domains.
private final class SessionRuntimeBackgroundResult<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Value, Error>?

    func store(_ value: Result<Value, Error>) {
        lock.lock()
        defer { lock.unlock() }
        result = value
    }

    func load() -> Result<Value, Error> {
        lock.lock()
        defer { lock.unlock() }
        // The semaphore is signaled only after store returns.
        return result!
    }
}
