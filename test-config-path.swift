#!/usr/bin/env swift

import Foundation

// Test the exact path that WizardSystemPaths.userConfigPath returns
print("🔍 Testing WizardSystemPaths.userConfigPath...")

// Simulate the logic from WizardSystemPaths
let homeDir = NSHomeDirectory()
let expectedPath = "\(homeDir)/.config/keypath/keypath.kbd"

print("Home directory: \(homeDir)")
print("Expected config path: \(expectedPath)")
print("Config file exists: \(FileManager.default.fileExists(atPath: expectedPath))")

// Check the directory structure
let configDir = "\(homeDir)/.config/keypath"
print("Config directory exists: \(FileManager.default.fileExists(atPath: configDir))")

// List directory contents if it exists
if FileManager.default.fileExists(atPath: configDir) {
    do {
        let contents = try FileManager.default.contentsOfDirectory(atPath: configDir)
        print("Config directory contents: \(contents)")
    } catch {
        print("Error reading config directory: \(error)")
    }
}

// Try to read the file content
if FileManager.default.fileExists(atPath: expectedPath) {
    do {
        let content = try String(contentsOfFile: expectedPath, encoding: .utf8)
        print("Config file size: \(content.count) characters")
        print("First 100 characters: \(String(content.prefix(100)))")
    } catch {
        print("Error reading config file: \(error)")
    }
}

// Also test legacy path to confirm it's not there
let legacyPath = "/usr/local/etc/kanata/keypath.kbd"
print("Legacy config exists: \(FileManager.default.fileExists(atPath: legacyPath))")
