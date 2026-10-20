# Secure Input at launch must wait, not replay setup

The Air installed `663c0ed2a` at 12:01 on October 18 while the screen was locked;
`loginwindow` held Secure Input. The worker reported `state=secureInput` twice,
ordinary startup treated that as terminal, and the launch opened the setup wizard
on "Start driverless remapping" with no worker running. A running session already
paused for secure typing and resumed when it ended (seven times that morning);
only startup lacked that path.

A verified, cleaned-up, owned `secureInput` startup report now joins the existing
interrupted-startup recovery loop (the held-key/wake loop). It waits for Secure
Input to end, an active console and all keys up, then starts through ordinary
admission. Quit, Stop and newer intent still cancel it. Unowned reports and
incomplete cleanup are refused as before.

The launch path's one-second wizard re-check called `inspectSystem()`, which has
no notion of a recovery in progress, so it would still have opened the wizard
while locked (and for held keys kept down over a second). It now skips the
wizard while `isInTransientRuntimeStartupWindow()` is true.

Regression coverage: `SessionLifecycleInterleavingTests.
testSecureInputStartupWaitsForUnlockThenResumesAutomatically` failed before the
fix ("Recovery was not armed"); the ownership/cleanup refusal test passes before
and after. Launch while locked, then unlock, is manual Air acceptance.

The same launch rewrote `RuleCollections.json`: bootstrap regenerates and saves
rule state on every launch (pre-existing). `keypath.kbd` and `CustomRules.json`
were byte-identical and enabled collections matched earlier launches.

## Follow-up: stranded launch splash (`1ada9c645`)

The locked launch then resumed correctly at unlock, but the splash stayed on
screen. The 3 s splash fallback hides it only when `hasCompletedInitialWizard()`
is true, which required the runtime to be running at that moment; otherwise it
left the splash for the wizard to cover. With the wizard correctly suppressed,
nothing hid it. Setup completion now also counts a pending runtime recovery
(`AppDelegate.initialSetupComplete`), so the splash hides, the overlay shows the
neutral recovery status, and reopening during recovery does not route to setup.
