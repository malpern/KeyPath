# Retaining the AppKit launch event during bootstrap

The signed session-observers 27edc236c guest campaign reached headless composition
and RuntimeCoordinator initialization but never logged AppDelegate launch completion
or headless auto-start. No fixture input was sent. Normal GUI startup had worked.

CompositionRoot touches NSApplication (including accessory activation policy) in
KeyPathApp.init, before SwiftUI has installed and configured its delegate. Relying
only on the delegate callback loses startup if AppKit finishes during that interval.
The missing callback is observed; exactly which bootstrap AppKit call causes finish
launching has not been proven by a guest trace.

AppDelegate now registers for the actual didFinishLaunching notification when the
SwiftUI adaptor creates it, before composition. It retains that event until all
application dependencies and the headless flag have been assigned. A small gate
coalesces notification and delegate delivery into one startup. Configuration alone
cannot trigger startup; no launch event is fabricated. The existing headless
RuntimeCoordinator start and its permission/lifecycle checks remain unchanged.

Pure gate tests cover early launch, normal launch, duplicate delivery, and missing
launch evidence. Signed guest startup remains the required integration verification.
