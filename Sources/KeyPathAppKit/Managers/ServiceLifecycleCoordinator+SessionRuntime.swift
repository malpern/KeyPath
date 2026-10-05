import AppKit
import Carbon
import KeyPathCore
import KeyPathPermissions

extension ServiceLifecycleCoordinator {
    func currentSessionReport() -> SessionRuntimeReport? {
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
            // Signal only the independently launched process owned by this call.
            if !application.isTerminated { kill(application.processIdentifier, SIGTERM) }
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
            let failure = terminalReport?.failure == "missing-current-process-permission"
                ? "Enable Accessibility and Input Monitoring for KeyPath in System Settings, then quit and reopen KeyPath."
                : terminalReport?.failure
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
            _ = await stopSessionRuntime()
            if sessionStartIsCurrent(generation) { onError?("Driverless runtime could not start: \(failure ?? "no current tap and TCP evidence")") }
        } catch {
            if didLaunch { _ = await stopSessionRuntime() }
            if sessionStartIsCurrent(generation) { onError?("Driverless runtime launch failed: \(error.localizedDescription)") }
        }
        onStateChanged?()
        return false
    }

    private func adoptRunningSession(generation: UInt64, responding: Bool) async -> Bool {
        guard sessionStartIsCurrent(generation) else { return false }
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
            kill(application.processIdentifier, SIGTERM)
            for _ in 0 ..< 40 {
                if application.isTerminated { break }
                await waitForSessionTermination()
            }
            if !application.isTerminated {
                kill(application.processIdentifier, SIGKILL)
                for _ in 0 ..< 20 {
                    if application.isTerminated { break }
                    await waitForSessionTermination()
                }
                guard application.isTerminated else {
                    onError?("Driverless runtime did not stop; restart was refused.")
                    return false
                }
            }
        }
        // Never clear a different launch's fields or delete its durable ledger.
        guard sessionApplication === application, sessionNonce == nonce,
              sessionReportURL == reportURL else { return false }
        if let application { _ = recoverSessionOutputs(for: application) }
        guard await restoreSessionCaps(for: application) else { return false }
        if let reportURL {
            try? FileManager.default.removeItem(at: reportURL.deletingLastPathComponent())
        }
        sessionApplication = nil
        sessionReportURL = nil
        sessionNonce = nil
        sessionOutputsRecovered = false
        onStateChanged?()
        return true
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
        onError?("Driverless remapping stopped. Original keyboard input remains available; restart to recover.")
        onStateChanged?()
        return false
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

    private func restoreSessionCaps(for application: NSRunningApplication?) async -> Bool {
        let directory = SessionCapsRuntimeSupport.journalDirectory()
        let nonce = sessionNonce
        let pid = application?.processIdentifier
        let parentPID = getpid(), uid = getuid()
        do {
            try await Task.detached {
                let owner: SessionCapsMappingPolicy.Owner? = if let nonce, let pid {
                    try .init(uid: uid, parentPID: parentPID, workerPID: pid, nonce: nonce,
                              generation: nonce, bootSessionUUID: SessionCapsRuntimeSupport.bootSessionUUID())
                } else { nil }
                try SessionCapsRuntimeSupport.recoverPending(directory: directory, expectedOwner: owner)
            }.value
            return true
        } catch {
            onError?("Caps mapping could not be restored safely. Restart was refused; its recovery record was retained.")
            return false
        }
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
        configuration.addsToRecentItems = false
        configuration.arguments = [
            capabilitiesOnly ? "--session-capabilities" : "--session-runtime",
            "--session-report", url.path, "--session-nonce", nonce,
            "--session-owner", String(getpid()), "--session-port", "37001",
            "--session-config", KeyPathConstants.Config.mainConfigPath
        ]
        if !capabilitiesOnly, let device = try SessionCapsRuntimeSupport.experimentalDevice() {
            let encoded = try JSONEncoder().encode(device)
            configuration.environment = [
                "KEYPATH_EXPERIMENTAL_MANAGED_CAPS_DEVICE": String(decoding: encoded, as: UTF8.self),
                "KEYPATH_EXPERIMENTAL_MANAGED_CAPS_RESERVE_F18": "1"
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
