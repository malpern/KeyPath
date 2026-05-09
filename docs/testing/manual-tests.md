# KeyPath Manual Test Cases

*Last updated: 2026-05-07*

Manual tests for flows that require the real app running, real key events, real permissions, or visual verification that snapshots can't capture (animation, timing, cross-window behavior).

Each test has: **preconditions**, **steps**, **expected result**, and **what breaks if it fails**.

Run these after any change to the overlay, mapper, gallery, or config generation pipeline.

---

## How to Use This Document

- Tests are grouped by feature area and ordered by priority within each group.
- **P0** = must pass before any release. **P1** = should pass. **P2** = nice to have.
- Mark pass/fail inline when executing. Use `[x]` for pass, `[ ]` for fail with a note.
- For AI-assisted runs (Peekaboo, computer-use), the "Verify" step describes what to look for in screenshots.

---

## 1. Gallery — Pack Install/Uninstall Lifecycle

### G-01: Install Caps Lock Remapper (P0)
- **Pre:** App running, no packs installed, overlay visible
- **Steps:**
  1. Open Gallery (Cmd+G or menu)
  2. Click "Caps Lock Remap" pack card
  3. In detail view, verify tap picker shows options (Escape, Backspace, etc.)
  4. Verify hold picker shows options (Hyper, Control, etc.)
  5. Click Install
- **Verify:**
  - Toast confirms installation
  - Overlay caps lock key shows the tap idle label (e.g., "⎋" for Escape)
  - Config file updated (check `~/.config/keypath/keypath.kbd` contains `caps`)
- **Breaks:** Overlay shows stale labels, config not regenerated, tap-hold idle labels missing

### G-02: Change Caps Lock Tap Selection After Install (P0)
- **Pre:** Caps Lock Remapper installed with Escape tap
- **Steps:**
  1. Open Gallery, click Caps Lock Remapper
  2. Change tap picker from Escape to Backspace
  3. Close detail view
- **Verify:**
  - Overlay caps lock idle label changes from "⎋" to "⌫"
  - Config file updated with new tap output
- **Breaks:** Picker selection doesn't persist, overlay doesn't refresh

### G-03: Uninstall Pack (P0)
- **Pre:** Caps Lock Remapper installed
- **Steps:**
  1. Open Gallery, click Caps Lock Remapper
  2. Click Uninstall
- **Verify:**
  - Toast confirms removal
  - Overlay caps lock key reverts to "⇪" (no idle label)
  - Config file no longer contains caps lock tap-hold
- **Breaks:** Labels stuck, config stale, pack still shown as installed

### G-04: Install Home Row Mods (P1)
- **Pre:** No HRM installed
- **Steps:**
  1. Open Gallery, click Home Row Mods
  2. Verify timing slider appears (default ~200ms)
  3. Adjust slider to 250ms
  4. Click Install
- **Verify:**
  - Overlay shows modifier symbols on A/S/D/F and J/K/L/; keys when idle
  - Hold A for 250ms+ → overlay shows Shift symbol
  - Tap A quickly → types "a" normally
- **Breaks:** HRM timing wrong, idle labels missing, hold detection incorrect

### G-05: Install Vim Navigation (P1)
- **Pre:** No vim nav installed
- **Steps:**
  1. Install Vim Navigation pack
  2. Activate nav layer (hold activator key)
- **Verify:**
  - Overlay switches to nav layer
  - H/J/K/L keys show ←/↓/↑/→ arrows
  - Pressing H sends Left arrow
- **Breaks:** Layer not created, labels wrong, key output incorrect

### G-06: Install Pack with Conflict (P1)
- **Pre:** Caps Lock Remapper installed
- **Steps:**
  1. Install another pack that uses caps lock (e.g., Backup Caps Lock)
- **Verify:**
  - Conflict dialog appears
  - Choosing "Keep new" replaces old mapping
  - Choosing "Keep existing" cancels install
- **Breaks:** Silent overwrite without dialog, or both mappings active (config error)

### G-07: Install Symbol Layer with Preset Picker (P1)
- **Pre:** No symbol layer installed
- **Steps:**
  1. Open Gallery, click Symbol Layer
  2. Verify layer preset picker shows options
  3. Select a preset
  4. Install
- **Verify:**
  - Overlay shows symbol layer when activated
  - Correct preset's symbols appear on keys
- **Breaks:** Wrong preset applied, layer not activatable

### G-08: Install Quick Launcher (P1)
- **Pre:** No launcher installed
- **Steps:**
  1. Install Quick Launcher pack
  2. Open launcher drawer in inspector
  3. Add a mapping: S → Safari
  4. Activate launcher mode (hold Hyper)
- **Verify:**
  - S key shows Safari icon on overlay
  - Pressing S launches Safari
  - Releasing Hyper returns to base layer
- **Breaks:** Icons not loaded, launch action fails, layer stuck

### G-09: KindaVim Visual-Only Pack (P2)
- **Pre:** None
- **Steps:**
  1. Install KindaVim pack
- **Verify:**
  - No config changes (visual-only)
  - No install button shows kanata side effects
  - Mode display appears when KindaVim is running (if installed)
- **Breaks:** Visual-only pack modifies config

### G-10: Leader Key Pack with Picker (P1)
- **Pre:** None
- **Steps:**
  1. Install Leader Key pack
  2. Change leader key from Space to Caps Lock via picker
- **Verify:**
  - Leader key activates on selected key
  - Config reflects chosen leader key
- **Breaks:** Wrong key used as leader, picker selection not persisted

---

## 2. Mapper — Key Remapping

### M-01: Plain Key Remap via Overlay Click (P0)
- **Pre:** Overlay visible with inspector/drawer open
- **Steps:**
  1. Click the "A" keycap on overlay
  2. In mapper drawer, click output keycap to record
  3. Press "B" on keyboard
  4. Verify auto-save
- **Verify:**
  - Overlay "A" key now shows "B"
  - Pressing A on keyboard outputs B
  - Config file contains the remap
- **Breaks:** outputKey vs displayLabel confusion, overlay not refreshed

### M-02: System Action Mapping (P0)
- **Pre:** Mapper drawer open
- **Steps:**
  1. Click a key on overlay
  2. Switch output type to System Action
  3. Select "Spotlight"
  4. Verify auto-save
- **Verify:**
  - Overlay shows magnifying glass icon on key
  - Pressing key opens Spotlight
- **Breaks:** System action identifier wrong, icon not shown

### M-03: App Launch Mapping (P1)
- **Pre:** Mapper drawer open
- **Steps:**
  1. Click a key on overlay
  2. Switch output type to App Launch
  3. Browse and select Safari
  4. Verify auto-save
- **Verify:**
  - Overlay shows Safari icon on key
  - Pressing key launches Safari
- **Breaks:** Bundle ID wrong, icon not loaded, launch fails

### M-04: URL Mapping (P1)
- **Pre:** Mapper drawer open
- **Steps:**
  1. Click a key
  2. Switch output type to URL
  3. Enter "https://github.com"
  4. Verify auto-save
- **Verify:**
  - Overlay shows favicon on key
  - Pressing key opens URL in browser
- **Breaks:** URL encoding wrong, favicon not fetched

### M-05: Hold Action (Dual-Role Key) (P0)
- **Pre:** Mapper drawer open
- **Steps:**
  1. Click a key (e.g., Caps Lock)
  2. Set tap output to Escape
  3. Set hold output to Control
  4. Save
- **Verify:**
  - Quick tap sends Escape
  - Hold sends Control
  - Overlay shows tap label when idle, hold label when held
- **Breaks:** Tap/hold timing wrong, labels don't switch

### M-06: Shifted Output (P1)
- **Pre:** Mapper drawer, plain key mapping
- **Steps:**
  1. Map A → B
  2. Enable shifted output
  3. Set shifted output to C
  4. Save
- **Verify:**
  - Pressing A outputs B
  - Pressing Shift+A outputs C (not Shift+B)
- **Breaks:** Shifted output not in config, wrong key sent

### M-07: Shifted Output Blocked States (P1)
- **Pre:** Mapper drawer open
- **Steps:**
  1. Set an app-specific condition → verify shifted output toggle is disabled with reason
  2. Clear app condition, set a hold action → verify shifted output disabled with reason
  3. Clear hold action, set system action output → verify shifted output disabled with reason
- **Verify:** Each blocking state shows correct reason message
- **Breaks:** Shifted output allowed when it shouldn't be (config error)

### M-08: App-Specific Rule (P1)
- **Pre:** Mapper drawer open
- **Steps:**
  1. Click a key
  2. Set app condition to Safari
  3. Map H → Left Arrow
  4. Save
  5. Switch to Safari → press H → verify Left Arrow
  6. Switch to another app → press H → verify types "h"
- **Verify:** Mapping only active in Safari
- **Breaks:** App condition not in config, rule active everywhere

### M-09: Device-Specific Rule (P2)
- **Pre:** Two keyboards connected (e.g., MacBook + external)
- **Steps:**
  1. Click a key
  2. Set device condition to external keyboard
  3. Map a key
  4. Save
- **Verify:** Mapping only active on external keyboard, not MacBook
- **Breaks:** Device hash wrong, rule applied to all keyboards

### M-10: Macro Recording (P1)
- **Pre:** Mapper drawer open
- **Steps:**
  1. Click a key
  2. Enable macro mode
  3. Record: type "hello"
  4. Save
- **Verify:** Pressing key outputs "hello" as a sequence
- **Breaks:** Macro sequence wrong, timing issues

### M-11: Double-Tap / Multi-Tap (P1)
- **Pre:** Mapper drawer open
- **Steps:**
  1. Click a key
  2. Set single-tap output to A
  3. Set double-tap output to B
  4. Save
- **Verify:**
  - Single tap → A
  - Double tap → B
- **Breaks:** Tap detection timing, tap-dance config wrong

### M-12: Conflict Resolution in Mapper (P1)
- **Pre:** Existing mapping on key A
- **Steps:**
  1. Click key A in overlay
  2. Change output to something new
  3. Save (autoResolveConflicts: true in mapper)
- **Verify:** New mapping replaces old, overlay updates
- **Breaks:** Old mapping still active, duplicate rules in config

### M-13: Delete Mapping (P1)
- **Pre:** Key A has a mapping
- **Steps:**
  1. Click A on overlay
  2. Use clear/reset button in mapper drawer
- **Verify:**
  - Overlay reverts A to default label
  - Config no longer contains the remap
- **Breaks:** Mapping stuck, config stale

---

## 3. Overlay — Display and Interaction

### O-01: Key Press Highlights (P0)
- **Pre:** Overlay visible, kanata running
- **Steps:**
  1. Press and hold a key on keyboard
  2. Release key
- **Verify:**
  - Keycap highlights blue while held
  - Highlight fades on release
- **Breaks:** CGEvent tap not working, TCP connection lost

### O-02: Hold Label Display (P0)
- **Pre:** Caps Lock remapped to tap=Esc, hold=Hyper
- **Steps:**
  1. Tap Caps Lock quickly → verify no hold label flash
  2. Hold Caps Lock for 200ms+ → verify hold label appears (✦)
  3. Release → verify label returns to idle (⎋)
- **Verify:** Label transitions match tap/hold state
- **Breaks:** tapHoldIdleLabel missing, holdLabel not received via TCP

### O-03: Layer Switch Updates Labels (P0)
- **Pre:** Vim nav installed, overlay visible
- **Steps:**
  1. Activate nav layer (hold activator)
  2. Verify all keycap labels change to nav layer mappings
  3. Release activator
  4. Verify labels return to base layer
- **Verify:** Full label set updates, not just individual keys
- **Breaks:** layerKeyMap not rebuilt, notification missed

### O-04: Overlay Drag and Reposition (P1)
- **Pre:** Overlay visible
- **Steps:**
  1. Drag the overlay header to a new position
  2. Release
- **Verify:** Overlay stays at new position
- **Breaks:** Drag gesture not registered, window snaps back

### O-05: Overlay Position Persists Across Restart (P1)
- **Pre:** Overlay moved to non-default position
- **Steps:**
  1. Quit KeyPath
  2. Relaunch
- **Verify:** Overlay appears at saved position
- **Breaks:** OverlayWindowFrameStore not saving/restoring

### O-06: Overlay Resize (P1)
- **Pre:** Overlay visible
- **Steps:**
  1. Resize overlay (drag edge)
- **Verify:**
  - Keyboard scales proportionally
  - Key labels remain readable
  - Keycaps maintain aspect ratio
- **Breaks:** Scale calculation wrong, labels clipped

### O-07: Health Indicator States (P0)
- **Pre:** Overlay visible
- **Steps:**
  1. With kanata running → verify green/healthy state (auto-dismisses)
  2. Stop kanata service → verify red/unhealthy state with issue count
  3. Restart kanata → verify returns to healthy then dismisses
- **Verify:** States transition correctly, issue count matches real issues
- **Breaks:** Stale state (the "System Not Ready" bug), wrong count

### O-08: Inspector Panel Open/Close (P1)
- **Pre:** Overlay visible
- **Steps:**
  1. Click inspector toggle (or Touch ID key)
  2. Verify panel slides open, overlay widens
  3. Click again → panel closes, overlay narrows
- **Verify:** Animation smooth, panel content visible, no clipping
- **Breaks:** Window frame math wrong, inspector overlaps screen edge

### O-09: App Suppression (P2)
- **Pre:** Overlay visible, excluded app configured
- **Steps:**
  1. Switch to excluded app (if configured)
  2. Verify overlay hides
  3. Switch back to non-excluded app
  4. Verify overlay reappears
- **Verify:** Suppression toggles correctly
- **Breaks:** Overlay stays visible in excluded app, or doesn't return

### O-10: Collection Colors on Keycaps (P1)
- **Pre:** Multiple packs installed (vim=orange, window=purple)
- **Steps:**
  1. Verify keycaps show correct colors per collection
  2. Switch layers → verify colors update
- **Verify:** Each collection's keys use its designated color
- **Breaks:** Color routing wrong, all keys same color

---

## 4. Launcher Mode

### L-01: Enter and Exit Launcher Mode (P1)
- **Pre:** Quick Launcher installed with mappings
- **Steps:**
  1. Hold Hyper key (or configured activator)
  2. Verify overlay switches to launcher layer with icons
  3. Release Hyper
  4. Verify overlay returns to base layer
- **Verify:** Layer switch is smooth, icons visible, base layer restored
- **Breaks:** Layer stuck, icons not preloaded

### L-02: Launch App from Launcher (P1)
- **Pre:** Launcher mode with S → Safari mapping
- **Steps:**
  1. Hold Hyper
  2. Press S
  3. Release Hyper
- **Verify:** Safari launches, overlay returns to base
- **Breaks:** Action URI not dispatched, wrong app launched

### L-03: Cancel Launcher with Escape (P2)
- **Pre:** In launcher mode
- **Steps:**
  1. Hold Hyper to enter launcher
  2. Press Escape
- **Verify:** Returns to base layer without launching anything
- **Breaks:** ESC not handled, layer stuck

---

## 5. Wizard and System Health

### W-01: Fresh Install Wizard Flow (P0)
- **Pre:** Fresh install, no permissions granted, no helper installed
- **Steps:**
  1. Launch KeyPath
  2. Wizard should open automatically
  3. Follow prompts: install helper → grant Accessibility → grant Input Monitoring → start service
- **Verify:**
  - Each step shows correct status
  - Permission dialogs appear when expected
  - Service starts successfully
  - Overlay appears after completion
- **Breaks:** Wrong wizard page shown, permission check stale, service won't start

### W-02: Wizard with Existing Karabiner (P1)
- **Pre:** Karabiner-Elements installed and running
- **Steps:**
  1. Launch KeyPath wizard
- **Verify:**
  - Conflict detection page appears
  - Shows option to stop Karabiner or coexist
- **Breaks:** Conflict not detected, wizard skips straight to service start (will fail)

### W-03: Repair Flow (P1)
- **Pre:** KeyPath was working but service stopped
- **Steps:**
  1. Click health indicator on overlay (should show unhealthy)
  2. Wizard opens to summary page
  3. Click "Fix" or "Repair"
- **Verify:** Service restarts, overlay returns to healthy
- **Breaks:** Wrong issue diagnosed, fix action fails

---

## 6. Settings and Preferences

### S-01: Change Keymap (P1)
- **Pre:** Overlay visible with inspector settings shelf
- **Steps:**
  1. Open Keyboard tab in settings shelf
  2. Select Dvorak keymap
- **Verify:**
  - Overlay labels update to Dvorak layout
  - Key presses still work (remapping applies on top of keymap)
- **Breaks:** Labels wrong, keymap not applied, config conflict

### S-02: Change Physical Layout (P2)
- **Pre:** Settings shelf open
- **Steps:**
  1. Open Layout tab
  2. Switch from ANSI to ISO
- **Verify:**
  - Overlay shows ISO key geometry (extra key between Shift and Z)
  - Key widths adjust
- **Breaks:** Layout geometry wrong, keys overlap

### S-03: Change Keycap Colorway (P2)
- **Pre:** Settings shelf open
- **Steps:**
  1. Open Keycaps tab
  2. Select a different colorway
- **Verify:** Keycap colors change, text remains readable
- **Breaks:** Colors wrong, contrast too low

---

## Coverage Matrix

| Feature Area | Unit Tests | Snapshots | Integration | Manual Tests | Total Coverage |
|---|---|---|---|---|---|
| Overlay labels/rendering | ✅ effectiveLabel, labelMetadata | ✅ keycap states | — | O-01 to O-10 | High |
| Mapper data flow | ✅ payload, canSave, conflict | ✅ keycap pair | — | M-01 to M-13 | High |
| Gallery pack install | ✅ registry, collection mapping | ✅ pack cards | ✅ full pipeline | G-01 to G-10 | High |
| Config generation | ✅ kanata format, key mapping | — | ✅ .kbd file | G-01, M-01 | High |
| Tap-hold idle labels | ✅ population logic | ✅ overlay with labels | ✅ install chain | G-01, O-02 | High |
| Notification chain | — | — | ✅ .ruleCollectionsChanged | O-03 | Medium |
| Launcher | ✅ 38 tests | ✅ drawer | — | L-01 to L-03 | Medium |
| HRM | ✅ 54 tests | ✅ timing slider | — | G-04 | Medium |
| Advanced behaviors | ✅ 140 tests | — | — | M-05, M-10, M-11 | Medium |
| Wizard routing | ✅ golden tests | — | — | W-01 to W-03 | Medium |
| Real key events | — | — | — | O-01, O-02, O-03 | Manual only |
| Permissions | ✅ oracle logic | — | — | W-01 | Manual only |
| Window management | ✅ frame store, sizing | — | — | O-04 to O-06, O-08 | Manual only |
