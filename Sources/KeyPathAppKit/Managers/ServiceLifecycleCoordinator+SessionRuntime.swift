import AppKit
import Carbon
import KeyPathCore
import KeyPathPermissions

extension ServiceLifecycleCoordinator {
    func currentSessionReport() -> SessionRuntimeReport? {
        #if DEBUG
            if let report = testSessionCurrentReport { return report() }
        #endif
        guard let application = sessionApplication, !application.isTerminated,
              let url = sessionReportURL, let nonce = sessionNonce,
              let report = Self.readSessionReport(url),
              report.isCurrent(nonce: nonce, pid: application.processIdentifier, uid: getuid(), now: Date())
        else { return nil }
        return report
    }

    var sessionManagedCapsActive: Bool {
        guard let report = currentSessionReport(), report.state == .running, report.tapActive,
              let generation = report.managedCapsGeneration else { return false }
        return generation == sessionNonce
    }

    func sessionCapabilities() async -> PermissionOracle.PermissionSet? {
        if let report = currentSessionReport() { return Self.permissionSet(report) }
        guard !startsSuppressed else { return nil }
        // Capability checks launch a separate copy of the app too. Serialize
        // them with stop so uninstall waits for existing probes before trashing
        // the bundle, and queued checks cannot launch during shutdown.
        let probedPermissions: PermissionOracle.PermissionSet?
        do {
            probedPermissions = try await sessionOperationGate.withOperation { [self] _ in
                await probeSessionCapabilities()
            }
        } catch {
            return nil
        }
        // An owned runtime may finish starting while the independent probe is
        // suspended. Revalidate ownership/freshness before publishing the older
        // probe result (including a missing result) to the permission cache.
        if let report = currentSessionReport() { return Self.permissionSet(report) }
        return probedPermissions
    }

    private func probeSessionCapabilities() async -> PermissionOracle.PermissionSet? {
        guard !startsSuppressed, !Task.isCancelled else { return nil }
        #if DEBUG
            if let probe = testSessionCapabilityProbe { return await probe() }
        #endif
        do {
            let (application, url, nonce) = try await launchSessionProcess(capabilitiesOnly: true)
            defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
            for _ in 0 ..< 40 {
                if let report = Self.readSessionReport(url),
                   report.state == .capabilities,
                   report.isCurrent(nonce: nonce, pid: application.processIdentifier, uid: getuid(), now: Date())
                {
                    return Self.permissionSet(report)
                }
                try await Task.sleep(for: .milliseconds(50))
            }
            // NSWorkspace may return an application without a valid PID (e.g. -1).
            // Never let that become a process-group/broadcast signal target.
            // Signal only the independently launched process owned by this call.
            let probePID = application.processIdentifier
            if probePID > 0, !application.isTerminated { kill(probePID, SIGTERM) }
        } catch {
            AppLogger.shared.warn("Session permission report unavailable")
        }
        return nil
    }

    func startSessionRuntime(reason: String, generation: UInt64) async -> Bool {
        guard sessionStartIsCurrent(generation) else { return false }
        #if DEBUG
            if let readiness = testSessionRunningReadiness {
                let responding = await readiness()
                return await adoptRunningSession(generation: generation, responding: responding)
            }
        #endif
        if let report = currentSessionReport(), report.state == .running, report.tapActive {
            let responding = await SystemStateProvider.shared.isTCPPortResponding(port: Int(report.tcpPort), timeoutMs: 300)
            return await adoptRunningSession(generation: generation, responding: responding)
        }
        guard await stopSessionRuntime(), sessionStartIsCurrent(generation) else { return false }
        // A legacy runtime cannot coexist with a modifying session tap. Do not
        // terminate or migrate a privileged installation implicitly.
        let legacyRunning = await kanataDaemonService.isDaemonRunning()
        guard sessionStartIsCurrent(generation) else { return false }
        if legacyRunning {
            onError?("Stop the existing keyboard service before trying driverless mode.")
            return false
        }
        var didLaunch = false
        do {
            sessionLaunchWakeEpoch = sessionWakeEpoch
            let (application, url, nonce) = try await launchSessionProcess(capabilitiesOnly: false)
            sessionApplication = application
            sessionReportURL = url
            sessionNonce = nonce
            sessionOutputsRecovered = false
            didLaunch = true
            // NSWorkspace can finish a launch despite task cancellation. Retain
            // its ownership first, then clean it before releasing admission.
            guard sessionStartIsCurrent(generation) else {
                _ = await stopSessionRuntime()
                return false
            }
            for _ in 0 ..< 40 {
                guard sessionStartIsCurrent(generation) else {
                    _ = await stopSessionRuntime()
                    return false
                }
                if let report = currentSessionReport() {
                    if report.state == .running, report.tapActive,
                       await SystemStateProvider.shared.isTCPPortResponding(port: Int(report.tcpPort), timeoutMs: 300)
                    {
                        guard sessionStartIsCurrent(generation) else {
                            _ = await stopSessionRuntime()
                            return false
                        }
                        await AppContextService.shared.start()
                        guard sessionStartIsCurrent(generation) else {
                            _ = await stopSessionRuntime()
                            return false
                        }
                        onError?(nil)
                        onWarning?(nil)
                        onStateChanged?()
                        guard sessionStartIsCurrent(generation), sessionApplication === application,
                              sessionNonce == nonce, !application.isTerminated else { return false }
                        superviseSessionRuntime(generation: generation)
                        guard sessionStartIsCurrent(generation), sessionApplication === application,
                              sessionNonce == nonce, !application.isTerminated else { return false }
                        AppLogger.shared.log(
                            "Session runtime ready (\(reason)) parentPID=\(getpid()) workerPID=\(application.processIdentifier) nonce=\(nonce)"
                        )
                        return true
                    }
                    if report.state == .failed || report.state == .secureInput { break }
                }
                if application.isTerminated { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            let terminalReport = sessionReportURL.flatMap(Self.readSessionReport)
            if let terminalReport, terminalReport.belongsTo(nonce: nonce, pid: application.processIdentifier, uid: getuid()) {
                AppLogger.shared
                    .info("[SessionRuntime] Startup retired state=\(terminalReport.state.rawValue) reason=\(terminalReport.recoveryReason ?? "none") failure=\(terminalReport.failure ?? "none")")
            }
            #if KEYPATH_TAP_TIMEOUT_EXPERIMENT
                if let terminalReport,
                   sessionStartIsCurrent(generation),
                   sessionApplication === application,
                   sessionReportURL == url,
                   sessionNonce == nonce,
                   let diagnostic = terminalReport.experimentalTerminalStartupDiagnosticJSON(
                       parentPID: getpid(), expectedWorkerPID: application.processIdentifier,
                       expectedUID: getuid(), expectedNonce: nonce,
                       launchGeneration: generation, now: Date()
                   )
                {
                    // This is evidence only. The original failure and cleanup path
                    // proceeds unchanged even when the diagnostic is absent.
                    AppLogger.shared.error("SESSION_TERMINAL_STARTUP \(diagnostic)")
                }
            #endif
            let cleanedUp = await stopSessionRuntime()
            if reason == "System wake", sessionStartIsCurrent(generation),
               Self.canRetryWakeStartup(terminalReport, nonce: nonce, pid: application.processIdentifier,
                                        uid: getuid(), cleanedUp: cleanedUp)
            {
                sessionWakeRetryGeneration = generation
                onWarning?("Waiting for your keyboard to become ready.")
                onStateChanged?()
                return false
            }
            if scheduleInterruptedStartupRecovery(terminalReport, nonce: nonce,
                                                  pid: application.processIdentifier,
                                                  generation: generation, cleanedUp: cleanedUp) { return false }
            let failure = terminalReport?.failure.map(Self.sessionFailureRecoveryMessage)
            if sessionStartIsCurrent(generation) { onError?("Driverless runtime could not start: \(failure ?? "no current tap and TCP evidence")") }
        } catch {
            if didLaunch { _ = await stopSessionRuntime() }
            if sessionStartIsCurrent(generation) { onError?("Driverless runtime launch failed: \(error.localizedDescription)") }
        }
        onStateChanged?()
        return false
    }

    /// A retained worker needs supervision even with stale or terminal health.
    /// The existing supervisor checks launch identity and owns cleanup/recovery.
    func retainOwnedSessionSupervision(generation: UInt64) {
        guard sessionStartIsCurrent(generation) else { return }
        superviseSessionRuntime(generation: generation)
    }

    private func adoptRunningSession(generation: UInt64, responding: Bool) async -> Bool {
        guard sessionStartIsCurrent(generation), sessionCleanupTask == nil,
              sessionTerminationGuard == nil else { return false }
        guard responding else {
            _ = await stopSessionAdmitted(reason: "Existing session did not respond")
            return false
        }
        // Public starts change intent even when the same process remains live.
        // Transfer supervision to that intent instead of abandoning the worker.
        superviseSessionRuntime(generation: generation)
        return true
    }

    /// Called only under lifecycle admission. Cancellation never skips cleanup.
    func stopSessionRuntime() async -> Bool {
        let application = sessionApplication
        let reportURL = sessionReportURL
        let nonce = sessionNonce
        sessionSupervisionTask?.cancel()
        sessionSupervisionTask = nil
        await AppContextService.shared.stop()
        if let application, !application.isTerminated {
            let exited = sessionTerminationGuard == nil ? await Self.awaitGracefulSessionExit(
                isTerminated: { application.isTerminated },
                sendTermination: { _ = Self.signalSessionProcess(pid: application.processIdentifier, signal: SIGTERM) },
                wait: { await self.waitForSessionTermination() }
            ) : false
            if !exited {
                await terminateIdleSessionWorker(application, nonce: nonce)
            }
            guard application.isTerminated else {
                scheduleSessionCleanup(application, nonce: nonce)
                onError?("Keyboard cleanup is still finishing. Wait a moment and try again.")
                return false
            }
        }
        // Never clear a different launch's fields or delete its durable ledger.
        guard sessionApplication === application, sessionNonce == nonce,
              sessionReportURL == reportURL else { return false }
        // The worker is dead: release exclusion before normal journal recovery.
        sessionTerminationGuard?.release()
        sessionTerminationGuard = nil
        if let application { _ = recoverSessionOutputs(for: application) }
        guard await restoreSessionCaps(for: application) else {
            if let application { scheduleSessionCleanup(application, nonce: nonce) }
            return false
        }
        if let reportURL {
            try? FileManager.default.removeItem(at: reportURL.deletingLastPathComponent())
        }
        sessionCleanupTask?.cancel()
        sessionCleanupTask = nil
        sessionApplication = nil
        sessionReportURL = nil
        sessionNonce = nil
        sessionOutputsRecovered = false
        onStateChanged?()
        return true
    }

    /// Exclusion is held until the exact worker is observed dead, not merely
    /// until kill returns. A marker or foreign owner always refuses escalation.
    private func terminateIdleSessionWorker(_ application: NSRunningApplication, nonce: String?) async {
        guard let nonce, sessionApplication === application, sessionNonce == nonce else { return }
        if sessionTerminationGuard == nil {
            let pid = application.processIdentifier, uid = getuid(), parentPID = getpid()
            let directory = SessionCapsRuntimeSupport.journalDirectory()
            do {
                sessionTerminationGuard = try await Task.detached {
                    let owner = try SessionCapsMappingPolicy.Owner(
                        uid: uid, parentPID: parentPID, workerPID: pid, nonce: nonce,
                        generation: nonce, bootSessionUUID: SessionCapsRuntimeSupport.bootSessionUUID()
                    )
                    return try SessionCapsMappingLease(directory: directory, backend: SessionCapsHIDUtilTransport.backend())
                        .acquireTerminationGuard(expectedOwner: owner)
                }.value
            } catch { return }
        }
        guard !application.isTerminated else { return }
        _ = Self.signalSessionProcess(pid: application.processIdentifier, signal: SIGKILL)
        for _ in 0 ..< 40 {
            if application.isTerminated { return }
            await waitForSessionTermination()
        }
    }

    /// Cleanup survives Stop intent and caller cancellation. It never starts a
    /// replacement worker, and stale cleanup cannot touch a subsequent launch.
    private func scheduleSessionCleanup(_ application: NSRunningApplication, nonce: String?) {
        guard sessionCleanupTask == nil, let nonce else { return }
        let pid = application.processIdentifier
        sessionCleanupTask = Task.detached { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, await self?.sessionCleanupTick(nonce: nonce, pid: pid) == true else { return }
            }
        }
    }

    private func sessionCleanupTick(nonce: String, pid: Int32) async -> Bool {
        await (try? sessionOperationGate.withOperation { @MainActor [self] _ in
            guard sessionNonce == nonce, let application = sessionApplication,
                  application.processIdentifier == pid else { return false }
            if !application.isTerminated { await terminateIdleSessionWorker(application, nonce: nonce) }
            guard application.isTerminated else { return true }
            return await !stopSessionRuntime()
        }) ?? true
    }

    /// One signal boundary for owned session shutdown; injected transport keeps
    /// lifecycle tests from signaling the host or its process group.
    @discardableResult
    static func signalSessionProcess(
        pid: Int32, signal: Int32,
        send: (Int32, Int32) -> Int32 = { kill($0, $1) }
    ) -> Bool {
        guard pid > 0 else { return false }
        return send(pid, signal) == 0
    }

    /// Thirty seconds covers bounded acquisition plus restoration. Escalation
    /// is separate and requires the retained mapping exclusion guard.
    static func awaitGracefulSessionExit(isTerminated: () -> Bool,
                                         sendTermination: () -> Void,
                                         wait: () async -> Void) async -> Bool
    {
        if isTerminated() { return true }
        sendTermination()
        for _ in 0 ..< 600 {
            if isTerminated() { return true }
            await wait()
        }
        return isTerminated()
    }

    private func waitForSessionTermination() async {
        // A cancelled start still owns its late launch. Give shutdown the same
        // bounded grace instead of cancelled sleeps racing straight to SIGKILL.
        await Task.detached {
            try? await Task.sleep(for: .milliseconds(50))
            return ()
        }.value
    }

    private func superviseSessionRuntime(generation: UInt64) {
        #if DEBUG
            if let observe = testSessionSupervisionStarted {
                observe(generation)
                return
            }
        #endif
        guard let application = sessionApplication, let nonce = sessionNonce else { return }
        let pid = application.processIdentifier
        sessionSupervisionTask?.cancel()
        // Do not inherit ConfigurationOperationGate's active TaskLocal permit.
        // Only scalar launch identity crosses this detached boundary. The weak
        // coordinator is promoted for one actor hop, not retained between polls.
        sessionSupervisionTask = Task.detached { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled,
                      await self?.superviseSessionTick(expectedNonce: nonce, pid: pid, generation: generation) == true else { return }
            }
        }
    }

    /// All process/report ownership and recovery remain on the main actor.
    /// Returns true only when this exact launch still needs another poll.
    private func superviseSessionTick(expectedNonce: String, pid: Int32, generation: UInt64) async -> Bool {
        guard sessionStartIsCurrent(generation), sessionNonce == expectedNonce,
              let application = sessionApplication, application.processIdentifier == pid else { return false }
        if !application.isTerminated {
            if currentSessionReport() == nil {
                _ = try? await sessionOperationGate.withOperation { [self] _ in
                    await stopUnresponsiveSession(expectedGeneration: generation, nonce: expectedNonce)
                }
                return false
            }
            return true
        }
        let terminalReport = recoverSessionOutputs(for: application)
        let restored = await (try? sessionOperationGate.withOperation { @MainActor [self] _ in
            guard sessionStartIsCurrent(generation), sessionApplication === application,
                  sessionNonce == expectedNonce else { return false }
            return await restoreSessionCaps(for: application)
        }) ?? false
        guard restored, sessionStartIsCurrent(generation), sessionApplication === application,
              sessionNonce == expectedNonce else { return false }
        if terminalReport?.state == .secureInput {
            let recoveryID = UUID()
            sessionWakeRecoveryRevision &+= 1
            sessionWakeRecovery = (generation, recoveryID)
            defer {
                if sessionWakeRecovery?.id == recoveryID {
                    sessionWakeRecovery = nil
                    sessionWakeRecoveryRevision &+= 1
                    onStateChanged?()
                }
            }
            onWarning?("Remapping is paused during secure typing.")
            while IsSecureEventInputEnabled() {
                guard sessionStartIsCurrent(generation), sessionApplication === application,
                      sessionNonce == expectedNonce else { return false }
                try? await Task.sleep(for: .milliseconds(250))
            }
            guard sessionStartIsCurrent(generation), sessionApplication === application,
                  sessionNonce == expectedNonce else { return false }
            // The same lifecycle owner resumes only after Secure Input ends.
            // Other failures require explicit recovery.
            _ = await resumeSessionRuntime(expectedGeneration: generation)
            return false
        }
        if let failure = terminalReport?.recoveryReason,
           Self.isRecoverableSessionBoundary(failure)
        {
            _ = await resumeAfterSystemWake(expectedGeneration: generation,
                                            launchWakeEpoch: sessionLaunchWakeEpoch,
                                            wakeAlreadyObserved: failure != "system-will-sleep",
                                            retiredAt: terminalReport?.timestamp)
            return false
        }
        let recovery = terminalReport?.failure.map(Self.sessionFailureRecoveryMessage)
            ?? "Quit and reopen KeyPath to recover."
        onError?("Driverless remapping stopped. Original keyboard input remains available. \(recovery)")
        onStateChanged?()
        return false
    }

    static func isRecoverableSessionBoundary(_ reason: String) -> Bool {
        ["system-will-sleep", "system-wake-observed", "session-resigned-active",
         "console-session-change-observed", "console-session-inactive"].contains(reason)
    }

    /// Called only after startup cleanup, while admission is still held. The
    /// separate task waits until that admission is released before relaunching.
    @discardableResult
    func scheduleInterruptedStartupRecovery(_ report: SessionRuntimeReport?, nonce: String,
                                            pid: Int32, generation: UInt64, cleanedUp: Bool) -> Bool
    {
        guard cleanedUp, sessionStartIsCurrent(generation), let report,
              report.belongsTo(nonce: nonce, pid: pid, uid: getuid()),
              report.state == .stopped || report.state == .failed,
              Self.isRecoverableSessionBoundary(report.recoveryReason ?? "")
                || Self.canRetryWakeStartup(report, nonce: nonce, pid: pid, uid: getuid(), cleanedUp: cleanedUp) else { return false }
        let reason = report.recoveryReason
        let epoch = sessionLaunchWakeEpoch
        sessionSupervisionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await resumeAfterSystemWake(expectedGeneration: generation, launchWakeEpoch: epoch,
                                            wakeAlreadyObserved: reason != "system-will-sleep",
                                            retiredAt: report.timestamp)
        }
        return true
    }

    /// Retirement restores old output first. A wake starts through ordinary
    /// admission; it never reuses the retired worker or its event queues.
    func resumeAfterSystemWake(expectedGeneration: UInt64, launchWakeEpoch: UInt64,
                               wakeAlreadyObserved: Bool, retiredAt: Date? = nil) async -> Bool
    {
        guard sessionStartIsCurrent(expectedGeneration) else { return false }
        let recoveryID = UUID()
        sessionWakeRecoveryRevision &+= 1
        sessionWakeRecovery = (expectedGeneration, recoveryID)
        defer {
            if sessionWakeRecovery?.id == recoveryID {
                sessionWakeRecovery = nil
                sessionWakeRecoveryRevision &+= 1
                onStateChanged?()
            }
        }
        // This supervisor now owns recovery rather than the retired worker.
        // Starting/cleaning a replacement must not cancel the task running this loop.
        // Stop, Quit and newer starts still invalidate its intent generation.
        sessionSupervisionTask = nil
        onWarning?("Remapping will resume when your keyboard session is ready.")
        onStateChanged?()
        let recoveryStarted = Date()
        var lastBlocker: String?
        while sessionStartIsCurrent(expectedGeneration) {
            // Screen wake can precede system wake by tens of seconds after a
            // quick lid close/open. Only a signal after this retirement counts;
            // an earlier display wake during the old worker's life must not.
            let signalled = wakeAlreadyObserved || (retiredAt.map { retirement in
                sessionLastWakeSignalAt.map { $0 >= retirement } ?? false
            } ?? (sessionWakeEpoch != launchWakeEpoch))
            let blocker = signalled ? sessionWakeReadinessBlocker() : "wake-notification"
            if blocker != lastBlocker {
                AppLogger.shared.info("[SessionRuntime] Wake recovery gate: \(blocker ?? "ready") elapsedMs=\(Int(Date().timeIntervalSince(recoveryStarted) * 1000))")
                lastBlocker = blocker
            }
            if blocker == nil {
                AppLogger.shared.info("[SessionRuntime] Resuming after keyboard readiness")
                sessionWakeRetryGeneration = nil
                if await resumeSessionRuntime(expectedGeneration: expectedGeneration, reason: "System wake") { return true }
                guard sessionStartIsCurrent(expectedGeneration),
                      sessionWakeRetryGeneration == expectedGeneration else { return false }
                AppLogger.shared.info("[SessionRuntime] Wake startup interrupted; retrying after readiness checks")
            }
            #if DEBUG
                if let wait = testSessionWakeWait {
                    await wait()
                    continue
                }
            #endif
            do { try await Task.sleep(for: .milliseconds(250)) }
            catch { return false }
        }
        return false
    }

    static func canRetryWakeStartup(_ report: SessionRuntimeReport?, nonce: String,
                                    pid: Int32, uid: UInt32, cleanedUp: Bool) -> Bool
    {
        guard cleanedUp, let report, report.belongsTo(nonce: nonce, pid: pid, uid: uid) else { return false }
        // A late system-wake notification can retire the replacement before
        // startup has installed its supervisor. Preserve the same recovery loop
        // after verified cleanup, just as for a held-key activation race.
        if report.state == .stopped || report.state == .failed,
           report.recoveryReason == "system-wake-observed" { return true }
        return report.state == .failed
            && report.failure == "managed-caps-activation-refused: physicalKeysHeld"
    }

    private func sessionWakeReadinessBlocker() -> String? {
        #if DEBUG
            if let ready = testSessionWakeReady { return ready() ? nil : "test-not-ready" }
        #endif
        guard !IsSecureEventInputEnabled() else { return "secure-input" }
        guard let console = SessionRuntimeEnvironmentObserver.currentConsole(),
              console.uid == getuid(), console.onConsole, console.loginDone else { return "console-not-ready" }
        do { try SessionCapsRuntimeSupport.requirePhysicalAllUp(); return nil }
        catch { return "held-keys" }
    }

    /// Disabled taps can indicate revoked consent, but the notification does not
    /// prove that cause. Offer permission recovery without reporting a false denial.
    static func sessionFailureRecoveryMessage(_ failure: String) -> String {
        AppLogger.shared.error("[SessionRuntime] Terminal failure: \(failure)")
        switch failure {
        case "missing-current-process-permission":
            return "Enable \(AccessibilityPermissionPresentation.current.name) for KeyPath in System Settings, then quit and reopen KeyPath."
        case "tap-disabled-by-user-input", "tap-disabled-observed", "modifying-tap-unavailable", "modifying-tap-not-enabled":
            return "Check \(AccessibilityPermissionPresentation.current.name) for KeyPath in System Settings. If access is disabled, enable it, then quit and reopen KeyPath."
        case "managed-caps-ownership-lost":
            return "Caps Lock keyboard setup could not be verified. Connect only the selected keyboard, then quit and reopen KeyPath."
        case "tap-disabled-by-timeout":
            return "macOS stopped keyboard capture because it timed out. Quit and reopen KeyPath to recover."
        default:
            return "Quit and reopen KeyPath to recover."
        }
    }

    private func stopUnresponsiveSession(expectedGeneration: UInt64, nonce: String) async -> Bool {
        guard sessionStartIsCurrent(expectedGeneration), sessionNonce == nonce else { return false }
        sessionSupervisionTask = nil
        let stopped = await stopSessionRuntime()
        if expectedGeneration == sessionIntentGeneration {
            onError?("Driverless remapping stopped after its heartbeat was lost. Restart to recover.")
        }
        return stopped
    }

    func restoreSessionCaps(for application: NSRunningApplication?) async -> Bool {
        let directory = SessionCapsRuntimeSupport.journalDirectory()
        let nonce = sessionNonce
        let pid = application?.processIdentifier
        let parentPID = getpid(), uid = getuid()
        do {
            #if DEBUG
                if let recover = testSessionCapsRecovery {
                    try await recover()
                } else {
                    try await recoverSessionCapsOnDisk(directory: directory, nonce: nonce, pid: pid,
                                                       parentPID: parentPID, uid: uid)
                }
            #else
                try await recoverSessionCapsOnDisk(directory: directory, nonce: nonce, pid: pid,
                                                   parentPID: parentPID, uid: uid)
            #endif
            sessionRecoveryRefusal = nil
            return true
        } catch {
            let reason = "Caps mapping could not be restored safely. Restart was refused; its recovery record was retained."
            if sessionRecoveryRefusal != reason {
                sessionRecoveryRefusal = reason
                onError?(reason)
            }
            onStateChanged?()
            return false
        }
    }

    private func recoverSessionCapsOnDisk(directory: URL, nonce: String?, pid: Int32?,
                                          parentPID: Int32, uid: UInt32) async throws
    {
        try await Task.detached {
            let owner: SessionCapsMappingPolicy.Owner? = if let nonce, let pid {
                try .init(uid: uid, parentPID: parentPID, workerPID: pid, nonce: nonce,
                          generation: nonce, bootSessionUUID: SessionCapsRuntimeSupport.bootSessionUUID())
            } else { nil }
            try SessionCapsRuntimeSupport.recoverPending(directory: directory, expectedOwner: owner)
        }.value
    }

    private func recoverSessionOutputs(for application: NSRunningApplication) -> SessionRuntimeReport? {
        guard application.isTerminated, let nonce = sessionNonce,
              let report = sessionReportURL.flatMap(Self.readSessionReport),
              report.belongsTo(nonce: nonce, pid: application.processIdentifier, uid: getuid())
        else { return nil }
        if !sessionOutputsRecovered {
            releaseReportedOutputs(report)
            sessionOutputsRecovered = true
        }
        return report
    }

    private func releaseReportedOutputs(_ report: SessionRuntimeReport) {
        var state = SessionOutputState()
        for usage in report.heldOutputUsages {
            _ = try? state.translate(.init(value: 1, usagePage: 7, usage: usage))
        }
        for output in state.releaseAll() {
            guard let source = CGEventSource(stateID: .privateState),
                  let event = CGEvent(keyboardEventSource: source, virtualKey: output.keyCode, keyDown: false) else { continue }
            event.flags = CGEventFlags(rawValue: output.flags)
            event.setIntegerValueField(.eventSourceUserData, value: 0x4B50_5345_5353_494F)
            event.post(tap: .cgSessionEventTap)
        }
    }

    private func launchSessionProcess(capabilitiesOnly: Bool) async throws -> (NSRunningApplication, URL, String) {
        guard !TestEnvironment.isTestHostProcess else {
            throw KeyPathError.process(.startFailed(reason: "Session application launches are disabled in unit tests"))
        }
        let nonce = UUID().uuidString
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("keypath-session-\(nonce)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        let url = directory.appendingPathComponent("report.json")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.activates = false
        configuration.hides = true
        configuration.addsToRecentItems = false
        configuration.arguments = [
            capabilitiesOnly ? "--session-capabilities" : "--session-runtime",
            "--session-report", url.path, "--session-nonce", nonce,
            "--session-owner", String(getpid()), "--session-port", String(KeyPathConstants.Networking.defaultTCPPort),
            "--session-config", KeyPathConstants.Config.mainConfigPath
        ]
        if !capabilitiesOnly, SessionCapsRuntimeSupport.validate(configPath: KeyPathConstants.Config.mainConfigPath, runtimeHost: .current()).managedCaps,
           let device = try SessionCapsRuntimeSupport.selectedDevice()
        {
            let selection = try SessionCapsSelection(device: device, bootSessionUUID: SessionCapsRuntimeSupport.bootSessionUUID(), reservesF18: true)
            configuration.environment = try [
                SessionCapsRuntimeSupport.selectionEnvironmentKey: String(decoding: JSONEncoder().encode(selection), as: UTF8.self)
            ]
        }
        AppLogger.shared.log(
            "Session application launch requested parentPID=\(getpid()) nonce=\(nonce) capabilitiesOnly=\(capabilitiesOnly)"
        )
        do {
            let application = try await NSWorkspace.shared.openApplication(
                at: URL(fileURLWithPath: Bundle.main.bundlePath), configuration: configuration
            )
            AppLogger.shared.log(
                "Session application launch returned parentPID=\(getpid()) workerPID=\(application.processIdentifier) nonce=\(nonce) capabilitiesOnly=\(capabilitiesOnly)"
            )
            return (application, url, nonce)
        } catch {
            let launchError = error as NSError
            let redactedPaths = [directory.path, KeyPathConstants.Config.mainConfigPath,
                                 Bundle.main.bundlePath, NSHomeDirectory()]
            let description = redactedPaths.reduce(launchError.localizedDescription) {
                $0.replacingOccurrences(of: $1, with: "[redacted-path]")
            }.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
            AppLogger.shared.log(
                "Session application launch failed parentPID=\(getpid()) nonce=\(nonce) capabilitiesOnly=\(capabilitiesOnly) domain=\(launchError.domain.prefix(128)) code=\(launchError.code) description=\(description.prefix(256))"
            )
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    private static func readSessionReport(_ url: URL) -> SessionRuntimeReport? {
        guard let data = try? Data(contentsOf: url), data.count <= 16384 else { return nil }
        return try? JSONDecoder().decode(SessionRuntimeReport.self, from: data)
    }

    private static func permissionSet(_ report: SessionRuntimeReport) -> PermissionOracle.PermissionSet {
        .init(
            accessibility: report.accessibility ? .granted : .denied,
            inputMonitoring: report.effectiveInputAccess ? .granted : .denied,
            source: report.inputAccessSource ?? "session-process.apple-api.legacy-listen-event", confidence: .high, timestamp: report.timestamp
        )
    }
}
