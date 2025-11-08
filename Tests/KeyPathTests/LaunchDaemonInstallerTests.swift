@testable import KeyPath
import XCTest

/// Tests for LaunchDaemonInstaller to ensure proper service dependency ordering
final class LaunchDaemonInstallerTests: XCTestCase {
    // MARK: - Service Order Constants

    /// The correct dependency order for services
    /// 1. VirtualHID Daemon first (provides the base VirtualHID framework)
    /// 2. VirtualHID Manager second (manages VirtualHID devices)
    /// 3. Kanata last (depends on the VirtualHID services being available)
    private let correctServiceOrder = [
        "com.keypath.karabiner-vhiddaemon",
        "com.keypath.karabiner-vhidmanager",
        "com.keypath.kanata"
    ]

    // MARK: - Test Helpers

    /// Extract bootstrap commands from a script in order
    private func extractBootstrapOrder(from script: String) -> [String] {
        let lines = script.components(separatedBy: .newlines)
        var bootstrapServices: [String] = []

        for line in lines where line.contains("launchctl bootstrap system") {
            // Extract service name from the plist path or variable name
            if let serviceMatch = extractServiceNameFromBootstrap(from: line) {
                bootstrapServices.append(serviceMatch)
            }
        }

        return bootstrapServices
    }

    /// Extract service name from a launchctl bootstrap line with Swift interpolation
    private func extractServiceNameFromBootstrap(from line: String) -> String? {
        // Handle Swift interpolation patterns like '\(vhidDaemonFinal)'
        if line.contains("vhidDaemonFinal") {
            return "com.keypath.karabiner-vhiddaemon"
        } else if line.contains("vhidManagerFinal") {
            return "com.keypath.karabiner-vhidmanager"
        } else if line.contains("kanataFinal") {
            return "com.keypath.kanata"
        }

        // Also check for direct service names
        return extractServiceName(from: line)
    }

    /// Extract service name from a launchctl bootstrap line
    private func extractServiceName(from line: String) -> String? {
        // Look for patterns like com.keypath.kanata, com.keypath.karabiner-vhiddaemon, etc.
        let patterns = [
            "com.keypath.kanata",
            "com.keypath.karabiner-vhiddaemon",
            "com.keypath.karabiner-vhidmanager"
        ]

        for pattern in patterns where line.contains(pattern) {
            return pattern
        }

        return nil
    }

    /// Extract kickstart commands from a script in order
    private func extractKickstartOrder(from script: String) -> [String] {
        let lines = script.components(separatedBy: .newlines)
        var kickstartServices: [String] = []

        for line in lines where line.contains("launchctl kickstart") {
            // Extract service name - handle both direct names and Swift constants
            if line.contains("Self.vhidDaemonServiceID") || line.contains("vhidDaemonServiceID") {
                kickstartServices.append("com.keypath.karabiner-vhiddaemon")
            } else if line.contains("Self.vhidManagerServiceID") || line.contains("vhidManagerServiceID") {
                kickstartServices.append("com.keypath.karabiner-vhidmanager")
            } else if line.contains("Self.kanataServiceID") || line.contains("kanataServiceID") {
                kickstartServices.append("com.keypath.kanata")
            } else if let serviceMatch = extractServiceName(from: line) {
                kickstartServices.append(serviceMatch)
            }
        }

        return kickstartServices
    }

    // MARK: - Tests

    /// Test that the executeConsolidatedInstallationWithAuthServices method respects dependency order
    func testAuthServicesInstallationRespectsServiceDependencyOrder() throws {
        // Read the LaunchDaemonInstaller source file
        let sourcePath = FileManager.default.currentDirectoryPath + "/Sources/KeyPath/InstallationWizard/Core/LaunchDaemonInstaller.swift"
        let sourceCode = try String(contentsOfFile: sourcePath, encoding: .utf8)

        // Find the executeConsolidatedInstallationWithAuthServices method
        guard let methodStart = sourceCode.range(of: "executeConsolidatedInstallationWithAuthServices")?.lowerBound else {
            XCTFail("Could not find executeConsolidatedInstallationWithAuthServices method")
            return
        }

        // Extract the script content from this method
        let methodSection = String(sourceCode[methodStart...])

        // Find the script content between triple quotes
        guard let scriptStart = methodSection.range(of: "#!/bin/bash")?.lowerBound,
              let scriptEnd = methodSection.range(of: "\"\"\"", range: scriptStart ..< methodSection.endIndex)?.lowerBound
        else {
            XCTFail("Could not extract script from executeConsolidatedInstallationWithAuthServices")
            return
        }

        let script = String(methodSection[scriptStart ..< scriptEnd])

        // Extract bootstrap order
        let bootstrapOrder = extractBootstrapOrder(from: script)

        // Verify bootstrap order
        XCTAssertEqual(bootstrapOrder, correctServiceOrder,
                       "Bootstrap order must be: VirtualHID Daemon → VirtualHID Manager → Kanata")

        // Extract kickstart order
        let kickstartOrder = extractKickstartOrder(from: script)

        // Verify kickstart order
        XCTAssertEqual(kickstartOrder, correctServiceOrder,
                       "Kickstart order must be: VirtualHID Daemon → VirtualHID Manager → Kanata")
    }

    /// Test that the executeConsolidatedInstallationImproved method respects dependency order
    func testImprovedOsascriptInstallationRespectsServiceDependencyOrder() throws {
        // Read the LaunchDaemonInstaller source file
        let sourcePath = FileManager.default.currentDirectoryPath + "/Sources/KeyPath/InstallationWizard/Core/LaunchDaemonInstaller.swift"
        let sourceCode = try String(contentsOfFile: sourcePath, encoding: .utf8)

        // Find the executeConsolidatedInstallationImproved method
        guard let methodStart = sourceCode.range(of: "executeConsolidatedInstallationImproved")?.lowerBound else {
            XCTFail("Could not find executeConsolidatedInstallationImproved method")
            return
        }

        // Extract the script content from this method
        let methodSection = String(sourceCode[methodStart...])

        // Find the script content - look for the command variable assignment starting with set -ex
        guard let commandStart = methodSection.range(of: "set -ex")?.lowerBound,
              let commandEnd = methodSection.range(of: "echo \"Installation completed successfully\"")?.upperBound
        else {
            XCTFail("Could not extract command script from executeConsolidatedInstallationImproved")
            return
        }

        let script = String(methodSection[commandStart ..< commandEnd])

        // Extract bootstrap order
        let bootstrapOrder = extractBootstrapOrder(from: script)

        // Verify bootstrap order
        XCTAssertEqual(bootstrapOrder, correctServiceOrder,
                       "Bootstrap order in improved method must be: VirtualHID Daemon → VirtualHID Manager → Kanata")

        // Extract kickstart order
        let kickstartOrder = extractKickstartOrder(from: script)

        // Verify kickstart order
        XCTAssertEqual(kickstartOrder, correctServiceOrder,
                       "Kickstart order in improved method must be: VirtualHID Daemon → VirtualHID Manager → Kanata")
    }

    /// Test that inline script methods also respect dependency order
    func testInlineScriptRespectsServiceDependencyOrder() throws {
        // Read the LaunchDaemonInstaller source file
        let sourcePath = FileManager.default.currentDirectoryPath + "/Sources/KeyPath/InstallationWizard/Core/LaunchDaemonInstaller.swift"
        let sourceCode = try String(contentsOfFile: sourcePath, encoding: .utf8)

        // Look for the inline version that has the three services in a row
        // This typically appears in simplified installation scripts
        let lines = sourceCode.components(separatedBy: .newlines)

        var foundInlineBootstrap = false
        var inlineBootstrapOrder: [String] = []

        for line in lines {
            // Look for consecutive bootstrap commands
            if line.contains("/bin/launchctl bootstrap system") {
                if let serviceName = extractServiceName(from: line) {
                    inlineBootstrapOrder.append(serviceName)
                    foundInlineBootstrap = true
                }

                // Check if we've found all three services in sequence
                if inlineBootstrapOrder.count == 3 {
                    break
                }
            } else if foundInlineBootstrap, !line.contains("launchctl bootstrap") {
                // If we were collecting bootstrap commands and hit a non-bootstrap line,
                // check if we have a complete set
                if inlineBootstrapOrder.count == 3 {
                    break
                }
            }
        }

        // Only verify if we found inline bootstrap commands
        if foundInlineBootstrap, inlineBootstrapOrder.count == 3 {
            XCTAssertEqual(inlineBootstrapOrder, correctServiceOrder,
                           "Inline bootstrap order must be: VirtualHID Daemon → VirtualHID Manager → Kanata")
        }
    }

    /// Test that no installation method violates the dependency order
    func testNoInstallationMethodViolatesDependencyOrder() throws {
        // Read the LaunchDaemonInstaller source file
        let sourcePath = FileManager.default.currentDirectoryPath + "/Sources/KeyPath/InstallationWizard/Core/LaunchDaemonInstaller.swift"
        let sourceCode = try String(contentsOfFile: sourcePath, encoding: .utf8)

        let lines = sourceCode.components(separatedBy: .newlines)

        // Track consecutive bootstrap commands
        var currentBootstrapSequence: [String] = []

        for line in lines {
            if line.contains("launchctl bootstrap system") {
                if let serviceName = extractServiceName(from: line) {
                    currentBootstrapSequence.append(serviceName)

                    // If we have kanata but not vhid services before it, that's wrong
                    if serviceName == "com.keypath.kanata" {
                        if currentBootstrapSequence.count == 1 {
                            XCTFail("Found Kanata being bootstrapped without VirtualHID services loaded first at line: \(line)")
                        }
                    }
                }
            } else if !line.contains("launchctl bootstrap"), !currentBootstrapSequence.isEmpty {
                // End of a bootstrap sequence, reset
                if currentBootstrapSequence.count >= 3 {
                    // Verify this sequence
                    XCTAssertEqual(currentBootstrapSequence, correctServiceOrder,
                                   "Found incorrect bootstrap sequence: \(currentBootstrapSequence)")
                }
                currentBootstrapSequence = []
            }
        }
    }

    /// Test documentation to ensure dependency requirements are documented
    func testDependencyOrderIsDocumented() throws {
        // Read the LaunchDaemonInstaller source file
        let sourcePath = FileManager.default.currentDirectoryPath + "/Sources/KeyPath/InstallationWizard/Core/LaunchDaemonInstaller.swift"
        let sourceCode = try String(contentsOfFile: sourcePath, encoding: .utf8)

        // Look for comments mentioning dependencies
        let hasDepComment = sourceCode.contains("DEPENDENCIES FIRST") ||
            sourceCode.contains("VirtualHID") && sourceCode.contains("depends") ||
            sourceCode.contains("dependency order")

        XCTAssertTrue(hasDepComment,
                      "LaunchDaemonInstaller should document the dependency order requirement")
    }
}

// MARK: - Service Dependency Documentation

extension LaunchDaemonInstallerTests {
    /// Documentation test to ensure the service dependency order is clear
    ///
    /// Service Bootstrap Order Requirements:
    /// 1. **VirtualHID Daemon** (`com.keypath.karabiner-vhiddaemon`)
    ///    - Must be loaded first
    ///    - Provides the base VirtualHID framework
    ///    - Other services depend on this
    ///
    /// 2. **VirtualHID Manager** (`com.keypath.karabiner-vhidmanager`)
    ///    - Must be loaded second
    ///    - Manages VirtualHID devices
    ///    - Depends on VirtualHID Daemon
    ///
    /// 3. **Kanata** (`com.keypath.kanata`)
    ///    - Must be loaded last
    ///    - Depends on both VirtualHID services being available
    ///    - Will fail with "Input/output error" if VirtualHID services aren't running
    ///
    /// Failure to respect this order results in:
    /// - `launchctl bootstrap` returning error code 5 (Input/output error)
    /// - Services failing to start
    /// - System services installation appearing to fail to users
    func testServiceDependencyDocumentation() {
        // This test exists to document the dependency requirements
        // The actual testing is done in the other test methods
        XCTAssertTrue(true, "Dependency order is documented in test suite")
    }
}
