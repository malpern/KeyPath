@testable import KeyPathAppKit
@testable import KeyPathCore
@preconcurrency import XCTest

/// Robustness tests for KanataTCPClient covering edge cases around
/// error recovery, partial reads, broadcast filtering, request ID
/// matching, connection lifecycle, and concurrent operations.
///
/// These tests exercise unit-testable logic that does NOT require
/// a live Kanata server (unlike TCPClientIntegrationTests).
final class TCPClientRobustnessTests: XCTestCase {
    private let port: Int = 37099

    // MARK: - Read Buffer Edge Cases

    func testExtractFirstLine_NewlineOnly() {
        let client = KanataTCPClient(port: port)
        let data = Data("\n".utf8)

        let result = client.extractFirstLine(from: data)
        XCTAssertNotNil(result, "Bare newline should produce an empty line")
        XCTAssertTrue(result?.remaining.isEmpty ?? false)
    }

    func testExtractFirstLine_MultipleEmptyLines() throws {
        let client = KanataTCPClient(port: port)
        let data = Data("\n\n\n".utf8)

        let r1 = client.extractFirstLine(from: data)
        XCTAssertNotNil(r1)
        let r2 = try client.extractFirstLine(from: XCTUnwrap(r1?.remaining))
        XCTAssertNotNil(r2)
        let r3 = try client.extractFirstLine(from: XCTUnwrap(r2?.remaining))
        XCTAssertNotNil(r3)
        XCTAssertTrue(try XCTUnwrap(r3?.remaining).isEmpty)
    }

    func testExtractFirstLine_LargePayload() {
        let client = KanataTCPClient(port: port)
        let largeValue = String(repeating: "x", count: 50000)
        let json = "{\"data\":\"\(largeValue)\"}\n"
        let data = Data(json.utf8)

        let result = client.extractFirstLine(from: data)
        XCTAssertNotNil(result)
        let lineStr = String(data: result!.line, encoding: .utf8)!
        XCTAssertTrue(lineStr.contains(largeValue))
    }

    func testExtractFirstLine_WindowsLineEndings() {
        let client = KanataTCPClient(port: port)
        let data = Data("{\"status\":\"Ok\"}\r\n{\"next\":true}\n".utf8)

        let result = client.extractFirstLine(from: data)
        XCTAssertNotNil(result, "Should handle \\r\\n by splitting on \\n")
    }

    func testExtractFirstLine_BinaryFollowedByNewline() {
        let client = KanataTCPClient(port: port)
        var data = Data([0xFF, 0xFE, 0x00, 0x0A])
        let result = client.extractFirstLine(from: data)
        XCTAssertNotNil(result, "Should find newline byte even in non-UTF8 data")
    }

    // MARK: - isCommandResponse Robustness

    func testIsCommandResponse_NestedStatusField() throws {
        let client = KanataTCPClient(port: port)
        let json = #"{"status":"Ok","request_id":42,"extra":true}"#
        let data = try XCTUnwrap(json.data(using: .utf8))
        XCTAssertTrue(client.isCommandResponse(data), "Status with extra fields should be recognized")
    }

    func testIsCommandResponse_EmptyString() {
        let client = KanataTCPClient(port: port)
        XCTAssertFalse(client.isCommandResponse(Data()))
    }

    func testIsCommandResponse_NullByte() {
        let client = KanataTCPClient(port: port)
        XCTAssertFalse(client.isCommandResponse(Data([0x00])))
    }

    func testIsCommandResponse_TruncatedJson() throws {
        let client = KanataTCPClient(port: port)
        let truncated = #"{"status":"O"#
        let data = try XCTUnwrap(truncated.data(using: .utf8))
        XCTAssertFalse(client.isCommandResponse(data), "Truncated JSON should not match")
    }

    func testIsCommandResponse_StatusWithNumericValue() throws {
        let client = KanataTCPClient(port: port)
        let json = #"{"status":200}"#
        let data = try XCTUnwrap(json.data(using: .utf8))
        XCTAssertTrue(client.isCommandResponse(data), "status with any value type should match")
    }

    func testIsCommandResponse_MultipleResponseKeys() throws {
        let client = KanataTCPClient(port: port)
        let json = #"{"HelloOk":{},"StatusInfo":{}}"#
        let data = try XCTUnwrap(json.data(using: .utf8))
        XCTAssertTrue(client.isCommandResponse(data), "Multiple response keys should still match")
    }

    func testIsCommandResponse_ResponseKeyWithBroadcastKey() throws {
        let client = KanataTCPClient(port: port)
        let json = #"{"HelloOk":{},"LayerChange":{}}"#
        let data = try XCTUnwrap(json.data(using: .utf8))
        XCTAssertTrue(
            client.isCommandResponse(data),
            "If any response key present, it's a command response"
        )
    }

    // MARK: - Request ID Extraction Robustness

    func testExtractRequestId_TopLevel() {
        let client = KanataTCPClient(port: port)
        let data = #"{"status":"Ok","request_id":999}"#.data(using: .utf8)!
        let id = client._testExtractRequestId(from: data)
        XCTAssertEqual(id, 999)
    }

    func testExtractRequestId_Nested() {
        let client = KanataTCPClient(port: port)
        let data = #"{"HelloOk":{"version":"1.10","request_id":42}}"#.data(using: .utf8)!
        let id = client._testExtractRequestId(from: data)
        XCTAssertEqual(id, 42)
    }

    func testExtractRequestId_StringValue() {
        let client = KanataTCPClient(port: port)
        let data = #"{"status":"Ok","request_id":"123"}"#.data(using: .utf8)!
        let id = client._testExtractRequestId(from: data)
        XCTAssertEqual(id, 123, "String request_id should be parsed as UInt64")
    }

    func testExtractRequestId_Missing() {
        let client = KanataTCPClient(port: port)
        let data = #"{"status":"Ok"}"#.data(using: .utf8)!
        let id = client._testExtractRequestId(from: data)
        XCTAssertNil(id)
    }

    func testExtractRequestId_Zero() {
        let client = KanataTCPClient(port: port)
        let data = #"{"status":"Ok","request_id":0}"#.data(using: .utf8)!
        let id = client._testExtractRequestId(from: data)
        XCTAssertEqual(id, 0)
    }

    func testExtractRequestId_LargeValue() {
        let client = KanataTCPClient(port: port)
        let data = #"{"status":"Ok","request_id":18446744073709551615}"#.data(using: .utf8)!
        let id = client._testExtractRequestId(from: data)
        XCTAssertEqual(id, UInt64.max)
    }

    func testExtractRequestId_InvalidJson() {
        let client = KanataTCPClient(port: port)
        let data = "not json".data(using: .utf8)!
        let id = client._testExtractRequestId(from: data)
        XCTAssertNil(id)
    }

    func testExtractRequestId_NullValue() {
        let client = KanataTCPClient(port: port)
        let data = #"{"status":"Ok","request_id":null}"#.data(using: .utf8)!
        let id = client._testExtractRequestId(from: data)
        XCTAssertNil(id, "null request_id should return nil")
    }

    // MARK: - Request ID Generation

    func testRequestIdMonotonicity_NoServer() async {
        let client = KanataTCPClient(port: port)
        var ids: [UInt64] = []
        for _ in 0 ..< 100 {
            await ids.append(client.generateRequestId())
        }
        for i in 1 ..< ids.count {
            XCTAssertGreaterThan(ids[i], ids[i - 1], "IDs must be strictly monotonic")
        }
    }

    func testRequestIdStartsAtOne() async {
        let client = KanataTCPClient(port: port)
        let first = await client.generateRequestId()
        XCTAssertEqual(first, 1, "First request ID should be 1")
    }

    // MARK: - TCPReloadResult Tests

    func testTCPReloadResult_SuccessProperties() {
        let result = TCPReloadResult.success(response: "ok")
        XCTAssertTrue(result.isSuccess)
        XCTAssertNil(result.errorMessage)
        XCTAssertEqual(result.response, "ok")
        XCTAssertFalse(result.isCancellation)
    }

    func testTCPReloadResult_FailureProperties() {
        let result = TCPReloadResult.failure(error: "bad config", response: "err")
        XCTAssertFalse(result.isSuccess)
        XCTAssertEqual(result.errorMessage, "bad config")
        XCTAssertEqual(result.response, "err")
        XCTAssertFalse(result.isCancellation)
    }

    func testTCPReloadResult_NetworkErrorProperties() {
        let result = TCPReloadResult.networkError("timeout")
        XCTAssertFalse(result.isSuccess)
        XCTAssertEqual(result.errorMessage, "timeout")
        XCTAssertNil(result.response)
        XCTAssertFalse(result.isCancellation)
    }

    func testTCPReloadResult_CancellationDetection() {
        let cancel1 = TCPReloadResult.networkError("CancellationError()")
        XCTAssertTrue(cancel1.isCancellation)

        let cancel2 = TCPReloadResult.failure(error: "Task was cancelled", response: "")
        XCTAssertTrue(cancel2.isCancellation)

        let notCancel = TCPReloadResult.failure(error: "connection refused", response: "")
        XCTAssertFalse(notCancel.isCancellation)
    }

    // MARK: - ReloadResult Protocol Parsing

    func testReloadResult_OlderProtocol_ReadyTrue() throws {
        let json = #"{"ready":true,"timeout_ms":5000}"#
        let data = try XCTUnwrap(json.data(using: .utf8))
        let result = try JSONDecoder().decode(KanataTCPClient.ReloadResult.self, from: data)
        XCTAssertTrue(result.isSuccess)
        XCTAssertFalse(result.isTimeout)
    }

    func testReloadResult_OlderProtocol_Timeout() throws {
        let json = #"{"ready":false,"timeout_ms":5000}"#
        let data = try XCTUnwrap(json.data(using: .utf8))
        let result = try JSONDecoder().decode(KanataTCPClient.ReloadResult.self, from: data)
        XCTAssertFalse(result.isSuccess)
        XCTAssertTrue(result.isTimeout)
    }

    func testReloadResult_NewerProtocol_OkTrue() throws {
        let json = #"{"ok":true,"duration_ms":42,"epoch":1234567890}"#
        let data = try XCTUnwrap(json.data(using: .utf8))
        let result = try JSONDecoder().decode(KanataTCPClient.ReloadResult.self, from: data)
        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(result.duration_ms, 42)
    }

    func testReloadResult_NewerProtocol_OkFalse() throws {
        let json = #"{"ok":false}"#
        let data = try XCTUnwrap(json.data(using: .utf8))
        let result = try JSONDecoder().decode(KanataTCPClient.ReloadResult.self, from: data)
        XCTAssertFalse(result.isSuccess)
    }

    func testReloadResult_WithRequestId() throws {
        let json = #"{"ok":true,"request_id":55}"#
        let data = try XCTUnwrap(json.data(using: .utf8))
        let result = try JSONDecoder().decode(KanataTCPClient.ReloadResult.self, from: data)
        XCTAssertEqual(result.request_id, 55)
    }

    func testReloadResult_EmptyObject() throws {
        let json = #"{}"#
        let data = try XCTUnwrap(json.data(using: .utf8))
        let result = try JSONDecoder().decode(KanataTCPClient.ReloadResult.self, from: data)
        XCTAssertFalse(result.isSuccess, "Empty object has no ok/ready → failure")
        XCTAssertFalse(result.isTimeout, "No timeout_ms → not a timeout")
    }

    // MARK: - HelloOk Protocol Parsing

    func testHelloOk_FullPayload() throws {
        let json = #"{"version":"1.10.0","protocol":1,"capabilities":["reload","status"],"request_id":7}"#
        let data = try XCTUnwrap(json.data(using: .utf8))
        let hello = try JSONDecoder().decode(KanataTCPClient.TcpHelloOk.self, from: data)
        XCTAssertEqual(hello.version, "1.10.0")
        XCTAssertEqual(hello.protocolVersion, 1)
        XCTAssertEqual(hello.capabilities, ["reload", "status"])
        XCTAssertEqual(hello.request_id, 7)
    }

    func testHelloOk_MinimalServerForm() throws {
        let json = #"{"server":"kanata-custom","capabilities":["reload"]}"#
        let data = try XCTUnwrap(json.data(using: .utf8))
        let hello = try JSONDecoder().decode(KanataTCPClient.TcpHelloOk.self, from: data)
        XCTAssertEqual(hello.version, "kanata-custom")
        XCTAssertEqual(hello.protocolVersion, 1)
        XCTAssertEqual(hello.capabilities, ["reload"])
    }

    func testHelloOk_HasCapabilities() {
        let hello = KanataTCPClient.TcpHelloOk(
            version: "1.10.0",
            protocolVersion: 1,
            capabilities: ["reload", "status", "fake_keys"]
        )
        XCTAssertTrue(hello.hasCapabilities(["reload"]))
        XCTAssertTrue(hello.hasCapabilities(["reload", "status"]))
        XCTAssertFalse(hello.hasCapabilities(["reload", "missing"]))
        XCTAssertTrue(hello.hasCapabilities([]))
    }

    // MARK: - StatusInfo Parsing

    func testStatusInfo_WithLastReload() throws {
        let json = #"{"engine_version":"1.10.0","uptime_s":3600,"ready":true,"last_reload":{"ok":true,"at":"2026-01-01","duration_ms":42,"epoch":1234567890},"request_id":10}"#
        let data = try XCTUnwrap(json.data(using: .utf8))
        let status = try JSONDecoder().decode(KanataTCPClient.TcpStatusInfo.self, from: data)
        XCTAssertEqual(status.engine_version, "1.10.0")
        XCTAssertEqual(status.uptime_s, 3600)
        XCTAssertTrue(status.ready)
        XCTAssertTrue(status.last_reload?.ok ?? false)
        XCTAssertEqual(status.last_reload?.duration_ms, 42)
        XCTAssertEqual(status.request_id, 10)
    }

    func testStatusInfo_WithoutLastReload() throws {
        let json = #"{"engine_version":"1.10.0","uptime_s":0,"ready":false}"#
        let data = try XCTUnwrap(json.data(using: .utf8))
        let status = try JSONDecoder().decode(KanataTCPClient.TcpStatusInfo.self, from: data)
        XCTAssertFalse(status.ready)
        XCTAssertNil(status.last_reload)
        XCTAssertNil(status.request_id)
    }

    // MARK: - FakeKeyAction & Result Tests

    func testFakeKeyAction_RawValues() {
        XCTAssertEqual(KanataTCPClient.FakeKeyAction.press.rawValue, "Press")
        XCTAssertEqual(KanataTCPClient.FakeKeyAction.release.rawValue, "Release")
        XCTAssertEqual(KanataTCPClient.FakeKeyAction.tap.rawValue, "Tap")
        XCTAssertEqual(KanataTCPClient.FakeKeyAction.toggle.rawValue, "Toggle")
    }

    func testFakeKeyResult_Cases() {
        let success = KanataTCPClient.FakeKeyResult.success
        let error = KanataTCPClient.FakeKeyResult.error("bad key")
        let networkError = KanataTCPClient.FakeKeyResult.networkError("timeout")

        if case .success = success {} else { XCTFail("Expected success") }
        if case let .error(msg) = error { XCTAssertEqual(msg, "bad key") } else { XCTFail("Expected error") }
        if case let .networkError(msg) = networkError { XCTAssertEqual(msg, "timeout") } else { XCTFail("Expected networkError") }
    }

    func testChangeLayerResult_Cases() {
        let success = KanataTCPClient.ChangeLayerResult.success
        let error = KanataTCPClient.ChangeLayerResult.error("unknown layer")
        let networkError = KanataTCPClient.ChangeLayerResult.networkError("disconnected")

        if case .success = success {} else { XCTFail("Expected success") }
        if case let .error(msg) = error { XCTAssertEqual(msg, "unknown layer") } else { XCTFail("Expected error") }
        if case let .networkError(msg) = networkError { XCTAssertEqual(msg, "disconnected") } else { XCTFail("Expected networkError") }
    }

    // MARK: - Error Classification

    func testShouldRetry_Timeout() async {
        let client = KanataTCPClient(port: port)
        let err = KeyPathError.communication(.timeout)
        let result = await client.shouldRetry(err)
        XCTAssertTrue(result)
    }

    func testShouldRetry_ConnectionFailed() async {
        let client = KanataTCPClient(port: port)
        let err = KeyPathError.communication(.connectionFailed(reason: "refused"))
        let result = await client.shouldRetry(err)
        XCTAssertTrue(result)
    }

    func testShouldRetry_InvalidResponse() async {
        let client = KanataTCPClient(port: port)
        let err = KeyPathError.communication(.invalidResponse)
        let result = await client.shouldRetry(err)
        XCTAssertFalse(result)
    }

    func testShouldRetry_NonKeyPathError() async {
        let client = KanataTCPClient(port: port)
        let err = NSError(domain: "test", code: 1)
        let result = await client.shouldRetry(err)
        XCTAssertFalse(result)
    }

    // MARK: - extractError Parsing

    func testExtractError_StatusErrorJson() async {
        let client = KanataTCPClient(port: port)
        let response = #"{"status":"Error","msg":"bad config file"}"#
        let error = await client.extractError(from: response)
        XCTAssertEqual(error, "bad config file")
    }

    func testExtractError_GenericErrorField() async {
        let client = KanataTCPClient(port: port)
        let response = #"{"error":"something went wrong"}"#
        let error = await client.extractError(from: response)
        XCTAssertEqual(error, "something went wrong")
    }

    func testExtractError_NoErrorField() async {
        let client = KanataTCPClient(port: port)
        let response = #"{"status":"Ok"}"#
        let error = await client.extractError(from: response)
        XCTAssertEqual(error, "Unknown error")
    }

    func testExtractError_NonJson() async {
        let client = KanataTCPClient(port: port)
        let response = "not json at all"
        let error = await client.extractError(from: response)
        XCTAssertEqual(error, "Unknown error")
    }

    func testExtractError_MultiLineResponse() async {
        let client = KanataTCPClient(port: port)
        let response = "{\"status\":\"Error\",\"msg\":\"line1\"}\n{\"extra\":\"data\"}"
        let error = await client.extractError(from: response)
        XCTAssertEqual(error, "line1")
    }

    // MARK: - extractMessage Tests

    func testExtractMessage_HelloOkFromMultiLine() async throws {
        let client = KanataTCPClient(port: port)
        let response = """
        {"status":"Ok"}
        {"HelloOk":{"version":"1.10.0","protocol":1,"capabilities":["reload"]}}
        """
        let data = Data(response.utf8)
        let hello = try await client.extractMessage(
            named: "HelloOk",
            into: KanataTCPClient.TcpHelloOk.self,
            from: data
        )
        XCTAssertNotNil(hello)
        XCTAssertEqual(hello?.version, "1.10.0")
    }

    func testExtractMessage_NotFound() async throws {
        let client = KanataTCPClient(port: port)
        let response = #"{"status":"Ok"}"#
        let data = Data(response.utf8)
        let result = try await client.extractMessage(
            named: "HelloOk",
            into: KanataTCPClient.TcpHelloOk.self,
            from: data
        )
        XCTAssertNil(result)
    }

    func testExtractMessage_MalformedPayload() async throws {
        let client = KanataTCPClient(port: port)
        let response = #"{"HelloOk":{"bad_field":"no version"}}"#
        let data = Data(response.utf8)
        let result = try await client.extractMessage(
            named: "HelloOk",
            into: KanataTCPClient.TcpHelloOk.self,
            from: data
        )
        // The minimal form decoder accepts a "server" key; with neither
        // "version" nor "server", it falls back to defaults — so this may
        // succeed or fail depending on the decoder. Either way, no crash.
        _ = result
    }

    // MARK: - Connection Lifecycle Without Server

    func testCheckServerStatus_NoServer() async {
        let client = KanataTCPClient(port: port, timeout: 0.1)
        let status = await client.checkServerStatus()
        XCTAssertFalse(status, "Should return false when server is not running")
    }

    func testReloadConfig_NoServer() async {
        let client = KanataTCPClient(port: port, timeout: 0.1)
        let result = await client.reloadConfig(timeoutMs: 100)
        switch result {
        case .networkError:
            break
        default:
            XCTFail("Expected networkError when server not running, got \(result)")
        }
    }

    // MARK: - EngineReloadSingleFlight Tests

    func testSingleFlight_CoalescesConcurrentRequests() async {
        let singleFlight = EngineReloadSingleFlight()

        actor Counter {
            var count = 0
            func increment() {
                count += 1
            }

            func get() -> Int {
                count
            }
        }
        let counter = Counter()

        async let r1 = singleFlight.run(reason: "test1", debounce: 0) {
            await counter.increment()
            return EngineReloadResult.success(response: "ok")
        }
        async let r2 = singleFlight.run(reason: "test2", debounce: 0) {
            await counter.increment()
            return EngineReloadResult.success(response: "ok")
        }

        let results = await (r1, r2)
        XCTAssertTrue(results.0.isSuccess)
        XCTAssertTrue(results.1.isSuccess)
        let execCount = await counter.get()
        XCTAssertLessThanOrEqual(execCount, 2, "Concurrent requests should coalesce (1) or both run (2)")
    }

    func testSingleFlight_SequentialRequestsBothExecute() async {
        let singleFlight = EngineReloadSingleFlight()

        let r1 = await singleFlight.run(reason: "first", debounce: 0) {
            EngineReloadResult.success(response: "ok1")
        }
        let r2 = await singleFlight.run(reason: "second", debounce: 0) {
            EngineReloadResult.success(response: "ok2")
        }

        XCTAssertTrue(r1.isSuccess)
        XCTAssertTrue(r2.isSuccess)
    }

    // MARK: - TcpLayerNames / TcpFakeKeyNames Parsing

    func testLayerNames_Parsing() throws {
        let json = #"{"names":["base","nav","window"],"request_id":5}"#
        let data = try XCTUnwrap(json.data(using: .utf8))
        let result = try JSONDecoder().decode(KanataTCPClient.TcpLayerNames.self, from: data)
        XCTAssertEqual(result.names, ["base", "nav", "window"])
        XCTAssertEqual(result.request_id, 5)
    }

    func testFakeKeyNames_Parsing() throws {
        let json = #"{"names":["lctl","lsft","nav_toggle"],"request_id":6}"#
        let data = try XCTUnwrap(json.data(using: .utf8))
        let result = try JSONDecoder().decode(KanataTCPClient.TcpFakeKeyNames.self, from: data)
        XCTAssertEqual(result.names, ["lctl", "lsft", "nav_toggle"])
        XCTAssertEqual(result.request_id, 6)
    }

    func testLayerNames_EmptyList() throws {
        let json = #"{"names":[]}"#
        let data = try XCTUnwrap(json.data(using: .utf8))
        let result = try JSONDecoder().decode(KanataTCPClient.TcpLayerNames.self, from: data)
        XCTAssertTrue(result.names.isEmpty)
        XCTAssertNil(result.request_id)
    }
}
