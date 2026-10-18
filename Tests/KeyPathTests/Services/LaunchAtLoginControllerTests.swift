@testable import KeyPathAppKit
import ServiceManagement
import XCTest

@MainActor
final class LaunchAtLoginControllerTests: XCTestCase {
    private final class Service: SMAppServiceProtocol, @unchecked Sendable {
        private let lock = NSLock()
        private var value: SMAppService.Status = .notRegistered
        var resultingStatus: SMAppService.Status = .enabled
        var rejectChange = false
        var status: SMAppService.Status { lock.withLock { value } }
        func setStatus(_ status: SMAppService.Status) { lock.withLock { value = status } }
        func register() throws {
            if rejectChange { throw CocoaError(.fileWriteNoPermission) }
            setStatus(resultingStatus)
        }
        func unregister() async throws {
            if rejectChange { throw CocoaError(.fileWriteNoPermission) }
            setStatus(.notRegistered)
        }
    }

    func testEnableAndDisableUseSystemRegistration() async throws {
        let service = Service()
        let controller = LaunchAtLoginController(service: service)
        await controller.refresh()
        XCTAssertFalse(controller.isEnabled)
        try await controller.setEnabled(true)
        XCTAssertEqual(controller.status, .enabled)
        try await controller.setEnabled(false)
        XCTAssertEqual(service.status, .notRegistered)
        XCTAssertFalse(controller.isBusy)
    }

    func testApprovalPendingIsVisibleAndCanBeCancelled() async throws {
        let service = Service()
        service.resultingStatus = .requiresApproval
        let controller = LaunchAtLoginController(service: service)
        try await controller.setEnabled(true)
        XCTAssertEqual(controller.status, .requiresApproval)
        XCTAssertTrue(controller.isEnabled)
        try await controller.setEnabled(false)
        XCTAssertFalse(controller.isEnabled)
    }

    func testExternalSystemSettingsChangeRefreshesWithoutReregistering() async throws {
        let service = Service()
        let controller = LaunchAtLoginController(service: service)
        try await controller.setEnabled(true)
        service.setStatus(.notRegistered)
        await controller.refresh()
        XCTAssertFalse(controller.isEnabled)
        XCTAssertEqual(service.status, .notRegistered)
    }

    func testFailedRemovalDoesNotReportDisabled() async throws {
        let service = Service()
        service.setStatus(.enabled)
        service.rejectChange = true
        let controller = LaunchAtLoginController(service: service)
        do {
            try await controller.setEnabled(false)
            XCTFail("Must surface failed removal")
        } catch {}
        XCTAssertTrue(controller.isEnabled)
        XCTAssertFalse(controller.isBusy)
    }

    func testSuccessfulCallWithoutPostconditionIsNotSuccess() async {
        let service = Service()
        service.resultingStatus = .notRegistered
        let controller = LaunchAtLoginController(service: service)
        do {
            try await controller.setEnabled(true)
            XCTFail("Must verify system registration")
        } catch {}
        XCTAssertFalse(controller.isEnabled)
    }
}
