import Foundation
import KeyPathCore

// MARK: - Message Parsing and Broadcast Detection

extension KanataTCPClient {
    /// Check if a JSON message is an unsolicited broadcast event (not a command response)
    nonisolated func isUnsolicitedBroadcast(_ data: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }

        // These are broadcast events that Kanata sends to all clients
        let broadcastKeys = ["LayerChange", "ConfigFileReload", "MessagePush", "Ready", "ConfigError"]
        return broadcastKeys.contains(where: { json[$0] != nil })
    }

    /// Helper to extract request_id from a JSON response
    nonisolated func extractRequestId(from data: Data) -> UInt64? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        func parseRequestIdValue(_ value: Any) -> UInt64? {
            if let number = value as? NSNumber {
                return number.uint64Value
            }
            if let stringValue = value as? String, let parsed = UInt64(stringValue) {
                return parsed
            }
            return value as? UInt64
        }

        if let topLevel = json["request_id"], let id = parseRequestIdValue(topLevel) {
            return id
        }

        // Try to find request_id in the first level of any message type
        for (_, value) in json {
            if let dict = value as? [String: Any],
               let nested = dict["request_id"],
               let requestId = parseRequestIdValue(nested)
            {
                return requestId
            }
        }

        return nil
    }

    #if DEBUG
        /// Test hook exposed in DEBUG builds to validate request_id parsing behavior.
        nonisolated func _testExtractRequestId(from data: Data) -> UInt64? {
            extractRequestId(from: data)
        }
    #endif

    /// Extract error message from JSON response using structured parsing
    func extractError(from response: String) -> String {
        // Try to parse as ServerResponse first
        if let data = response.data(using: .utf8) {
            // Check if it's a single-line response
            let lines = response.split(separator: "\n")
            if let firstLine = lines.first,
               let lineData = String(firstLine).data(using: .utf8)
            {
                if let serverResponse = try? JSONDecoder().decode(TcpServerResponse.self, from: lineData),
                   serverResponse.isError
                {
                    return serverResponse.msg ?? "Unknown error"
                }
            }

            // Fallback: try parsing as generic JSON
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let error = json["error"] as? String {
                    return error
                }
                if let msg = json["msg"] as? String {
                    return msg
                }
            }
        }
        return "Unknown error"
    }

    /// Extract a named server message (second line) from a newline-delimited response
    func extractMessage<T: Decodable>(named name: String, into _: T.Type, from data: Data)
        throws -> T?
    {
        guard let s = String(data: data, encoding: .utf8) else {
            AppLogger.shared.log("🔍 [TCP extractMessage] Failed to decode data as UTF-8")
            return nil
        }

        AppLogger.shared.log(
            "🔍 [TCP extractMessage] Looking for '\(name)' in response: \(s.prefix(200))"
        )

        // Split by newlines; look for an object where the top-level key is the provided name
        for (index, line) in s.split(separator: "\n").map(String.init).enumerated() {
            AppLogger.shared.log("🔍 [TCP extractMessage] Line \(index): \(line.prefix(150))")

            guard let lineData = line.data(using: .utf8) else { continue }
            // Try loose parse via JSONSerialization to locate the named object
            guard let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                AppLogger.shared.log("🔍 [TCP extractMessage] Line \(index): Not valid JSON object")
                continue
            }

            AppLogger.shared.log(
                "🔍 [TCP extractMessage] Line \(index) keys: \(obj.keys.joined(separator: ", "))"
            )

            guard let payload = obj[name] else {
                AppLogger.shared.log("🔍 [TCP extractMessage] Line \(index): Missing key '\(name)'")
                continue
            }

            // Re-encode payload and decode strongly
            guard let payloadData = try? JSONSerialization.data(withJSONObject: payload) else {
                AppLogger.shared.log("🔍 [TCP extractMessage] Line \(index): Failed to re-encode payload")
                continue
            }

            do {
                let decoded = try JSONDecoder().decode(T.self, from: payloadData)
                AppLogger.shared.log(
                    "✅ [TCP extractMessage] Successfully decoded '\(name)' from line \(index)"
                )
                return decoded
            } catch {
                AppLogger.shared.log("❌ [TCP extractMessage] Line \(index): Decoding failed: \(error)")
                continue
            }
        }

        AppLogger.shared.log("❌ [TCP extractMessage] Could not find '\(name)' in any line")
        return nil
    }
}
