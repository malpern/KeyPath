@testable import KeyPath
import XCTest

final class TcpServerResponseTests: XCTestCase {
    func testDecodeOk() throws {
        let json = #"{"status":"Ok"}"#
        let data = Data(json.utf8)
        let resp = try JSONDecoder().decode(TcpServerResponse.self, from: data)
        XCTAssertTrue(resp.isOk)
        XCTAssertFalse(resp.isError)
        XCTAssertNil(resp.msg)
    }

    func testDecodeErrorWithMessage() throws {
        let json = #"{"status":"Error","msg":"something went wrong"}"#
        let data = Data(json.utf8)
        let resp = try JSONDecoder().decode(TcpServerResponse.self, from: data)
        XCTAssertTrue(resp.isError)
        XCTAssertFalse(resp.isOk)
        XCTAssertEqual(resp.msg, "something went wrong")
    }
}


