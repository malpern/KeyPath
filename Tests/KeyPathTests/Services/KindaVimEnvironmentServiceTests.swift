import Foundation
@testable import KeyPathAppKit
@preconcurrency import XCTest

@MainActor
final class KindaVimEnvironmentServiceTests: XCTestCase {
    func testParseModeFromValidPayload() throws {
        let data = try XCTUnwrap(#"{"mode":"insert"}"#.data(using: .utf8))
        XCTAssertEqual(KindaVimEnvironmentService.parseMode(from: data), "insert")
    }

    func testParseModeFromInvalidPayloadReturnsNil() throws {
        let data = try XCTUnwrap(#"{"not_mode":"insert"}"#.data(using: .utf8))
        XCTAssertNil(KindaVimEnvironmentService.parseMode(from: data))
    }

    func testNormalizedModeMapping() {
        XCTAssertEqual(KindaVimEnvironmentService.normalizedMode(from: "insert"), .insert)
        XCTAssertEqual(KindaVimEnvironmentService.normalizedMode(from: "normal"), .normal)
        XCTAssertEqual(KindaVimEnvironmentService.normalizedMode(from: "visual"), .visual)
        XCTAssertEqual(KindaVimEnvironmentService.normalizedMode(from: "operator_pending"), .operatorPending)
        XCTAssertEqual(KindaVimEnvironmentService.normalizedMode(from: "operator pending"), .operatorPending)
        XCTAssertEqual(KindaVimEnvironmentService.normalizedMode(from: "operator-pending"), .operatorPending)
        XCTAssertEqual(KindaVimEnvironmentService.normalizedMode(from: nil), .unknown)
        XCTAssertEqual(KindaVimEnvironmentService.normalizedMode(from: "something-else"), .unknown)
    }
}
