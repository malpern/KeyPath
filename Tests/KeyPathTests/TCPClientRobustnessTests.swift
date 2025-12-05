import Network
@preconcurrency import XCTest

@testable import KeyPathAppKit

/// Comprehensive robustness tests for KanataTCPClient.
/// These tests focus on error handling, timeout behavior, message parsing, and state transitions
/// without requiring a real TCP server connection.
@MainActor
final class TCPClientRobustnessTests: KeyPathTestCase {
    // MARK: - Response Matching Tests

    /// Test request_id extraction from various JSON response formats
    func testExtractRequestIDFromTopLevel() {
        let client = KanataTCPClient(port: 37001)

        // Top-level request_id
        let json1 = #"{"status":"Ok","request_id":42}"#.data(using: .utf8)!
        XCTAssertEqual(client._testExtractRequestId(from: json1), 42)

        // Nested in message type
        let json2 = #"{"HelloOk":{"version":"1.10.0","request_id":99}}"#.data(using: .utf8)!
        XCTAssertEqual(client._testExtractRequestId(from: json2), 99)

        // No request_id
        let json3 = #"{"status":"Ok"}"#.data(using: .utf8)!
        XCTAssertNil(client._testExtractRequestId(from: json3))
    }

    /// Test request_id extraction handles numeric types correctly
    func testExtractRequestIDNumericTypes() {
        let client = KanataTCPClient(port: 37001)

        // Integer
        let json1 = #"{"request_id":123}"#.data(using: .utf8)!
        XCTAssertEqual(client._testExtractRequestId(from: json1), 123)

        // Large number
        let json2 = #"{"request_id":18446744073709551615}"#.data(using: .utf8)!
        XCTAssertNotNil(client._testExtractRequestId(from: json2))

        // String-encoded number (some servers might do this)
        let json3 = #"{"request_id":"456"}"#.data(using: .utf8)!
        XCTAssertEqual(client._testExtractRequestId(from: json3), 456)
    }

    /// Test request_id extraction from deeply nested structures
    func testExtractRequestIDDeepNesting() {
        let client = KanataTCPClient(port: 37001)

        // Nested in StatusInfo
        let statusJson = """
        {"StatusInfo":{"engine_version":"1.10.0","uptime_s":100,"ready":true,"request_id":77}}
        """
        let statusData = statusJson.data(using: .utf8)!
        XCTAssertEqual(client._testExtractRequestId(from: statusData), 77)

        // Nested in ValidationResult
        let validationJson = """
        {"ValidationResult":{"errors":[],"warnings":[],"request_id":88}}
        """
        let validationData = validationJson.data(using: .utf8)!
        XCTAssertEqual(client._testExtractRequestId(from: validationData), 88)
    }

    /// Test request_id extraction handles malformed JSON gracefully
    func testExtractRequestIDMalformedJSON() {
        let client = KanataTCPClient(port: 37001)

        // Invalid JSON
        let invalid1 = "not json".data(using: .utf8)!
        XCTAssertNil(client._testExtractRequestId(from: invalid1))

        // Empty data
        let empty = Data()
        XCTAssertNil(client._testExtractRequestId(from: empty))

        // Incomplete JSON
        let incomplete = #"{"request_id":"#.data(using: .utf8)!
        XCTAssertNil(client._testExtractRequestId(from: incomplete))

        // JSON array instead of object
        let array = #"[{"request_id":1}]"#.data(using: .utf8)!
        XCTAssertNil(client._testExtractRequestId(from: array))
    }

    // MARK: - Message Handling Tests

    /// Test parsing of fake-key broadcast messages
    func testParseFakeKeyBroadcast() {
        let broadcastJson = #"{"MessagePush":{"message":"fakekey:nav-mode:tap"}}"#.data(using: .utf8)!

        // Verify JSON structure is valid
        let json = try? JSONSerialization.jsonObject(with: broadcastJson) as? [String: Any]
        XCTAssertNotNil(json)
        XCTAssertNotNil(json?["MessagePush"])
    }

    /// Test parsing of layer change broadcast messages
    func testParseLayerChangeBroadcast() {
        let broadcastJson = #"{"LayerChange":{"new":"vim","old":"base"}}"#.data(using: .utf8)!

        let json = try? JSONSerialization.jsonObject(with: broadcastJson) as? [String: Any]
        XCTAssertNotNil(json)
        XCTAssertNotNil(json?["LayerChange"])

        if let layerChange = json?["LayerChange"] as? [String: Any] {
            XCTAssertEqual(layerChange["new"] as? String, "vim")
            XCTAssertEqual(layerChange["old"] as? String, "base")
        }
    }

    /// Test parsing of config reload broadcasts
    func testParseConfigReloadBroadcast() {
        let broadcastJson = #"{"ConfigFileReload":{"path":"/path/to/config.kbd"}}"#.data(using: .utf8)!

        let json = try? JSONSerialization.jsonObject(with: broadcastJson) as? [String: Any]
        XCTAssertNotNil(json)
        XCTAssertNotNil(json?["ConfigFileReload"])
    }

    /// Test parsing of ready broadcasts
    func testParseReadyBroadcast() {
        let broadcastJson = #"{"Ready":{}}"#.data(using: .utf8)!

        let json = try? JSONSerialization.jsonObject(with: broadcastJson) as? [String: Any]
        XCTAssertNotNil(json)
        XCTAssertNotNil(json?["Ready"])
    }

    /// Test parsing of config error broadcasts
    func testParseConfigErrorBroadcast() {
        let broadcastJson =
            #"{"ConfigError":{"error":"Parse error at line 42","location":"config.kbd:42"}}"#
                .data(using: .utf8)!

        let json = try? JSONSerialization.jsonObject(with: broadcastJson) as? [String: Any]
        XCTAssertNotNil(json)
        XCTAssertNotNil(json?["ConfigError"])
    }

    /// Test handling of partial/buffered lines
    func testPartialLineBuffering() {
        let client = KanataTCPClient(port: 37001)

        // First chunk: complete line + partial second line
        let chunk1 = Data("{\"status\":\"Ok\"}\n{\"partial\":".utf8)
        let result1 = client.extractFirstLine(from: chunk1)

        XCTAssertNotNil(result1)
        XCTAssertEqual(String(data: result1!.line, encoding: .utf8), "{\"status\":\"Ok\"}\n")
        XCTAssertEqual(String(data: result1!.remaining, encoding: .utf8), "{\"partial\":")

        // Second chunk: complete the partial line
        var accumulated = result1!.remaining
        let chunk2 = Data("\"data\"}\n".utf8)
        accumulated.append(chunk2)

        let result2 = client.extractFirstLine(from: accumulated)
        XCTAssertNotNil(result2)
        XCTAssertEqual(String(data: result2!.line, encoding: .utf8), "{\"partial\":\"data\"}\n")
        XCTAssertTrue(result2!.remaining.isEmpty)
    }

    /// Test handling of multiple complete lines in one buffer
    func testMultipleCompleteLines() {
        let client = KanataTCPClient(port: 37001)

        // Three complete lines in one buffer
        let buffer = Data(
            "{\"line1\":\"data\"}\n{\"line2\":\"data\"}\n{\"line3\":\"data\"}\n".utf8
        )

        // Extract all three lines sequentially
        var remaining = buffer

        let r1 = client.extractFirstLine(from: remaining)
        XCTAssertEqual(String(data: r1!.line, encoding: .utf8), "{\"line1\":\"data\"}\n")
        remaining = r1!.remaining

        let r2 = client.extractFirstLine(from: remaining)
        XCTAssertEqual(String(data: r2!.line, encoding: .utf8), "{\"line2\":\"data\"}\n")
        remaining = r2!.remaining

        let r3 = client.extractFirstLine(from: remaining)
        XCTAssertEqual(String(data: r3!.line, encoding: .utf8), "{\"line3\":\"data\"}\n")
        XCTAssertTrue(r3!.remaining.isEmpty)
    }

    /// Test handling of empty lines (consecutive newlines)
    func testEmptyLines() {
        let client = KanataTCPClient(port: 37001)

        // Data with empty line (double newline)
        let buffer = Data("{\"data\":\"value\"}\n\n{\"next\":\"value\"}\n".utf8)

        let r1 = client.extractFirstLine(from: buffer)
        XCTAssertEqual(String(data: r1!.line, encoding: .utf8), "{\"data\":\"value\"}\n")

        let r2 = client.extractFirstLine(from: r1!.remaining)
        XCTAssertEqual(String(data: r2!.line, encoding: .utf8), "\n")

        let r3 = client.extractFirstLine(from: r2!.remaining)
        XCTAssertEqual(String(data: r3!.line, encoding: .utf8), "{\"next\":\"value\"}\n")
    }

    /// Test handling of very long lines
    func testVeryLongLine() {
        let client = KanataTCPClient(port: 37001)

        // Create a line with 10KB of data
        let longValue = String(repeating: "x", count: 10240)
        let longLine = "{\"long\":\"\(longValue)\"}\n"
        let data = Data(longLine.utf8)

        let result = client.extractFirstLine(from: data)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.line.count, data.count)
        XCTAssertTrue(result!.remaining.isEmpty)
    }

    /// Test malformed JSON handling
    func testMalformedJSON() {
        // Test that malformed JSON can be extracted as lines (parsing happens separately)
        let client = KanataTCPClient(port: 37001)

        let malformed = Data("{invalid json}\n".utf8)
        let result = client.extractFirstLine(from: malformed)

        XCTAssertNotNil(result)
        XCTAssertEqual(String(data: result!.line, encoding: .utf8), "{invalid json}\n")

        // Verify it fails to parse as JSON
        let json = try? JSONSerialization.jsonObject(with: result!.line)
        XCTAssertNil(json)
    }

    /// Test JSON with unexpected structure
    func testUnexpectedJSONStructure() throws {
        // Array instead of object
        let arrayJson = #"["item1","item2"]"#.data(using: .utf8)!
        let arrayResult = try? JSONSerialization.jsonObject(with: arrayJson)
        XCTAssertTrue(arrayResult is [Any])

        // Null value - JSONSerialization can handle it (doesn't return a parseable object for this use case)
        let nullJson = "null".data(using: .utf8)!
        do {
            _ = try JSONSerialization.jsonObject(with: nullJson)
            // If it succeeds, that's fine - null is valid JSON
        } catch {
            XCTFail("Should be able to parse null JSON: \(error)")
        }

        // Number - JSONSerialization can handle it
        let numberJson = "42".data(using: .utf8)!
        do {
            _ = try JSONSerialization.jsonObject(with: numberJson)
            // If it succeeds, that's fine - number is valid JSON
        } catch {
            XCTFail("Should be able to parse number JSON: \(error)")
        }

        // String - JSONSerialization can handle it
        let stringJson = #""hello""#.data(using: .utf8)!
        do {
            _ = try JSONSerialization.jsonObject(with: stringJson)
            // If it succeeds, that's fine - string is valid JSON
        } catch {
            XCTFail("Should be able to parse string JSON: \(error)")
        }
    }

    // MARK: - Protocol Model Tests

    /// Test TcpServerResponse parsing for success
    func testServerResponseSuccess() throws {
        let json = #"{"status":"Ok"}"#.data(using: .utf8)!
        let response = try JSONDecoder().decode(TcpServerResponse.self, from: json)

        XCTAssertTrue(response.isOk)
        XCTAssertFalse(response.isError)
        XCTAssertNil(response.msg)
    }

    /// Test TcpServerResponse parsing for error with message
    func testServerResponseError() throws {
        let json = #"{"status":"Error","msg":"Something went wrong"}"#.data(using: .utf8)!
        let response = try JSONDecoder().decode(TcpServerResponse.self, from: json)

        XCTAssertFalse(response.isOk)
        XCTAssertTrue(response.isError)
        XCTAssertEqual(response.msg, "Something went wrong")
    }

    /// Test TcpServerResponse parsing with missing optional fields
    func testServerResponseMinimal() throws {
        let json = #"{"status":"Ok"}"#.data(using: .utf8)!
        let response = try JSONDecoder().decode(TcpServerResponse.self, from: json)

        XCTAssertTrue(response.isOk)
        XCTAssertNil(response.msg)
    }

    /// Test TcpHelloOk parsing with full fields
    func testHelloOkFullParsing() throws {
        let json = """
        {"version":"1.10.0","protocol":1,"capabilities":["reload","validate"],"request_id":42}
        """
        let data = json.data(using: .utf8)!
        let hello = try JSONDecoder().decode(KanataTCPClient.TcpHelloOk.self, from: data)

        XCTAssertEqual(hello.version, "1.10.0")
        XCTAssertEqual(hello.protocolVersion, 1)
        XCTAssertEqual(hello.capabilities, ["reload", "validate"])
        XCTAssertEqual(hello.request_id, 42)
    }

    /// Test TcpHelloOk parsing with minimal fields (backward compat)
    func testHelloOkMinimalParsing() throws {
        let json = """
        {"server":"kanata","capabilities":[]}
        """
        let data = json.data(using: .utf8)!
        let hello = try JSONDecoder().decode(KanataTCPClient.TcpHelloOk.self, from: data)

        XCTAssertEqual(hello.version, "kanata")
        XCTAssertEqual(hello.protocolVersion, 1)
        XCTAssertTrue(hello.capabilities.isEmpty)
        XCTAssertNil(hello.request_id)
    }

    /// Test TcpStatusInfo parsing
    func testStatusInfoParsing() throws {
        let json = """
        {"engine_version":"1.10.0","uptime_s":1234,"ready":true,"last_reload":{"ok":true,"at":"2024-01-01","duration_ms":50,"epoch":1234567890},"request_id":99}
        """
        let data = json.data(using: .utf8)!
        let status = try JSONDecoder().decode(KanataTCPClient.TcpStatusInfo.self, from: data)

        XCTAssertEqual(status.engine_version, "1.10.0")
        XCTAssertEqual(status.uptime_s, 1234)
        XCTAssertTrue(status.ready)
        XCTAssertNotNil(status.last_reload)
        XCTAssertEqual(status.last_reload?.ok, true)
        XCTAssertEqual(status.request_id, 99)
    }

    /// Test TcpValidationResult parsing with errors and warnings
    func testValidationResultParsing() throws {
        let json = """
        {"errors":[{"code":"E001","message":"Syntax error","line":42,"column":10}],"warnings":[{"code":"W001","message":"Deprecated syntax"}],"request_id":123}
        """
        let data = json.data(using: .utf8)!
        let result = try JSONDecoder().decode(
            KanataTCPClient.TcpValidationResult.self, from: data
        )

        XCTAssertEqual(result.errors.count, 1)
        XCTAssertEqual(result.errors[0].code, "E001")
        XCTAssertEqual(result.errors[0].message, "Syntax error")
        XCTAssertEqual(result.errors[0].line, 42)
        XCTAssertEqual(result.errors[0].column, 10)

        XCTAssertEqual(result.warnings.count, 1)
        XCTAssertEqual(result.warnings[0].code, "W001")
        XCTAssertEqual(result.warnings[0].message, "Deprecated syntax")

        XCTAssertEqual(result.request_id, 123)
    }

    /// Test TcpValidationResult with no line/column info
    func testValidationResultMinimal() throws {
        let json = """
        {"errors":[],"warnings":[],"request_id":456}
        """
        let data = json.data(using: .utf8)!
        let result = try JSONDecoder().decode(
            KanataTCPClient.TcpValidationResult.self, from: data
        )

        XCTAssertTrue(result.errors.isEmpty)
        XCTAssertTrue(result.warnings.isEmpty)
        XCTAssertEqual(result.request_id, 456)
    }

    // MARK: - Capability Checking Tests

    /// Test hasCapabilities with all required capabilities present
    func testHasCapabilitiesAllPresent() {
        let hello = KanataTCPClient.TcpHelloOk(
            version: "1.10.0",
            protocolVersion: 1,
            capabilities: ["reload", "validate", "status", "fakekey"]
        )

        XCTAssertTrue(hello.hasCapabilities(["reload"]))
        XCTAssertTrue(hello.hasCapabilities(["reload", "validate"]))
        XCTAssertTrue(hello.hasCapabilities(["status", "fakekey"]))
        XCTAssertTrue(hello.hasCapabilities(["reload", "validate", "status", "fakekey"]))
    }

    /// Test hasCapabilities with missing capabilities
    func testHasCapabilitiesSomeMissing() {
        let hello = KanataTCPClient.TcpHelloOk(
            version: "1.10.0",
            protocolVersion: 1,
            capabilities: ["reload", "status"]
        )

        XCTAssertTrue(hello.hasCapabilities(["reload"]))
        XCTAssertFalse(hello.hasCapabilities(["validate"]))
        XCTAssertFalse(hello.hasCapabilities(["reload", "validate"]))
        XCTAssertFalse(hello.hasCapabilities(["nonexistent"]))
    }

    /// Test hasCapabilities with empty requirements
    func testHasCapabilitiesEmptyRequired() {
        let hello = KanataTCPClient.TcpHelloOk(
            version: "1.10.0",
            protocolVersion: 1,
            capabilities: ["reload"]
        )

        XCTAssertTrue(hello.hasCapabilities([]))
    }

    /// Test hasCapabilities with empty server capabilities
    func testHasCapabilitiesEmptyServer() {
        let hello = KanataTCPClient.TcpHelloOk(
            version: "1.10.0",
            protocolVersion: 1,
            capabilities: []
        )

        XCTAssertTrue(hello.hasCapabilities([]))
        XCTAssertFalse(hello.hasCapabilities(["reload"]))
    }

    // MARK: - Result Type Tests

    /// Test TCPValidationResult cases
    func testValidationResultCases() {
        let success = TCPValidationResult.success
        let failure = TCPValidationResult.failure(errors: ["Error 1", "Error 2"])
        let networkError = TCPValidationResult.networkError("Connection failed")

        // Verify we can switch on cases
        switch success {
        case .success:
            break
        default:
            XCTFail("Expected success case")
        }

        switch failure {
        case let .failure(errors):
            XCTAssertEqual(errors.count, 2)
        default:
            XCTFail("Expected failure case")
        }

        switch networkError {
        case let .networkError(msg):
            XCTAssertEqual(msg, "Connection failed")
        default:
            XCTFail("Expected networkError case")
        }
    }

    /// Test TCPReloadResult cases and helpers
    func testReloadResultHelpers() {
        let success = TCPReloadResult.success(response: "{\"status\":\"Ok\"}")
        let failure = TCPReloadResult.failure(
            error: "timeout", response: "{\"status\":\"Error\"}"
        )
        let networkError = TCPReloadResult.networkError("Connection lost")

        // Test isSuccess
        XCTAssertTrue(success.isSuccess)
        XCTAssertFalse(failure.isSuccess)
        XCTAssertFalse(networkError.isSuccess)

        // Test errorMessage
        XCTAssertNil(success.errorMessage)
        XCTAssertEqual(failure.errorMessage, "timeout")
        XCTAssertEqual(networkError.errorMessage, "Connection lost")

        // Test response
        XCTAssertEqual(success.response, "{\"status\":\"Ok\"}")
        XCTAssertEqual(failure.response, "{\"status\":\"Error\"}")
        XCTAssertNil(networkError.response)
    }

    /// Test FakeKeyResult cases
    func testFakeKeyResultCases() {
        let success = KanataTCPClient.FakeKeyResult.success
        let error = KanataTCPClient.FakeKeyResult.error("Key not found")
        let networkError = KanataTCPClient.FakeKeyResult.networkError("Connection failed")

        // Verify we can switch on cases
        switch success {
        case .success:
            break
        default:
            XCTFail("Expected success case")
        }

        switch error {
        case let .error(msg):
            XCTAssertEqual(msg, "Key not found")
        default:
            XCTFail("Expected error case")
        }

        switch networkError {
        case let .networkError(msg):
            XCTAssertEqual(msg, "Connection failed")
        default:
            XCTFail("Expected networkError case")
        }
    }

    // MARK: - Edge Case Tests

    /// Test line extraction with only newline
    func testExtractLineOnlyNewline() {
        let client = KanataTCPClient(port: 37001)
        let data = Data("\n".utf8)

        let result = client.extractFirstLine(from: data)
        XCTAssertNotNil(result)
        XCTAssertEqual(String(data: result!.line, encoding: .utf8), "\n")
        XCTAssertTrue(result!.remaining.isEmpty)
    }

    /// Test line extraction with CR+LF line endings
    func testExtractLineWithCRLF() {
        let client = KanataTCPClient(port: 37001)
        let data = Data("{\"data\":\"value\"}\r\n".utf8)

        let result = client.extractFirstLine(from: data)
        XCTAssertNotNil(result)

        // Should stop at \n (0x0A), keeping \r as part of line
        let line = String(data: result!.line, encoding: .utf8)!
        XCTAssertTrue(line.hasSuffix("\n"))
    }

    /// Test line extraction with binary data before newline
    func testExtractLineWithBinaryData() {
        let client = KanataTCPClient(port: 37001)

        var data = Data()
        data.append(contentsOf: [0x00, 0x01, 0xFF, 0xFE])  // Binary bytes
        data.append(0x0A)  // Newline

        let result = client.extractFirstLine(from: data)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.line.count, 5)  // 4 bytes + newline
        XCTAssertTrue(result!.remaining.isEmpty)
    }

    /// Test line extraction with UTF-8 multibyte characters
    func testExtractLineWithUTF8() {
        let client = KanataTCPClient(port: 37001)

        // Japanese characters (multibyte UTF-8)
        let data = Data("{\"message\":\"こんにちは\"}\n".utf8)

        let result = client.extractFirstLine(from: data)
        XCTAssertNotNil(result)

        let line = String(data: result!.line, encoding: .utf8)!
        XCTAssertTrue(line.contains("こんにちは"))
        XCTAssertTrue(result!.remaining.isEmpty)
    }

    /// Test behavior with maximum buffer size concerns
    func testLargeBufferHandling() {
        let client = KanataTCPClient(port: 37001)

        // Create a very large line (but under 64KB limit)
        let largeString = String(repeating: "x", count: 60000)
        let data = Data("{\"data\":\"\(largeString)\"}\n".utf8)

        let result = client.extractFirstLine(from: data)
        XCTAssertNotNil(result)
        XCTAssertGreaterThan(result!.line.count, 60000)
        XCTAssertTrue(result!.remaining.isEmpty)
    }

    // MARK: - State Consistency Tests

    /// Test that multiple clients don't interfere with each other
    func testMultipleClientIsolation() async {
        let client1 = KanataTCPClient(port: 37001)
        let client2 = KanataTCPClient(port: 37002)

        // Each client should have independent state
        let data = Data("{\"line\":\"1\"}\n{\"line\":\"2\"}\n".utf8)

        let r1 = client1.extractFirstLine(from: data)
        let r2 = client2.extractFirstLine(from: data)

        // Both should get the same first line (they're independent)
        XCTAssertEqual(String(data: r1!.line, encoding: .utf8), "{\"line\":\"1\"}\n")
        XCTAssertEqual(String(data: r2!.line, encoding: .utf8), "{\"line\":\"1\"}\n")
    }

    /// Test parsing of protocol messages
    func testProtocolMessageParsing() throws {
        // TcpHelloOk encoding (note: request_id is not encoded, it's receive-only)
        let hello = KanataTCPClient.TcpHelloOk(
            version: "1.10.0",
            protocolVersion: 1,
            capabilities: ["reload", "validate"],
            request_id: 42
        )
        let helloData = try JSONEncoder().encode(hello)
        let helloDecoded = try JSONDecoder().decode(
            KanataTCPClient.TcpHelloOk.self, from: helloData
        )

        XCTAssertEqual(helloDecoded.version, hello.version)
        XCTAssertEqual(helloDecoded.protocolVersion, hello.protocolVersion)
        XCTAssertEqual(helloDecoded.capabilities, hello.capabilities)
        // request_id is not encoded (it's receive-only from server)
        XCTAssertNil(helloDecoded.request_id)

        // TcpServerResponse parsing (decode only - no memberwise init)
        let responseJson = #"{"status":"Ok"}"#
        let responseData = responseJson.data(using: .utf8)!
        let response = try JSONDecoder().decode(TcpServerResponse.self, from: responseData)

        XCTAssertEqual(response.status, "Ok")
        XCTAssertTrue(response.isOk)
        XCTAssertNil(response.msg)
    }
}
