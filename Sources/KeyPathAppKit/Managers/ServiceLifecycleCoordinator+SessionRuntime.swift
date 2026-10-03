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

    func startSessionRuntime(reason: String) async -> Bool {
        if let report = currentSessionReport(), report.state == .running, report.tapActive {
            return await SystemStateProvider.shared.isTCPPortResponding(port: Int(report.tcpPort), timeoutMs: 300)
        }
        guard await stopSessionRuntime() else { return false }
        // A legacy runtime cannot coexist with a modifying session tap. Do not
        // terminate or migrate a privileged installation implicitly.
        if await kanataDaemonService.isDaemonRunning() {
            onError?("Stop the existing keyboard service before trying driverless mode.")
            return false
        }
        isStartingKanata = true
        defer { isStartingKanata = false }
        do {
            let (application, url, nonce) = try await launchSessionProcess(capabilitiesOnly: false)
            sessionApplication = application
            sessionReportURL = url
            sessionNonce = nonce
            for _ in 0 ..< 40 {
                if let report = currentSessionReport() {
                    if report.state == .running, report.tapActive,
                       await SystemStateProvider.shared.isTCPPortResponding(port: Int(report.tcpPort), timeoutMs: 300)
                    {
                        AppLogger.shared.log("Session runtime ready (\(reason))")
                        await AppContextService.shared.start()
                        onError?(nil)
                        onWarning?(nil)
                        onStateChanged?()
                        superviseSessionRuntime()
                        return true
                    }
                    if report.state == .failed || report.state == .secureInput { break }
                }
                if application.isTerminated { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            let failure = sessionReportURL.flatMap(Self.readSessionReport)?.failure
            _ = await stopSessionRuntime()
            onError?("Driverless runtime could not start: \(failure ?? "no current tap and TCP evidence")")
        } catch {
            onError?("Driverless runtime launch failed: \(error.localizedDescription)")
        }
        onStateChanged?()
        return false
    }

    func stopSessionRuntime() async -> Bool {
        sessionSupervisionTask?.cancel()
        sessionSupervisionTask = nil
        await AppContextService.shared.stop()
        if let application = sessionApplication, !application.isTerminated {
            kill(application.processIdentifier, SIGTERM)
            for _ in 0 ..< 40 {
                if application.isTerminated { break }
                try? await Task.sleep(for: .milliseconds(50))
            }
            if !application.isTerminated {
                // Only this launch's NSRunningApplication is eligible. Preserve
                // its final emitted-key ledger before terminating a hung worker.
                let report = sessionReportURL.flatMap(Self.readSessionReport)
                kill(application.processIdentifier, SIGKILL)
                for _ in 0 ..< 20 {
                    if application.isTerminated { break }
                    try? await Task.sleep(for: .milliseconds(50))
                }
                guard application.isTerminated else {
                    onError?("Driverless runtime did not stop; restart was refused.")
                    return false
                }
                if let report, report.nonce == sessionNonce, report.pid == application.processIdentifier,
                   report.uid == getuid() { releaseReportedOutputs(report) }
            }
        }
        if let url = sessionReportURL {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        sessionApplication = nil
        sessionReportURL = nil
        sessionNonce = nil
        onStateChanged?()
        return true
    }

    private func superviseSessionRuntime() {
        sessionSupervisionTask?.cancel()
        sessionSupervisionTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled, let self, let application = sessionApplication else { return }
                if !application.isTerminated {
                    if currentSessionReport() == nil {
                        sessionSupervisionTask = nil
                        _ = await stopSessionRuntime()
                        onError?("Driverless remapping stopped after its heartbeat was lost. Restart to recover.")
                        return
                    }
                    continue
                }
                let report = sessionReportURL.flatMap(Self.readSessionReport)
                if let report, let nonce = sessionNonce,
                   report.isCurrent(nonce: nonce, pid: application.processIdentifier, uid: getuid(), now: Date())
                {
                    releaseReportedOutputs(report)
                    if report.state == .secureInput {
                        onWarning?("Remapping is paused during secure typing.")
                        while IsSecureEventInputEnabled(), !Task.isCancelled {
                            try? await Task.sleep(for: .milliseconds(250))
                        }
                        guard !Task.isCancelled else { return }
                        // The same lifecycle owner resumes only after Secure Input
                        // ends. Other failures require explicit recovery.
                        sessionSupervisionTask = nil
                        _ = await startSessionRuntime(reason: "Secure typing ended")
                        return
                    }
                }
                onError?("Driverless remapping stopped. Original keyboard input remains available; restart to recover.")
                onStateChanged?()
                return
            }
        }
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
        do {
            let application = try await NSWorkspace.shared.openApplication(
                at: URL(fileURLWithPath: Bundle.main.bundlePath), configuration: configuration
            )
            return (application, url, nonce)
        } catch {
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
            source: "session-process.apple-api", confidence: .high, timestamp: report.timestamp
        )
    }
}
