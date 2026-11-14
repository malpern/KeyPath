import AppKit
import Foundation
import KeyPathCore
import KeyPathInstallationWizard
import KeyPathWizardCore

/// Answers `RuntimeControl` requests from the app's own view of the runtime.
/// Lifecycle changes go through `RuntimeCoordinator`, which serializes them with
/// every other start, stop and restart (UI, wake recovery, updates).
@MainActor
enum RuntimeControlHandler {
    static func make(for manager: RuntimeCoordinator) -> RuntimeControlServer.Handler {
        { [weak manager] request in
            guard let manager else {
                return response(ok: false, operation: request.operation, status: .unknown, lastError: "KeyPath is shutting down")
            }
            return await handle(request, manager: manager)
        }
    }

    static func handle(_ request: RuntimeControl.Request, manager: RuntimeCoordinator) async -> RuntimeControl.Response {
        let reason = request.reason.map { "CLI: \($0)" } ?? "CLI \(request.operation.rawValue)"
        switch request.operation {
        case .status, .start, .stop, .restart:
            let ok: Bool = switch request.operation {
            case .start: await manager.startKanata(reason: reason)
            case .stop: await manager.stopKanata(reason: reason)
            case .restart: await manager.restartKanata(reason: reason)
            default: true
            }
            let status = await manager.currentRuntimeStatusInternal()
            return response(ok: ok, operation: request.operation, status: status, lastError: manager.lastError)
        case .doctor:
            return await doctor(operation: .doctor, ok: true, message: nil, manager: manager)
        case .repair:
            return await repair(manager: manager, reason: reason)
        case .uninstall:
            return await uninstall(confirmed: request.confirmed == true,
                                   resetPermissions: request.argument == RuntimeControl.Request.resetPermissionsArgument,
                                   manager: manager)
        case .reload, .layer, .layers, .changeLayer, .hrmStats, .resetHrmStats:
            return await engine(request, manager: manager)
        }
    }

    /// Engine commands for the CLI, sent on the app's own connection: the
    /// engine admits only this process (ADR-046). Reload goes through the
    /// reload coordinator, like every other reload.
    static func engine(_ request: RuntimeControl.Request, manager: RuntimeCoordinator) async -> RuntimeControl.Response {
        let status = await manager.currentRuntimeStatusInternal()
        var answer = response(ok: true, operation: request.operation, status: status, lastError: nil)
        let client = KanataTCPClient(timeout: 3.0)
        defer { Task { await client.cancelInflightAndCloseConnection() } }
        do {
            switch request.operation {
            case .reload:
                let result = await manager.triggerConfigReload()
                answer = await response(ok: result.isSuccess, operation: .reload,
                                        status: manager.currentRuntimeStatusInternal(),
                                        lastError: result.isSuccess ? nil : result.errorMessage)
            case .layer:
                answer.layer = try await client.requestCurrentLayerName()
            case .layers:
                answer.layers = try await client.requestLayerNames()
            case .changeLayer:
                guard let name = request.argument, !name.isEmpty else {
                    return response(ok: false, operation: .changeLayer, status: status, lastError: "No layer name given")
                }
                switch await client.changeLayer(name) {
                case .success: break
                case let .error(message), let .networkError(message):
                    return response(ok: false, operation: .changeLayer, status: status, lastError: message)
                }
            case .hrmStats:
                let stats = try await client.requestHrmStats()
                answer.hrmStats = .init(totalDecisions: stats.decisionsTotal, tapCount: stats.tapCount,
                                        holdCount: stats.holdCount)
            case .resetHrmStats:
                try await client.resetHrmStats()
            default:
                break
            }
        } catch {
            return response(ok: false, operation: request.operation, status: status,
                            lastError: "The remapping engine did not answer: \(error.localizedDescription)")
        }
        return answer
    }

    /// The same inspection `keypath system inspect` and the About window use, run
    /// inside the app so it sees this process's permissions and its runtime.
    static func doctor(operation: RuntimeControl.Operation, ok: Bool, message: String?,
                       manager: RuntimeCoordinator) async -> RuntimeControl.Response
    {
        let context = await InstallerEngine().inspectSystem()
        let issues = SystemFacade.issues(from: context).map { issue in
            RuntimeControl.Issue(title: issue.title, category: issue.category, fix: issue.action,
                                 needsUser: issue.requiresUserAction, settingsURL: issue.remediationURL)
        }
        let status = await manager.currentRuntimeStatusInternal()
        var result = response(ok: ok, operation: operation, status: status, lastError: manager.lastError)
        result.ready = SystemFacade.isOperational(context) && status.isRunning
        result.issues = issues
        result.message = message
        result.admission = manager.ruleCollectionsManager.admissionFindings()
        return result
    }

    /// The About window's Repair, then start remapping unless a person is needed.
    static func repair(manager: RuntimeCoordinator, reason: String) async -> RuntimeControl.Response {
        let report = await InstallerEngine().run(intent: .repair)
        if await !manager.currentRuntimeStatusInternal().isRunning {
            _ = await manager.startKanata(reason: reason)
        }
        return await doctor(operation: .repair, ok: report.success, message: report.failureReason, manager: manager)
    }

    /// Asks the person at the Mac before a CLI uninstall. `--yes` proves only
    /// that some process running as the user sent the request, and uninstall
    /// deletes the config. Cancel is the default. The dialog closes itself as
    /// "cancelled" before the CLI stops waiting (120 s), so a late click can
    /// never uninstall after the CLI reported a failure. Replaceable for tests.
    @MainActor static var confirmUninstallFromCLI: @MainActor () -> Bool = {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Uninstall KeyPath?")
        alert.informativeText = String(localized: "The keypath command asked to remove KeyPath and delete your configuration. Your remapping stops.")
        alert.addButton(withTitle: String(localized: "Cancel")).setAccessibilityIdentifier("cli-uninstall-cancel-button")
        let uninstall = alert.addButton(withTitle: String(localized: "Uninstall"))
        uninstall.setAccessibilityIdentifier("cli-uninstall-confirm-button")
        uninstall.hasDestructiveAction = true
        NSApp.activate()
        let timeout = Timer(timeInterval: cliConfirmationTimeout, repeats: false) { _ in
            // The timer fires on the main run loop, in the modal panel mode.
            MainActor.assumeIsolated { NSApp.abortModal() }
        }
        RunLoop.main.add(timeout, forMode: .modalPanel)
        defer { timeout.invalidate() }
        return alert.runModal() == .alertSecondButtonReturn
    }

    /// Shorter than the CLI's 120-second wait.
    static let cliConfirmationTimeout: TimeInterval = 100

    /// Why a CLI uninstall stops before changing anything, or nil to go ahead.
    @MainActor static func uninstallRefusal(confirmed: Bool, ask: () -> Bool) -> String? {
        guard confirmed else { return "Uninstall needs confirmation; nothing was changed." }
        guard ask() else { return "Uninstall was not confirmed in KeyPath; nothing was changed." }
        return nil
    }

    /// The app's own uninstall. On success the app quits shortly after answering.
    static func uninstall(confirmed: Bool, resetPermissions: Bool = false,
                          manager: RuntimeCoordinator) async -> RuntimeControl.Response
    {
        let status = await manager.currentRuntimeStatusInternal()
        if let refusal = await MainActor.run(body: { uninstallRefusal(confirmed: confirmed, ask: confirmUninstallFromCLI) }) {
            var refused = response(ok: false, operation: .uninstall, status: status, lastError: nil)
            refused.message = refusal
            return refused
        }
        // tccutil finds the app by bundle id, which fails once it is in the
        // Trash, so clear the entries now, after the person confirmed.
        let permissionNote = resetPermissions ? resetPermissionEntries() : nil
        RuntimeControlServer.shared.withdrawForUninstall()
        // The same entry point as Settings' Uninstall dialog. It also records that
        // cleanup finished, which is what lets the app quit afterwards.
        let report = await manager.uninstall(deleteConfig: true)
        if !report.success { RuntimeControlServer.shared.restoreAfterFailedUninstall() }
        var answer = await response(ok: report.success, operation: .uninstall,
                                    status: manager.currentRuntimeStatusInternal(), lastError: nil)
        answer.message = [report.success ? report.logs.first : report.failureReason, permissionNote]
            .compactMap { $0 }.joined(separator: "\n")
        if report.success {
            // Answer first, then quit as the dialog does, from the run loop.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                DispatchQueue.main.async { NSApplication.shared.terminate(nil) }
            }
        }
        return answer
    }

    static func response(ok: Bool, operation: RuntimeControl.Operation,
                         status: RuntimeStatus, lastError: String?) -> RuntimeControl.Response
    {
        let state: RuntimeControl.State
        var workerPID: Int?
        var failure: String?
        switch status {
        case let .running(pid):
            state = .running
            workerPID = pid
        case .starting: state = .starting
        case .stopped: state = .stopped
        case let .failed(reason):
            state = .failed
            failure = reason
        case .unknown: state = .unknown
        }
        return RuntimeControl.Response(
            ok: ok, operation: operation, state: state, workerPID: workerPID, failure: failure,
            lastError: lastError, layer: DistributedNotificationBridge.currentLayer,
            appPID: ProcessInfo.processInfo.processIdentifier,
            appVersion: BuildInfo.current().version
        )
    }

    /// Clears KeyPath's privacy entries. ListenEvent and PostEvent rows may
    /// remain from builds or prompts that requested them.
    static func resetPermissionEntries() -> String {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.keypath.KeyPath"
        var cleared = 0
        for service in ["Accessibility", "ListenEvent", "PostEvent"] {
            let tcc = Process()
            tcc.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            tcc.arguments = ["reset", service, bundleID]
            tcc.standardOutput = FileHandle.nullDevice
            tcc.standardError = FileHandle.nullDevice
            if (try? tcc.run()) != nil {
                tcc.waitUntilExit()
                if tcc.terminationStatus == 0 { cleared += 1 }
            }
        }
        return cleared == 3 ? "Permission entries cleared."
            : "Some permission entries could not be cleared; remove KeyPath in System Settings > Privacy & Security."
    }
}
