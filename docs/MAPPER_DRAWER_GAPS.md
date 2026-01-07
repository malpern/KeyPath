# Mapper Drawer vs Standalone Mapper (Feature Gaps)

This doc tracks functionality present in the standalone Mapper view (`Sources/KeyPathAppKit/UI/Experimental/MapperView.swift`) that is not yet available in the overlay drawer mapper (`Sources/KeyPathAppKit/UI/Overlay/OverlayMapperSection.swift`).

## Current Behavior
- Clicking keys only updates the drawer mapper when the drawer is visible.
- The closed overlay keyboard is used for window dragging (no click-to-open mapper behavior).

## Gaps (Standalone Mapper → Drawer Mapper)
- **Advanced behavior (tap/hold + tap dance):**
  - Hold action recording and hold-behavior variants (tap‑preferred, hold‑preferred, etc.).
  - Double‑tap and multi‑tap (tap dance) actions with add/remove steps.
- **Timing customization:**
  - Tapping term settings.
  - Separate tap vs hold timing (advanced timing toggle).
- **Conflict resolution UI:**
  - The conflict dialog that allows resolving overlaps (e.g., keep hold vs keep tap) is not surfaced in the drawer.

## Notes
- Both UIs share `MapperViewModel`, but the drawer UI intentionally omits the advanced controls listed above.
- This list should be updated as parity work lands in the drawer.
