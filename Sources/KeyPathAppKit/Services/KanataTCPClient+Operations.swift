import Foundation
import KeyPathCore

// MARK: - Server Operations

extension KanataTCPClient {
    // MARK: - Handshake / Status

    /// Perform Hello handshake and cache capabilities.
    /// Kanata may emit a status line and/or broadcast lines before HelloOk.
    /// We parse HelloOk from the first response and fall back to reading
    /// additional lines only if needed.
    func hello() async throws -> TcpHelloOk {
        // FIX #3: Wrap operation with error recovery to clean up bad connections
        try await withErrorRecovery {
            if let cachedHello { return cachedHello }

            let requestId = generateRequestId()
            let requestData = try JSONEncoder().encode(["Hello": ["request_id": requestId]])
            let start = CFAbsoluteTimeGetCurrent()

            // Read first response (may already contain HelloOk)
            let firstLine = try await send(requestData)
            let firstLineStr = String(data: firstLine, encoding: .utf8) ?? ""
            AppLogger.shared.log("🌐 [TCP] Hello response: \(firstLineStr)")

            if let hello = try extractMessage(named: "HelloOk", into: TcpHelloOk.self, from: firstLine) {
                let dt = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
                AppLogger.shared.log(
                    "✅ [TCP] hello ok (duration=\(dt)ms, protocol=\(hello.protocolVersion), caps=\(hello.capabilities.joined(separator: ",")))"
                )
                cachedHello = hello
                return hello
            }

            // Check if first line indicates error
            if let json = try? JSONSerialization.jsonObject(with: firstLine) as? [String: Any],
               let status = json["status"] as? String,
               status.lowercased() == "error" {
                let errorMsg = json["msg"] as? String ?? "Hello request failed"
                throw KeyPathError.communication(.connectionFailed(reason: errorMsg))
            }

            // Fallback: read additional lines until we find HelloOk or time out.
            let connection = try await ensureConnectionCore()
            let deadline = CFAbsoluteTimeGetCurrent() + 5.0
            var attempts = 0
            var lastLine = firstLine

            while CFAbsoluteTimeGetCurrent() < deadline, attempts < 5 {
                let remaining = max(0.1, deadline - CFAbsoluteTimeGetCurrent())
                let nextLine = try await withTimeout(seconds: remaining) {
                    try await self.readUntilNewline(on: connection)
                }
                attempts += 1
                lastLine = nextLine

                if isUnsolicitedBroadcast(nextLine) {
                    continue
                }

                if let hello = try extractMessage(named: "HelloOk", into: TcpHelloOk.self, from: nextLine) {
                    let dt = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
                    AppLogger.shared.log(
                        "✅ [TCP] hello ok (duration=\(dt)ms, protocol=\(hello.protocolVersion), caps=\(hello.capabilities.joined(separator: ",")))"
                    )
                    cachedHello = hello
                    return hello
                }

                if let json = try? JSONSerialization.jsonObject(with: nextLine) as? [String: Any],
                   let status = json["status"] as? String,
                   status.lowercased() == "error" {
                    let errorMsg = json["msg"] as? String ?? "Hello request failed"
                    throw KeyPathError.communication(.connectionFailed(reason: errorMsg))
                }
            }

            let raw = String(data: lastLine, encoding: .utf8) ?? ""
            AppLogger.shared.error("🌐 [TCP] hello parse failed: \(raw)")
            throw KeyPathError.communication(.invalidResponse)
        }
    }

    /// Enforce minimum protocol/capabilities. Callers pass only what they need.
    func enforceMinimumCapabilities(required: [String]) async throws {
        let hello = try await hello()
        guard hello.protocolVersion >= 1, hello.hasCapabilities(required) else {
            AppLogger.shared.error(
                "🌐 [TCP] capability check failed required=\(required.joined(separator: ",")) caps=\(hello.capabilities.joined(separator: ","))"
            )
            throw KeyPathError.communication(.invalidResponse)
        }
        AppLogger.shared.debug(
            "🌐 [TCP] capability check ok required=\(required.joined(separator: ","))"
        )
    }

    /// Fetch StatusInfo
    func getStatus() async throws -> TcpStatusInfo {
        // FIX #3: Wrap operation with error recovery to clean up bad connections
        try await withErrorRecovery {
            let requestId = generateRequestId()
            let requestData = try JSONEncoder().encode(["Status": ["request_id": requestId]])
            let responseData = try await send(requestData)
            if let status = try extractMessage(
                named: "StatusInfo", into: TcpStatusInfo.self, from: responseData
            ) {
                return status
            }
            throw KeyPathError.communication(.invalidResponse)
        }
    }

    /// Request available layer names from Kanata
    func requestLayerNames() async throws -> [String] {
        try await withErrorRecovery {
            let requestId = generateRequestId()
            let requestData = try JSONEncoder().encode(["RequestLayerNames": ["request_id": requestId]])
            let responseData = try await send(requestData)
            if let response = try extractMessage(
                named: "LayerNames", into: TcpLayerNames.self, from: responseData
            ) {
                return response.names
            }
            throw KeyPathError.communication(.invalidResponse)
        }
    }

    /// Check if TCP server is available
    func checkServerStatus() async -> Bool {
        AppLogger.shared.debug("🌐 [TCP] Checking server status for \(host):\(port)")

        do {
            // Use RequestCurrentLayerName as a simple ping
            let pingData = try JSONEncoder().encode(["RequestCurrentLayerName": [:] as [String: String]])
            let responseData = try await send(pingData)

            if let responseString = String(data: responseData, encoding: .utf8) {
                AppLogger.shared.debug("✅ [TCP] Server is responding: \(responseString.prefix(100))")
                return true
            }

            return false
        } catch {
            AppLogger.shared.warn("❌ [TCP] Server check failed: \(error)")
            // FIX #3: Close connection on error so next call gets fresh connection
            if shouldRetry(error) {
                AppLogger.shared.debug("🌐 [TCP] Closing connection after server check failure")
                closeConnection()
            }
            return false
        }
    }

    /// Send reload command to Kanata
    /// Prefer Reload(wait/timeout_ms); fall back to basic {"Reload":{}} and Ok/Error if needed.
    func reloadConfig(timeoutMs: UInt32 = 5000) async -> TCPReloadResult {
        let startTime = Date()
        AppLogger.shared.log("⏱️ [TCP] t=0ms: Starting reload (timeoutMs=\(timeoutMs))")

        do {
            // Preferred: wait contract (v2)
            let requestId = generateRequestId()
            let req: [String: Any] = [
                "Reload": [
                    "wait": true,
                    "timeout_ms": Int(timeoutMs),
                    "request_id": requestId
                ]
            ]
            let requestData = try JSONSerialization.data(withJSONObject: req)

            AppLogger.shared.log("⏱️ [TCP] t=\(Int(Date().timeIntervalSince(startTime) * 1000))ms: Sending reload request")

            // Read first line (status response) with timeout
            let firstLine = try await withThrowingTaskGroup(of: Data.self) { group in
                group.addTask {
                    try await self.send(requestData)
                }

                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(timeoutMs + 1000) * 1_000_000)
                    throw KeyPathError.communication(.timeout)
                }

                let result = try await group.next()!
                group.cancelAll()
                return result
            }
            let firstLineStr = String(data: firstLine, encoding: .utf8) ?? ""
            let connectionStateAfterFirstRead = stateString(connection?.state)
            AppLogger.shared.log("⏱️ [TCP] t=\(Int(Date().timeIntervalSince(startTime) * 1000))ms: First line received, connection state=\(connectionStateAfterFirstRead)")
            AppLogger.shared.log("🔄 [TCP] Reload status: \(firstLineStr)")

            // Check if first line indicates error
            if let json = try? JSONSerialization.jsonObject(with: firstLine) as? [String: Any],
               let status = json["status"] as? String,
               status.lowercased() == "error" {
                let errorMsg = json["msg"] as? String ?? "Reload failed"
                AppLogger.shared.log("❌ [TCP] Reload failed: \(errorMsg)")
                return .failure(error: errorMsg, response: firstLineStr)
            }

            if let reload = try extractMessage(
                named: "ReloadResult", into: ReloadResult.self, from: firstLine
            ) {
                if reload.ready {
                    let dur = reload.duration_ms ?? 0
                    let ep = reload.epoch ?? 0
                    let totalTime = Int(Date().timeIntervalSince(startTime) * 1000)
                    AppLogger.shared.log("✅ [TCP] Reload(wait) ok duration=\(dur)ms epoch=\(ep)")
                    AppLogger.shared.log("⏱️ [TCP] t=\(totalTime)ms: Reload completed successfully")
                    return .success(response: firstLineStr)
                } else {
                    let totalTime = Int(Date().timeIntervalSince(startTime) * 1000)
                    AppLogger.shared.log("⚠️ [TCP] Reload(wait) timeout before \(reload.timeout_ms) ms")
                    AppLogger.shared.log("⏱️ [TCP] t=\(totalTime)ms: Reload timed out")
                    return .failure(error: "timeout", response: firstLineStr)
                }
            }

            // If we couldn't parse ReloadResult, treat status OK as success (backward compat)
            let totalTime = Int(Date().timeIntervalSince(startTime) * 1000)
            AppLogger.shared.log("✅ [TCP] Config reload acknowledged (status OK, no ReloadResult)")
            AppLogger.shared.log("⏱️ [TCP] t=\(totalTime)ms: Reload completed (backward compat mode)")
            return .success(response: firstLineStr)
        } catch {
            let totalTime = Int(Date().timeIntervalSince(startTime) * 1000)
            let connectionState = stateString(connection?.state)
            AppLogger.shared.log("❌ [TCP] Reload error at t=\(totalTime)ms: \(error)")
            AppLogger.shared.log("❌ [TCP] Connection state at error: \(connectionState)")
            // FIX #3: Close connection on error so next call gets fresh connection
            if shouldRetry(error) {
                AppLogger.shared.debug("🌐 [TCP] Closing connection after reload error")
                closeConnection()
            }
            return .networkError(error.localizedDescription)
        }
    }

    // MARK: - Virtual/Fake Key Actions

    /// Trigger a virtual/fake key defined in Kanata config via TCP
    ///
    /// This allows external tools (deep links, Raycast, etc.) to trigger
    /// actions defined in `defvirtualkeys` or `deffakekeys`.
    ///
    /// Example Kanata config:
    /// ```
    /// (defvirtualkeys
    ///   email-sig (macro H e l l o spc W o r l d)
    ///   launch-obsidian (cmd open -a Obsidian)
    /// )
    /// ```
    ///
    /// Then trigger via: `keypath://fakekey/email-sig/tap`
    ///
    /// - Parameters:
    ///   - name: The name of the virtual/fake key as defined in config
    ///   - action: The action to perform (press, release, tap, toggle)
    /// - Returns: Result indicating success or failure
    func actOnFakeKey(name: String, action: FakeKeyAction) async -> FakeKeyResult {
        AppLogger.shared.log("🎹 [TCP] ActOnFakeKey: \(name) \(action.rawValue)")

        do {
            let requestId = generateRequestId()
            let req: [String: Any] = [
                "ActOnFakeKey": [
                    "name": name,
                    "action": action.rawValue,
                    "request_id": requestId
                ]
            ]
            let requestData = try JSONSerialization.data(withJSONObject: req)

            let responseData = try await send(requestData)
            let responseStr = String(data: responseData, encoding: .utf8) ?? ""
            AppLogger.shared.log("🎹 [TCP] ActOnFakeKey response: \(responseStr)")

            // Parse response
            if let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
               let status = json["status"] as? String {
                if status.lowercased() == "ok" {
                    AppLogger.shared.log("✅ [TCP] ActOnFakeKey success: \(name)")
                    return .success
                } else {
                    let errorMsg = json["msg"] as? String ?? "Unknown error"
                    AppLogger.shared.log("❌ [TCP] ActOnFakeKey failed: \(errorMsg)")
                    return .error(errorMsg)
                }
            }

            return .success
        } catch {
            AppLogger.shared.error("❌ [TCP] ActOnFakeKey error: \(error)")
            if shouldRetry(error) {
                closeConnection()
            }
            return .networkError(error.localizedDescription)
        }
    }

    // MARK: - Change Layer

    /// Switch to a different layer in Kanata via TCP
    ///
    /// Sends the `ChangeLayer` command to Kanata to programmatically switch layers.
    /// This is typically used when the user clicks on a layer in the layer picker.
    ///
    /// - Parameter layerName: The name of the layer to switch to (e.g., "nav", "base")
    /// - Returns: Result indicating success or failure
    func changeLayer(_ layerName: String) async -> ChangeLayerResult {
        AppLogger.shared.log("🔀 [TCP] ChangeLayer: \(layerName)")

        do {
            let requestId = generateRequestId()
            let req: [String: Any] = [
                "ChangeLayer": [
                    "new": layerName,
                    "request_id": requestId
                ]
            ]
            let requestData = try JSONSerialization.data(withJSONObject: req)

            let responseData = try await send(requestData)
            let responseStr = String(data: responseData, encoding: .utf8) ?? ""
            AppLogger.shared.log("🔀 [TCP] ChangeLayer response: \(responseStr)")

            // Parse response
            if let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
               let status = json["status"] as? String {
                if status.lowercased() == "ok" {
                    AppLogger.shared.log("✅ [TCP] ChangeLayer success: \(layerName)")
                    return .success
                } else {
                    let errorMsg = json["msg"] as? String ?? "Unknown error"
                    AppLogger.shared.log("❌ [TCP] ChangeLayer failed: \(errorMsg)")
                    return .error(errorMsg)
                }
            }

            return .success
        } catch {
            AppLogger.shared.error("❌ [TCP] ChangeLayer error: \(error)")
            if shouldRetry(error) {
                closeConnection()
            }
            return .networkError(error.localizedDescription)
        }
    }
}
