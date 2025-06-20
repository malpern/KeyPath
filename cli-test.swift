#!/usr/bin/env swift

// Command Line Test Utility for KeyPath
// This script tests Kanata installation and rule validation directly

import Foundation

// Copy essential functionality from KeyPath for CLI testing
class CLIKanataInstaller {
    private let configPath = NSString(string: "~/.config/kanata/kanata.kbd").expandingTildeInPath
    private let fileManager = FileManager.default
    
    // Find kanata executable in common locations
    func findKanataPath() -> String? {
        let commonPaths = [
            "/opt/homebrew/bin/kanata",
            "/usr/local/bin/kanata",
            "/usr/bin/kanata"
        ]
        
        for path in commonPaths {
            if fileManager.fileExists(atPath: path) {
                print("✅ Kanata found at: \(path)")
                return path
            }
        }
        
        // Try using which command as fallback
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["which", "kanata"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            if task.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !path.isEmpty {
                    print("✅ Kanata found via which: \(path)")
                    return path
                }
            }
        } catch {
            print("❌ Failed to run which command: \(error)")
        }
        
        print("❌ Kanata not found in common locations")
        return nil
    }
    
    // Check Kanata setup
    func checkKanataSetup() -> Bool {
        let configDir = NSString(string: "~/.config/kanata").expandingTildeInPath
        
        // Check if config directory exists
        var isDirectory: ObjCBool = false
        if !fileManager.fileExists(atPath: configDir, isDirectory: &isDirectory) || !isDirectory.boolValue {
            print("❌ Kanata configuration directory not found at ~/.config/kanata/")
            return false
        }
        
        // Check if config file exists
        if !fileManager.fileExists(atPath: configPath) {
            print("❌ Kanata configuration file not found at ~/.config/kanata/kanata.kbd")
            return false
        }
        
        print("✅ Kanata configuration directory and file found")
        return true
    }
    
    // Get current config content
    func getCurrentConfig() -> String? {
        guard fileManager.fileExists(atPath: configPath) else {
            print("❌ Config file does not exist at: \(configPath)")
            return nil
        }
        
        do {
            let content = try String(contentsOfFile: configPath, encoding: .utf8)
            print("✅ Successfully read config file (\(content.count) characters)")
            return content
        } catch {
            print("❌ Failed to read config file: \(error)")
            return nil
        }
    }
    
    // Validate a rule using kanata --check
    func validateRule(_ rule: String) -> Bool {
        guard let kanataPath = findKanataPath() else {
            print("❌ Cannot validate rule - Kanata not found")
            return false
        }
        
        // Create temporary config file with the rule
        let tempDir = NSTemporaryDirectory()
        let tempConfigPath = tempDir + "kanata-test-\(UUID().uuidString).kbd"
        
        let testConfig = """
        ;; Test configuration for rule validation
        (defcfg
          process-unmapped-keys yes
        )
        
        ;; Define source keys
        (defsrc
          caps a b c d e f g h i j k l m n o p q r s t u v w x y z
          lsft rsft lctl rctl lalt ralt
        )
        
        ;; Define layer
        (deflayer base
          caps a b c d e f g h i j k l m n o p q r s t u v w x y z
          lsft rsft lctl rctl lalt ralt
        )
        
        ;; Test rule
        \(rule)
        """
        
        do {
            try testConfig.write(toFile: tempConfigPath, atomically: true, encoding: .utf8)
            
            let task = Process()
            task.executableURL = URL(fileURLWithPath: kanataPath)
            task.arguments = ["--check", "--cfg", tempConfigPath]
            
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            
            try task.run()
            task.waitUntilExit()
            
            // Clean up temp file
            try? fileManager.removeItem(atPath: tempConfigPath)
            
            if task.terminationStatus == 0 {
                print("✅ Rule validation passed")
                return true
            } else {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? "Unknown error"
                print("❌ Rule validation failed: \(output)")
                return false
            }
            
        } catch {
            print("❌ Failed to validate rule: \(error)")
            return false
        }
    }
}

// Main CLI functionality
func main() {
    print("🔧 KeyPath CLI Test Utility")
    print("==========================")
    
    let installer = CLIKanataInstaller()
    
    // Test 1: Check if Kanata is installed
    print("\n1. Checking Kanata Installation...")
    let kanataPath = installer.findKanataPath()
    
    // Test 2: Check Kanata setup (config directory and file)
    print("\n2. Checking Kanata Setup...")
    let setupOK = installer.checkKanataSetup()
    
    // Test 3: Read current config
    print("\n3. Reading Current Config...")
    if let config = installer.getCurrentConfig() {
        let lines = config.components(separatedBy: .newlines)
        print("   Config has \(lines.count) lines")
        if lines.count > 0 {
            print("   First line: \(lines[0])")
        }
        if lines.count > 1 {
            print("   Last line: \(lines.last ?? "")")
        }
    }
    
    // Test 4: Validate sample rules (only if Kanata is installed)
    if kanataPath != nil {
        print("\n4. Testing Rule Validation...")
        
        let testRules = [
            "(defalias caps esc)",
            "(defalias a b)",
            "(defalias caps (tap-hold 200 esc lctl))"
        ]
        
        for (index, rule) in testRules.enumerated() {
            print("   Testing rule \(index + 1): \(rule)")
            let isValid = installer.validateRule(rule)
            print("   Result: \(isValid ? "✅ Valid" : "❌ Invalid")")
        }
        
        // Test an invalid rule
        print("   Testing invalid rule: (invalid syntax)")
        let invalidResult = installer.validateRule("(invalid syntax)")
        print("   Result: \(invalidResult ? "❌ Should have failed" : "✅ Correctly failed")")
    }
    
    // Summary
    print("\n📊 Test Summary")
    print("===============")
    print("Kanata Installed: \(kanataPath != nil ? "✅ Yes" : "❌ No")")
    print("Config Setup: \(setupOK ? "✅ Yes" : "❌ No")")
    
    if kanataPath == nil {
        print("\n💡 To install Kanata:")
        print("   brew install kanata")
    }
    
    if !setupOK {
        print("\n💡 To set up Kanata config:")
        print("   mkdir -p ~/.config/kanata")
        print("   touch ~/.config/kanata/kanata.kbd")
    }
}

// Run the main function
main()