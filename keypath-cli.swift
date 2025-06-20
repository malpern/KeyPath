#!/usr/bin/env swift

// Enhanced KeyPath CLI Tool
// Command line interface for testing and managing Kanata rules

import Foundation

// Command line argument parsing
struct CLIArgs {
    var command: String = "test"
    var rule: String = ""
    var file: String = ""
    var help: Bool = false

    init(args: [String]) {
        for i in 0..<args.count {
            switch args[i] {
            case "--help", "-h":
                help = true
            case "--rule", "-r":
                if i + 1 < args.count {
                    rule = args[i + 1]
                }
            case "--file", "-f":
                if i + 1 < args.count {
                    file = args[i + 1]
                }
            case "test", "validate", "install", "status", "config":
                command = args[i]
            default:
                continue
            }
        }
    }
}

// Enhanced Kanata CLI functionality
class KeyPathCLI {
    private let configPath = NSString(string: "~/.config/kanata/kanata.kbd").expandingTildeInPath
    private let fileManager = FileManager.default

    func showHelp() {
        print("""
        🔧 KeyPath CLI Tool - Kanata Rule Management
        ==========================================

        USAGE:
            swift keypath-cli.swift <command> [options]

        COMMANDS:
            test        Run comprehensive Kanata environment tests
            validate    Validate a specific Kanata rule
            install     Install a rule to the active configuration
            status      Show current Kanata status and configuration
            config      Show current Kanata configuration

        OPTIONS:
            --rule, -r <rule>    Kanata rule to validate or install
            --file, -f <file>    File containing Kanata rules
            --help, -h           Show this help message

        EXAMPLES:
            swift keypath-cli.swift test
            swift keypath-cli.swift validate --rule "(defalias caps esc)"
            swift keypath-cli.swift install --rule "(defalias caps esc)"
            swift keypath-cli.swift status
            swift keypath-cli.swift config
        """)
    }

    // Find kanata executable
    func findKanataPath() -> String? {
        let commonPaths = [
            "/opt/homebrew/bin/kanata",
            "/usr/local/bin/kanata",
            "/usr/bin/kanata"
        ]

        for path in commonPaths {
            if fileManager.fileExists(atPath: path) {
                return path
            }
        }

        // Try using which command
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
                    return path
                }
            }
        } catch {
            // Silently fail
        }

        return nil
    }

    // Check if Kanata is running
    func isKanataRunning() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["pgrep", "-f", "kanata"]

        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    // Get current config content
    func getCurrentConfig() -> String? {
        guard fileManager.fileExists(atPath: configPath) else {
            return nil
        }

        return try? String(contentsOfFile: configPath, encoding: .utf8)
    }

    // Validate a Kanata rule
    func validateRule(_ rule: String) -> (Bool, String) {
        guard let kanataPath = findKanataPath() else {
            return (false, "Kanata executable not found")
        }

        // Create temporary config file with the rule
        let tempDir = NSTemporaryDirectory()
        let tempConfigPath = tempDir + "kanata-test-\(UUID().uuidString).kbd"

        let testConfig = """
        ;; Test configuration for rule validation
        (defcfg
          process-unmapped-keys yes
        )

        ;; Define source keys (comprehensive layout)
        (defsrc
          esc  f1   f2   f3   f4   f5   f6   f7   f8   f9   f10  f11  f12
          grv  1    2    3    4    5    6    7    8    9    0    -    =    bspc
          tab  q    w    e    r    t    y    u    i    o    p    [    ]    \\
          caps a    s    d    f    g    h    j    k    l    ;    '    ret
          lsft z    x    c    v    b    n    m    ,    .    /    rsft
          lctl lalt                    spc                 ralt rctl
        )

        ;; Define base layer
        (deflayer base
          esc  f1   f2   f3   f4   f5   f6   f7   f8   f9   f10  f11  f12
          grv  1    2    3    4    5    6    7    8    9    0    -    =    bspc
          tab  q    w    e    r    t    y    u    i    o    p    [    ]    \\
          caps a    s    d    f    g    h    j    k    l    ;    '    ret
          lsft z    x    c    v    b    n    m    ,    .    /    rsft
          lctl lalt                    spc                 ralt rctl
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

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            // Clean up temp file
            try? fileManager.removeItem(atPath: tempConfigPath)

            if task.terminationStatus == 0 {
                return (true, "Rule validation passed")
            } else {
                return (false, output)
            }

        } catch {
            return (false, "Failed to validate rule: \(error)")
        }
    }

    // Install rule to configuration
    func installRule(_ rule: String) -> (Bool, String) {
        guard fileManager.fileExists(atPath: configPath) else {
            return (false, "Kanata configuration file not found at: \(configPath)")
        }

        // Validate rule first
        let (isValid, validationMessage) = validateRule(rule)
        guard isValid else {
            return (false, "Rule validation failed: \(validationMessage)")
        }

        do {
            let currentConfig = try String(contentsOfFile: configPath, encoding: .utf8)

            // Create backup
            let backupPath = "\(configPath).keypath-backup-\(Int(Date().timeIntervalSince1970))"
            try currentConfig.write(toFile: backupPath, atomically: true, encoding: .utf8)

            // Add rule to config
            let newConfig = currentConfig + """

            ;; KeyPath installed rule - \(Date())
            \(rule)
            """

            try newConfig.write(toFile: configPath, atomically: true, encoding: .utf8)

            return (true, "Rule installed successfully. Backup created at: \(backupPath)")

        } catch {
            return (false, "Failed to install rule: \(error)")
        }
    }

    // Show comprehensive status
    func showStatus() {
        print("🔧 KeyPath - Kanata Status")
        print("=========================")

        // Check Kanata installation
        if let kanataPath = findKanataPath() {
            print("✅ Kanata installed at: \(kanataPath)")

            // Get version
            let task = Process()
            task.executableURL = URL(fileURLWithPath: kanataPath)
            task.arguments = ["--version"]

            let pipe = Pipe()
            task.standardOutput = pipe

            do {
                try task.run()
                task.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let version = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    print("   Version: \(version)")
                }
            } catch {
                print("   Version: Could not determine")
            }
        } else {
            print("❌ Kanata not installed")
        }

        // Check if running
        print("Process Status: \(isKanataRunning() ? "✅ Running" : "❌ Not running")")

        // Check config
        let configDir = NSString(string: "~/.config/kanata").expandingTildeInPath
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: configDir, isDirectory: &isDirectory) && isDirectory.boolValue {
            print("✅ Config directory exists: ~/.config/kanata/")

            if fileManager.fileExists(atPath: configPath) {
                print("✅ Config file exists: ~/.config/kanata/kanata.kbd")

                if let config = getCurrentConfig() {
                    let lines = config.components(separatedBy: .newlines)
                    print("   Lines: \(lines.count)")
                    print("   Size: \(config.count) characters")

                    // Count KeyPath rules
                    let keypathRules = lines.filter { $0.contains("KeyPath") }.count
                    if keypathRules > 0 {
                        print("   KeyPath rules: \(keypathRules)")
                    }
                }
            } else {
                print("❌ Config file missing: ~/.config/kanata/kanata.kbd")
            }
        } else {
            print("❌ Config directory missing: ~/.config/kanata/")
        }

        // Check permissions
        let homeDir = NSHomeDirectory()
        print("Current user: \(NSUserName())")
        print("Home directory: \(homeDir)")
    }

    // Show current configuration
    func showConfig() {
        print("📄 Current Kanata Configuration")
        print("==============================")

        guard let config = getCurrentConfig() else {
            print("❌ Could not read configuration file at: \(configPath)")
            return
        }

        let lines = config.components(separatedBy: .newlines)
        for (index, line) in lines.enumerated() {
            let lineNumber = String(format: "%3d", index + 1)
            print("\(lineNumber): \(line)")
        }

        print("\n📊 Configuration Summary")
        print("Lines: \(lines.count)")
        print("Characters: \(config.count)")
        print("File: \(configPath)")
    }

    // Run comprehensive tests
    func runTests() {
        print("🧪 KeyPath Comprehensive Tests")
        print("==============================")

        var passCount = 0
        var totalTests = 0

        // Test 1: Kanata Installation
        print("\n1. Testing Kanata Installation...")
        totalTests += 1
        if let kanataPath = findKanataPath() {
            print("   ✅ PASS: Kanata found at \(kanataPath)")
            passCount += 1
        } else {
            print("   ❌ FAIL: Kanata not found")
        }

        // Test 2: Configuration Setup
        print("\n2. Testing Configuration Setup...")
        totalTests += 1
        if getCurrentConfig() != nil {
            print("   ✅ PASS: Configuration file accessible")
            passCount += 1
        } else {
            print("   ❌ FAIL: Configuration file not accessible")
        }

        // Test 3: Rule Validation
        print("\n3. Testing Rule Validation...")
        let testRules = [
            ("Simple remap", "(defalias caps esc)"),
            ("Number remap", "(defalias 1 2)"),
            ("Modifier key", "(defalias lalt ralt)"),
            ("Tap-hold (corrected)", "(defalias caps (tap-hold 200 200 esc lctl))")
        ]

        for (name, rule) in testRules {
            totalTests += 1
            let (isValid, message) = validateRule(rule)
            if isValid {
                print("   ✅ PASS: \(name) - \(rule)")
                passCount += 1
            } else {
                print("   ❌ FAIL: \(name) - \(rule)")
                print("          \(message.components(separatedBy: .newlines).first ?? "")")
            }
        }

        // Test 4: Invalid Rule Detection
        print("\n4. Testing Invalid Rule Detection...")
        totalTests += 1
        let (invalidResult, _) = validateRule("(invalid syntax here)")
        if !invalidResult {
            print("   ✅ PASS: Invalid rule correctly rejected")
            passCount += 1
        } else {
            print("   ❌ FAIL: Invalid rule was accepted")
        }

        // Test Summary
        print("\n📊 Test Results")
        print("==============")
        print("Passed: \(passCount)/\(totalTests)")
        print("Success Rate: \(Int(Double(passCount)/Double(totalTests) * 100))%")

        if passCount == totalTests {
            print("🎉 All tests passed! KeyPath is ready to use.")
        } else {
            print("⚠️  Some tests failed. Check the output above for details.")
        }
    }

    // Main CLI entry point
    func run(args: CLIArgs) {
        if args.help {
            showHelp()
            return
        }

        switch args.command {
        case "test":
            runTests()

        case "validate":
            if args.rule.isEmpty {
                print("❌ Error: No rule specified. Use --rule to provide a rule to validate.")
                return
            }

            print("🔍 Validating rule: \(args.rule)")
            let (isValid, message) = validateRule(args.rule)

            if isValid {
                print("✅ Rule is valid")
            } else {
                print("❌ Rule is invalid:")
                print("\(message)")
            }

        case "install":
            if args.rule.isEmpty {
                print("❌ Error: No rule specified. Use --rule to provide a rule to install.")
                return
            }

            print("📥 Installing rule: \(args.rule)")
            let (success, message) = installRule(args.rule)

            if success {
                print("✅ \(message)")
                print("💡 Restart Kanata to apply changes")
            } else {
                print("❌ \(message)")
            }

        case "status":
            showStatus()

        case "config":
            showConfig()

        default:
            print("❌ Unknown command: \(args.command)")
            print("Use --help for usage information")
        }
    }
}

// Main execution
let args = Array(CommandLine.arguments.dropFirst()) // Remove script name
let cliArgs = CLIArgs(args: args)
let cli = KeyPathCLI()
cli.run(args: cliArgs)
