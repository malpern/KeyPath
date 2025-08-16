import XCTest

@testable import KeyPath

/// Integration tests for system state detection
/// Tests real system behavior with minimal mocking
class SystemStateDetectorTests: XCTestCase {
    var realKanataManager: KanataManager!
    var detector: SystemStateDetector!

    @MainActor
    override func setUp() {
        super.setUp()
        realKanataManager = KanataManager()
        detector = SystemStateDetector(kanataManager: realKanataManager)
    }

    // MARK: - Real System Integration Tests

    func testDetectsActualSystemState() async {
        // When: Detecting current system state
        let result = await detector.detectCurrentState()

        // Then: Should return a valid system state
        XCTAssertNotEqual(
            result.state, .initializing, "Should complete detection and return actual state"
        )

        // Should have detection timestamp
        XCTAssertLessThan(
            Date().timeIntervalSince(result.detectionTimestamp), 5.0, "Detection should be recent"
        )

        // State should be consistent with issues found
        switch result.state {
        case let .conflictsDetected(conflicts):
            XCTAssertFalse(conflicts.isEmpty, "If conflicts detected, should have actual conflicts")
            XCTAssertTrue(result.hasBlockingIssues, "Conflicts should be blocking")

        case let .missingPermissions(missing):
            XCTAssertFalse(missing.isEmpty, "If permissions missing, should specify which ones")

        case let .missingComponents(missing):
            XCTAssertFalse(missing.isEmpty, "If components missing, should specify which ones")

        case .active:
            XCTAssertFalse(result.hasBlockingIssues, "Active state should have no blocking issues")

        default:
            // Other states are valid
            break
        }

        print("✅ Detected system state: \(result.state)")
        print("✅ Found \(result.issues.count) issues")
    }

    func testConflictDetectionWithRealProcesses() async {
        // When: Detecting conflicts
        let result = await detector.detectConflicts()

        // Then: Should handle real system processes correctly
        for conflict in result.conflicts {
            switch conflict {
            case let .kanataProcessRunning(pid, command):
                XCTAssertGreaterThan(pid, 0, "PID should be valid")
                XCTAssertTrue(command.contains("kanata"), "Command should contain kanata")
                XCTAssertFalse(command.contains("pgrep"), "Should filter out pgrep itself")
                print("✅ Found kanata process: PID \(pid), command: \(command)")

            case let .karabinerGrabberRunning(pid):
                print("✅ Found Karabiner Elements grabber conflict: PID \(pid)")

            case let .exclusiveDeviceAccess(device):
                print("✅ Found exclusive device access conflict: \(device)")

            case let .karabinerVirtualHIDDeviceRunning(pid, processName):
                print("✅ Found Karabiner VirtualHIDDevice conflict: PID \(pid), process: \(processName)")

            case let .karabinerVirtualHIDDaemonRunning(pid):
                print("✅ Found Karabiner VirtualHID daemon conflict: PID \(pid)")
            }
        }

        print("✅ Total conflicts detected: \(result.conflicts.count)")
        print("✅ Can auto-resolve: \(result.canAutoResolve)")
    }

    func testPermissionCheckingWithRealSystem() async {
        // When: Checking permissions
        let result = await detector.checkPermissions()

        // Then: Should reflect actual system permissions
        XCTAssertFalse(
            result.granted.isEmpty || result.missing.isEmpty,
            "Should have some permissions granted or missing"
        )

        // Permissions should be mutually exclusive
        let grantedSet = Set(result.granted)
        let missingSet = Set(result.missing)
        XCTAssertTrue(
            grantedSet.isDisjoint(with: missingSet),
            "Permission should not be both granted and missing"
        )

        // Should cover all permission types
        let allPermissions: Set<PermissionRequirement> = [
            .keyPathInputMonitoring, .kanataInputMonitoring,
            .keyPathAccessibility, .kanataAccessibility,
            .driverExtensionEnabled, .backgroundServicesEnabled
        ]
        let checkedPermissions = grantedSet.union(missingSet)
        XCTAssertEqual(
            checkedPermissions, allPermissions,
            "Should check all required permissions"
        )

        print("✅ Permissions granted: \(result.granted.count)")
        print("✅ Permissions missing: \(result.missing.count)")
        print("✅ Needs user action: \(result.needsUserAction)")
    }

    func testComponentCheckingWithRealSystem() async {
        // When: Checking components
        let result = await detector.checkComponents()

        // Then: Should reflect actual component installation
        let allComponents: Set<ComponentRequirement> = [
            .kanataBinary, .karabinerDriver, .karabinerDaemon
        ]

        let installedSet = Set(result.installed)
        let missingSet = Set(result.missing)

        // Components should be mutually exclusive
        XCTAssertTrue(
            installedSet.isDisjoint(with: missingSet),
            "Component should not be both installed and missing"
        )

        // Should account for all components
        let checkedComponents = installedSet.union(missingSet)
        XCTAssertEqual(
            checkedComponents, allComponents,
            "Should check all required components"
        )

        print("✅ Components installed: \(result.installed.count)")
        print("✅ Components missing: \(result.missing.count)")
    }

    // MARK: - Auto-Fix Action Logic Tests

    func testAutoFixActionsBasedOnRealState() async {
        // When: Detecting current state
        let result = await detector.detectCurrentState()

        // Then: Auto-fix actions should match detected issues
        for action in result.autoFixActions {
            switch action {
            case .terminateConflictingProcesses:
                if case let .conflictsDetected(conflicts) = result.state {
                    XCTAssertFalse(conflicts.isEmpty, "Should only suggest termination if conflicts exist")
                }

            case .installMissingComponents:
                if case let .missingComponents(missing) = result.state {
                    XCTAssertFalse(missing.isEmpty, "Should only suggest installation if components missing")
                }

            case .startKarabinerDaemon:
                XCTAssertEqual(
                    result.state, .serviceNotRunning, "Should only suggest daemon start if not running"
                )

            case .restartVirtualHIDDaemon, .createConfigDirectories:
                // These are always potentially helpful
                break

            case .activateVHIDDeviceManager:
                // Should be suggested when VHIDDevice needs activation
                break

            case .installLaunchDaemonServices:
                // Should be suggested when LaunchDaemon services are missing
                break

            case .installViaBrew:
                // Should be suggested when components can be installed via Homebrew
                break

            case .repairVHIDDaemonServices:
                // Should be suggested when VHID misconfiguration detected
                break

            case .synchronizeConfigPaths:
                // Should be suggested when config paths need synchronization
                break

            case .restartUnhealthyServices:
                // Should be suggested when services are unhealthy
                break

            case .adoptOrphanedProcess:
                // Should be suggested when orphaned processes can be adopted
                break

            case .replaceOrphanedProcess:
                // Should be suggested when orphaned processes need replacement
                break
            }
        }

        print("✅ Suggested auto-fix actions: \(result.autoFixActions)")
    }

    // MARK: - Navigation Logic Integration Tests

    func testNavigationLogicWithRealState() async {
        // When: Detecting state and determining navigation
        let result = await detector.detectCurrentState()
        let navigationEngine = WizardNavigationEngine()
        let currentPage = navigationEngine.determineCurrentPage(
            for: result.state, issues: result.issues
        )

        // Then: Page should match system state appropriately
        switch result.state {
        case .conflictsDetected:
            XCTAssertEqual(currentPage, WizardPage.conflicts, "Should navigate to conflicts page")

        case let .missingPermissions(missing):
            if missing.contains(.keyPathInputMonitoring) || missing.contains(.kanataInputMonitoring) {
                XCTAssertEqual(
                    currentPage, WizardPage.inputMonitoring, "Should prioritize input monitoring"
                )
            } else {
                XCTAssertEqual(
                    currentPage, WizardPage.accessibility, "Should show accessibility if only that missing"
                )
            }

        case .missingComponents:
            XCTAssertEqual(
                currentPage, WizardPage.kanataComponents, "Should navigate to installation page"
            )

        case .serviceNotRunning, .daemonNotRunning:
            XCTAssertEqual(currentPage, WizardPage.service, "Should navigate to daemon page")

        case .ready, .active:
            XCTAssertEqual(currentPage, WizardPage.summary, "Should show summary for final states")

        case .initializing:
            XCTAssertEqual(currentPage, WizardPage.summary, "Should show summary during initialization")
        }

        print("✅ Recommended page for state \(result.state): \(currentPage)")
    }

    // MARK: - Error Condition Tests (Minimal Mocking)

    func testHandlesSystemCommandFailures() async {
        // This test uses real system calls but tests edge cases
        // We can't easily mock system command failures, so we test robustness

        // When: Running detection multiple times rapidly (stress test)
        var results: [SystemStateResult] = []

        await withTaskGroup(of: SystemStateResult.self) { group in
            for _ in 0 ..< 3 {
                group.addTask {
                    await self.detector.detectCurrentState()
                }
            }

            for await result in group {
                results.append(result)
            }
        }

        // Then: Should handle concurrent detection gracefully
        XCTAssertEqual(results.count, 3, "Should complete all concurrent detections")

        // All results should be valid (not stuck in initializing)
        for result in results {
            XCTAssertNotEqual(result.state, .initializing, "Should complete detection")
        }

        print("✅ Concurrent detection completed successfully")
    }

    func testDetectionPerformance() async {
        // When: Measuring detection performance
        let startTime = Date()

        let result = await detector.detectCurrentState()

        let duration = Date().timeIntervalSince(startTime)

        // Then: Should complete detection in reasonable time
        XCTAssertLessThan(duration, 10.0, "Detection should complete within 10 seconds")
        XCTAssertNotEqual(result.state, .initializing, "Should complete detection")

        print("✅ Detection completed in \(String(format: "%.2f", duration)) seconds")
    }

    // MARK: - Integration with Real KanataManager

    func testIntegrationWithRealKanataManager() async {
        // When: Using real KanataManager methods
        let isInstalled = realKanataManager.isInstalled()
        let hasInputMonitoring = realKanataManager.hasInputMonitoringPermission()
        let hasAccessibility = realKanataManager.hasAccessibilityPermission()
        let isDaemonRunning = realKanataManager.isKarabinerDaemonRunning()

        // When: Detecting state
        let result = await detector.detectCurrentState()

        // Then: Detection should be consistent with manager state
        switch result.state {
        case let .missingComponents(missing):
            if missing.contains(.kanataBinary) {
                XCTAssertFalse(isInstalled, "Should detect missing binary correctly")
            }

        case let .missingPermissions(missing):
            if missing.contains(.keyPathInputMonitoring) {
                XCTAssertFalse(hasInputMonitoring, "Should detect missing input monitoring")
            }
            if missing.contains(.keyPathAccessibility) {
                XCTAssertFalse(hasAccessibility, "Should detect missing accessibility")
            }

        case .serviceNotRunning:
            XCTAssertFalse(isDaemonRunning, "Should detect daemon not running")

        default:
            // Other states may have different conditions
            break
        }

        print("✅ Detection consistent with KanataManager state")
        print("   - Binary installed: \(isInstalled)")
        print("   - Input monitoring: \(hasInputMonitoring)")
        print("   - Accessibility: \(hasAccessibility)")
        print("   - Daemon running: \(isDaemonRunning)")
    }

    // MARK: - Path Normalization Tests

    @MainActor
    func testPathNormalization() {
        // Test basic path normalization
        XCTAssertEqual(
            detector.testNormalizedPath("/simple/path"),
            "/simple/path",
            "Simple paths should normalize to themselves"
        )

        // Test paths with .. components
        XCTAssertEqual(
            detector.testNormalizedPath("/path/../other/file"),
            "/other/file",
            "Should resolve .. components"
        )

        // Test paths with . components
        XCTAssertEqual(
            detector.testNormalizedPath("/path/./file"),
            "/path/file",
            "Should resolve . components"
        )

        // Test relative paths
        let currentDir = FileManager.default.currentDirectoryPath
        XCTAssertEqual(
            detector.testNormalizedPath("relative/path"),
            "\(currentDir)/relative/path",
            "Should resolve relative paths to absolute"
        )

        // Test tilde expansion
        let homeDir = NSHomeDirectory()
        XCTAssertEqual(
            detector.testNormalizedPath("~/config/file"),
            "\(homeDir)/config/file",
            "Should expand tilde to home directory"
        )
    }

    @MainActor
    func testCommandLineParsing() {
        // Test simple command without quotes
        let simpleCommand = "/usr/local/bin/kanata --cfg /path/to/config.kbd"
        let simpleResult = detector.testParseCommandLine(simpleCommand)
        XCTAssertEqual(simpleResult, ["/usr/local/bin/kanata", "--cfg", "/path/to/config.kbd"])

        // Test command with quoted path containing spaces
        let quotedCommand = "/usr/local/bin/kanata --cfg \"/path with spaces/config.kbd\""
        let quotedResult = detector.testParseCommandLine(quotedCommand)
        XCTAssertEqual(quotedResult, ["/usr/local/bin/kanata", "--cfg", "/path with spaces/config.kbd"])

        // Test multiple quoted arguments
        let multiQuotedCommand = "\"kanata binary\" --cfg \"/config path/file.kbd\" --port 37000"
        let multiResult = detector.testParseCommandLine(multiQuotedCommand)
        XCTAssertEqual(multiResult, ["kanata binary", "--cfg", "/config path/file.kbd", "--port", "37000"])

        // Test mixed quoted and unquoted
        let mixedCommand = "/bin/kanata --cfg \"/spaced path/file\" --verbose"
        let mixedResult = detector.testParseCommandLine(mixedCommand)
        XCTAssertEqual(mixedResult, ["/bin/kanata", "--cfg", "/spaced path/file", "--verbose"])

        // Test empty string
        let emptyResult = detector.testParseCommandLine("")
        XCTAssertEqual(emptyResult, [])

        // Test string with only spaces
        let spacesResult = detector.testParseCommandLine("   ")
        XCTAssertEqual(spacesResult, [])

        // Test unclosed quotes (should still parse what it can)
        let unclosedCommand = "/bin/kanata --cfg \"/unclosed/quote/path"
        let unclosedResult = detector.testParseCommandLine(unclosedCommand)
        XCTAssertEqual(unclosedResult, ["/bin/kanata", "--cfg", "/unclosed/quote/path"])
    }

    @MainActor
    func testExtractConfigPath() {
        // Test extraction from simple command
        let simpleCommand = "/usr/local/bin/kanata --cfg /path/to/config.kbd"
        let simplePath = detector.testExtractConfigPath(from: simpleCommand)
        XCTAssertEqual(simplePath, "/path/to/config.kbd")

        // Test extraction from quoted path
        let quotedCommand = "/usr/local/bin/kanata --cfg \"/path with spaces/config.kbd\""
        let quotedPath = detector.testExtractConfigPath(from: quotedCommand)
        XCTAssertEqual(quotedPath, "/path with spaces/config.kbd")

        // Test command without --cfg
        let noCfgCommand = "/usr/local/bin/kanata --verbose --port 37000"
        let noCfgPath = detector.testExtractConfigPath(from: noCfgCommand)
        XCTAssertNil(noCfgPath)

        // Test --cfg at end without value
        let incompleteCfgCommand = "/usr/local/bin/kanata --cfg"
        let incompletePath = detector.testExtractConfigPath(from: incompleteCfgCommand)
        XCTAssertNil(incompletePath)

        // Test multiple --cfg (should return first)
        let multipleCfgCommand = "/usr/local/bin/kanata --cfg /first/path --cfg /second/path"
        let multiplePath = detector.testExtractConfigPath(from: multipleCfgCommand)
        XCTAssertEqual(multiplePath, "/first/path")

        // Test KeyPath's expected config path
        let expectedPath = WizardSystemPaths.userConfigPath
        let keyPathCommand = "/usr/local/bin/kanata --cfg \(expectedPath)"
        let extractedPath = detector.testExtractConfigPath(from: keyPathCommand)
        XCTAssertEqual(extractedPath, expectedPath)
    }

    @MainActor
    func testConfigPathNormalizationIntegration() {
        // Test that extraction + normalization work together correctly
        let testCases: [(command: String, expectedNormalized: String)] = [
            (
                "/usr/local/bin/kanata --cfg ~/Library/Application\\ Support/KeyPath/keypath.kbd",
                "\(NSHomeDirectory())/Library/Application Support/KeyPath/keypath.kbd"
            ),
            (
                "/usr/local/bin/kanata --cfg \"~/Library/Application Support/KeyPath/keypath.kbd\"",
                "\(NSHomeDirectory())/Library/Application Support/KeyPath/keypath.kbd"
            ),
            (
                "/usr/local/bin/kanata --cfg /Users/../Users/\(NSUserName())/Library/Application\\ Support/KeyPath/keypath.kbd",
                "\(NSHomeDirectory())/Library/Application Support/KeyPath/keypath.kbd"
            )
        ]

        for (command, expectedNormalized) in testCases {
            if let extractedPath = detector.testExtractConfigPath(from: command) {
                let normalizedPath = detector.testNormalizedPath(extractedPath)
                XCTAssertEqual(
                    normalizedPath, expectedNormalized,
                    "Command '\(command)' should extract and normalize to '\(expectedNormalized)'"
                )
            } else {
                XCTFail("Failed to extract config path from command: \(command)")
            }
        }
    }

    // MARK: - Orphaned Process Detection Logic Tests

    @MainActor
    func testOrphanedProcessDetectionWithMocks() async {
        // Test the orphaned process detection decision matrix using mocks
        let testCases: [(processCount: Int, plistPresent: Bool, serviceLoaded: Bool, expectedAction: AutoFixAction?)] = [
            // No external processes - no action needed
            (0, false, false, nil),
            (0, true, false, nil),
            (0, true, true, nil),

            // Single external process, no plist - adopt or replace based on config
            (1, false, false, .adoptOrphanedProcess), // Will use .adoptOrphanedProcess for expected config

            // Single external process, plist present but not loaded - replace to converge
            (1, true, false, .replaceOrphanedProcess),

            // Single external process, service loaded (unusual) - replace to converge
            (1, true, true, .replaceOrphanedProcess),

            // Multiple external processes - always replace for safety
            (2, false, false, .replaceOrphanedProcess),
            (2, true, false, .replaceOrphanedProcess),
            (2, true, true, .replaceOrphanedProcess)
        ]

        for (index, testCase) in testCases.enumerated() {
            // Create mock processes using expected config path
            let expectedConfigPath = WizardSystemPaths.userConfigPath
            let mockProcesses = (0 ..< testCase.processCount).map { pid in
                ProcessLifecycleManager.ProcessInfo(
                    pid: pid_t(1000 + pid),
                    command: "/usr/local/bin/kanata --cfg \(expectedConfigPath)"
                )
            }

            // Create mock LaunchDaemonInstaller
            let mockInstaller = MockLaunchDaemonInstaller(
                kanataLoaded: testCase.serviceLoaded,
                vhidDaemonLoaded: true,
                vhidManagerLoaded: true
            )

            // Create detector with mocked installer
            let testDetector = SystemStateDetector(
                kanataManager: realKanataManager,
                launchDaemonInstaller: mockInstaller
            )

            // Mock the plist installation status
            let mockPlistPresent = testCase.plistPresent

            // Test using a test helper method (need to add this)
            let result = await testDetector.testComputeOrphanedProcessAutoFixWithMocks(
                externalProcesses: mockProcesses,
                managedProcesses: [],
                plistPresent: mockPlistPresent,
                serviceLoaded: testCase.serviceLoaded
            )

            XCTAssertEqual(
                result, testCase.expectedAction,
                "Test case \(index): processCount=\(testCase.processCount), plistPresent=\(testCase.plistPresent), serviceLoaded=\(testCase.serviceLoaded) should recommend \(String(describing: testCase.expectedAction))"
            )
        }
    }

    @MainActor
    func testOrphanedProcessDetectionWithDifferentConfigPaths() async {
        // Test how config path affects the adoption vs replacement decision
        let expectedPath = WizardSystemPaths.userConfigPath
        let unexpectedPath = "/different/config/path.kbd"

        let testCases: [(configPath: String, expectedAction: AutoFixAction?)] = [
            // Expected config path - safe to adopt
            (expectedPath, .adoptOrphanedProcess),

            // Different config path - replace for safety
            (unexpectedPath, .replaceOrphanedProcess)
        ]

        for (configPath, expectedAction) in testCases {
            let mockProcess = ProcessLifecycleManager.ProcessInfo(
                pid: 1234,
                command: "/usr/local/bin/kanata --cfg \(configPath)"
            )

            let mockInstaller = MockLaunchDaemonInstaller(
                kanataLoaded: false,
                vhidDaemonLoaded: true,
                vhidManagerLoaded: true
            )

            let testDetector = SystemStateDetector(
                kanataManager: realKanataManager,
                launchDaemonInstaller: mockInstaller
            )

            let result = await testDetector.testComputeOrphanedProcessAutoFixWithMocks(
                externalProcesses: [mockProcess],
                managedProcesses: [],
                plistPresent: false,
                serviceLoaded: false
            )

            XCTAssertEqual(
                result, expectedAction,
                "Config path \(configPath) should recommend \(String(describing: expectedAction))"
            )
        }
    }

    @MainActor
    func testOrphanedProcessDetectionWithManagedProcesses() async {
        // Test that presence of managed processes prevents orphaned detection
        let externalProcess = ProcessLifecycleManager.ProcessInfo(
            pid: 1234,
            command: "/usr/local/bin/kanata --cfg \(WizardSystemPaths.userConfigPath)"
        )

        let managedProcess = ProcessLifecycleManager.ProcessInfo(
            pid: 5678,
            command: "/usr/local/bin/kanata --cfg \(WizardSystemPaths.userConfigPath)"
        )

        let mockInstaller = MockLaunchDaemonInstaller(
            kanataLoaded: true,
            vhidDaemonLoaded: true,
            vhidManagerLoaded: true
        )

        let testDetector = SystemStateDetector(
            kanataManager: realKanataManager,
            launchDaemonInstaller: mockInstaller
        )

        // With managed processes present, should not detect orphaned
        let result = await testDetector.testComputeOrphanedProcessAutoFixWithMocks(
            externalProcesses: [externalProcess],
            managedProcesses: [managedProcess],
            plistPresent: true,
            serviceLoaded: true
        )

        XCTAssertNil(result, "Should not detect orphaned process when managed processes exist")
    }

    @MainActor
    func testOrphanedProcessDetectionWithComplexCommandLines() async {
        // Test config path extraction from complex command lines
        let testCases: [(command: String, expectedAction: AutoFixAction?)] = [
            // Quoted path with spaces - matches expected
            ("/usr/local/bin/kanata --cfg \"\(WizardSystemPaths.userConfigPath)\"", .adoptOrphanedProcess),

            // Escaped spaces - matches expected
            ("/usr/local/bin/kanata --cfg \(WizardSystemPaths.userConfigPath.replacingOccurrences(of: " ", with: "\\ "))", .adoptOrphanedProcess),

            // Different path with extra arguments
            ("/usr/local/bin/kanata --cfg /other/path.kbd --verbose --port 37000", .replaceOrphanedProcess),

            // No --cfg parameter
            ("/usr/local/bin/kanata --verbose", .replaceOrphanedProcess)
        ]

        for (command, expectedAction) in testCases {
            let mockProcess = ProcessLifecycleManager.ProcessInfo(
                pid: 1234,
                command: command
            )

            let mockInstaller = MockLaunchDaemonInstaller(
                kanataLoaded: false,
                vhidDaemonLoaded: true,
                vhidManagerLoaded: true
            )

            let testDetector = SystemStateDetector(
                kanataManager: realKanataManager,
                launchDaemonInstaller: mockInstaller
            )

            let result = await testDetector.testComputeOrphanedProcessAutoFixWithMocks(
                externalProcesses: [mockProcess],
                managedProcesses: [],
                plistPresent: false,
                serviceLoaded: false
            )

            XCTAssertEqual(
                result, expectedAction,
                "Command '\(command)' should recommend \(String(describing: expectedAction))"
            )
        }
    }
}
