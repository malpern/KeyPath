# CGEvent Tap Conflict Resolution Plan

## ⚠️ CRITICAL ISSUE: Competing Event Taps Causing Keyboard Freezing

**PROBLEM:** KeyPath currently violates the "one event tapper" rule on macOS, causing keyboard freezing that requires emergency escape sequences.

### Current Conflicting Architecture

```swift
// CURRENT ARCHITECTURE CREATES CONFLICTS:
KeyPath.app (User GUI)     ←→ CGEvent taps for key recording
     ↓ (conflicts with)
kanata daemon (Root)       ←→ CGEvent taps for system remapping
     ↓ (result)
Keyboard freezing requiring emergency escape sequences
```

**Evidence in Codebase:**
- `KeyboardCapture.swift:108-123` - GUI creates event tap for recording
- `KeyboardCapture.swift:243-254` - GUI creates second event tap for emergency stop
- Kanata daemon also creates event taps for remapping
- **Result:** Competing event taps cause keyboard freezing

### Industry Best Practice: Split Architecture

**Karabiner-Elements Pattern (Verified):**
- **GUI (User privileges)**: Handles permissions, configuration, UI, NO event taps
- **Daemon (Root privileges)**: Handles ALL HID access via single event tap system
- **Communication**: IPC between GUI and daemon for coordination

### Recommended Solution Architecture

```
[User Session]                    [System (Root)]
┌─────────────────┐              ┌──────────────────┐
│ KeyPath.app     │◄─────TCP────►│ kanata daemon    │
│ - Permission    │              │ - ONLY event     │
│   checks (✓)    │              │   tapper         │
│ - TCC prompts   │              │ - Recording mode │
│ - User guidance │              │   via TCP        │
│ - Config UI     │              │ - Emergency stop │
│ - NO event taps │              │   handling       │
└─────────────────┘              └──────────────────┘
```

## Implementation Plan

### Phase 1: Extend Kanata TCP API
**Required TCP Commands:**
```json
// Start recording mode (temporary exclusive access)
{"command": "start_recording_mode", "timeout_ms": 5000}
→ {"status": "recording", "mode": "single_key"}

// Get recorded key
{"command": "get_recorded_key"}
→ {"key": "caps", "timestamp": 1234567890}

// Stop recording mode
{"command": "stop_recording_mode"}
→ {"status": "normal_operation"}

// Emergency stop (already exists)
{"command": "emergency_stop"}
→ {"status": "stopped"}
```

### Phase 2: Replace KeyboardCapture.swift
**Current GUI Event Taps to Remove:**
1. `setupEventTap()` - Lines 105-133 in KeyboardCapture.swift
2. `setupEmergencyEventTap()` - Lines 240-264 in KeyboardCapture.swift

**New TCP-Based Implementation:**
```swift
class KeyboardCaptureViaTCP: ObservableObject {
    private let kanataClient = KanataTCPClient.shared
    
    func startCapture(callback: @escaping (String) -> Void) async {
        // No event tap - use TCP instead
        let response = await kanataClient.startRecordingMode()
        if response.status == "recording" {
            let key = await kanataClient.getRecordedKey()
            callback(key.name)
        }
    }
    
    func startEmergencyMonitoring(callback: @escaping () -> Void) {
        // Emergency stop handled by daemon, not GUI
        // GUI just listens for emergency notifications via TCP
    }
}
```

### Phase 3: Update ContentView Integration
**Files to Modify:**
- `Sources/KeyPath/UI/ContentView.swift` - Replace KeyboardCapture usage
- Remove all `@StateObject private var keyboardCapture = KeyboardCapture()`
- Replace with TCP-based key recording

### Phase 4: Testing & Validation
**Test Scenarios:**
1. **Single Key Recording**: Verify TCP recording works without GUI event taps
2. **Emergency Stop**: Confirm emergency sequence works via daemon only
3. **No Keyboard Freezing**: Extended testing to ensure no competing taps
4. **Permission Requirements**: Only kanata needs Input Monitoring, not GUI

## Benefits After Implementation

- ✅ **Eliminates keyboard freezing** from competing event taps
- ✅ **Follows proven architecture** - matches Karabiner-Elements pattern  
- ✅ **Simplified permissions** - only kanata needs Input Monitoring
- ✅ **GUI becomes pure UI** with no system-level conflicts
- ✅ **Better reliability** - single event tap source eliminates race conditions

## CGEvent Tap Anti-Patterns to Avoid

### ❌ NEVER DO THIS - Multiple event taps in same application
```swift
class KeyboardCapture {
    func startCapture() {
        eventTap = CGEvent.tapCreate(...)  // GUI tap for recording
    }
    func startEmergencyMonitoring() {
        emergencyEventTap = CGEvent.tapCreate(...)  // Second GUI tap
    }
}
// While kanata daemon also creates event taps - CAUSES KEYBOARD FREEZING
```

### ❌ NEVER DO THIS - GUI application creating system-level event taps
```swift
func recordKeyInGUI() -> Bool {
    let eventTap = CGEvent.tapCreate(.cgSessionEventTap, ...)
    // Competes with daemon event taps, violates macOS event handling rules
}
```

### ❌ NEVER DO THIS - Ignore event tap conflicts
```swift
func setupKeyCapture() {
    // Just hope the event taps don't interfere - they will!
    createEventTap()
}
```

### ✅ CORRECT - Only daemon creates event taps, GUI uses IPC
```swift
func recordKeyViaDaemon() async -> String {
    let response = await kanataClient.startRecordingMode()
    return response.recordedKey
}
```

## Risk Assessment

**Risk Level:** 🟡 Medium
- **Impact:** Core functionality change affecting key recording
- **Complexity:** Requires kanata TCP API extension and GUI refactoring  
- **Mitigation:** Emergency workarounds exist (Ctrl+Space+Esc)
- **Testing:** Extensive testing required for keyboard functionality

## Implementation Timeline

**Phase 1** (TCP API): 2-3 days - Extend kanata with recording commands
**Phase 2** (GUI Refactor): 1-2 days - Replace KeyboardCapture.swift  
**Phase 3** (Integration): 1 day - Update ContentView and related components
**Phase 4** (Testing): 2-3 days - Comprehensive keyboard functionality testing

**Total Estimated Time:** 6-9 days

## Success Criteria

- [ ] GUI creates zero CGEvent taps
- [ ] All key recording happens via TCP to kanata
- [ ] Emergency stop works via daemon monitoring
- [ ] No keyboard freezing during extended use
- [ ] Only kanata process needs Input Monitoring permission
- [ ] All existing keyboard recording functionality preserved

---

**Priority:** Medium - Core functionality improvement with manageable implementation complexity

**Recommendation:** Implement during a maintenance cycle when keyboard functionality testing can be thorough.