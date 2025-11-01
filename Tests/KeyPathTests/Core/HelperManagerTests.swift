import XCTest
@testable import KeyPath
import ServiceManagement

final class HelperManagerTests: XCTestCase {
    private var originalFactory: ((String) -> SMAppServiceProtocol)!

    override func setUp() {
        super.setUp()
        originalFactory = HelperManager.smServiceFactory
    }

    override func tearDown() {
        HelperManager.smServiceFactory = originalFactory
        super.tearDown()
    }

    func testInstallHelperAttemptsRegisterWhenStatusIsNotFoundAndSurfacesError() async {
        // Arrange: Simulate .notFound and an SMAppService error with detailed description
        let expectedDescription = "Codesigning failure loading plist: com.keypath.helper code: -67028"
        let smError = NSError(domain: "SMAppServiceErrorDomain", code: 3, userInfo: [NSLocalizedDescriptionKey: expectedDescription])
        HelperManager.smServiceFactory = { _ in FakeSMAppService(status: .notFound, registerError: smError) }

        // Act + Assert
        do {
            try await HelperManager.shared.installHelper()
            XCTFail("Expected installHelper() to throw when register fails")
        } catch {
            // Verify we surface the underlying SMAppService error text
            let msg = (error as NSError).localizedDescription
            XCTAssertTrue(msg.contains("SMAppService register failed"), "missing SMAppService prefix: \(msg)")
            XCTAssertTrue(msg.contains(expectedDescription), "missing detailed SM error: \(msg)")
        }
    }
}

// MARK: - Test Doubles

private struct FakeSMAppService: SMAppServiceProtocol {
    let status: SMAppService.Status
    let registerError: Error
    func register() throws { throw registerError }
    func unregister() async throws {}
}

