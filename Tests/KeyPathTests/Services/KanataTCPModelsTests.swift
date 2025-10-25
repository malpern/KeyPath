import XCTest
@testable import KeyPath

final class KanataTCPModelsTests: XCTestCase {
    func testClientMessageEncodingDecoding() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let messages: [TCPClientMessage] = [.reload, .reloadNext, .requestCurrentLayerName]
        for msg in messages {
            let data = try encoder.encode(msg)
            let decoded = try decoder.decode(TCPClientMessage.self, from: data)
            switch (msg, decoded) {
            case (.reload, .reload), (.reloadNext, .reloadNext), (.requestCurrentLayerName, .requestCurrentLayerName):
                break // ok
            default:
                XCTFail("Round-trip mismatch for \(msg)")
            }
        }
    }

    func testServerResponseEncodingDecoding() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let ok = TCPServerResponse.ok
        let okData = try encoder.encode(ok)
        let okDecoded = try decoder.decode(TCPServerResponse.self, from: okData)
        if case .ok = okDecoded {} else { XCTFail("Expected .ok") }

        let err = TCPServerResponse.error(msg: "boom")
        let errData = try encoder.encode(err)
        let errDecoded = try decoder.decode(TCPServerResponse.self, from: errData)
        if case let .error(msg) = errDecoded { XCTAssertEqual(msg, "boom") } else { XCTFail("Expected .error") }
    }

    func testServerMessageEncodingDecoding() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let msgs: [TCPServerMessage] = [
            .layerChange(new: "nav"),
            .currentLayerName(name: "base"),
            .configFileReload(new: "a.kbd"),
            .configFileReloadNew(new: "b.kbd"),
        ]
        for msg in msgs {
            let data = try encoder.encode(msg)
            let decoded = try decoder.decode(TCPServerMessage.self, from: data)
            switch (msg, decoded) {
            case let (.layerChange(a), .layerChange(b)): XCTAssertEqual(a, b)
            case let (.currentLayerName(a), .currentLayerName(b)): XCTAssertEqual(a, b)
            case let (.configFileReload(a), .configFileReload(b)): XCTAssertEqual(a, b)
            case let (.configFileReloadNew(a), .configFileReloadNew(b)): XCTAssertEqual(a, b)
            default: XCTFail("Round-trip mismatch: \(msg)")
            }
        }
    }
}

