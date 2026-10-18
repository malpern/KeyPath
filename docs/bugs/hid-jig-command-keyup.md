# HID capture Jig omitted Command-modified key release

Observed 2026-10-18 during physical Caps Lock hold/Hyper acceptance. The worker
reported four inputs, ten outputs and no held output usages; the fixture ended
all-up. The native capture had all modifier down/up events and A-down but no
A-up, so the strict oracle correctly refused to pass.

AppKit shortcut dispatch can omit Command-modified keyUp from the view's
responder. Capture local keyUp before that dispatch, only when the Jig's own
window is key and its canvas is first responder. Consume the event after
recording it to prevent duplicate responder capture. No global event monitor or
new permission is needed; the native acceptance requirements remain unchanged.

Validation: 37 HIDCaptureCore tests passed; the signed updated Jig in owned
macOS 26.5.2 lease cbx_6a7d61356f4e passed physical Hyper+A with A-up and every
modifier release, then repeat tap-to-Escape. These live tests exercise the AppKit
boundary that the core unit tests do not. Receipts and pinned binaries:
~/keypath-review-evidence/20261018-tour-final/caps-live/physical/
caps-hold-keyup.json, caps-tap-keyup.json, manifest-keyup.json.

This changes the test observer, not the KeyPath product binary.
