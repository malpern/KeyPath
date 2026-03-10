import Foundation
import KeyPathCore
import ApplicationServices

private enum Launcher {
    static let retryCountPath = "/var/tmp/keypath-vhid-retry-count"
    static let startupBlockedPath = "/var/tmp/keypath-startup-blocked"
    static let maxRetries = 3
    static let retryResetSeconds: TimeInterval = 60
    static let preferencesPlistBasename = "com.keypath.KeyPath.plist"
    static let verboseLoggingPrefKey = "KeyPath.Diagnostics.VerboseKanataLogging"
    static let inProcessRuntimeEnvKey = "KEYPATH_EXPERIMENTAL_HOST_RUNTIME"
    static let outputBridgeSocketEnvKey = "KEYPATH_EXPERIMENTAL_OUTPUT_BRIDGE_SOCKET"
    static let outputBridgeSessionEnvKey = "KEYPATH_EXPERIMENTAL_OUTPUT_BRIDGE_SESSION"
    static let outputBridgeModifierProbeEnvKey = "KEYPATH_EXPERIMENTAL_OUTPUT_BRIDGE_SMOKE_MODIFIERS"
    static let outputBridgeEmitProbeEnvKey = "KEYPATH_EXPERIMENTAL_OUTPUT_BRIDGE_SMOKE_EMIT"
    static let outputBridgeResetProbeEnvKey = "KEYPATH_EXPERIMENTAL_OUTPUT_BRIDGE_SMOKE_RESET"
    static let passthruRuntimeEnvKey = "KEYPATH_EXPERIMENTAL_HOST_PASSTHRU_RUNTIME"
    static let passthruForwardEnvKey = "KEYPATH_EXPERIMENTAL_HOST_PASSTHRU_FORWARD"
    static let passthruOnlyEnvKey = "KEYPATH_EXPERIMENTAL_HOST_PASSTHRU_ONLY"
    static let passthruInjectEnvKey = "KEYPATH_EXPERIMENTAL_HOST_PASSTHRU_INJECT"
    static let passthruCaptureEnvKey = "KEYPATH_EXPERIMENTAL_HOST_PASSTHRU_CAPTURE"
    static let passthruPersistEnvKey = "KEYPATH_EXPERIMENTAL_HOST_PASSTHRU_PERSIST"
    static let passthruForwardLimit = 32
    static let passthruPollDurationEnvKey = "KEYPATH_EXPERIMENTAL_HOST_PASSTHRU_POLL_MS"
    static let passthruPollIntervalMillis: UInt32 = 25
    static let defaultPassthruPollDurationMillis: UInt64 = 1500
}

private func logLine(_ message: String) {
    FileHandle.standardError.write(Data("[kanata-launcher] \(message)\n".utf8))
}

private func readRetryCount() -> Int {
    let path = Launcher.retryCountPath
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
          let modified = attributes[.modificationDate] as? Date,
          Date().timeIntervalSince(modified) <= Launcher.retryResetSeconds,
          let raw = try? String(contentsOfFile: path, encoding: .utf8),
          let value = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines))
    else {
        try? FileManager.default.removeItem(atPath: path)
        return 0
    }
    return value
}

private func writeRetryCount(_ count: Int) {
    try? "\(count)".write(toFile: Launcher.retryCountPath, atomically: true, encoding: .utf8)
}

private func isVHIDDaemonRunning() -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    process.arguments = ["-f", "VirtualHIDDevice-Daemon"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()
    do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    } catch {
        return false
    }
}

private func consoleUser() -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/stat")
    process.arguments = ["-f%Su", "/dev/console"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()
    do {
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let user = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return user.isEmpty ? "root" : user
    } catch {
        return "root"
    }
}

private func homeDirectory(for user: String) -> String {
    guard user != "root", !user.isEmpty else { return "/var/root" }
    if let dir = FileManager.default.homeDirectory(forUser: user)?.path, !dir.isEmpty {
        return dir
    }
    return "/Users/\(user)"
}

private func ensureConfigFile(for user: String, home: String) -> String {
    let configPath = "\(home)/.config/keypath/keypath.kbd"
    let configDir = URL(fileURLWithPath: configPath).deletingLastPathComponent().path
    try? FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)
    if !FileManager.default.fileExists(atPath: configPath) {
        FileManager.default.createFile(atPath: configPath, contents: Data())
    }

    if user != "root", let pw = getpwnam(user) {
        _ = chown(configDir, pw.pointee.pw_uid, pw.pointee.pw_gid)
        _ = chown(configPath, pw.pointee.pw_uid, pw.pointee.pw_gid)
    }

    return configPath
}

private func isVerboseLoggingEnabled(home: String) -> Bool {
    let prefs = "\(home)/Library/Preferences/\(Launcher.preferencesPlistBasename)"
    guard let dict = NSDictionary(contentsOfFile: prefs),
          let value = dict[Launcher.verboseLoggingPrefKey]
    else {
        return false
    }

    switch value {
    case let number as NSNumber:
        return number.boolValue
    case let string as NSString:
        return string.boolValue
    default:
        return false
    }
}

private func execKanata(commandLine args: [String]) -> Never {
    let binaryPath = args[0]
    let cArgs = args.map { strdup($0) } + [nil]
    defer {
        for ptr in cArgs where ptr != nil {
            free(ptr)
        }
    }

    execv(binaryPath, cArgs)
    let err = String(cString: strerror(errno))
    logLine("execv failed for \(binaryPath): \(err)")
    Foundation.exit(1)
}

private func shouldUseInProcessRuntime() -> Bool {
    environmentFlag(Launcher.inProcessRuntimeEnvKey)
}

private func environmentFlag(_ key: String) -> Bool {
    let value = ProcessInfo.processInfo.environment[key]?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    return value == "1" || value == "true" || value == "yes"
}

private func environmentUInt64(_ key: String, defaultValue: UInt64) -> UInt64 {
    guard
        let raw = ProcessInfo.processInfo.environment[key]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
        let value = UInt64(raw)
    else {
        return defaultValue
    }
    return value
}

private func extractTCPPort(from arguments: [String]) -> UInt16 {
    guard let portFlagIndex = arguments.firstIndex(of: "--port"),
          arguments.indices.contains(portFlagIndex + 1),
          let port = UInt16(arguments[portFlagIndex + 1])
    else {
        return 0
    }
    return port
}

private func experimentalOutputBridgeSession() -> KanataOutputBridgeSession? {
    let environment = ProcessInfo.processInfo.environment
    guard
        let socketPath = environment[Launcher.outputBridgeSocketEnvKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
        !socketPath.isEmpty,
        let sessionID = environment[Launcher.outputBridgeSessionEnvKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
        !sessionID.isEmpty
    else {
        return nil
    }

    return KanataOutputBridgeSession(
        sessionID: sessionID,
        socketPath: socketPath,
        socketDirectory: (socketPath as NSString).deletingLastPathComponent,
        hostPID: getpid(),
        hostUID: getuid(),
        hostGID: getgid(),
        detail: "environment-provided experimental bridge session"
    )
}

private func runExperimentalOutputBridgeSmoke(
    session: KanataOutputBridgeSession
) throws {
    let handshake = try KanataOutputBridgeClient.performHandshake(session: session)
    logLine("Experimental output bridge handshake: \(String(describing: handshake))")

    let ping = try KanataOutputBridgeClient.ping(session: session)
    logLine("Experimental output bridge ping: \(String(describing: ping))")

    if environmentFlag(Launcher.outputBridgeModifierProbeEnvKey) {
        let modifiers = KanataOutputBridgeModifierState(leftShift: true)
        let response = try KanataOutputBridgeClient.syncModifiers(modifiers, session: session)
        logLine(
            "Experimental output bridge modifier sync (\(String(describing: modifiers))): \(String(describing: response))"
        )
    }

    if environmentFlag(Launcher.outputBridgeEmitProbeEnvKey) {
        let event = KanataOutputBridgeKeyEvent(
            usagePage: 0x07,
            usage: 0x68,
            action: .keyDown,
            sequence: 1
        )
        let response = try KanataOutputBridgeClient.emitKey(event, session: session)
        logLine("Experimental output bridge emit (\(String(describing: event))): \(String(describing: response))")
    }

    if environmentFlag(Launcher.outputBridgeResetProbeEnvKey) {
        let response = try KanataOutputBridgeClient.reset(session: session)
        logLine("Experimental output bridge reset: \(String(describing: response))")
    }
}

private func runExperimentalPassthruRuntimeProbe(
    runtimeHost: KanataRuntimeHost,
    configPath: String,
    tcpPort: UInt16,
    outputBridgeSession: KanataOutputBridgeSession?
) {
    guard environmentFlag(Launcher.passthruRuntimeEnvKey) else {
        return
    }

    let passthru = KanataHostBridge.createPassthruRuntime(
        runtimeHost: runtimeHost,
        configPath: configPath,
        tcpPort: tcpPort
    )
    logLine(passthru.result.logSummary)

    guard let handle = passthru.handle else {
        return
    }

    let shouldInject = environmentFlag(Launcher.passthruInjectEnvKey)
    let shouldForward = environmentFlag(Launcher.passthruForwardEnvKey)
    let shouldCapture = environmentFlag(Launcher.passthruCaptureEnvKey)
    let shouldPersist = environmentFlag(Launcher.passthruPersistEnvKey)

    if shouldForward || shouldInject || shouldCapture {
        logLine("Experimental passthru runtime starting")
        switch handle.start() {
        case .success:
            logLine("Experimental passthru runtime started")
        case let .failure(error):
            logLine(error.logSummary)
            return
        }
    }

    if shouldInject {
        switch handle.sendInput(value: 1, usagePage: 0x07, usage: 0x04) {
        case .success:
            logLine("Experimental passthru runtime injected keyDown usagePage=0x07 usage=0x04")
        case let .failure(error):
            logLine(error.logSummary)
            return
        }

        switch handle.sendInput(value: 0, usagePage: 0x07, usage: 0x04) {
        case .success:
            logLine("Experimental passthru runtime injected keyUp usagePage=0x07 usage=0x04")
        case let .failure(error):
            logLine(error.logSummary)
            return
        }
    }

    if shouldCapture {
        runExperimentalPassthruCaptureLoop(
            handle: handle,
            outputBridgeSession: outputBridgeSession,
            shouldForward: shouldForward
        )
        return
    }

    if shouldPersist {
        var forwardedCount = 0
        logLine("Experimental passthru persistent non-capture loop starting")
        while true {
            _ = drainExperimentalPassthruOutput(
                handle: handle,
                outputBridgeSession: outputBridgeSession,
                shouldForward: shouldForward,
                forwardedCount: &forwardedCount,
                maxForwardCount: nil
            )
            usleep(Launcher.passthruPollIntervalMillis * 1_000)
        }
    }

    let shouldPoll = shouldForward || shouldInject
    let pollDurationMillis = environmentUInt64(
        Launcher.passthruPollDurationEnvKey,
        defaultValue: Launcher.defaultPassthruPollDurationMillis
    )
    let pollDeadline = DispatchTime.now().uptimeNanoseconds + (pollDurationMillis * 1_000_000)

    var forwardedCount = 0
    var sawEmptyPoll = false
    logLine("Experimental passthru runtime entering poll loop")
    while forwardedCount < Launcher.passthruForwardLimit {
        switch handle.tryReceiveOutput() {
        case let .success(event):
            guard let event else {
                if !shouldPoll || DispatchTime.now().uptimeNanoseconds >= pollDeadline {
                    if forwardedCount == 0 {
                        logLine("Experimental passthru runtime output channel is currently empty")
                    } else {
                        logLine("Experimental passthru runtime forwarded \(forwardedCount) output event(s)")
                    }
                    return
                }

                if !sawEmptyPoll {
                    logLine("Experimental passthru runtime output channel is currently empty")
                    sawEmptyPoll = true
                }
                usleep(Launcher.passthruPollIntervalMillis * 1_000)
                continue
            }

            logLine(
                "Experimental passthru runtime drained output event: value=\(event.value) page=\(event.usagePage) code=\(event.usage)"
            )

            guard shouldForward else {
                forwardedCount += 1
                continue
            }

            guard let outputBridgeSession else {
                logLine("Experimental passthru forwarding requested but no output bridge session was provided")
                return
            }

            let bridgeEvent = KanataOutputBridgeKeyEvent(
                usagePage: event.usagePage,
                usage: event.usage,
                action: event.value == 0 ? .keyUp : .keyDown,
                sequence: UInt64(forwardedCount + 1)
            )

            do {
                let response = try KanataOutputBridgeClient.emitKey(bridgeEvent, session: outputBridgeSession)
                logLine(
                    "Experimental passthru forwarded output event: \(String(describing: bridgeEvent)) -> \(String(describing: response))"
                )
            } catch {
                logLine("Experimental passthru forwarding failed: \(error.localizedDescription)")
                return
            }

            forwardedCount += 1
            sawEmptyPoll = false
        case let .failure(error):
            logLine(error.logSummary)
            return
        }
    }

    logLine("Experimental passthru runtime hit forwarding limit of \(Launcher.passthruForwardLimit) event(s)")
}

private func drainExperimentalPassthruOutput(
    handle: KanataHostBridgePassthruRuntimeHandle,
    outputBridgeSession: KanataOutputBridgeSession?,
    shouldForward: Bool,
    forwardedCount: inout Int,
    maxForwardCount: Int?
) -> Bool {
    while maxForwardCount.map({ forwardedCount < $0 }) ?? true {
        switch handle.tryReceiveOutput() {
        case let .success(event):
            guard let event else {
                return false
            }

            logLine(
                "Experimental passthru runtime drained output event: value=\(event.value) page=\(event.usagePage) code=\(event.usage)"
            )

            guard shouldForward else {
                forwardedCount += 1
                continue
            }

            guard let outputBridgeSession else {
                logLine("Experimental passthru forwarding requested but no output bridge session was provided")
                return true
            }

            let bridgeEvent = KanataOutputBridgeKeyEvent(
                usagePage: event.usagePage,
                usage: event.usage,
                action: event.value == 0 ? .keyUp : .keyDown,
                sequence: UInt64(forwardedCount + 1)
            )

            do {
                let response = try KanataOutputBridgeClient.emitKey(bridgeEvent, session: outputBridgeSession)
                logLine(
                    "Experimental passthru forwarded output event: \(String(describing: bridgeEvent)) -> \(String(describing: response))"
                )
            } catch {
                logLine("Experimental passthru forwarding failed: \(error.localizedDescription)")
                return true
            }

            forwardedCount += 1
        case let .failure(error):
            logLine(error.logSummary)
            return true
        }
    }

    return true
}

private func runExperimentalPassthruCaptureLoop(
    handle: KanataHostBridgePassthruRuntimeHandle,
    outputBridgeSession: KanataOutputBridgeSession?,
    shouldForward: Bool
) {
    let shouldPersist = environmentFlag(Launcher.passthruPersistEnvKey)
    let durationMillis = environmentUInt64(
        Launcher.passthruPollDurationEnvKey,
        defaultValue: Launcher.defaultPassthruPollDurationMillis
    )
    let deadline = Date().addingTimeInterval(TimeInterval(durationMillis) / 1000)
    final class CaptureState {
        let handle: KanataHostBridgePassthruRuntimeHandle
        let outputBridgeSession: KanataOutputBridgeSession?
        let shouldForward: Bool
        let shouldPersist: Bool
        var forwardedCount = 0

        init(
            handle: KanataHostBridgePassthruRuntimeHandle,
            outputBridgeSession: KanataOutputBridgeSession?,
            shouldForward: Bool,
            shouldPersist: Bool
        ) {
            self.handle = handle
            self.outputBridgeSession = outputBridgeSession
            self.shouldForward = shouldForward
            self.shouldPersist = shouldPersist
        }
    }
    let state = CaptureState(
        handle: handle,
        outputBridgeSession: outputBridgeSession,
        shouldForward: shouldForward,
        shouldPersist: shouldPersist
    )

    logLine("Experimental passthru capture loop starting")
    let refcon = Unmanaged.passRetained(state).toOpaque()
    let eventMask = (1 << CGEventType.keyDown.rawValue)
        | (1 << CGEventType.keyUp.rawValue)
        | (1 << CGEventType.flagsChanged.rawValue)

    let eventTap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .listenOnly,
        eventsOfInterest: CGEventMask(eventMask),
        callback: { _, _, event, refcon in
            guard let refcon else {
                return Unmanaged.passUnretained(event)
            }

            let state = Unmanaged<CaptureState>.fromOpaque(refcon).takeUnretainedValue()
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let isKeyDown: Bool

            switch event.type {
            case .keyDown:
                if event.getIntegerValueField(.keyboardEventAutorepeat) == 1 {
                    return Unmanaged.passUnretained(event)
                }
                isKeyDown = true
            case .keyUp:
                isKeyDown = false
            case .flagsChanged:
                let modifierMask = event.flags
                switch keyCode {
                case 55, 54:
                    isKeyDown = modifierMask.contains(.maskCommand)
                case 56, 60:
                    isKeyDown = modifierMask.contains(.maskShift)
                case 58, 61:
                    isKeyDown = modifierMask.contains(.maskAlternate)
                case 59, 62:
                    isKeyDown = modifierMask.contains(.maskControl)
                case 57:
                    isKeyDown = modifierMask.contains(.maskAlphaShift)
                default:
                    return Unmanaged.passUnretained(event)
                }
            default:
                return Unmanaged.passUnretained(event)
            }

            guard let inputEvent = ExperimentalHostPassthruInputMapper.eventForKeyCode(keyCode, isKeyDown: isKeyDown) else {
                logLine("Experimental passthru capture ignoring unsupported mac keyCode=\(keyCode)")
                return Unmanaged.passUnretained(event)
            }

            switch state.handle.sendInput(
                value: inputEvent.value,
                usagePage: inputEvent.usagePage,
                usage: inputEvent.usage
            ) {
            case .success:
                logLine(
                    "Experimental passthru captured mac keyCode=\(keyCode) -> usagePage=\(inputEvent.usagePage) usage=\(inputEvent.usage) value=\(inputEvent.value)"
                )
                _ = drainExperimentalPassthruOutput(
                    handle: state.handle,
                    outputBridgeSession: state.outputBridgeSession,
                    shouldForward: state.shouldForward,
                    forwardedCount: &state.forwardedCount,
                    maxForwardCount: state.shouldPersist ? nil : Launcher.passthruForwardLimit
                )
            case let .failure(error):
                logLine(error.logSummary)
            }

            return Unmanaged.passUnretained(event)
        },
        userInfo: refcon
    )

    defer {
        Unmanaged<CaptureState>.fromOpaque(refcon).release()
        if let eventTap {
            CFMachPortInvalidate(eventTap)
        }
    }

    guard let eventTap else {
        logLine("Experimental passthru capture failed to create CGEvent tap")
        return
    }

    let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
    CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
    CGEvent.tapEnable(tap: eventTap, enable: true)

    while shouldPersist || (Date() < deadline && state.forwardedCount < Launcher.passthruForwardLimit) {
        _ = drainExperimentalPassthruOutput(
            handle: handle,
            outputBridgeSession: outputBridgeSession,
            shouldForward: shouldForward,
            forwardedCount: &state.forwardedCount,
            maxForwardCount: shouldPersist ? nil : Launcher.passthruForwardLimit
        )
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.025))
    }

    _ = drainExperimentalPassthruOutput(
        handle: handle,
        outputBridgeSession: outputBridgeSession,
        shouldForward: shouldForward,
        forwardedCount: &state.forwardedCount,
        maxForwardCount: shouldPersist ? nil : Launcher.passthruForwardLimit
    )

    if shouldPersist {
        logLine("Experimental passthru persistent capture loop exited after forwarding \(state.forwardedCount) output event(s)")
    } else {
        logLine("Experimental passthru capture loop completed with \(state.forwardedCount) forwarded output event(s)")
    }
}

private func handleMissingVHID() -> Never {
    let retryCount = readRetryCount() + 1
    writeRetryCount(retryCount)
    logLine("VirtualHID daemon not running (attempt \(retryCount)/\(Launcher.maxRetries))")

    if retryCount >= Launcher.maxRetries {
        let message = "\(Date()): VirtualHID daemon not available after \(Launcher.maxRetries) attempts\n"
        try? message.write(toFile: Launcher.startupBlockedPath, atomically: true, encoding: .utf8)
        logLine("Max retries reached. Exiting cleanly to stop restart loop.")
        Foundation.exit(0)
    }

    Foundation.exit(1)
}

@main
struct KeyPathKanataLauncher {
    static func main() {
        guard isVHIDDaemonRunning() else {
            handleMissingVHID()
        }

        try? FileManager.default.removeItem(atPath: Launcher.retryCountPath)
        try? FileManager.default.removeItem(atPath: Launcher.startupBlockedPath)

        let user = consoleUser()
        let home = homeDirectory(for: user)
        let configPath = ensureConfigFile(for: user, home: home)
        let runtimeHost = KanataRuntimeHost.current()
        let addTrace = isVerboseLoggingEnabled(home: home)

        let launchRequest = KanataRuntimeLaunchRequest(
            configPath: configPath,
            inheritedArguments: Array(CommandLine.arguments.dropFirst()),
            addTraceLogging: addTrace
        )
        let binaryPath = launchRequest.resolvedCoreBinaryPath(using: runtimeHost)
        let commandLine = launchRequest.commandLine(binaryPath: binaryPath)

        logLine("Launching Kanata for user=\(user) config=\(configPath)")
        logLine("Runtime host path: \(runtimeHost.launcherPath)")
        logLine(KanataHostBridge.probe(runtimeHost: runtimeHost).logSummary)
        logLine(KanataHostBridge.validateConfig(runtimeHost: runtimeHost, configPath: configPath).logSummary)
        logLine(KanataHostBridge.createRuntime(runtimeHost: runtimeHost, configPath: configPath).logSummary)

        if shouldUseInProcessRuntime() {
            let tcpPort = extractTCPPort(from: launchRequest.inheritedArguments)
            logLine("Running in-process host runtime mode")
            let outputBridgeSession = experimentalOutputBridgeSession()
            runExperimentalPassthruRuntimeProbe(
                runtimeHost: runtimeHost,
                configPath: configPath,
                tcpPort: tcpPort,
                outputBridgeSession: outputBridgeSession
            )
            if environmentFlag(Launcher.passthruOnlyEnvKey) {
                logLine("Experimental passthru-only host mode completed")
                Foundation.exit(0)
            }
            if let outputBridgeSession {
                do {
                    try runExperimentalOutputBridgeSmoke(session: outputBridgeSession)
                } catch {
                    logLine("Experimental output bridge smoke test failed: \(error.localizedDescription)")
                    Foundation.exit(1)
                }
            } else {
                logLine("Experimental output bridge session not provided; skipping socket smoke test")
            }
            let result = KanataHostBridge.runRuntime(
                runtimeHost: runtimeHost,
                configPath: configPath,
                tcpPort: tcpPort
            )
            logLine(result.logSummary)
            Foundation.exit(result == .completed ? 0 : 1)
        }

        logLine("Using kanata binary: \(binaryPath)")
        if addTrace {
            logLine("Verbose logging enabled via user preference (--trace)")
        }

        execKanata(commandLine: commandLine)
    }
}
