#!/usr/bin/env swift

import Foundation

print("🔍 Checking for immediate debug files...")

let home = NSHomeDirectory()
let fixButtonFile = home + "/fix-button-debug.txt"
let actualFixButtonFile = home + "/actual-fix-button-debug.txt"
let realFixButtonFile = home + "/real-fix-button-debug.txt"
let restartServicesFile = home + "/restart-services-debug.txt"
let kanataFixButtonFile = home + "/kanata-fix-button-debug.txt"

print("🏠 Home directory: \(home)")

// Check Fix Button Debug File
print("\n📄 Fix Button Debug File: \(fixButtonFile)")
if FileManager.default.fileExists(atPath: fixButtonFile) {
    print("✅ EXISTS")
    do {
        let content = try String(contentsOfFile: fixButtonFile)
        print("📝 Content:")
        print(content)
    } catch {
        print("❌ Error reading: \(error)")
    }
} else {
    print("❌ NOT FOUND")
}

// Check ACTUAL Fix Button Debug File
print("\n📄 ACTUAL Fix Button Debug File: \(actualFixButtonFile)")
if FileManager.default.fileExists(atPath: actualFixButtonFile) {
    print("✅ EXISTS")
    do {
        let content = try String(contentsOfFile: actualFixButtonFile, encoding: .utf8)
        print("📝 Content:")
        print(content)
    } catch {
        print("❌ Error reading: \(error)")
    }
} else {
    print("❌ NOT FOUND")
}

// Check REAL Fix Button Debug File
print("\n📄 REAL Fix Button Debug File: \(realFixButtonFile)")
if FileManager.default.fileExists(atPath: realFixButtonFile) {
    print("✅ EXISTS")
    do {
        let content = try String(contentsOfFile: realFixButtonFile, encoding: .utf8)
        print("📝 Content:")
        print(content)
    } catch {
        print("❌ Error reading: \(error)")
    }
} else {
    print("❌ NOT FOUND")
}

// Check Restart Services Debug File
print("\n📄 Restart Services Debug File: \(restartServicesFile)")
if FileManager.default.fileExists(atPath: restartServicesFile) {
    print("✅ EXISTS")
    do {
        let content = try String(contentsOfFile: restartServicesFile)
        print("📝 Content:")
        print(content)
    } catch {
        print("❌ Error reading: \(error)")
    }
} else {
    print("❌ NOT FOUND")
}

// Check Kanata Fix Button Debug File
print("\n📄 Kanata Fix Button Debug File: \(kanataFixButtonFile)")
if FileManager.default.fileExists(atPath: kanataFixButtonFile) {
    print("✅ EXISTS")
    do {
        let content = try String(contentsOfFile: kanataFixButtonFile, encoding: .utf8)
        print("📝 Content:")
        print(content)
    } catch {
        print("❌ Error reading: \(error)")
    }
} else {
    print("❌ NOT FOUND")
}

print("\n💡 If these files don't exist after clicking Fix button:")
print("1. The Fix button click is not reaching our method")
print("2. There's a UI binding issue")
print("3. The method is crashing before our first line")

print("\n✅ Check complete")
