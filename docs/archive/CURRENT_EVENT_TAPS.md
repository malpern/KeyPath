# KeyPath CGEvent Tap Analysis

**Created:** August 26, 2025  
**Purpose:** Validate EventTag compatibility for architectural refactoring  
**Status:** Analysis Complete ✅

## Summary

KeyPath uses CGEvent taps **only in KeyboardCapture service** for user input recording, not for system-wide key remapping. The EventTag system proposed in PLAN.md is **fully compatible** with the current implementation.

## Current CGEvent Tap Usage

### KeyboardCapture Service
**Location:** `Sources/KeyPath/Services/KeyboardCapture.swift`  
**Purpose:** Record user keystrokes for creating key mappings  
**Type:** Session-level tap for UI input capture  

#### Tap Configuration
```swift
// Primary event tap for key capture
eventTap = CGEvent.tapCreate(
    tap: .cgSessionEventTap,          // Session-level, not system-wide
    place: .headInsertEventTap,       // Early in event pipeline
    options: .defaultTap,             // Standard tap options
    eventsOfInterest: CGEventMask(eventMask), // Only keyDown events
    callback: { _, _, event, refcon -> Unmanaged<CGEvent>? in
        // Process key event for mapping creation
        // Returns nil to suppress event (capture mode)
    },
    userInfo: Unmanaged.passUnretained(self).toOpaque()
)

// Emergency stop sequence detection
emergencyEventTap = CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .headInsertEventTap, 
    options: .defaultTap,
    eventsOfInterest: CGEventMask(keyUp | keyDown), // Both up/down for sequence
    callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
        // Detect Ctrl+Space+Esc emergency stop
        // Returns Unmanaged.passRetained(event) to pass through
    },
    userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
)
```

#### Key Characteristics
- **Session-level taps only** - not system-wide remapping
- **Temporary usage** - only active during key mapping creation
- **Event suppression** - primary tap returns `nil` to consume events
- **Pass-through emergency tap** - returns event unmodified
- **No field modification** - does not read or write CGEvent fields

## EventTag Compatibility Analysis

### ✅ CGEventField.eventSourceUserData Availability
- **Current usage:** No existing code reads or writes `eventSourceUserData`
- **Field availability:** 32-bit field available in all CGEvent instances
- **Namespace collision risk:** None - field is completely unused
- **Compatibility:** 100% safe to use for EventTag system

### ✅ Tap Architecture Compatibility
- **Multiple taps supported:** KeyboardCapture already uses 2 concurrent taps
- **TapSupervisor design:** Non-owning registry is fully compatible
- **Event loop integration:** Existing CFRunLoop integration patterns can be preserved
- **No tap consolidation needed:** Aligns with CLAUDE.md constraint to avoid tap conflicts

### ✅ Event Processing Patterns
- **Event modification:** Current code only suppresses or passes through events
- **Field access:** No existing CGEventField usage to conflict with
- **Processing chains:** Simple callback pattern easily adaptable to EventRouter
- **Performance impact:** EventTag operations are O(1) field access - minimal overhead

## Proposed EventTag Integration

### Safe Integration Points

1. **KeyboardCapture Tap Callbacks**
   ```swift
   callback: { _, _, event, refcon -> Unmanaged<CGEvent>? in
       // Add EventTag.tag(event, processorId: .keyboardCapture, phase: .input)
       guard let refcon else { return Unmanaged.passRetained(event) }
       
       let capture = Unmanaged<KeyboardCapture>.fromOpaque(refcon).takeUnretainedValue()
       capture.handleKeyEvent(event)
       
       return nil // Suppress event as before
   }
   ```

2. **Emergency Tap Integration**
   ```swift
   callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
       // Check if already tagged by KeyboardCapture to avoid processing loops
       if EventTag.isTaggedBySelf(event) {
           return Unmanaged.passRetained(event) // Pass through tagged events
       }
       
       // Tag for emergency processing
       EventTag.tag(event, processorId: .emergencyStop, phase: .input)
       
       let capture = Unmanaged<KeyboardCapture>.fromOpaque(refcon).takeUnretainedValue()
       capture.handleEmergencyEvent(event: event, type: type)
       
       return Unmanaged.passRetained(event) // Pass through as before
   }
   ```

3. **Future KanataManager Taps**
   - When system-wide remapping taps are added (future milestone)
   - EventTag system prevents processing loops between capture and remapping
   - Clear separation between UI capture and system remapping

## Remapping Architecture (Kanata Integration)

### Current System
KeyPath uses **Kanata as external subprocess** for system-wide key remapping:
- **Kanata process** handles CGEvent taps for remapping
- **KeyPath app** manages Kanata lifecycle and configuration
- **No direct remapping taps** in KeyPath itself currently

### Future Integration (Post-Refactoring)
When KanataManager gains direct event processing capabilities:
- **MappingEngine service** can use EventTag system
- **Multiple tap coordination** via TapSupervisor
- **Event loop prevention** via EventTag namespace checking
- **Clear separation** between capture (UI) and remapping (system) taps

## Testing Implications

### EventTag Testing Strategy
1. **Field persistence:** Verify tagged events maintain tags through processing
2. **Namespace isolation:** Confirm KeyPath namespace (0x4B50) doesn't conflict
3. **Performance impact:** Measure O(1) overhead of field access operations
4. **Loop prevention:** Test that tagged events are correctly identified and handled

### Integration Testing
1. **Keyboard capture still works** with EventTag calls added
2. **Emergency stop still functions** with tag checking
3. **No event dropping** due to tag processing overhead
4. **Clean tag removal** when events leave KeyPath processing

## Recommendations

### ✅ Immediate Actions (Milestone 3)
1. **Implement EventTag system** - zero compatibility risk
2. **Add TapSupervisor registration** to existing KeyboardCapture taps
3. **Test tag/untag cycles** for performance impact
4. **Document field usage** to prevent future conflicts

### ✅ Future Considerations
1. **Reserve tag namespace** for KeyPath (0x4B50 = 'KP')
2. **Define processor IDs** for different tap purposes:
   - `0x01` - KeyboardCapture primary tap
   - `0x02` - Emergency stop tap  
   - `0x03` - Future mapping tap
   - `0x04` - Future system monitoring
3. **Phase tracking** for event lifecycle debugging
4. **Cross-process coordination** if needed for Kanata integration

## Conclusion

The EventTag system is **fully compatible** with KeyPath's current CGEvent tap usage. Implementation can proceed with confidence in Milestone 3 of the architectural refactoring plan.

**Key Benefits:**
- No breaking changes to existing tap behavior
- Clean foundation for future tap coordination
- Loop prevention for complex event processing
- Performance overhead is minimal (single field access)
- Full compatibility with multi-manager architecture

**Zero Risk Assessment:** ✅ Safe to implement as planned