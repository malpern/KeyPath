#!/usr/bin/env swift

import Foundation

// Simple test to verify TCP validation integration
func testTCPValidationIntegration() async {
    print("🧪 Testing TCP validation integration...")
    
    // Check if kanata is running with TCP
    let checkKanataProcess = Process()
    checkKanataProcess.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    checkKanataProcess.arguments = ["-f", "kanata.*--port"]
    
    do {
        try checkKanataProcess.run()
        checkKanataProcess.waitUntilExit()
        
        if checkKanataProcess.terminationStatus == 0 {
            print("✅ Kanata is running with TCP server")
            
            // Test basic TCP connection
            let testConnection = Process()
            testConnection.executableURL = URL(fileURLWithPath: "/usr/bin/nc")
            testConnection.arguments = ["-z", "127.0.0.1", "37000"]
            
            try testConnection.run()
            testConnection.waitUntilExit()
            
            if testConnection.terminationStatus == 0 {
                print("✅ TCP port 37000 is accessible")
                
                // Test validation with simple config
                let validateSimple = Process()
                validateSimple.executableURL = URL(fileURLWithPath: "/bin/sh")
                validateSimple.arguments = ["-c", "cat test-config-simple.kbd | jq -R -s -c '{ValidateConfig: {config_content: .}}' | nc 127.0.0.1 37000"]
                
                let pipe = Pipe()
                validateSimple.standardOutput = pipe
                
                try validateSimple.run()
                validateSimple.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                
                if output.contains("\"success\":true") {
                    print("✅ TCP validation working correctly")
                } else {
                    print("⚠️ TCP validation response: \(output)")
                }
            } else {
                print("❌ TCP port 37000 not accessible")
            }
        } else {
            print("⚠️ Kanata not running with TCP server")
        }
    } catch {
        print("❌ Error testing TCP validation: \(error)")
    }
}

await testTCPValidationIntegration()
print("🏁 TCP validation integration test completed")