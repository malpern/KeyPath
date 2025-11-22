# Apple's Recommended Permission UX: Research & Analysis

## Current State: KeyPath's Permission Flow

### Current Approach
1. **Wizard-based upfront request**: User goes through installation wizard
2. **Manual System Settings**: App opens System Settings, user manually adds apps
3. **7-step manual process**: Click '+', navigate, add KeyPath, add kanata, enable checkboxes, restart

### When Permissions Are Requested
- **During setup wizard**: Permissions requested upfront before app is functional
- **Before feature use**: User can't use keyboard remapping until permissions granted
- **Wizard pages**: Dedicated pages for Input Monitoring and Accessibility

---

## Apple's Recommended Approaches

### Option 1: Automatic Permission Prompts (What We Proposed)
**APIs**: `IOHIDRequestAccess()`, `AXIsProcessTrustedWithOptions()`

**How it works**:
- App calls API → System shows permission dialog automatically
- System automatically adds app to permission list
- User clicks "Allow" → Done

**Pros**:
- ✅ Automatic (no manual '+' clicking)
- ✅ Standard macOS flow
- ✅ Matches apps like Homerow
- ✅ Better than current manual approach

**Cons**:
- ⚠️ Still requires user to approve dialog
- ⚠️ May feel intrusive if called at wrong time

**Apple's View**: ✅ **This IS the standard TCC prompt approach** - it's what Apple recommends

---

### Option 2: Just-in-Time Permission Requests (Potentially Better)

**Concept**: Request permissions when the user actually tries to use the feature, not upfront

**How it works**:
1. User tries to use keyboard remapping feature
2. App detects permission missing
3. App shows contextual explanation: "KeyPath needs permission to remap keys"
4. App calls `IOHIDRequestAccess()` or `AXIsProcessTrustedWithOptions()`
5. System shows permission dialog
6. User approves → Feature works immediately

**Pros**:
- ✅ **Better UX**: Permission request is contextual (user understands why)
- ✅ **Less intrusive**: Only asks when needed
- ✅ **Apple's preferred approach**: Request permissions in context
- ✅ **Higher approval rate**: Users more likely to approve when they understand the need

**Cons**:
- ⚠️ Requires detecting when feature is needed
- ⚠️ May interrupt user workflow
- ⚠️ Need fallback for setup scenarios

**Apple's View**: ✅ **This is Apple's preferred approach** - request permissions just-in-time when feature is needed

---

### Option 3: Hybrid Approach (Best of Both Worlds)

**Concept**: Combine wizard setup with just-in-time requests

**How it works**:
1. **Setup wizard**: Explain what permissions are needed and why
2. **Offer to request now**: "Would you like to grant permissions now?"
3. **If user says yes**: Call `IOHIDRequestAccess()` / `AXIsProcessTrustedWithOptions()`
4. **If user says later**: Allow app to continue, request just-in-time when feature used
5. **Just-in-time fallback**: If user tries to use feature without permission, request then

**Pros**:
- ✅ **Flexible**: User can grant now or later
- ✅ **Contextual**: Requests happen when user understands need
- ✅ **Non-blocking**: App can be used even without permissions (with limited functionality)
- ✅ **Best UX**: Matches Apple's recommendations

**Cons**:
- ⚠️ More complex to implement
- ⚠️ Need to handle partial functionality states

---

## Apple's Official Recommendations

### Human Interface Guidelines: Requesting Permissions

**Key Principles**:

1. **Request permissions in context**
   - Don't request all permissions upfront
   - Request when user tries to use the feature
   - Explain why permission is needed

2. **Use system APIs**
   - Use `IOHIDRequestAccess()` for Input Monitoring
   - Use `AXIsProcessTrustedWithOptions()` for Accessibility
   - These automatically show system dialogs

3. **Provide clear explanations**
   - Explain what the permission enables
   - Show benefits to the user
   - Make it clear why permission is needed

4. **Don't block app functionality**
   - Allow app to be used without permissions (with limitations)
   - Request permissions when feature is actually needed
   - Provide graceful degradation

### What Apple Says About Setup Wizards

**From HIG**:
- Setup wizards are OK for initial configuration
- But permissions should still be requested contextually
- Don't force users through permission setup before they can use the app

---

## Comparison: Current vs. Recommended Approaches

### Current Approach (Manual System Settings)
- ❌ User must manually add apps
- ❌ 7-step manual process
- ❌ Error-prone
- ❌ Poor UX

### Automatic Prompts (What We Proposed)
- ✅ Automatic system dialog
- ✅ 1-click approval
- ✅ Standard macOS flow
- ⚠️ Still upfront (during wizard)

### Just-in-Time Requests (Apple's Preferred)
- ✅ ✅ Contextual (user understands why)
- ✅ ✅ Less intrusive
- ✅ ✅ Requested when feature needed
- ✅ ✅ Higher approval rate
- ⚠️ More complex implementation

### Hybrid Approach (Best UX)
- ✅ ✅ ✅ Flexible (now or later)
- ✅ ✅ ✅ Contextual requests
- ✅ ✅ ✅ Non-blocking
- ✅ ✅ ✅ Matches Apple's recommendations
- ⚠️ Most complex to implement

---

## Recommendation: Hybrid Approach

### Why Hybrid is Best

1. **Matches Apple's Guidelines**: Requests permissions contextually
2. **Better UX**: User understands why permission is needed
3. **Flexible**: User can grant now or when needed
4. **Non-blocking**: App can be used without permissions initially
5. **Higher Success Rate**: Users more likely to approve contextual requests

### Implementation Strategy

#### Phase 1: Add Automatic Prompt APIs
- Add `requestInputMonitoringPermission()` using `IOHIDRequestAccess()`
- Add `requestAccessibilityPermission()` using `AXIsProcessTrustedWithOptions()`
- Keep current wizard flow but use automatic prompts

#### Phase 2: Add Just-in-Time Requests
- Detect when keyboard remapping feature is used
- If permission missing, show contextual explanation
- Request permission automatically
- Enable feature immediately after approval

#### Phase 3: Make Wizard Optional
- Allow app to be used without permissions (with limited functionality)
- Show clear indicators of what's disabled
- Request permissions just-in-time when user tries to use feature
- Keep wizard as "complete setup" option

---

## What Needs to Change

### Immediate (Better than Current)
1. ✅ Replace manual System Settings flow with automatic prompts
2. ✅ Use `IOHIDRequestAccess()` and `AXIsProcessTrustedWithOptions()`
3. ✅ Keep wizard but make it use automatic prompts

### Future (Best UX - Apple's Preferred)
1. ✅ Add just-in-time permission requests
2. ✅ Detect when feature is actually needed
3. ✅ Request permissions contextually
4. ✅ Make wizard optional (not blocking)

---

## Conclusion

**Automatic prompts (`IOHIDRequestAccess` / `AXIsProcessTrustedWithOptions`) are Apple's standard approach**, but **just-in-time contextual requests are Apple's preferred UX**.

**Best approach**: 
- Use automatic prompts (better than current manual flow)
- But request them just-in-time when feature is needed (best UX)
- Keep wizard as optional "complete setup" flow

This matches Apple's Human Interface Guidelines and provides the best user experience.

