# Key Recording – Phase 1 (Listen-Only) Specification

Status: Draft for implementation  
Owners: KanataManager/KeyboardCapture/ContentView  
Related ADR: ADR-006 (CGEvent Tap Conflict Resolution)

## Purpose
Enable recording while Kanata is running by observing the effective (mapped) keystrokes via a session-level listen-only CGEvent tap, without introducing a second intercepting tap.

## Scope
- In-scope: KeyboardCapture, ContentView hints, logging, tests.  
- Out-of-scope: Daemon “Training Mode” streaming API (Phase 2), protocol changes.

## User Experience
- When Kanata is running: recording works and label shows “Recording mode: Effective (mapped)”.
- When Kanata is not running: recording works as today (Raw capture), label shows “Recording mode: Raw (direct)”.
- Timeouts and permission messages remain as-is; no modal dialogs.

## Behavior Matrix
- Kanata running = true → KeyboardCapture installs `.listenOnly` tap; captures mapped output; does NOT suppress events.  
- Kanata running = false → KeyboardCapture installs `.defaultTap`; suppresses events during capture; returns raw/chord/sequence per current logic.

## Technical Design
- KeyboardCapture.setupEventTap():
  - Remove early-exit that blocks setup when `kanataManager.isRunning == true`.
  - Choose `options: .listenOnly` when running; else `options: .defaultTap`.
  - Keep `place: .headInsertEventTap`, `tap: .cgSessionEventTap`.
- Event processing: in listen-only mode, call `handleKeyEvent(event)` directly; do not return `nil` to suppress.
- UI: add a lightweight mode string in the input/output display helper (e.g., prefix small gray caption “Effective (mapped)” / “Raw (direct)”). Non-blocking, optional if space is tight.
- Logging: AppLogger messages on start of capture indicating chosen mode and reason.

## Edge Cases & Risks
- Macros/sequences expand into multiple events → expected; display the expanded result.
- Pass-through mappings appear identical to raw → acceptable; we label the mode.
- Duplicates from injected events should not occur at session-level; monitor logs; add test.
- Accessibility permission still required; unchanged.

## Testing
- Unit: small tests for mode selection (given isRunning true/false → chosen tap option).
- UI snapshots: verify mode hint visibility toggles.
- Manual: 
  1) With Kanata running, record a mapped key: expect effective output text.  
  2) With Kanata stopped, record the same key: expect raw capture text.  
  3) Macro mapping: verify sequence expansion shows.
- Logs: verify entries like “🎹 [KeyboardCapture] Starting capture (mode=effective, listenOnly)” / “(mode=raw, defaultTap)”.

## Success Criteria
- Recording works in both states without quitting the service.  
- No keyboard freeze or missed input during listen-only capture.  
- Clear user messaging of the active mode.

## Rollback Plan
- Reinstate the previous early-exit guard (block capture when running) via feature flag `CAPTURE_LISTEN_ONLY_ENABLED=false` (guard at setupEventTap).

## Follow-on (Phase 2 – Training Mode)
- Authenticated daemon API to stream both raw and effective events for N keystrokes; GUI subscribes and renders with provenance.

