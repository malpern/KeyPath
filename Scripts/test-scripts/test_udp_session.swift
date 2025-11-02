#!/usr/bin/env swift

import Foundation
import Network

// Test script to demonstrate the UDP session persistence fix

let host = "127.0.0.1"
let port: UInt16 = 54141
let token = "zRI9ygKn46yc0-kowyIfdAWpfSfRm5mrq3Uui6211Kc"

func testUDPSession() async {
    print("🧪 Testing UDP session persistence fix")
    print("🌐 Connecting to Kanata UDP server at \(host):\(port)")

    // Create a persistent connection (our fix)
    guard let nwPort = NWEndpoint.Port(rawValue: port) else {
        print("❌ Invalid port")
        return
    }

    let connection = NWConnection(
        host: NWEndpoint.Host(host),
        port: nwPort,
        using: .udp
    )

    let queue = DispatchQueue(label: "udp-test")

    await withCheckedContinuation { continuation in
        var hasStarted = false

        connection.stateUpdateHandler = { state in
            print("📡 Connection state: \(state)")
            if state == .ready && !hasStarted {
                hasStarted = true
                continuation.resume()
            }
        }

        connection.start(queue: queue)
    }

    // Test 1: Authentication
    print("\n🔐 Step 1: Authentication")
    let authRequest = "{\"Authenticate\": {\"token\": \"\(token)\", \"client_name\": \"TestScript\"}}"
    let authData = authRequest.data(using: .utf8)!

    let authResponse = await sendMessage(connection: connection, data: authData)
    print("🔐 Auth response: \(authResponse)")

    // Extract session ID
    guard let sessionId = extractSessionId(from: authResponse) else {
        print("❌ Failed to get session ID")
        return
    }
    print("✅ Got session ID: \(sessionId)")

    // Test 2: Config reload using SAME connection (our fix)
    print("\n🔄 Step 2: Config reload with same connection")
    let reloadRequest = "{\"Reload\": {\"session_id\": \"\(sessionId)\"}}"
    let reloadData = reloadRequest.data(using: .utf8)!

    let reloadResponse = await sendMessage(connection: connection, data: reloadData)
    print("🔄 Reload response: \(reloadResponse)")

    if reloadResponse.contains("AuthRequired") {
        print("❌ Session lost - our fix didn't work!")
    } else if reloadResponse.contains("Ok") || reloadResponse.contains("success") {
        print("✅ Success! Session persisted - our fix works!")
    } else {
        print("🤔 Unexpected response: \(reloadResponse)")
    }

    connection.cancel()
    print("\n🧪 Test completed")
}

func sendMessage(connection: NWConnection, data: Data) async -> String {
    await withCheckedContinuation { continuation in
        connection.send(content: data, completion: .contentProcessed { error in
            if let error = error {
                continuation.resume(returning: "Error: \(error)")
                return
            }

            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { responseData, _, _, error in
                if let error = error {
                    continuation.resume(returning: "Receive error: \(error)")
                } else if let responseData = responseData,
                          let responseString = String(data: responseData, encoding: .utf8) {
                    continuation.resume(returning: responseString)
                } else {
                    continuation.resume(returning: "No response")
                }
            }
        })
    }
}

func extractSessionId(from response: String) -> String? {
    // Simple JSON parsing to extract session_id
    if let data = response.data(using: .utf8),
       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let authResult = json["AuthResult"] as? [String: Any],
        let sessionId = authResult["session_id"] as? String {
        return sessionId
    }
    return nil
}

// Run the test
Task {
    await testUDPSession()
    exit(0)
}

RunLoop.main.run()



