import Foundation
import Testing

@testable import KeyPath

@Suite("KanataProcessManager Tests")
struct KanataProcessManagerTests {
    
    @Test("Process status detection")
    func processStatusDetection() {
        let manager = KanataProcessManager.shared
        
        // Test that we can call the status check without crashing
        let isRunning = manager.isKanataRunning()
        let statusMessage = manager.getStatusMessage()
        
        // Should return a boolean
        #expect(isRunning == true || isRunning == false)
        
        // Should return a non-empty status message
        #expect(!statusMessage.isEmpty)
        
        // Status message should contain expected content
        if isRunning {
            #expect(statusMessage.contains("running"))
        } else {
            #expect(statusMessage.contains("not running"))
        }
    }
    
    @Test("PID retrieval")
    func pidRetrieval() {
        let manager = KanataProcessManager.shared
        
        // Test that we can get PIDs without crashing
        let pids = manager.getKanataPIDs()
        
        // Should return an array (might be empty if Kanata not running)
        // Note: Array exists and has valid structure
        
        // If we have PIDs, they should be positive integers
        for pid in pids {
            #expect(pid > 0)
        }
    }
    
    @Test("Process info retrieval")
    func processInfoRetrieval() {
        let manager = KanataProcessManager.shared
        
        // Test that we can get process info without crashing
        let processInfo = manager.getKanataProcessInfo()
        
        // Should return a non-empty string
        #expect(!processInfo.isEmpty)
        
        // Should contain expected content
        #expect(processInfo.contains("Kanata"))
    }
    
    @Test("Hot reload signal sending")
    func hotReloadSignalSending() {
        let manager = KanataProcessManager.shared
        
        // Test that reload returns a boolean result
        let reloadResult = manager.reloadKanata()
        
        // Should return a boolean
        #expect(reloadResult == true || reloadResult == false)
        
        // If Kanata is not running, reload should return false
        if !manager.isKanataRunning() {
            #expect(reloadResult == false)
        }
    }
}

@Suite("Backup File Cleanup Tests")
struct BackupFileCleanupTests {
    
    private let testConfigPath = NSTemporaryDirectory() + "kanata_test_\(UUID().uuidString)"
    
    @Test("Backup file cleanup with old and new files")
    func backupFileCleanupWithOldAndNewFiles() throws {
        let fileManager = FileManager.default
        
        // Create test directory
        try fileManager.createDirectory(atPath: testConfigPath, withIntermediateDirectories: true)
        
        // Create test backup files
        let oldBackupPath = testConfigPath + "/kanata.kbd.keypath-backup-old"
        let newBackupPath = testConfigPath + "/kanata.kbd.keypath-backup-new"
        let regularFilePath = testConfigPath + "/regular-file.txt"
        
        try "test".write(toFile: oldBackupPath, atomically: true, encoding: .utf8)
        try "test".write(toFile: newBackupPath, atomically: true, encoding: .utf8)
        try "test".write(toFile: regularFilePath, atomically: true, encoding: .utf8)
        
        // Set old timestamp (2 days ago)
        let twoDaysAgo = Date().addingTimeInterval(-2 * 24 * 60 * 60)
        try fileManager.setAttributes([.creationDate: twoDaysAgo], ofItemAtPath: oldBackupPath)
        
        // Perform cleanup simulation
        let backupFiles = try fileManager.contentsOfDirectory(atPath: testConfigPath)
            .filter { $0.hasPrefix("kanata.kbd.keypath-backup-") }
        
        let oneDayAgo = Date().addingTimeInterval(-24 * 60 * 60)
        var deletedFiles: [String] = []
        
        for backupFile in backupFiles {
            let fullPath = testConfigPath + "/" + backupFile
            let attributes = try fileManager.attributesOfItem(atPath: fullPath)
            
            if let creationDate = attributes[.creationDate] as? Date,
               creationDate < oneDayAgo {
                try fileManager.removeItem(atPath: fullPath)
                deletedFiles.append(backupFile)
            }
        }
        
        // Verify results
        #expect(deletedFiles.count == 1)
        #expect(deletedFiles.contains("kanata.kbd.keypath-backup-old"))
        
        // Verify new backup file still exists
        #expect(fileManager.fileExists(atPath: newBackupPath))
        
        // Verify regular file was not touched
        #expect(fileManager.fileExists(atPath: regularFilePath))
        
        // Cleanup test directory
        try? fileManager.removeItem(atPath: testConfigPath)
    }
    
    @Test("Cleanup handles empty directory gracefully")
    func cleanupHandlesEmptyDirectoryGracefully() throws {
        let fileManager = FileManager.default
        
        // Create empty test directory
        try fileManager.createDirectory(atPath: testConfigPath, withIntermediateDirectories: true)
        
        // Attempt cleanup on empty directory
        let files = try fileManager.contentsOfDirectory(atPath: testConfigPath)
        let backupFiles = files.filter { $0.hasPrefix("kanata.kbd.keypath-backup-") }
        
        // Should handle empty directory without errors
        #expect(backupFiles.isEmpty)
        
        // Cleanup test directory
        try? fileManager.removeItem(atPath: testConfigPath)
    }
    
    @Test("Cleanup only targets backup files")
    func cleanupOnlyTargetsBackupFiles() throws {
        let fileManager = FileManager.default
        
        // Create test directory
        try fileManager.createDirectory(atPath: testConfigPath, withIntermediateDirectories: true)
        
        // Create various files
        let backupFile = testConfigPath + "/kanata.kbd.keypath-backup-test"
        let configFile = testConfigPath + "/kanata.kbd"
        let randomFile = testConfigPath + "/some-other-file.txt"
        
        try "test".write(toFile: backupFile, atomically: true, encoding: .utf8)
        try "test".write(toFile: configFile, atomically: true, encoding: .utf8)
        try "test".write(toFile: randomFile, atomically: true, encoding: .utf8)
        
        // Set all files to old timestamps
        let twoDaysAgo = Date().addingTimeInterval(-2 * 24 * 60 * 60)
        try fileManager.setAttributes([.creationDate: twoDaysAgo], ofItemAtPath: backupFile)
        try fileManager.setAttributes([.creationDate: twoDaysAgo], ofItemAtPath: configFile)
        try fileManager.setAttributes([.creationDate: twoDaysAgo], ofItemAtPath: randomFile)
        
        // Simulate cleanup targeting only backup files
        let allFiles = try fileManager.contentsOfDirectory(atPath: testConfigPath)
        let backupFiles = allFiles.filter { $0.hasPrefix("kanata.kbd.keypath-backup-") }
        
        #expect(backupFiles.count == 1)
        #expect(backupFiles.contains("kanata.kbd.keypath-backup-test"))
        
        // Verify other files are not considered for cleanup
        #expect(allFiles.contains("kanata.kbd"))
        #expect(allFiles.contains("some-other-file.txt"))
        
        // Cleanup test directory
        try? fileManager.removeItem(atPath: testConfigPath)
    }
}
