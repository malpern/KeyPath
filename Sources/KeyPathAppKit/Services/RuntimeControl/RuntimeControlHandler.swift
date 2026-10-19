import Foundation
import KeyPathCore

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
        let ok: Bool = switch request.operation {
        case .status: true
        case .start: await manager.startKanata(reason: reason)
        case .stop: await manager.stopKanata(reason: reason)
        case .restart: await manager.restartKanata(reason: reason)
        }
        let status = await manager.currentRuntimeStatusInternal()
        return response(ok: ok, operation: request.operation, status: status, lastError: manager.lastError)
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
