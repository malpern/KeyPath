@testable import KeyPathAppKit
@testable import KeyPathCore
import ServiceManagement
@preconcurrency import XCTest

final class SystemStateProviderSMAppServiceTests: XCTestCase {
    private var originalStatusProvider: SMAppServiceStatusProvider!
    private var originalSynchronousServiceFactory: ((String) -> SMAppServiceProtocol)!

    override func setUp() {
        super.setUp()
        originalStatusProvider = SMAppServiceStatusProvider.shared
        originalSynchronousServiceFactory = SMAppServiceStatusProvider.synchronousServiceFactory
    }

    override func tearDown() {
        SMAppServiceStatusProvider.shared = originalStatusProvider
        SMAppServiceStatusProvider.synchronousServiceFactory = originalSynchronousServiceFactory
        super.tearDown()
    }

    func testSMAppServiceStatusAccessDelegatesToCentralStatusProvider() async {
        let service = CountingSMAppService(status: .requiresApproval)
        SMAppServiceStatusProvider.shared = SMAppServiceStatusProvider(
            cacheTTL: 60,
            serviceFactory: { _ in service }
        )

        let provider = SystemStateProvider()

        let first = await provider.cachedSMAppServiceStatus(for: "com.keypath.kanata.plist")
        let second = await provider.cachedSMAppServiceStatus(for: "com.keypath.kanata.plist")

        XCTAssertEqual(first, .requiresApproval)
        XCTAssertEqual(second, .requiresApproval)
        XCTAssertEqual(service.statusReads, 1)
    }

    func testSMAppServiceStatusInvalidationDelegatesToCentralStatusProvider() async {
        let service = CountingSMAppService(status: .enabled)
        SMAppServiceStatusProvider.shared = SMAppServiceStatusProvider(
            cacheTTL: 60,
            serviceFactory: { _ in service }
        )

        let provider = SystemStateProvider()

        _ = await provider.cachedSMAppServiceStatus(for: "com.keypath.kanata.plist")
        await provider.invalidateSMAppServiceStatus(plistName: "com.keypath.kanata.plist")
        _ = await provider.cachedSMAppServiceStatus(for: "com.keypath.kanata.plist")

        XCTAssertEqual(service.statusReads, 2)
    }

    func testSMAppServiceFreshStatusBypassesCache() async {
        let service = CountingSMAppService(status: .enabled)
        SMAppServiceStatusProvider.shared = SMAppServiceStatusProvider(
            cacheTTL: 60,
            serviceFactory: { _ in service }
        )

        let provider = SystemStateProvider()

        _ = await provider.freshSMAppServiceStatus(for: "com.keypath.kanata.plist")
        _ = await provider.freshSMAppServiceStatus(for: "com.keypath.kanata.plist")

        XCTAssertEqual(service.statusReads, 2)
    }

    func testSynchronousSMAppServiceStatusDelegatesToCentralStatusProviderBridge() {
        let service = CountingSMAppService(status: .requiresApproval)
        SMAppServiceStatusProvider.synchronousServiceFactory = { _ in service }

        let status = SystemStateProvider.shared
            .smAppServiceStatusSynchronously(for: "com.keypath.helper.plist")

        XCTAssertEqual(status, .requiresApproval)
        XCTAssertEqual(service.statusReads, 1)
    }
}

private final class CountingSMAppService: SMAppServiceProtocol, @unchecked Sendable {
    var statusValue: SMAppService.Status
    private(set) var statusReads = 0

    init(status: SMAppService.Status) {
        statusValue = status
    }

    var status: SMAppService.Status {
        statusReads += 1
        return statusValue
    }

    func register() throws {}
    func unregister() async throws {}
}
