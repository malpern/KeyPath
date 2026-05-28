import Foundation
@testable import KeyPathAppKit
import Testing

// MARK: - First-Time Install Detection

@Suite("InstallationCoordinator — First-Time Install Detection")
@MainActor
struct InstallationCoordinatorFirstTimeInstallTests {
    @Test("isFirstTimeInstall returns true for nonexistent config path")
    func isFirstTimeInstallReturnsTrueForNonexistentConfig() {
        let coordinator = InstallationCoordinator()
        let fakePath = "/tmp/keypath-test-\(UUID().uuidString)/nonexistent.kbd"
        #expect(coordinator.isFirstTimeInstall(configPath: fakePath) == true)
    }

    @Test("isFirstTimeInstall returns true when binary missing even if config exists")
    func isFirstTimeInstallReturnsTrueWhenBinaryMissingEvenIfConfigExists() throws {
        let coordinator = InstallationCoordinator()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("keypath-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let configFile = tempDir.appendingPathComponent("keypath.kbd")
        try ";; test config".write(to: configFile, atomically: true, encoding: .utf8)

        // In the swift test environment the kanata binary is not in an app bundle,
        // so KanataBinaryDetector reports it as missing. Even though the config
        // file exists, the missing binary makes this a first-time install.
        let result = coordinator.isFirstTimeInstall(configPath: configFile.path)
        #expect(result == true)
    }
}

// MARK: - StepResult Struct

@Suite("InstallationCoordinator — StepResult")
@MainActor
struct InstallationCoordinatorStepResultTests {
    @Test("StepResult stores all properties correctly")
    func stepResultStoresAllProperties() {
        let result = InstallationCoordinator.StepResult(
            stepNumber: 3,
            totalSteps: 7,
            success: true,
            warning: false
        )
        #expect(result.stepNumber == 3)
        #expect(result.totalSteps == 7)
        #expect(result.success == true)
        #expect(result.warning == false)
    }
}

// MARK: - Config File Check

@Suite("InstallationCoordinator — Config File Check")
@MainActor
struct InstallationCoordinatorConfigFileTests {
    @Test("checkConfigFile succeeds when file exists")
    func checkConfigFileSucceedsWhenFileExists() throws {
        let coordinator = InstallationCoordinator()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("keypath-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let configFile = tempDir.appendingPathComponent("keypath.kbd")
        try ";; test config".write(to: configFile, atomically: true, encoding: .utf8)

        let result = coordinator.checkConfigFile(configPath: configFile.path)
        #expect(result.success == true)
        #expect(result.warning == false)
    }

    @Test("checkConfigFile fails when file missing")
    func checkConfigFileFailsWhenFileMissing() {
        let coordinator = InstallationCoordinator()
        let fakePath = "/tmp/keypath-test-\(UUID().uuidString)/nonexistent.kbd"

        let result = coordinator.checkConfigFile(configPath: fakePath)
        #expect(result.success == false)
        #expect(result.warning == false)
    }

    @Test("checkConfigFile respects custom step numbers")
    func checkConfigFileRespectsCustomStepNumbers() {
        let coordinator = InstallationCoordinator()
        let fakePath = "/tmp/keypath-test-\(UUID().uuidString)/nonexistent.kbd"

        let result = coordinator.checkConfigFile(
            configPath: fakePath,
            stepNumber: 7,
            totalSteps: 10
        )
        #expect(result.stepNumber == 7)
        #expect(result.totalSteps == 10)
    }
}

// MARK: - Installation Result Logging

@Suite("InstallationCoordinator — Installation Result Logging")
@MainActor
struct InstallationCoordinatorLogResultTests {
    @Test("logInstallationResult returns true when 4 or more steps completed")
    func logInstallationResultTrueWhenFourCompleted() {
        let coordinator = InstallationCoordinator()
        let success = coordinator.logInstallationResult(
            stepsCompleted: 4, stepsFailed: 1, totalSteps: 5
        )
        #expect(success == true)
    }

    @Test("logInstallationResult returns true when all 5 steps completed")
    func logInstallationResultTrueWhenAllCompleted() {
        let coordinator = InstallationCoordinator()
        let success = coordinator.logInstallationResult(
            stepsCompleted: 5, stepsFailed: 0, totalSteps: 5
        )
        #expect(success == true)
    }

    @Test("logInstallationResult returns false when fewer than 4 steps completed")
    func logInstallationResultFalseWhenFewerThanFour() {
        let coordinator = InstallationCoordinator()
        let success = coordinator.logInstallationResult(
            stepsCompleted: 3, stepsFailed: 2, totalSteps: 5
        )
        #expect(success == false)
    }

    @Test("logInstallationResult returns false when 0 steps completed")
    func logInstallationResultFalseWhenZeroCompleted() {
        let coordinator = InstallationCoordinator()
        let success = coordinator.logInstallationResult(
            stepsCompleted: 0, stepsFailed: 5, totalSteps: 5
        )
        #expect(success == false)
    }
}

// MARK: - Karabiner Driver Check

@Suite("InstallationCoordinator — Karabiner Driver Check")
@MainActor
struct InstallationCoordinatorKarabinerDriverTests {
    @Test("checkKarabinerDriver returns success")
    func checkKarabinerDriverReturnsSuccess() {
        let coordinator = InstallationCoordinator()
        let result = coordinator.checkKarabinerDriver()
        // Always returns success (even if driver missing, it returns success with warning)
        #expect(result.success == true)
    }

    @Test("checkKarabinerDriver uses correct step number")
    func checkKarabinerDriverUsesCorrectStepNumber() {
        let coordinator = InstallationCoordinator()
        let result = coordinator.checkKarabinerDriver()
        #expect(result.stepNumber == 2)
        #expect(result.totalSteps == 5)
    }
}
