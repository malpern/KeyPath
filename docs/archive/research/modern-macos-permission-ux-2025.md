# Modern macOS Permission UX: November 2025 Analysis

## KeyPath Context

- **Target macOS**: 15.0 (Sequoia) - Latest macOS
- **Current Approach**: Wizard-based upfront permission requests
- **User Flow**: Must grant permissions before app is functional

---

## Research: How Modern Mac Apps Handle Permissions (2024-2025)

### Key Finding: **Just-in-Time is Still the Standard**

Based on research of modern Mac apps (Raycast, Alfred, Keyboard Maestro, etc.):

1. **Most apps request permissions just-in-time** when features are used
2. **Setup wizards are optional**, not blocking
3. **Automatic prompts** (`IOHIDRequestAccess` / `AXIsProcessTrustedWithOptions`) are standard
4. **Pre-permission dialogs** (explaining why) are common before system prompts

### Modern App Patterns (2024-2025)

#### Pattern 1: Just-in-Time with Pre-Dialog (Most Common)
```
1. User tries to use feature (e.g., keyboard remapping)
2. App shows custom dialog: "KeyPath needs permission to remap keys. This allows..."
3. User clicks "Allow" → System dialog appears automatically
4. User approves → Feature works immediately
```

**Examples**: Raycast, Alfred, Keyboard Maestro

#### Pattern 2: Optional Setup Wizard
```
1. App launches → Can explore UI
2. Optional "Complete Setup" button
3. If clicked → Wizard guides through permissions
4. If skipped → Permissions requested just-in-time
```

**Examples**: Many modern productivity apps

#### Pattern 3: Hybrid (Best UX)
```
1. App launches → Shows "Get Started" screen
2. User can skip or complete setup
3. If skipped → Permissions requested when features used
4. If completed → Permissions requested in wizard (with automatic prompts)
```

**Examples**: Most cutting-edge Mac apps in 2024-2025

---

## macOS 15 (Sequoia) Specific Considerations

### What Changed in macOS 15?

1. **More Frequent Permission Prompts**: Sequoia initially showed prompts more frequently, but Apple reduced this in updates
2. **Better System Integration**: System dialogs are more integrated
3. **Automatic Prompts Still Standard**: `IOHIDRequestAccess()` and `AXIsProcessTrustedWithOptions()` remain the standard APIs

### No New Permission APIs in macOS 15

- **No new APIs** for permission requests in Sequoia
- **Same APIs** as before: `IOHIDRequestAccess()` / `AXIsProcessTrustedWithOptions()`
- **Best practices unchanged**: Just-in-time, contextual requests

---

## Re-Evaluating the Plan

### Current Plan Assessment

**What We Proposed**:
- Use automatic prompts (`IOHIDRequestAccess` / `AXIsProcessTrustedWithOptions`)
- Keep wizard but use automatic prompts instead of manual System Settings

**Is This Still Best?**: ✅ **Yes, but incomplete**

### What's Missing: Just-in-Time Requests

**Current Plan**: ✅ Better than manual System Settings
**Missing**: ❌ Still upfront (during wizard)
**Best Practice**: ✅ Just-in-time when feature is used

---

## Updated Recommendation: Hybrid Approach

### Phase 1: Automatic Prompts (Immediate Improvement)
**Goal**: Replace manual System Settings with automatic prompts

**Changes**:
- Use `IOHIDRequestAccess()` for Input Monitoring
- Use `AXIsProcessTrustedWithOptions()` for Accessibility
- Keep wizard but use automatic prompts

**Result**: ✅ Much better than current (1 click vs 7 steps)

### Phase 2: Just-in-Time Requests (Best UX)
**Goal**: Request permissions when features are actually used

**Changes**:
- Detect when keyboard remapping is attempted
- Show contextual explanation
- Request permission automatically
- Enable feature immediately after approval

**Result**: ✅ ✅ Best UX, matches modern Mac apps

### Phase 3: Make Wizard Optional (Complete Solution)
**Goal**: Don't block app usage, make wizard optional

**Changes**:
- Allow app to launch without permissions
- Show "Complete Setup" option
- Request permissions just-in-time if wizard skipped
- Wizard becomes "quick setup" option, not requirement

**Result**: ✅ ✅ ✅ Matches cutting-edge Mac apps in 2024-2025

---

## Comparison: Current vs. Modern Apps

### KeyPath Current Flow
```
1. Launch app
2. Wizard appears (blocking)
3. Must grant permissions before using app
4. Manual System Settings flow (7 steps)
```

### Modern Mac Apps Flow (2024-2025)
```
1. Launch app
2. Can explore UI immediately
3. Optional "Complete Setup" button
4. When user tries feature → Permission requested automatically
5. System dialog appears → User approves → Feature works
```

### KeyPath with Updated Flow (Recommended)
```
1. Launch app
2. Can explore UI (with indicators showing what's disabled)
3. Optional "Complete Setup" wizard (uses automatic prompts)
4. OR: Try to remap key → Permission requested just-in-time
5. System dialog → User approves → Feature works immediately
```

---

## Implementation Priority

### Immediate (Phase 1): Automatic Prompts
**Why**: Huge improvement over current manual flow
**Effort**: Low-Medium
**Impact**: High (1 click vs 7 steps)

**Do This First**: ✅ Replace manual System Settings with automatic prompts

### Next (Phase 2): Just-in-Time Requests
**Why**: Matches modern Mac apps, better UX
**Effort**: Medium
**Impact**: Very High (contextual, less intrusive)

**Do This Second**: ✅ Add just-in-time permission requests

### Future (Phase 3): Optional Wizard
**Why**: Complete modern UX, non-blocking
**Effort**: Medium-High
**Impact**: Very High (matches cutting-edge apps)

**Do This Third**: ✅ Make wizard optional, allow partial functionality

---

## Conclusion

**For November 2025 macOS 15 (Sequoia)**:

1. ✅ **Automatic prompts are still the standard** - No new APIs, same approach
2. ✅ **Just-in-time requests are preferred** - Matches modern Mac apps
3. ✅ **Hybrid approach is best** - Automatic prompts + just-in-time + optional wizard

**Recommendation**: 
- **Start with Phase 1** (automatic prompts) - Immediate improvement
- **Plan Phase 2** (just-in-time) - Best UX
- **Consider Phase 3** (optional wizard) - Complete modern experience

This matches how cutting-edge Mac apps handle permissions in 2024-2025.

