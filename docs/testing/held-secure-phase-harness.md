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
old-worker exit and an accepted fresh `secureInput` transition report with empty
ledger are required. The transition is captured during secure-mode acknowledgement
polling, bounded by the command wall-time anchor and the three-second freshness
window. Its immutable receipt remains historical evidence after exit; an exited
worker is never required to republish. A first stale terminal receipt still fails.
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
The accepted fixed sample is then physically cleared after its verified all-up,
and the same target is returned to normal mode with empty held keys/modifiers.
The same field and cumulative counters remain intact; mode commands carry no text.
A failed campaign does not attempt an unverified physical clear or refocus.

Every complete parsed target poll, including a subsequently refused focus/history
receipt, is written once to a new unique evidence directory, including
raw journals and dropped counts. The signed target's single `receiptSequence`
is incremented for both `flagsChangedJournal` and
`combinedSessionControlJournal` (reviewed `capture-target.m` lines59/77/125).
Their cross-journal ordering is deliberate; `modeTransitions` uses a separate
command sequence and is never compared to that shared receipt sequence.
Lifetime drops before the campaign are allowed;
eviction or alteration of any retained phase anchor fails. Setup observations do
not create permanent ring anchors. The held phase begins after fixture load/arm,
immediately before start; its Control-down/release and combined-session anchors
remain required through the no-resurrection dwell, exact physical all-up trace and
target reconciliation. Each fresh tap/hold/chord and secure calibration has a new
phase. Anchor rows are deep-copied. An accepted evidence file is persisted before
that phase is retired, and a retirement receipt names the accepted file. Completed
phases may subsequently roll out of the 512-entry ring without invalidating their
saved immutable evidence; active phases cannot. Publication failure,
wrong focus, missing delivery or unexpected ownership stops acceptance without
replaying input/commands. Finally, only the campaign's exact fixture run can be
aborted. The run identifier is retained before the one-shot load, so an accepted
load with a lost response is still covered by that exact-status cleanup guard;
foreign runs remain untouched. Only revalidated owned PIDs can be signaled, and the saved profile is
restored with a bytewise comparison. The original profile backup is retained.

## Explicit transport and identity seam

Execution requires `--reviewed-execution`, parent/worker `--binary-sha`, target
`--target-sha`, and a reviewed `--fixture-factory` module. D8 imports the reviewed
shared module at
`/private/tmp/keypath-guest-identity/Scripts/experiments/session-runtime/guest-identity.py`;
it does not maintain a separate identity schema. Use its
`--guest-identity-receipt` argument (or `KEYPATH_GUEST_IDENTITY_RECEIPT` environment)
and optional matching `--guest-account` / `--guest-uid`. Its exact seven fields
are `version`, `lease`, `providerUUID`, `account`, `uid`, `home`, `bootEpoch`.

Without a declared receipt, the retained canonical default is `keypathqa` UID501.
A noncanonical lease-derived UID502 account requires a complete owned private
receipt; freely declaring its name and UID is rejected. Before guest commands,
the shared module checks frozen receipt contents, live owned lease manifest
provider UUID/owner/readiness/expiry and guest account/home/UID/console/boot.
Each phase poll reuses the shared private-receipt reader and provider validator:
one provider-status call and one read-only guarded guest snapshot return actual
account/home/UID/console/boot observations, the target, exact owned parent/worker
PID/UID/arguments, common executable hash, per-generation worker report, target
process/hash, and the old PID's exit observation when required. Labelled base64
records have an exact shape and terminal completion marker; missing, duplicate,
foreign or partial records fail. Process tables bracket the snapshot and must
match, so a generation change during the batch is refused. Target process
observations are bracketed too. The target executable and raw arguments are
separate labelled records, preserving spaces in `VM Lab Rig Target.app`; raw
arguments are compared to their exact preflight observation without guessing argv
quoting. KeyPath discovery explicitly requires its whitespace-free app path. Exit
proof requires a nonempty unique positive PID scan containing the observer shell,
all observed live owned processes and the target; missing PID data cannot become
a false exit. Kernel PID0 is filtered out by the observation command. No guest Python is needed for these reads.
Mode mutation remains a separate unreplayed write followed by acknowledgement.
Its existing Python dependency is explicitly checked during preflight, before
physical input. Setup and cleanup keep their individually guarded observations.
D8 additionally puts the live guest identity guard directly around each command,
including launch, reports, signals and bytewise restoration. A leading `true;`
is required by the established `prlctl` transport's first-command behavior; it
never masks the guard or operation's final failure. There is no credential loader.

`VM_LAB_RIG_ROOT` selects only the original `/private/tmp/vm-lab-hid-rig` or the
reviewed identity adapter `/private/tmp/vm-lab-guest-identity`; other roots refuse.
The factory receives the inherited validated receipt environment.

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
process-report lifecycle and cleanup races together with this harness. The source
firmware inspected accepts the 45-second script duration; this is not evidence of
which firmware is installed. The
shared module is an external reviewed-path dependency; its source must remain
at the reviewed checkpoint. PID start-time proof and OS-specific shell/process
formatting remain review topics, while UID/executable/exact observed arguments and worker nonce are
checked before owned signals. Batched reads reduce transport count but do not
measure or guarantee latency. Both observation and predicate completion are
checked against wait deadlines, and fixture status/trace acceptance also rejects
a completion observed after its deadline. Transport calls can still consume their
own bounded timeout before refusal; they are never replayed as mutations. The
45-second sample must fit measured guest/fixture round-trip latency and the
512-entry target rings; deadline or anchor eviction is a failed/untested campaign,
never permission to lengthen or replay physical input automatically.

The 27 pure checks include synthetic positive and negative tests for stale/focus
receipts, dropped/evicted anchors, actual versus sampled Control release,
physical hold ordering, command application, worker generations, no resurrection
with permitted q repeats, exact terminal all-up traces, phase retirement and
immutable ring anchors, fresh-once stopped-worker evidence, incomplete batches,
parent arguments/worker nonce/hash changes, no-retry focus refusal, and owner
cleanup continuing when fixture-client close fails. Shell syntax
and the failure/completion-marker contract are checked without guest operations.
These tests validate evidence contracts, not OS behavior. Real OS tap timeout, sleep/wake and console
departure/return remain explicitly **untested**; SIGKILL and a synthetic callback
are not substitutes. This source pass grants no D8 acceptance or Caps support.

Run pure checks without guest operations:

```sh
python3 -m unittest discover -s Scripts/experiments/session-runtime -p 'test_held_secure_predicates.py'
```

The guest command-channel dependency is the ordinary Python 3.13.16 framework
interpreter at `/Library/Frameworks/Python.framework/Versions/3.13/bin/python3.13`.
Receipt-guarded preflight verifies its version and required standard-library modules
before input. Command publication uses the same isolated interpreter and refuses a
version mismatch before opening a command file. The Apple developer-tools launcher
is not used.


D8 canonical parent readiness integration (source review only)

The unchanged reviewed `parent_readiness.py` dependency is pinned at SHA256
`69e69782c338a36768233fddcdadac54ea2b908a25d39ec84b9b4bcd6ee19f6b`.
Both initial and resumed admission now perform its identity-guarded combined
parent-log/current-worker-report read. The current parent PID, worker PID and
launch nonce must match an actual coordinator completion after this campaign's
parent launch request. A healthy tap without this completion keeps waiting;
identity and transport failures propagate. Each accepted worker receipt includes
`parentReadiness`. The helper instance is shared so transient refusal has the same
exception identity in both pollers; its source hash is checked on every access.
No timing budgets change. The extra provider/identity and combined guest read
must finish inside each existing eight-second worker deadline.

The actual read-only fixture preflight route is the separately reviewed
`/private/tmp/keypath-held-fixture-factory/read_only_preflight.py --requests 1`
(or three requests for latency sampling). It extracts only the selected credential
in memory, pins factory SHA256
`78d188b220934cfaf6f264bb3203dbe3c7ea24d8d2ef556a55e5dd7999800f1b`,
and reads status at the fixed numeric endpoint. This source task did not execute
that route. Status can establish the reported firmware/build/state and request
latency; the exposed factory has no read-only script-validation method. Its
local load checks only framing/run ID/ASCII size, and `load_script` itself mutates
the controller. Therefore read-only preflight cannot establish installed firmware
acceptance of the exact declared 45.3-second script. That remains a separately
released load-admission gate without arm/start or input, subject to owned idle
state and cleanup review. Installed build `fc98a5acc0a5` is a status identifier,
not a proven binding to the previously inspected duration-limit source.

The frozen RigTarget binary SHA256 is
`a8a0e0eeed6d1cbc63bb1bb5c51d80f6d9b36e3a92d06bfda4027f6326284f67`.
Its 512 combined samples at nominal 10Hz retain about 51.2 seconds; usable phase
anchors and fresh focus/secure-input receipts must survive the whole sequence.
Prior numeric status timings (0.0374/0.3734/0.0275 seconds) do not measure the
complete Control-down/secure/release/normal/resume path. Physical execution still
requires measured completion before q-up, preserved phase anchors, actual secure
focus, current firmware/USB ownership and the resumed canonical parent receipt.
No live D8 acceptance, timing fit or installed script admissibility is claimed.
