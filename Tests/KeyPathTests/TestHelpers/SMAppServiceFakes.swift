import Foundation
@testable import KeyPathAppKit
import ServiceManagement

/// Test double for SMAppService (helper registration/status scenarios)
/// Note: Renamed to avoid conflict with private FakeSMAppService in HelperManagerTests
final class SMAppServiceTestDouble: SMAppServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var _status: ServiceManagement.SMAppService.Status
    private(set) var registerCallCount: Int = 0
    private(set) var unregisterCallCount: Int = 0
    private var shouldFailRegister: Bool = false
    private var shouldFailUnregister: Bool = false

    init(status: ServiceManagement.SMAppService.Status = .notRegistered) {
        _status = status
    }

    var status: ServiceManagement.SMAppService.Status {
        lock.lock()
        defer { lock.unlock() }
        return _status
    }

    func register() throws {
        lock.lock()
        defer { lock.unlock() }
        registerCallCount += 1
        if shouldFailRegister {
            throw FakeSMAppServiceError.registrationFailed
        }
        _status = .requiresApproval
    }

    func unregister() async throws {
        // Note: Using withCheckedThrowingContinuation to bridge sync locking to async context
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            lock.lock()
            defer { lock.unlock() }
            unregisterCallCount += 1
            if shouldFailUnregister {
                continuation.resume(throwing: FakeSMAppServiceError.unregistrationFailed)
            } else {
                _status = .notRegistered
                continuation.resume()
            }
        }
    }

    func simulateStatus(_ status: ServiceManagement.SMAppService.Status) {
        lock.lock()
        defer { lock.unlock() }
        _status = status
    }

    func simulateRegisterFailure(_ shouldFail: Bool = true) {
        lock.lock()
        defer { lock.unlock() }
        shouldFailRegister = shouldFail
    }

    func simulateUnregisterFailure(_ shouldFail: Bool = true) {
        lock.lock()
        defer { lock.unlock() }
        shouldFailUnregister = shouldFail
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        registerCallCount = 0
        unregisterCallCount = 0
        shouldFailRegister = false
        shouldFailUnregister = false
        _status = .notRegistered
    }
}

enum FakeSMAppServiceError: Error, LocalizedError {
    case registrationFailed
    case unregistrationFailed

    var errorDescription: String? {
        switch self {
        case .registrationFailed:
            "Failed to register helper"
        case .unregistrationFailed:
            "Failed to unregister helper"
        }
    }
}

extension SMAppServiceTestDouble {
    static func notInstalled() -> SMAppServiceTestDouble {
        SMAppServiceTestDouble(status: .notRegistered)
    }

    static func healthy() -> SMAppServiceTestDouble {
        SMAppServiceTestDouble(status: .enabled)
    }

    static func pendingApproval() -> SMAppServiceTestDouble {
        SMAppServiceTestDouble(status: .requiresApproval)
    }

    static func notFound() -> SMAppServiceTestDouble {
        SMAppServiceTestDouble(status: .notFound)
    }
}

struct SMAppServiceFactoryRestorer {
    private let original: (String) -> SMAppServiceProtocol

    init() {
        original = HelperManager.smServiceFactory
    }

    func restore() {
        HelperManager.smServiceFactory = original
    }
}
