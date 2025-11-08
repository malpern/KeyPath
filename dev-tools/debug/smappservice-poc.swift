import Foundation
import OSLog
import ServiceManagement

/// POC utility for evaluating SMAppService vs launchctl for daemon management
///
/// Usage:
///   swift run smappservice-poc <plistName> [action]
///   swift run smappservice-poc com.keypath.helper.plist status
///   swift run smappservice-poc com.keypath.helper.plist register
///   swift run smappservice-poc com.keypath.helper.plist unregister
///   swift run smappservice-poc --create-test-plist
///   swift run smappservice-poc --lifecycle-test <plistName>
///
/// Actions:
///   status      - Check current SMAppService status (default)
///   register    - Register the daemon via SMAppService
///   unregister  - Unregister the daemon via SMAppService
///   lifecycle   - Test full lifecycle (register → wait → unregister)
///
/// Options:
///   --create-test-plist  - Create a minimal test daemon plist in app bundle
///   --lifecycle-test     - Test register → wait → check status → unregister
///   --verbose            - Enable OSLog diagnostics
@main
struct SMAppServicePOC {
    private static let logger = Logger(subsystem: "com.keypath.debug", category: "SMAppServicePOC")

  static func main() {
        let args = Array(CommandLine.arguments.dropFirst())

        // Handle special options
        if args.contains("--create-test-plist") {
            createTestPlist()
            return
        }

        guard let plistName = args.first(where: { !$0.hasPrefix("--") }) else {
            printUsage()
      exit(2)
    }

        let action = args.first(where: { !$0.hasPrefix("--") && $0 != plistName }) ?? "status"
        let verbose = args.contains("--verbose")

        if verbose {
            print("📋 macOS Version: \(ProcessInfo.processInfo.operatingSystemVersionString)")
            print("📦 App Bundle: \(Bundle.main.bundlePath)")
            print("🔍 Checking plist: \(plistName)")

            // Check if plist exists in bundle
            let expectedPath = "\(Bundle.main.bundlePath)/Contents/Library/LaunchDaemons/\(plistName)"
            if FileManager.default.fileExists(atPath: expectedPath) {
                print("✅ Found plist in bundle: \(expectedPath)")
            } else {
                print("⚠️ Plist not found in bundle (expected at \(expectedPath))")
            }
        }

        guard #available(macOS 13, *) else {
            print("❌ SMAppService.daemon requires macOS 13+")
            print("   Current version: \(ProcessInfo.processInfo.operatingSystemVersionString)")
            exit(1)
        }

    let svc = SMAppService.daemon(plistName: plistName)

    switch action {
    case "status":
            printStatus("SMAppService", svc: svc, verbose: verbose)

    case "register":
            testRegister(svc: svc, verbose: verbose)

    case "unregister":
            testUnregister(plistName: plistName, svc: svc, verbose: verbose)

        case "lifecycle":
            testLifecycle(svc: svc, plistName: plistName, verbose: verbose)

        default:
            print("❌ Unknown action: \(action)")
            printUsage()
            exit(2)
        }
    }

    private static func printUsage() {
        print("""
        Usage: smappservice-poc <plistName> [action] [options]

        Actions:
          status      - Check current SMAppService status (default)
          register    - Register the daemon via SMAppService
          unregister  - Unregister the daemon via SMAppService
          lifecycle   - Test full lifecycle (register → wait → unregister)

        Options:
          --create-test-plist  - Create a minimal test daemon plist in app bundle
          --lifecycle-test     - Alias for lifecycle action
          --verbose            - Enable verbose OSLog diagnostics

        Examples:
          swift run smappservice-poc com.keypath.helper.plist status
          swift run smappservice-poc com.keypath.helper.plist register --verbose
          swift run smappservice-poc com.keypath.helper.plist lifecycle
          swift run smappservice-poc --create-test-plist
        """)
    }

    private static func printStatus(_ prefix: String, svc: SMAppService, verbose: Bool) {
        let status = svc.status
        let statusDesc = statusDescription(status)
        print("\(prefix) status=\(status.rawValue) (\(statusDesc))")

        if verbose {
            logger.info("SMAppService status check: \(statusDesc, privacy: .public)")

            // Check launchctl status for comparison
            if let label = extractLabel(from: svc) {
                checkLaunchctlStatus(label: label)
            }
        }
    }

    private static func statusDescription(_ status: SMAppService.Status) -> String {
        switch status {
        case .notRegistered: return "notRegistered"
        case .enabled: return "enabled"
        case .requiresApproval: return "requiresApproval"
        case .notFound: return "notFound"
        @unknown default: return "unknown(\(status.rawValue))"
        }
    }

    private static func testRegister(svc: SMAppService, verbose: Bool) {
        printStatus("Before register", svc: svc, verbose: verbose)

        let startTime = Date()
        do {
            try svc.register()
            let duration = Date().timeIntervalSince(startTime)
            print("✅ register() succeeded (took \(String(format: "%.3f", duration))s)")

            if verbose {
                logger.info("SMAppService register succeeded in \(duration) seconds")
            }
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            print("❌ register() failed after \(String(format: "%.3f", duration))s: \(error)")

            if verbose {
                logger.error("SMAppService register failed: \(error.localizedDescription, privacy: .public)")
                print("💡 Check System Settings → Login Items for approval prompts")
        }
        }

        printStatus("After register", svc: svc, verbose: verbose)
    }

    private static func testUnregister(plistName: String, svc: SMAppService, verbose: Bool) {
        printStatus("Before unregister", svc: svc, verbose: verbose)

        guard #available(macOS 13, *) else {
        print("⚠️ unregister requires macOS 13+")
            return
        }

        let startTime = Date()
        let sema = DispatchSemaphore(value: 0)
        let errorBox = OSAllocatedUnfairLock<Error?>(initialState: nil)

        // Create service inside Task to avoid Sendable issues
        Task { @MainActor in
            let taskSvc = SMAppService.daemon(plistName: plistName)
            do {
                try await taskSvc.unregister()
            } catch {
                errorBox.withLock { $0 = error }
            }
            sema.signal()
        }

        _ = sema.wait(timeout: .now() + 10)

        let thrown = errorBox.withLock { $0 }
        if let thrown {
            let duration = Date().timeIntervalSince(startTime)
            print("❌ unregister() failed after \(String(format: "%.3f", duration))s: \(thrown)")
            if verbose {
                logger.error("SMAppService unregister failed: \(thrown.localizedDescription, privacy: .public)")
            }
        } else {
            let duration = Date().timeIntervalSince(startTime)
            print("✅ unregister() succeeded (took \(String(format: "%.3f", duration))s)")
            if verbose {
                logger.info("SMAppService unregister succeeded in \(duration) seconds")
    }
  }

        printStatus("After unregister", svc: svc, verbose: verbose)
    }

    private static func testLifecycle(svc: SMAppService, plistName: String, verbose: Bool) {
        print("🔄 Testing full lifecycle for \(plistName)...")
        print("")

        // Step 1: Check initial status
        print("Step 1: Initial status")
        printStatus("  ", svc: svc, verbose: verbose)
        print("")

        // Step 2: Register
        print("Step 2: Registering...")
        testRegister(svc: svc, verbose: verbose)
        print("")

        // Step 3: Wait and check status
        print("Step 3: Waiting 2 seconds, then checking status...")
        Thread.sleep(forTimeInterval: 2.0)
        printStatus("  ", svc: svc, verbose: verbose)
        print("")

        // Step 4: Unregister
        print("Step 4: Unregistering...")
        testUnregister(plistName: plistName, svc: svc, verbose: verbose)
        print("")

        print("✅ Lifecycle test complete")
    }

    // MARK: - Helper Methods

    private static func extractLabel(from _: SMAppService) -> String? {
        // SMAppService doesn't expose the label directly, but we can try to infer from plistName
        // This is a limitation - we'd need to read the plist to get the Label
        return nil
    }

    private static func checkLaunchctlStatus(label: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/launchctl")
        task.arguments = ["print", "system/\(label)"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            if task.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    print("📋 launchctl print output:")
                    print(output)
                }
            } else {
                print("⚠️ launchctl print failed (exit code: \(task.terminationStatus))")
            }
        } catch {
            print("⚠️ Could not check launchctl status: \(error)")
        }
    }

    private static func createTestPlist() {
        print("📝 Creating test daemon plist for POC...")

        let testPlistName = "com.keypath.test-daemon.plist"
        let testPlistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>com.keypath.test-daemon</string>
            <key>ProgramArguments</key>
            <array>
                <string>/bin/echo</string>
                <string>Test daemon started</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <false/>
            <key>StandardOutPath</key>
            <string>/tmp/keypath-test-daemon.log</string>
            <key>StandardErrorPath</key>
            <string>/tmp/keypath-test-daemon.log</string>
        </dict>
        </plist>
        """

        guard let bundlePath = Bundle.main.bundlePath as String? else {
            print("❌ Could not determine app bundle path")
            exit(1)
    }

        let launchDaemonsPath = "\(bundlePath)/Contents/Library/LaunchDaemons"
        let plistPath = "\(launchDaemonsPath)/\(testPlistName)"

        // Create directory if needed
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: launchDaemonsPath) {
            do {
                try fileManager.createDirectory(atPath: launchDaemonsPath, withIntermediateDirectories: true)
                print("✅ Created directory: \(launchDaemonsPath)")
            } catch {
                print("❌ Failed to create directory: \(error)")
                exit(1)
            }
        }

        // Write plist
        do {
            try testPlistContent.write(toFile: plistPath, atomically: true, encoding: .utf8)
            print("✅ Created test plist: \(plistPath)")
            print("")
            print("📋 Next steps:")
            print("   1. Rebuild the app bundle to include this plist")
            print("   2. Run: swift run smappservice-poc \(testPlistName) lifecycle --verbose")
        } catch {
            print("❌ Failed to write plist: \(error)")
            exit(1)
        }
  }
}
