# Drag-to-Authorize Permission Overlay

**Status:** Planning — no implementation started  
**Created:** 2026-05-17  
**Branch:** TBD (will create feature branch when implementation begins)

## Goal

Replace the current Finder-reveal permission flow with a floating overlay panel that lets users drag `kanata-launcher` directly into System Settings' privacy lists. Inspired by [Permiso](https://github.com/zats/permiso) and OpenAI Codex Desktop's approach.

## Problem

The current flow (`WizardPermissionFinderHelper.revealKanataLauncher()`) is fragile and confusing:

1. Opens System Settings to the correct privacy pane
2. Reveals `kanata-launcher` in Finder with siblings hidden via `chflags hidden`
3. Positions Settings and Finder side-by-side
4. User must locate the file in Finder, then drag it into Settings

Issues:
- Users don't understand they need to drag from Finder to Settings
- `chflags hidden` leaves files hidden if the app crashes before cleanup
- `positionSettingsAndFinderSideBySide()` can't actually resize Settings (it only repositions windows the app owns — Settings is a separate process)
- The Finder window often opens in column view, burying the file

## Proposed Solution

A floating `NSPanel` positioned directly below the Settings window, containing a clearly-labeled draggable icon of `kanata-launcher` with an animated arrow pointing up toward the privacy list.

### Key Design Decisions

1. **NSPanel, not NSWindow** — non-activating so dragging doesn't steal focus from Settings
2. **Track Settings window position** — poll `CGWindowListCopyWindowInfo` to keep the panel anchored below Settings even if the user moves it
3. **NSDraggingSource with `.fileURL`** — standard file drag pasteboard type that Settings accepts
4. **Permission polling** — use `PermissionOracle.forceRefresh()` to detect when the drop succeeds

### Proposed File Structure

```
Sources/KeyPathInstallationWizard/UI/Helpers/DragToAuthorize/
  DragToAuthorizeController.swift      — State machine, lifecycle, permission polling
  DragToAuthorizePanel.swift           — NSPanel (non-activating, borderless, floating)
  DragToAuthorizeOverlayView.swift     — SwiftUI content with glass material + animations
  DragToAuthorizeStateModel.swift      — @Observable model driving animation transitions
  DragToAuthorizeDragSource.swift      — NSView providing NSDraggingSource with .fileURL
  SettingsWindowTracker.swift          — CGWindowList polling with lerp interpolation
```

### State Machine

```
idle → presenting → visible → dragging → success → dismissing → idle
                            ↘ retrying ↗
```

### How It Would Work

1. User clicks "Add in Settings" on the wizard permission page
2. `DragToAuthorizeController.shared.present(for: .accessibility)` is called
3. Controller opens System Settings via deep-link URL
4. After brief delay, creates floating `DragToAuthorizePanel`
5. `SettingsWindowTracker` polls `CGWindowListCopyWindowInfo` to find and track Settings window
6. Panel anchors below Settings, horizontally centered, with lerp-smoothed tracking
7. User drags `kanata-launcher` icon from overlay into the Settings privacy list
8. Controller polls `PermissionOracle.forceRefresh()` to detect grant
9. On success: checkmark animation → auto-dismiss

### Animation Specs

| Animation | Spec |
|-----------|------|
| Present (from source rect) | Spring response: 0.5, damping: 0.75. Scale 0.3→1.0, opacity 0→1 |
| Present (no source) | Fade + slide up 20pt over 0.35s ease-out |
| Arrow pulse | scaleEffect 1.0↔1.15, easeInOut 1.2s, repeating |
| Drag lift | Scale 1.0→1.03, shadow 4→12, spring response: 0.2 |
| Success | Checkmark with .bounce symbolEffect, green circle bg |
| Retry shake | Offset x: [-8, 8, -4, 4, 0] over 0.3s |
| Dismiss | Opacity 1→0, offset y: 0→+20, easeIn 0.25s |
| Window tracking | Lerp factor 0.3 per 150ms tick |

### Integration Points

- **WizardAccessibilityPage** — replace `revealKanataLauncher()` + `openAccessibilitySettings()` with controller call
- **WizardInputMonitoringPage** — same pattern
- **onDisappear** — dismiss overlay when navigating away
- **AdvancedSettingsTabView** — `#if DEBUG` test buttons for manual validation

### Deep-Link URLs (already defined in `KeyPathConstants.swift`)

- Accessibility: `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`
- Input Monitoring: `x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent`
- Full Disk Access: `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles`

## Risk: Bare Binary Drag Acceptance

**Status: UNVALIDATED — requires manual test before implementation**

System Settings privacy lists accept `.fileURL` drops. Permiso proves this works for `.app` bundles. The open question is whether it works for bare Mach-O executables like `kanata-launcher`.

**Evidence supporting it will work:**
- TCC database registers kanata-launcher by full path (not bundle ID)
- kanata-launcher is properly code-signed with team ID X2RKZ5TG99
- The pasteboard type (`.fileURL`) is format-agnostic — it's just a URL

**How to validate (do this FIRST before building anything):**
1. Create a minimal test app with an `NSDraggingSource` that puts `kanata-launcher`'s path on the pasteboard as `.fileURL`
2. Open System Settings → Privacy & Security → Accessibility
3. Try to drag from the test app into the privacy list
4. If it works → proceed with full implementation
5. If it doesn't → fall back to dragging `KeyPath.app` bundle instead

**Fallback if bare binary doesn't work:**
- Drag `KeyPath.app` instead (definitely works per Permiso)
- KeyPath.app in the Accessibility list may still cover kanata-launcher if it's a child process (needs verification)

## Current Implementation (to be replaced)

`WizardPermissionFinderHelper` at:
```
Sources/KeyPathInstallationWizard/UI/Helpers/WizardPermissionFinderHelper.swift
```

Called from:
- `WizardAccessibilityPage.swift:449` — `WizardPermissionFinderHelper.revealKanataLauncher()`
- `WizardInputMonitoringPage.swift:465` — `WizardPermissionFinderHelper.revealKanataLauncher()`

## Implementation Order

1. **Validate bare binary drag** — build minimal test, confirm it works
2. **SettingsWindowTracker** — CGWindowList polling, tested standalone
3. **DragToAuthorizeDragSource** — NSView + NSDraggingSource, confirm pasteboard works
4. **DragToAuthorizePanel** — NSPanel shell, positioning logic
5. **DragToAuthorizeOverlayView** — SwiftUI content, animations
6. **DragToAuthorizeStateModel** — @Observable state machine
7. **DragToAuthorizeController** — orchestrator, Oracle polling, lifecycle
8. **Integration** — wire into wizard pages, remove old Finder helper calls
9. **Edge cases** — Settings closed mid-drag, space switching, multiple displays
10. **Cleanup** — remove `WizardPermissionFinderHelper` if no longer needed

## Research: Why Not Use Permiso Directly

Evaluated [zats/permiso](https://github.com/zats/permiso) and decided to implement natively:
- No license file (legally unusable)
- macOS 26 minimum (KeyPath targets macOS 15+)
- Only supports Accessibility + Screen Recording (missing Input Monitoring)
- Single-day proof of concept (8 commits, April 17 2026)
- No permission detection (we already have PermissionOracle)
- We need tighter integration with our wizard flow and state machine
