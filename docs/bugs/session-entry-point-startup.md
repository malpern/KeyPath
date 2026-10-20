# Keep the SwiftUI entry point synchronous

An independent `--driverless --headless` app launch initialized CompositionRoot
but never logged AppDelegate's finish-launching callback. No lifecycle worker
started. The same signed worker launched directly worked, so worker feasibility
was not integrated app startup proof. Failed campaign is retained as evidence.

The prototype had made the entire entry point asynchronous to await the worker
permission oracle, even on ordinary app launches. Keep ordinary SwiftUI startup
synchronous. Only explicit worker modes schedule the async worker on the main
actor and run the main run loop. This keeps permission evaluation asynchronous
without yielding the normal application's entry before SwiftUI installs its
application delegate. Signed parent/lifecycle retest is required.
