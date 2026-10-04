# D8 held Secure Input phase harness (source only)

`Scripts/experiments/session-runtime/held-secure-acceptance.py` is a separate
campaign for DL-02 / DL-09. It has not run against a guest. The frozen product
base is `6a35b48dd`; the target protocol reviewed for implementation is
`/private/tmp/vm-lab-held-secure/docs/held-secure-target-protocol.md`.
Existing physical/parent harnesses, rig source and previous evidence are unchanged.

The harness starts a headless parent with the exact temporary profile
`q → (tap-hold 200 200 q lctl)` and `a → a`. A persistent, already focused target
must begin with Carbon Secure Input false, empty keys/modifiers and zero counters.
The campaign never prepares/replaces/refocuses that target. It validates its
binary hash, PID, UID, nonce, actual responder and advancing wall/monotonic
publication, then retains cumulative counters and journal phase anchors.

One fixture q-down starts a bounded 45-second physical hold. Control keycode 59
must be delivered locally while the exact owned worker reports usage 224 held.
The PID/UID/nonce/sequence guarded command changes that same target to secure.
A local delivered Control-up after the command anchor must precede fixture q-up;
old-worker exit and a fresh `secureInput` report with empty ledger are required.
A combined-session Control-clear sample corroborates local delivery. A clear
ledger or sampled flag alone cannot establish release.

A second command switches the same target back to normal while the fixture still
reports exactly one submitted q-down. A new PID **and** nonce must appear. For a
bounded two-second observation its ledger stays empty and both local delivery
and combined-session journals contain no recreated Control. Native q repeats are
allowed. Exact terminal fixture all-up and target reconciliation follow. Fresh
q tap, Control hold and Control+a chord must have balanced independent output;
only afterwards does a separate secure phase physically clear any original
nonsecret q repeats with Command+A / Backspace and type fixed nonsecret `qaz123`.
The same field and cumulative counters remain intact; mode commands carry no text.

Every target poll is written once to a new unique evidence directory, including
raw journals and dropped counts. Lifetime drops before the campaign are allowed;
eviction or alteration of any retained phase anchor fails. Publication failure,
wrong focus, missing delivery or unexpected ownership stops acceptance without
replaying input/commands. Finally, only the campaign's exact fixture run can be
aborted, only revalidated owned PIDs can be signaled, and the saved profile is
restored with a bytewise comparison. The original profile backup is retained.

## Explicit transport and identity seam

Execution requires `--reviewed-execution`, explicit frozen `--account`, `--uid`,
`--home`, parent/worker `--binary-sha`, target `--target-sha`, and a reviewed
`--fixture-factory` module. Account names are constrained; home must equal
`/Users/<account>`. Independent directory-service UID/home and console UID are
rechecked at launch, worker-report, signal and profile-restore boundaries. There
is no QA501 assumption and no credential loader in this harness.

The factory exports `create_client()` returning a preauthenticated, persistent,
scoped client with `status`, `load_script`, `arm`, `start`, `abort`, `trace_all`
and `close`. It must preserve the existing rig's no-mutation-retry semantics and
not print credentials. Authentication/provisioning is outside this source pass.
Guest commands use the existing rig admission transport, with failures preserved
instead of shell success masking. No factory or physical input is invoked by
importing the script or running its pure tests.

## Review gates and remaining gaps

Sol high source review, signed target guest release and explicit owner admission
are required before execution. Review the factory and its fixture trace schema,
command directory ownership, signed target identity, guest Python availability,
process-report lifecycle and cleanup races together with this harness. The
45-second sample must fit measured guest/fixture round-trip latency and the
512-entry target rings; deadline or anchor eviction is a failed/untested campaign,
never permission to lengthen or replay physical input automatically.

The predicates have synthetic positive and negative tests for stale/focus
receipts, dropped/evicted anchors, actual versus sampled Control release,
physical hold ordering, command application, worker generations, no resurrection
with permitted q repeats, and exact terminal all-up traces. These tests validate
evidence contracts, not OS behavior. Real OS tap timeout, sleep/wake and console
departure/return remain explicitly **untested**; SIGKILL and a synthetic callback
are not substitutes. This source pass grants no D8 acceptance or Caps support.

Run pure checks without guest operations:

```sh
python3 -m unittest discover -s Scripts/experiments/session-runtime -p 'test_held_secure_predicates.py'
```
