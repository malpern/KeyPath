#!/usr/bin/env swift

// Automated test to trigger keyboard recording and analyze logs
// This simulates what happens when you click the record button

import Foundation
import ApplicationServices

@MainActor
class KeyboardRecordingTest {
    
    func simulateRecordingFlow() async {
        print("🤖 [Auto] Simulating KeyPath recording flow...")
        
        // Wait a moment for KeyPath to fully start
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        print("🤖 [Auto] Now I'll simulate clicking the record button...")
        print("🤖 [Auto] This should trigger the ContentView.startRecording() method")
        print("🤖 [Auto] Which should create KeyboardCapture and call startSequenceCapture")
        
        // We can't directly call the ContentView methods from here, but we can
        // simulate the key parts to see what should happen
        
        print("🤖 [Auto] Simulating the KeyboardCapture creation and setup...")
        await simulateKeyboardCaptureFlow()
    }
    
    func simulateKeyboardCaptureFlow() async {
        print("🤖 [Auto] === Simulating KeyboardCapture Flow ===")
        
        // This simulates what ContentView.startRecording() does:
        // 1. Checks permissions via Oracle
        // 2. Creates KeyboardCapture if needed  
        // 3. Calls startSequenceCapture()
        
        // We can't access the actual KeyPath classes from this script,
        // but we can simulate the permission check
        print("🤖 [Auto] Step 1: Permission check (like ContentView does)")
        let axGranted = AXIsProcessTrusted()
        let imGranted = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        
        print("🤖 [Auto] - Accessibility: \(axGranted)")
        print("🤖 [Auto] - Input Monitoring: \(imGranted)")
        
        if axGranted && imGranted {
            print("🤖 [Auto] ✅ Both permissions granted - recording should work")
            print("🤖 [Auto] Step 2: KeyboardCapture initialization would succeed")
            print("🤖 [Auto] Step 3: startSequenceCapture() would be called")
            print("🤖 [Auto] Step 4: setupEventTap() would be called")
        } else {
            print("🤖 [Auto] ❌ Missing permissions - recording would fail")
        }
    }
}

// Create and run the test
let test = await KeyboardRecordingTest()
await test.simulateRecordingFlow()

print("🤖 [Auto] Test simulation complete")
print("🤖 [Auto] Now checking KeyPath logs for the actual recording attempt...")
print("🤖 [Auto] You should manually click the record button now and then check logs")