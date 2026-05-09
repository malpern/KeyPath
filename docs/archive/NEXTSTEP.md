Problem Summary
The keymap switch animation (e.g., QWERTY → Dvorak) used to feel slow, bouncy, and uncoordinated — letters visibly jumbled and settled into place. Now it feels nearly instant, with the key letters appearing transparent and no “clown-car” motion.

What We Found
- The “clown-car” effect comes from floating labels in `OverlayKeyboardView` (`FloatingKeymapLabel`) which animate to new key positions using per-label randomized spring parameters and wobble.
- Two early-January changes suppress those floating labels during keymap switches:
  - `OverlayKeyboardView` now hides floating labels when a key is “remapped” (`isRemappedLabel`).
  - `OverlayKeycapView` treats “remapped” keys as special (`isRemappedKey`) and renders the mapped label directly, while standard labels become `Color.clear` when floating labels are enabled.
- Keymap changes are implemented as remaps, so the floating labels are effectively disabled during keymap switches. This makes labels appear transparent and transitions instant.
- A later change added `.id(layerKeyMapHash)` to `OverlayKeyboardView` (forcing view recreation and resetting animation state). That has already been removed, but the remap gating still blocks the animation.

Current Symptoms Explained
- Transparent letters: standard key labels are intentionally hidden when floating labels are enabled, but floating labels are suppressed by remap gating during keymap switches.
- No jumble: the floating label animation is not being used at all during remap-driven keymap changes.

Next Steps (Low Risk, No Functional Changes)
1) Restore floating labels during keymap transitions only:
   - Add a short “keymap transition” flag (e.g., 500–700ms) when `selectedKeymapId` changes.
   - While active, bypass the remap gating:
     - `OverlayKeyboardView`: ignore `isRemappedLabel` so floating labels stay visible.
     - `OverlayKeycapView`: ignore `isRemappedKey` so keycaps don’t replace labels during the transition.
   - After the window ends, revert to current behavior.
2) If the effect is still too tame, increase randomness:
   - Add per-label random delays (0–120ms).
   - Widen spring response/damping ranges in `FloatingKeymapLabel`.
3) Verify legend style and Reduce Motion:
   - Floating labels only render for `.standard` legends.
   - Reduce Motion disables the floating label animation entirely.

Files to Review
- `Sources/KeyPathAppKit/UI/Overlay/OverlayKeyboardView.swift`
- `Sources/KeyPathAppKit/UI/Overlay/OverlayKeycapView.swift`
- `Sources/KeyPathAppKit/UI/Overlay/LiveKeyboardOverlayView.swift`
