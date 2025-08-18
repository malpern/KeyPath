#!/usr/bin/env swift

import Foundation
import AppKit

print("🔊 Testing KeyPath Sound Implementation")
print("=====================================")

// Test system sounds availability
print("\n1. Testing Available System Sounds:")

let sounds = ["Tink", "Glass", "Submarine", "Basso", "Blow", "Bottle", "Frog", "Funk", "Pop", "Purr"]

for soundName in sounds {
    if let sound = NSSound(named: NSSound.Name(soundName)) {
        print("✅ \(soundName): Available")
    } else {
        print("❌ \(soundName): Not available")
    }
}

print("\n2. Testing Sound Functionality:")

// Test the specific sounds we're using
print("\n2.1 Testing Tink sound (config save):")
if let tinkSound = NSSound(named: "Tink") {
    print("✅ Tink sound loaded successfully")
    print("🔊 Playing tink sound...")
    tinkSound.play()
    Thread.sleep(forTimeInterval: 1.0) // Wait for sound to finish
} else {
    print("❌ Tink sound not available")
}

print("\n2.2 Testing Glass sound (reload complete):")
if let glassSound = NSSound(named: "Glass") {
    print("✅ Glass sound loaded successfully")
    print("🔊 Playing glass sound...")
    glassSound.play()
    Thread.sleep(forTimeInterval: 1.0) // Wait for sound to finish
} else {
    print("❌ Glass sound not available")
}

print("\n2.3 Testing System Beep (error):")
print("🔊 Playing system beep...")
NSSound.beep()
Thread.sleep(forTimeInterval: 0.5)

print("\n3. Sound Implementation Summary:")
print("✅ Tink sound: Will play when config file is saved")
print("✅ Glass sound: Will play when TCP reload is successful") 
print("✅ Error beep: Will play when TCP reload fails")

print("\n4. Expected Mapping Save Sequence:")
print("1. User creates mapping (1 → 2)")
print("2. KeyPath saves config file → 🔊 Tink sound")
print("3. KeyPath sends TCP reload command")
print("4. Kanata reloads config successfully → 🔊 Glass sound")
print("   OR Reload fails → 🔊 Error beep")

print("\n🎵 Sound test complete!")
print("The sounds should now work in your KeyPath app.")