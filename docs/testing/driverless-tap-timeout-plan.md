# Actual OS tap timeout — current planning checkpoint

Status: **cause observability resolved; actual OS timeout remains untested**.
This is a read-only source audit and bounded proposal, not an implementation,
signed-artifact acceptance or execution release. The original packet at
`/private/tmp/keypath-tap-timeout-harness` remains unchanged.

The current product source is `88e6674e13ca2f1cdd4c3d6737a42da22f66c98c`
in `/private/tmp/keypath-session-observers`. Exact source hashes and verified
line references are recorded in `source-audit.json`. The root-reported signed
main SHA is `4b8eb82877b734ca87dde4b67f6ee9e7eec6f116325832b78ee6659f99b5fbd7`;
this packet audits source, not the installed artifact or a new physical result.

The genuine registered Quartz callback calls `receive` at worker lines118–126.
Its actual `.tapDisabledByTimeout` case emits `tap-disabled-by-timeout` at
lines160–162. `.tapDisabledByUserInput` emits `tap-disabled-by-user-input` at
lines163–165. The timer's disabled-tap observation emits `tap-disabled-observed`
at line221. The old 6a35 packet's cause-collapse blocker is therefore resolved.
Only the real timeout callback is timeout evidence; timer/user-input failure,
Secure Input, heartbeat cleanup, SIGKILL or a synthetic callback is a separate case.

Normal running publication is nominally every500ms (worker line227). Parent
supervision polls every250ms (coordinator line197); report freshness is at most
2 seconds (report lines51–54). Only Secure Input receives automatic resume
(coordinator lines218–229); other failures require explicit recovery (232–234).
Normal finish disables the tap, releases owned output, publishes the terminal
report and exits (worker lines319–338). Preserve this ordering and the existing
permission, ownership and lifecycle owners.

## Smallest proposed experiment

Use a new, separately labeled artifact compiled with a dedicated experimental
condition, such as `KEYPATH_TAP_TIMEOUT_EXPERIMENT`. Normal builds contain neither
hook nor control interface; runtime default is off. This is not a generic debug
API, an environment-only switch, a signal experiment or an ordinary launch mode.

One private regular single-link0600 owned command beside the existing worker
report can admit one finite callback delay. Bind exact schema/version, worker
PID/UID/nonce, parent PID, config/binary hash, expiry and monotonically consumed
sequence. Validate and prepare outside the callback; consume once before delay.
Reject replay, a second arm, wrong generation, malformed/unbounded duration or
expired ownership. The external executor retains the actual shared lease/provider/
account/home/console/boot receipt and fresh guards; the product needs no VM-specific
network or lifecycle API. File owner/type/mode/link/metadata must remain valid
through read; no arbitrary text, eval, shell, secret logging or free UID declaration.

Trigger only on a genuine nonrepeat fixture key-down for an unmapped key (for
example b), while supported q→a is actually held, normal focus remains present,
Secure Input is false, environment/parent is current and owned output ledger is
exactly `[4]`. Delay only this real callback, locally bounded without requiring
remote cleanup. Record nonsecret monotonic entry/return and one-shot identity in
a separate owned diagnostic receipt or optional report fields. Actual timeout
origin/time/sequence must be populated only by the registered timeout callback.
Never directly invoke that handler, disable the tap, mutate the ledger or fabricate
its notification. Normal parent coordination must still launch the worker.

Freeze one finite delay after measuring current report age and scheduling margin:
`delay + current report age + measured margin < 2 seconds`. A proposed source
ceiling of1 second is only a safety ceiling, not an OS timeout threshold or a
chosen test duration. No universal threshold was established by this audit.
If no safe measured interval yields the actual callback, inducement is blocked.
Do not extend the heartbeat budget or progressively retry longer stalls.

The existing5ms timer can win the post-delay race and observe a disabled tap
before the Quartz notification is delivered. That result is **timer-only failure;
timeout origin untested**. Do not suppress, postpone, detune or reorder that timer
or parent supervision simply to force acceptance. A missed first terminal receipt
also prevents timeout acceptance, even when output release otherwise succeeds.

## Required physical proof and recovery

1. Freeze source/artifact/signatures, supported temporary q→a config, exact finite
   trigger/hold script, current scoped transport and measured timing. Admit the
   script under owned firmware/run guards. Prove actual normal focus, Secure Input
   false, fresh journals and canonical parent-ready evidence for the current
   parent/worker/nonce, with tap/TCP readiness and initially empty ledger.
2. Before the trigger, independently observe target a-down/held and current owned
   ledger `[4]`, plus exact same-run submitted fixture prefix proving q remains
   physically down. Trigger offsets must leave measured room for this baseline;
   freeze them before input rather than infer a successful baseline afterward.
3. Require same-generation actual Quartz timeout evidence and a first fresh,
   immutable terminal report. Independently observe target a-up after callback
   entry and before physical q-up, ledger empty/tap disabled, unchanged target,
   boot/focus and Secure Input false. Prove exact worker exit with a complete
   observer-inclusive process scan. Cleared ledger or sampled flags alone do not
   prove delivered release. Preserve relevant phase anchors until acceptance.
4. Finish exact physical all-up. With old worker exited and no replacement, a new
   finite balanced q tap must pass through q, with no recreated a output. Retain
   separate fresh target/trace evidence for fail-open behavior.
5. After all-up, invoke the ordinary canonical Restart Runtime action once. The
   actual UI action routes through RuntimeCoordinator.restartKanata to the
   lifecycle owner. Require a new worker PID/nonce under the same parent, current
   canonical parent readiness and empty ledger; a fresh balanced q tap must
   again deliver a down/up and release everything.
6. Cleanup only owned fixture/process identities without mutation replay, retain
   uncertain dispatch ownership, independently prove exits/all-up, restore the
   original profile bytewise and preserve separate cleanup/close errors. Follow
   the released USB adapter rather than changing persistent bindings.

A headless-only executor currently lacks an exposed ordinary same-parent restart
command. Use the guarded normal GUI action, or truthfully scope a normal parent
stop/relaunch as **new-parent recovery**, which does not establish same-parent
explicit recovery. Do not add a direct worker-launch side channel or infer
recovery from a tap alone.

## Outstanding gates

- Implement and review the narrow compile-gated hook and real executor; neither
  exists at this checkpoint. Add meaningful default-absence, one-shot ownership,
  malformed/replay/reflection and bounded-delay tests without simulating success.
- Establish a safe measured delay/transport window and freeze trigger offsets;
  timer-race classification remains mandatory. No actual OS threshold is proven.
- Capture callback/terminal/release-before-q-up evidence and fresh fail-open input;
  preserve immutable phase receipts and first-terminal freshness.
- Choose and review the canonical explicit-restart route, then prove fresh same-
  parent generation/readiness and balanced remap recovery.
- Update operational dependency/artifact/lease pins at execution freeze. The old
  packet's6a35 and old identity-module pins are historical references, not current
  execution authority. No physical pass from another case transfers to this case.

This packet prevents rediscovery of the resolved source issue. It grants no
source implementation acceptance, build/signing approval or physical release.
