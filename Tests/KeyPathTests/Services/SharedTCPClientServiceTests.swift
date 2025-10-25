import XCTest
@testable import KeyPath

final class SharedTCPClientServiceTests: XCTestCase {
    func testGetClientReturnsSingletonInstance() async {
        let first = await SharedTCPClientService.shared.getClient()
        let second = await SharedTCPClientService.shared.getClient()
        // Actor identity cannot be compared directly; rely on object identity via unsafe bit pattern
        XCTAssertTrue(ObjectIdentifier(first) == ObjectIdentifier(second), "Expected same TCP client instance")
    }

    func testResetClientCreatesNewInstance() async {
        let first = await SharedTCPClientService.shared.getClient()
        await SharedTCPClientService.shared.resetClient()
        let second = await SharedTCPClientService.shared.getClient()
        XCTAssertFalse(ObjectIdentifier(first) == ObjectIdentifier(second), "Expected a new TCP client after reset")
    }
}

