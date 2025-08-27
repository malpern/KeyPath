# Input Monitoring Auto-Addition Fix

## Problem
KeyPath was automatically re-adding itself to Input Monitoring preferences whenever the user turned it off, creating an annoying loop where the permission couldn't be disabled.

## Root Cause
The `PermissionService.checkTCCForInputMonitoring()` method was calling `IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)` to check permission status. However, this API call has a side effect - it can trigger macOS to automatically add the app to Input Monitoring preferences, even when just checking status.

This was being called continuously by:
1. The Installation Wizard's `SystemStatusChecker` (every 2-10 seconds based on adaptive polling)
2. Any permission status checks in the app

## Solution

### 1. Disabled Automatic Permission Checks
**File**: `Sources/KeyPath/Services/PermissionService.swift`

Changed `checkTCCForInputMonitoring()` to:
- **NO LONGER** calls `IOHIDCheckAccess` for status checks
- Returns `false` by default to prevent triggering re-addition
- Added clear warning comments about the issue

```swift
static func checkTCCForInputMonitoring(path: String) -> Bool {
    // IMPORTANT: We do NOT use IOHIDCheckAccess here because it can trigger
    // automatic re-addition to Input Monitoring preferences when the permission
    // is turned off. This creates an annoying loop where the user can't disable
    // the permission.
    
    if path == currentProcessPath {
        // DO NOT call IOHIDCheckAccess here - it triggers re-addition!
        return false
    }
    // ...
}
```

### 2. Added Explicit Permission Request Method
Added `requestInputMonitoringPermission()` with warnings:
- Should ONLY be called on explicit user action (button click)
- Never called automatically or in loops
- Clearly documented the re-addition behavior

### 3. Keyboard Capture Already Safe
`KeyboardCapture.swift` already handles this correctly:
- Checks for permissions without requesting them
- Shows warning if permissions missing
- Triggers wizard to help user, but doesn't auto-request

## Impact
- Users can now disable Input Monitoring permission without it being re-added
- Permission is only requested when user explicitly wants it (e.g., clicking "Grant Permission" button)
- The wizard will show permissions as "not granted" but won't trigger re-addition

## Testing
1. Remove KeyPath from System Settings > Privacy & Security > Input Monitoring
2. Open KeyPath - it should NOT automatically re-appear in the list
3. The wizard should show Input Monitoring as missing
4. Only when clicking "Grant Permission" should it be added

## Note
The app may show Input Monitoring as "not granted" even if it is, to avoid checking and triggering re-addition. The actual permission status is determined when features are used.