# Popover Crash: Output Type Dropdown on Overlay

**Date:** 2026-05-07
**Severity:** P0 (crash)
**Trigger:** Clicking "Keystroke ∨" output type dropdown in mapper drawer, then selecting "System Action"

## Symptoms

App crashes with `EXC_BAD_ACCESS (SIGSEGV)` — null pointer dereference (`pc=0x0`) on the main thread.

## Root Cause

The output type dropdown uses a SwiftUI `.popover()` attached to the overlay window. The overlay uses a borderless `NSWindow` with non-standard styling. When the popover opens and SwiftUI tries to animate its content view size, it triggers:

```
NSPopover._setContentView:size:canAnimate:
  → PopoverHostingView.updateAnimatedWindowSize
    → NSHostingView.windowDidLayout
      → NSWindow.setFrame:display:animate:
        → NSResizeMoveHelper._doAnimation
          → CFRunLoop observer callback → pc=0x0 (CRASH)
```

The null function pointer is called inside a `CFRunLoopObserver` callback during the window resize animation. This is a known class of macOS SwiftUI bug where popovers on non-standard windows crash during layout.

## Evidence

- Crash report: Thread 0, `Dispatch queue: com.apple.main-thread`
- Exception: `KERN_INVALID_ADDRESS at 0x0000000000000000`
- Call originates from `NSPopover._setContentView:size:canAnimate:` (frame 7)

## Location

`Sources/KeyPathAppKit/UI/Overlay/OverlayMapperSection+OutputTypeDropdown.swift:16`

```swift
.popover(isPresented: $isSystemActionPickerOpen, arrowEdge: .bottom) {
    systemActionPopover
}
```

## Fix Options

1. **Replace `.popover()` with a custom dropdown** — render the menu inline in the overlay view hierarchy instead of using an `NSPopover`. Avoids the AppKit popover + non-standard window interaction entirely.
2. **Use `Menu` instead of `.popover()`** — SwiftUI `Menu` uses `NSMenu` under the hood which doesn't have the same window animation issue.
3. **Delay popover presentation** — use `DispatchQueue.main.async` to present the popover outside the layout pass, avoiding the re-entrant animation. (Fragile workaround.)

**Recommendation:** Option 2 (`Menu`) is the safest fix. The output type selector is already a list of choices — `Menu` is the correct semantic control.

## Affected Popovers

The same pattern exists in:
- `LiveKeyboardOverlayView+Header.swift:528` — layer picker popover
- `OverlayMapperSection.swift:694` — app condition picker popover
- `OverlayMapperSection+HoldVariantPicker.swift:34` — hold variant popover

All of these could potentially crash the same way if they trigger during a window animation.
