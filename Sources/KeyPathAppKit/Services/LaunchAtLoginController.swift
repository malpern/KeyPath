import Foundation
import Observation
import ServiceManagement

/// The system registration is the source of truth; no parallel preference or daemon.
@MainActor
@Observable
final class LaunchAtLoginController {
    static let shared = LaunchAtLoginController()

    private(set) var status: SMAppService.Status = .notRegistered
    private(set) var isBusy = false
    private(set) var hasLoaded = false
    private let service: any SMAppServiceProtocol
    private let statusProvider: SMAppServiceStatusProvider

    init(service: any SMAppServiceProtocol = NativeSMAppService(wrapped: .mainApp)) {
        self.service = service
        statusProvider = SMAppServiceStatusProvider(serviceFactory: { _ in service })
    }

    var isEnabled: Bool { status == .enabled || status == .requiresApproval }

    func refresh() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        status = await readStatus()
        hasLoaded = true
    }

    func setEnabled(_ enabled: Bool) async throws {
        guard !isBusy else { throw ChangeError.busy }
        isBusy = true
        defer { isBusy = false }
        let service = service
        let current = await readStatus()
        do {
            // Apple's synchronous IPC must never block the UI actor.
            try await Task.detached {
                if enabled {
                    if current != .enabled && current != .requiresApproval {
                        try service.register()
                    }
                } else if current == .enabled || current == .requiresApproval {
                    try await service.unregister()
                }
            }.value
        } catch {
            status = await readStatus()
            hasLoaded = true
            throw error
        }
        status = await readStatus()
        hasLoaded = true
        guard enabled ? isEnabled : !isEnabled else { throw ChangeError.notApplied }
    }

    private func readStatus() async -> SMAppService.Status {
        await statusProvider.freshStatus(for: "main-app")
    }

    enum ChangeError: LocalizedError {
        case busy, notApplied
        var errorDescription: String? {
            switch self {
            case .busy: "A login setting change is still in progress. Try again in a moment."
            case .notApplied: "macOS did not apply the login setting. Check Login Items in System Settings."
            }
        }
    }
}
