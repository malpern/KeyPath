import ServiceManagement

/// Test seam over `SMAppService`, used by launch-at-login (`SMAppService.mainApp`).
protocol SMAppServiceProtocol: Sendable {
    var status: ServiceManagement.SMAppService.Status { get }
    func register() throws
    func unregister() async throws
}

struct NativeSMAppService: SMAppServiceProtocol, @unchecked Sendable {
    private let wrapped: ServiceManagement.SMAppService
    init(wrapped: ServiceManagement.SMAppService) {
        self.wrapped = wrapped
    }

    var status: ServiceManagement.SMAppService.Status {
        wrapped.status
    }

    func register() throws {
        try wrapped.register()
    }

    func unregister() async throws {
        try await wrapped.unregister()
    }
}
