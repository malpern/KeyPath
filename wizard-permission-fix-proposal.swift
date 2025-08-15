// WIZARD PERMISSION FIX PROPOSAL
// Add to PermissionService.swift

extension PermissionService {

    /// Enhanced system permission check with functional verification
    /// Combines TCC database checks with actual device access testing
    func checkSystemPermissionsWithVerification(kanataBinaryPath: String) -> SystemPermissionStatus {
        // Step 1: Standard TCC database checks (existing logic)
        let basicStatus = checkSystemPermissions(kanataBinaryPath: kanataBinaryPath)

        // Step 2: Functional verification for Kanata
        let kanataFunctionalStatus = verifyKanataFunctionalPermissions(
            binaryPath: kanataBinaryPath,
            tccStatus: basicStatus.kanata
        )

        return SystemPermissionStatus(
            keyPath: basicStatus.keyPath,
            kanata: kanataFunctionalStatus
        )
    }

    /// Verify that Kanata can actually access keyboard devices
    /// This catches cases where TCC shows permissions but functionality is broken
    private func verifyKanataFunctionalPermissions(
        binaryPath: String,
        tccStatus: BinaryPermissionStatus
    ) -> BinaryPermissionStatus {

        // Start with TCC status
        var verifiedInputMonitoring = tccStatus.hasInputMonitoring
        var verifiedAccessibility = tccStatus.hasAccessibility

        // Method 1: Check Kanata service logs for permission errors
        if verifiedInputMonitoring {
            verifiedInputMonitoring = !hasRecentPermissionErrors()
        }

        // Method 2: Test device enumeration capability
        if verifiedInputMonitoring {
            verifiedInputMonitoring = canEnumerateKeyboardDevices(binaryPath: binaryPath)
        }

        // Method 3: Check if TCP server can report device access
        if verifiedInputMonitoring {
            verifiedInputMonitoring = tcpServerReportsDeviceAccess()
        }

        AppLogger.shared.log(
            "🔍 [PermissionService] Functional verification - " +
            "TCC(\(tccStatus.hasInputMonitoring)) -> Verified(\(verifiedInputMonitoring))"
        )

        return BinaryPermissionStatus(
            binaryPath: binaryPath,
            hasInputMonitoring: verifiedInputMonitoring,
            hasAccessibility: verifiedAccessibility
        )
    }

    /// Check Kanata logs for recent permission-related errors
    private func hasRecentPermissionErrors() -> Bool {
        let logPath = "/var/log/kanata.log"

        do {
            let logContent = try String(contentsOfFile: logPath)
            let lines = logContent.components(separatedBy: .newlines)

            // Check last 50 lines for permission errors
            let recentLines = lines.suffix(50)

            let permissionErrorPatterns = [
                "IOHIDDeviceOpen error.*not permitted",
                "failed to open keyboard device",
                "Couldn't register any device",
                "permission denied",
                "access denied"
            ]

            for line in recentLines {
                for pattern in permissionErrorPatterns {
                    if line.range(of: pattern, options: .regularExpression) != nil {
                        AppLogger.shared.log("🚨 [PermissionService] Found permission error: \(line)")
                        return true
                    }
                }
            }

        } catch {
            AppLogger.shared.log("⚠️ [PermissionService] Could not read Kanata log: \(error)")
            // If we can't read the log, assume permissions might be problematic
            return true
        }

        return false
    }

    /// Test if Kanata can enumerate keyboard devices
    private func canEnumerateKeyboardDevices(binaryPath: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = ["--list"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            // Check if output contains actual devices (not just error messages)
            let hasValidDevices = output.contains("Available keyboard devices") &&
                                !output.contains("not permitted") &&
                                !output.contains("failed to open")

            AppLogger.shared.log("🔍 [PermissionService] Device enumeration test: \(hasValidDevices)")
            return hasValidDevices

        } catch {
            AppLogger.shared.log("⚠️ [PermissionService] Device enumeration failed: \(error)")
            return false
        }
    }

    /// Check if TCP server reports successful device access
    private func tcpServerReportsDeviceAccess() -> Bool {
        // Only test if TCP server is available
        guard isKanataTCPServerRunning() else {
            return true // Can't test via TCP, assume OK
        }

        do {
            let tcpClient = KanataTCPClient(port: PreferencesService.shared.tcpServerPort)

            // Request layer info - if Kanata can't access devices, this often fails
            let response = await tcpClient.requestLayerInfo()

            // If we get a valid response with layer info, device access is likely working
            let hasValidResponse = response != nil &&
                                 !response!.contains("error") &&
                                 !response!.contains("failed")

            AppLogger.shared.log("🔍 [PermissionService] TCP server device test: \(hasValidResponse)")
            return hasValidResponse

        } catch {
            AppLogger.shared.log("⚠️ [PermissionService] TCP server test failed: \(error)")
            return false
        }
    }

    /// Check if Kanata TCP server is running
    private func isKanataTCPServerRunning() -> Bool {
        // Implementation to check if TCP port is listening
        // Could use netstat or direct socket connection
        return true // Simplified for proposal
    }
}

// USAGE IN WIZARD:
// Replace calls to checkSystemPermissions() with checkSystemPermissionsWithVerification()
// in SystemStateDetector, ComponentDetector, and SystemStatusChecker
