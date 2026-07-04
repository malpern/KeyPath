@testable import KeyPathAppKit
import ServiceManagement
@preconcurrency import XCTest

final class HelperManagerTests: XCTestCase {
    private var originalFactory: ((String) -> SMAppServiceProtocol)!
    private var originalStatusProvider: SMAppServiceStatusProvider!

    override func setUp() {
        super.setUp()
        originalFactory = HelperManager.smServiceFactory
        originalStatusProvider = SMAppServiceStatusProvider.shared
    }

    override func tearDown() {
        HelperManager.smServiceFactory = originalFactory
        SMAppServiceStatusProvider.shared = originalStatusProvider
        HelperManager.testHelperFunctionalityOverride = nil
        HelperManager.staleHelperSMAppServiceBootoutOverride = nil
        super.tearDown()
    }

    /// Point both the register/unregister seam AND the centralized status provider
    /// (#853) at the same fake so status reads and mutation calls observe one instance.
    private func installFake(_ service: SMAppServiceProtocol) {
        HelperManager.smServiceFactory = { _ in service }
        SMAppServiceStatusProvider.shared = SMAppServiceStatusProvider(
            cacheTTL: 0,
            serviceFactory: { _ in service }
        )
    }

    func testInstallHelperAttemptsRegisterWhenStatusIsNotFoundAndSurfacesError() async {
        // Arrange: Simulate .notFound and an SMAppService error with detailed description
        let expectedDescription = "Codesigning failure loading plist: com.keypath.helper code: -67028"
        let smError = NSError(
            domain: "SMAppServiceErrorDomain", code: 3,
            userInfo: [NSLocalizedDescriptionKey: expectedDescription]
        )
        installFake(FakeSMAppService(status: .notFound, registerError: smError))

        // Act + Assert
        do {
            try await HelperManager.shared.installHelper()
            XCTFail("Expected installHelper() to throw when register fails")
        } catch {
            // Verify we surface the underlying SMAppService error text
            let msg = (error as NSError).localizedDescription
            XCTAssertTrue(
                msg.contains("SMAppService register failed"), "missing SMAppService prefix: \(msg)"
            )
            XCTAssertTrue(msg.contains(expectedDescription), "missing detailed SM error: \(msg)")
        }
    }

    func testStaleHelperSMAppServiceBootoutCommandsTargetSystemDomain() {
        XCTAssertEqual(
            HelperManager.staleHelperSMAppServiceBootoutCommands(),
            ["/bin/launchctl bootout system/com.keypath.helper 2>/dev/null || true"]
        )
    }

    func testInstallHelperRecoversEnabledButUnresponsiveRegistration() async throws {
        let service = FakeSMAppService(status: .enabled)
        installFake(service)

        var bootoutCalls = 0
        HelperManager.staleHelperSMAppServiceBootoutOverride = {
            bootoutCalls += 1
            return (true, "booted out")
        }

        HelperManager.testHelperFunctionalityOverride = {
            service.unregisterCalls > 0
        }

        try await HelperManager.shared.installHelper()

        XCTAssertEqual(service.registerCalls, 2)
        XCTAssertEqual(service.unregisterCalls, 1)
        XCTAssertEqual(bootoutCalls, 1)
    }
}

// MARK: - Test Doubles

private final class FakeSMAppService: SMAppServiceProtocol, @unchecked Sendable {
    var status: SMAppService.Status
    var registerError: Error?
    var registerCalls = 0
    var unregisterCalls = 0

    init(status: SMAppService.Status, registerError: Error? = nil) {
        self.status = status
        self.registerError = registerError
    }

    func register() throws {
        registerCalls += 1
        if let registerError {
            throw registerError
        }
    }

    func unregister() async throws {
        unregisterCalls += 1
    }
}
