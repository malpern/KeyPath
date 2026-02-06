@testable import KeyPathAppKit
@preconcurrency import XCTest

/// Unit tests for TCP read buffer behavior.
/// These tests verify the critical line-splitting logic that prevents hangs
/// when Kanata sends multiple JSON lines in a single TCP packet.
final class TCPReadBufferTests: XCTestCase {
    // MARK: - extractFirstLine Tests

    func testExtractFirstLine_SingleLine() throws {
        let client = KanataTCPClient(port: 37001)
        let data = Data("{\"status\":\"Ok\"}\n".utf8)

        let result = client.extractFirstLine(from: data)

        XCTAssertNotNil(result)
        XCTAssertEqual(try String(data: XCTUnwrap(result?.line), encoding: .utf8), "{\"status\":\"Ok\"}\n")
        XCTAssertTrue(try XCTUnwrap(result?.remaining.isEmpty))
    }

    func testExtractFirstLine_TwoLines() throws {
        let client = KanataTCPClient(port: 37001)
        // Simulates Kanata sending two lines in one packet
        let data = Data("{\"status\":\"Ok\"}\n{\"ValidationResult\":{\"errors\":[],\"warnings\":[]}}\n".utf8)

        let result = client.extractFirstLine(from: data)

        XCTAssertNotNil(result)
        XCTAssertEqual(try String(data: XCTUnwrap(result?.line), encoding: .utf8), "{\"status\":\"Ok\"}\n")
        XCTAssertEqual(
            try String(data: XCTUnwrap(result?.remaining), encoding: .utf8),
            "{\"ValidationResult\":{\"errors\":[],\"warnings\":[]}}\n"
        )

        // Extract second line from remaining
        let result2 = try client.extractFirstLine(from: XCTUnwrap(result?.remaining))
        XCTAssertNotNil(result2)
        XCTAssertEqual(
            try String(data: XCTUnwrap(result2?.line), encoding: .utf8),
            "{\"ValidationResult\":{\"errors\":[],\"warnings\":[]}}\n"
        )
        XCTAssertTrue(try XCTUnwrap(result2?.remaining.isEmpty))
    }

    func testExtractFirstLine_NoNewline() {
        let client = KanataTCPClient(port: 37001)
        let data = Data("{\"partial\":\"data\"".utf8) // No newline

        let result = client.extractFirstLine(from: data)

        XCTAssertNil(result, "Should return nil when no complete line exists")
    }

    func testExtractFirstLine_EmptyData() {
        let client = KanataTCPClient(port: 37001)
        let data = Data()

        let result = client.extractFirstLine(from: data)

        XCTAssertNil(result, "Should return nil for empty data")
    }

    func testExtractFirstLine_ThreeLines() throws {
        let client = KanataTCPClient(port: 37001)
        // Simulates broadcast + Ok + Result all arriving together
        let data = Data("{\"LayerChange\":{}}\n{\"status\":\"Ok\"}\n{\"ReloadResult\":{\"ready\":true}}\n".utf8)

        // Extract first line
        let r1 = client.extractFirstLine(from: data)
        XCTAssertEqual(try String(data: XCTUnwrap(r1?.line), encoding: .utf8), "{\"LayerChange\":{}}\n")

        // Extract second line
        let r2 = try client.extractFirstLine(from: XCTUnwrap(r1?.remaining))
        XCTAssertEqual(try String(data: XCTUnwrap(r2?.line), encoding: .utf8), "{\"status\":\"Ok\"}\n")

        // Extract third line
        let r3 = try client.extractFirstLine(from: XCTUnwrap(r2?.remaining))
        XCTAssertEqual(try String(data: XCTUnwrap(r3?.line), encoding: .utf8), "{\"ReloadResult\":{\"ready\":true}}\n")
        XCTAssertTrue(try XCTUnwrap(r3?.remaining.isEmpty))
    }

    func testExtractFirstLine_PartialSecondLine() throws {
        let client = KanataTCPClient(port: 37001)
        // First line complete, second line partial (no trailing newline)
        let data = Data("{\"status\":\"Ok\"}\n{\"partial\":".utf8)

        let result = client.extractFirstLine(from: data)

        XCTAssertNotNil(result)
        XCTAssertEqual(try String(data: XCTUnwrap(result?.line), encoding: .utf8), "{\"status\":\"Ok\"}\n")
        XCTAssertEqual(try String(data: XCTUnwrap(result?.remaining), encoding: .utf8), "{\"partial\":")
    }
}
