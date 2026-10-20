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
            return await uninstall(confirmed: request.confirmed == true, manager: manager)
        }
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
        let report = await InstallerEngine().run(intent: .repair, using: PrivilegeBroker())
        if await !manager.currentRuntimeStatusInternal().isRunning {
            _ = await manager.startKanata(reason: reason)
        }
        return await doctor(operation: .repair, ok: report.success, message: report.failureReason, manager: manager)
    }

    /// The app's own uninstall. On success the app quits shortly after answering.
    static func uninstall(confirmed: Bool, manager: RuntimeCoordinator) async -> RuntimeControl.Response {
        let status = await manager.currentRuntimeStatusInternal()
        guard confirmed else {
            var refused = response(ok: false, operation: .uninstall, status: status, lastError: nil)
            refused.message = "Uninstall needs confirmation; nothing was changed."
            return refused
        }
        RuntimeControlServer.shared.withdrawForUninstall()
        // The same entry point as Settings' Uninstall dialog. It also records that
        // cleanup finished, which is what lets the app quit afterwards.
        let report = await manager.uninstall(deleteConfig: true)
        if !report.success { RuntimeControlServer.shared.restoreAfterFailedUninstall() }
        var answer = await response(ok: report.success, operation: .uninstall,
                                    status: manager.currentRuntimeStatusInternal(), lastError: nil)
        answer.message = report.success ? report.logs.first : report.failureReason
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
                         status: ServiceLifecycleCoordinator.RuntimeStatus, lastError: String?) -> RuntimeControl.Response
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
}
