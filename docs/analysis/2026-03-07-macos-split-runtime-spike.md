# 2026-03-07 macOS Split Runtime Spike

## Summary

The host-runtime spike established two things:

1. A bundled user-session host can successfully load the Rust bridge, validate `keypath.kbd`,
   and construct a real `Kanata` runtime in-process.
2. A full in-process launch cannot own the entire current macOS runtime because the pqrs
   VirtualHID client path remains root-scoped.

This means the long-term solution is **not** "make the whole runtime a normal user-space app
process" and it is also **not** "keep one root-owned process for everything". The viable target is
instead a **split runtime**:

- user-session bundled host owns Input Monitoring and built-in keyboard capture
- privileged/root component owns VirtualHID output access

## 2026-03-08 Installer Note

Fresh-install logs on a clean post-reboot machine showed that the Kanata service could start
correctly but still miss the install postcondition because the app only waited 8s for
`running + TCP responsive + inputCaptureReady`.

That timeout was too short for real macOS startup behavior:

- Kanata sleeps for 2s on startup
- the DriverKit keyboard path can take up to ~10s to become ready
- the observed clean-machine TCP-ready transition happened about 13s after service recovery

The installer readiness timeout was increased to 20s so a clean boot no longer fails the
postcondition while Kanata is still legitimately coming up.

Fresh install and normal repair planning now use a separate `installRequiredRuntimeServices`
operation for the split-runtime architecture. That path installs only the privileged pieces the
new runtime actually needs in normal operation:

- VirtualHID services
- the dedicated output-bridge companion

The older bundled launchd install primitive is now explicitly treated as a legacy recovery-services
operation in the broker/coordinator layer rather than the normal install path.

The dedicated output-bridge restart probe now also rehydrates the active split-runtime host after
the companion restart. This turns the probe from "daemon restarted successfully" into a more
useful recovery check: the app can now bring the host back onto a fresh bridge session after the
privileged output daemon is recycled.

The Rust host bridge build is now also required to include the passthru feature set by default for
KeyPath builds. Without that, the installed `kanata-launcher` exits immediately in split-runtime
mode with `passthru output spike feature is not enabled in this bridge build`, which makes
persistent-host and recovery probes meaningless even though the rest of the architecture is intact.

After fixing that packaging issue and relaunching the app cleanly, the live
`exercise-output-bridge-companion-restart` probe now shows the full recovery path working:

- persistent split host starts
- output bridge companion restarts successfully
- companion is healthy again afterward
- the active split host is rehydrated onto a fresh session

Observed probe result:

```text
companion_running_before=true
capture=false
host_pid=40651
companion_restarted=1
companion_running_after=true
host_recovered=1
host_pid_after_recovery=40705
host_stopped=1
```

The same probe now also works in capture mode after a clean app relaunch:

```text
companion_running_before=true
capture=true
host_pid=43122
companion_restarted=1
companion_running_after=true
host_recovered=1
host_pid_after_recovery=43171
host_stopped=1
```

And the real signed-app lifecycle churn probe is now validated too:

```text
first_pid=44078
capture=true
stopped_first=1
second_pid=44137
stopped_second=1
```

So the current remaining work is no longer "can the split runtime survive churn at all?" It is
productionization:

- long-lived capture reliability
- deciding when the split path is safe enough for broader internal enablement
- eventually narrowing the legacy fallback path once split-runtime behavior stays boring under
  repeated real use

## Evidence

### Current runtime and launch model

- `SMAppService` launches `Contents/Library/KeyPath/kanata-launcher` in `gui/<uid>`
- current plist: `Sources/KeyPathApp/com.keypath.kanata.plist`
- legacy helper-generated launch daemon plist still exists in code and explicitly ran Kanata as
  `root:wheel`:
  - `Sources/KeyPathHelper/HelperService.swift`

### pqrs VirtualHID root boundary

On the test machine:

- `/Library/Application Support/org.pqrs/tmp/rootonly` is `root:wheel` with mode `700`
- the VirtualHID daemon itself runs as root:
  - `system/com.keypath.karabiner-vhiddaemon`

### Experimental host runtime results

The bundled launcher now supports:

```bash
KEYPATH_EXPERIMENTAL_HOST_RUNTIME=1 \
  dist/KeyPath.app/Contents/Library/KeyPath/kanata-launcher --port 37003
```

Observed results:

- bridge loads successfully
- config validates successfully
- `Kanata` runtime object is created successfully
- if the requested TCP port is already occupied, host mode now fails cleanly
- when run on an unused port, the host reaches pqrs VirtualHID startup and then fails because the
  client tries to access:

```text
/Library/Application Support/org.pqrs/tmp/rootonly/vhidd_server
```

The raw pqrs client crash path was reproduced before adding the launcher-side preflight. The
launcher now fails earlier with a clear message when it detects the root-only boundary:

```text
vhid driver socket directory is root-only at
/Library/Application Support/org.pqrs/tmp/rootonly; bundled host runtime needs a privileged output bridge
```

To support the next split-runtime milestone, the privileged helper now also exposes a read-only
`getKanataOutputBridgeStatus` XPC probe so the app can ask whether the pqrs output boundary is
root-scoped before attempting host-owned activation.

The next contract seam now exists too: the helper can prepare a privileged output-bridge session
descriptor that reserves a root-owned UNIX socket path under the pqrs root-only directory. This
does not implement the bridge yet; it defines the shape that a future privileged companion or
helper-backed bridge will speak.

The bundled launcher can also now smoke-test that socket protocol in experimental mode when a
session ID and socket path are provided via environment. That gives the host side a real UNIX
socket client path before the privileged bridge server is implemented.

That launcher-side experimental smoke no longer stops at handshake/ping. When a helper-prepared
session is provided via:

- `KEYPATH_EXPERIMENTAL_OUTPUT_BRIDGE_SESSION`
- `KEYPATH_EXPERIMENTAL_OUTPUT_BRIDGE_SOCKET`

the bundled host can also opt into the same bridge probes already used from diagnostics:

- `KEYPATH_EXPERIMENTAL_OUTPUT_BRIDGE_SMOKE_MODIFIERS=1`
- `KEYPATH_EXPERIMENTAL_OUTPUT_BRIDGE_SMOKE_EMIT=1`
- `KEYPATH_EXPERIMENTAL_OUTPUT_BRIDGE_SMOKE_RESET=1`

This remains experimental and off by default. The purpose is to let the host-owned runtime path
exercise the privileged bridge contract directly before switching any production traffic to it.

The app-side runtime coordinator now has the matching seam to prepare and activate a helper-backed
bridge session and generate those launcher environment variables. That still sits behind
experimental code paths only.

One useful negative result: a standalone `keypath-cli` process is not a valid smoke-test client for
this helper bridge path. The helper's XPC security model intentionally accepts only the signed app
identity, and an ad-hoc SwiftPM CLI build is rejected before the bridge session is created. The
smoke path therefore needs to remain app-signed (for example, via app-owned diagnostics or another
app-hosted debug surface) rather than a loose developer CLI.

To keep that direction explicit in code, the smoke path now lives behind an app-side
`KanataOutputBridgeSmokeService` that prepares the helper session, activates the socket listener,
and drives handshake/ping/reset through injectable client operations. That keeps the workflow in an
app-owned surface instead of weakening helper caller validation.

`DiagnosticsService` now has an explicit opt-in hook for this too. When
`KEYPATH_ENABLE_OUTPUT_BRIDGE_SMOKE_DIAGNOSTIC=1` is set for a signed app run, system diagnostics
append a single experimental bridge-smoke result instead of requiring a separate loose tool. The
default path remains unchanged.

That diagnostic smoke can also opt into a single bridge `emitKey` probe with
`KEYPATH_ENABLE_OUTPUT_BRIDGE_SMOKE_EMIT=1`. This remains off by default because it will inject one
real output event through the privileged bridge.

The same diagnostics seam can now also opt into a modifier-state sync probe with
`KEYPATH_ENABLE_OUTPUT_BRIDGE_SMOKE_MODIFIERS=1`. This remains separate from the emitted-key probe
so modifier state and single-event output can be exercised independently while the bridge matures.

The first nontrivial privileged output-side action is now wired too: bridge `reset` requests no
longer only ack locally, they call the Karabiner VirtualHID manager activation path as a real
root-scoped pqrs-side operation. Key emission itself is still no-op/ack-only pending a narrower
plan for actual event injection.

That next step is now partially landed too: helper-side `emitKey` requests no longer stop at a
local ack. The helper loads the existing Rust host-bridge dylib from the app bundle and calls a new
`keypath_kanata_bridge_emit_key` export, which uses the same `karabiner_driverkit::send_key`
primitive Kanata's own macOS output path uses. `syncModifiers` is no longer ack-only either: the
helper now diffs the prior and desired modifier state and emits the corresponding left/right
modifier usages (`0xE0...0xE7`) through that same primitive.

One more important implementation result came from feature-spiking the vendored Kanata crate inside
the Rust host bridge:

- the bridge crate builds successfully on macOS with `kanata/simulated_output`
- after adding a missing no-op `release_tracked_output_keys` method to the vendored
  `sim_passthru::KbdOut`, the bridge crate also builds successfully with
  `kanata/simulated_input + kanata/simulated_output`

That second result matters more. It means the bundled host can be compiled against Kanata's
channel-backed passthrough-style output seam on macOS today, rather than requiring an immediate
large fork of the output path. It does **not** finish the migration by itself, but it changes the
next step from "invent a new abstraction first" to "adapt the existing `sim_passthru` seam to feed
the privileged output bridge."

The host bridge now exposes the first feature-gated API for that seam too. In
`passthru-output-spike` builds it can:

- create a passthrough-style runtime handle with `Kanata::new_with_output_channel`
- report the runtime's layer count
- non-blockingly drain one channel-backed output event as raw `value/page/code`

This still does not route output into the privileged UNIX socket bridge. It is the intermediate
step that proves the bundled host bridge can hold a runtime and observe its channel-backed output
without depending on direct pqrs emission from `KbdOut`.

The bundled launcher now has the matching experimental Swift-side hook. In addition to
`KEYPATH_EXPERIMENTAL_HOST_PASSTHRU_RUNTIME=1`, a host-mode run can opt into forwarding drained
passthrough output events into the privileged UNIX socket bridge with:

- `KEYPATH_EXPERIMENTAL_HOST_PASSTHRU_FORWARD=1`
- `KEYPATH_EXPERIMENTAL_HOST_PASSTHRU_POLL_MS=<duration>`

This remains explicitly non-default and bounded. The launcher drains at most a small fixed batch of
events per probe pass, and the passthrough path now polls for a short bounded window after startup
instead of checking the output channel only once. Drained events are translated into `emitKey`
bridge requests. That gives the split runtime path its first end-to-end
host-output-to-privileged-bridge forwarding seam without changing the production launch path.

There is now also an app-owned invocation path for this experiment. When the signed app is launched
with `KEYPATH_ENABLE_HOST_PASSTHRU_DIAGNOSTIC=1`, `applicationDidFinishLaunching` runs
`DiagnosticsService.getSystemDiagnostics()`, which in turn can launch the bundled
`kanata-launcher` child in passthru-only experimental mode, print the resulting host-passthru
diagnostic block to stderr, and exit. This avoids the helper caller-validation problem that blocks
the same flow from an ad-hoc CLI process.

That app-owned diagnostic now provides one more decisive result. With a helper-prepared privileged
bridge session and a passthrough-enabled host bridge embedded in `/Applications/KeyPath.app`, the
bundled host gets past:

- bridge load
- config validation
- in-process runtime construction
- passthrough runtime construction
- passthrough runtime `start()`
- entry into the bounded passthrough poll loop

and then still aborts from inside the user-session launcher process with:

```text
filesystem error: in posix_stat: failed to determine attributes for the specified path:
Permission denied ["/Library/Application Support/org.pqrs/tmp/rootonly/vhidd_server"]
```

This narrows the remaining blocker further. The current `passthru-output-spike` path does not only
need a privileged output bridge for emitted events; Kanata's existing macOS event-loop path still
calls `karabiner_driverkit::is_sink_ready()` directly from the host process before the bridge can
take over output ownership. In other words, the host is still coupled to pqrs sink readiness even
when output events are being forwarded elsewhere.

That means the next real runtime migration step is **not** more socket/bridge plumbing. It is to
separate host-owned input capture from pqrs sink health in the vendored macOS runtime path, so the
user-session host can read built-in keyboard events without touching the root-only
`vhidd_server` boundary.

That specific Kanata-side blocker has now been cleared by the follow-up vendored macOS backend
refactor captured in `2026-03-08-kanata-backend-refactor-handoff.md`. After rebuilding and
deploying `/Applications/KeyPath.app` with the passthrough-enabled bridge and the new Kanata
backend seam, the signed host-passthru diagnostic no longer aborts with the earlier
`vhidd_server` root-only filesystem exception and no longer wedges creating the direct pqrs
client.

The later verified signed-app run now shows:

- helper repair succeeds
- privileged bridge session preparation succeeds
- `kanata-launcher` child launches successfully
- the child exits cleanly with code `0`
- passthrough runtime creation and startup succeed in the user-session host

That moves the remaining gap from vendored Kanata startup into KeyPath-side input orchestration.
The processing-only passthrough runtime can now be started without constructing the direct pqrs
client, but it will not emit output unless input is explicitly injected into the new passthrough
input seam.

That injected-input seam is now working in direct launcher validation too. A manual run of the
packaged launcher with:

```bash
HOME=/Users/<user> \
KEYPATH_EXPERIMENTAL_HOST_RUNTIME=1 \
KEYPATH_EXPERIMENTAL_HOST_PASSTHRU_RUNTIME=1 \
KEYPATH_EXPERIMENTAL_HOST_PASSTHRU_ONLY=1 \
KEYPATH_EXPERIMENTAL_HOST_PASSTHRU_INJECT=1 \
KEYPATH_EXPERIMENTAL_HOST_PASSTHRU_FORWARD=1 \
/Applications/KeyPath.app/Contents/Library/KeyPath/kanata-launcher
```

now shows:

- passthrough runtime starts successfully
- synthetic key-down / key-up injection succeeds
- the runtime emits a real channel-backed output event
- the launcher drains that event from the passthrough queue
- forwarding then stops only because no privileged bridge session was provided in that direct shell run

The next signed-app diagnostic then pushed one step further: with a helper-prepared privileged
bridge session, the launcher still started, injected input, and drained output successfully, but
forwarding failed with:

```text
Failed to connect to output bridge socket (13)
```

That identified the next KeyPath-side bug. The helper had been creating the experimental bridge
socket under the pqrs `rootonly` directory and then locking both the directory and socket down to
root-only permissions. That kept pqrs access privileged, but it also prevented the user-session
host from connecting to the bridge transport at all. The transport socket therefore needs to live
in a separate KeyPath-owned run directory that is connectable by the host, while the helper keeps
actual pqrs access root-only on the server side.

That is the current status line for the split-runtime migration:

- vendored Kanata startup is no longer the blocker
- processing-only passthrough runtime plus injected input can produce output
- the remaining production work is KeyPath-side:
  - supply real host-owned input capture
  - feed that into `keypath_kanata_bridge_passthru_send_input(...)`
  - continue forwarding drained output events through the privileged bridge
- the prior root-only pqrs readiness crash is **absent**

This is important progress. It means the vendored Kanata event loop no longer hard-calls pqrs sink
readiness from the user-session host. The migration is now blocked by a new, narrower failure mode
after startup rather than by the original architectural contradiction.

So the current state is:

- **resolved:** direct host-side `vhidd_server` crash caused by pqrs sink-readiness coupling
- **remaining:** determine the new `exit_code=6` path in the signed host-passthru diagnostic and
  continue KeyPath-side bridge/runtime integration from there

Further signed-app validation narrowed that new failure too. After the Kanata-side refactor, the
host diagnostic no longer exits immediately with code `6`; on a later rebuild it instead wedges
until timeout. A live stack sample of the running `kanata-launcher` process showed:

- the main thread sleeping inside the bounded passthrough poll loop
- the macOS input event-loop thread blocked in `wait_key`
- a background pqrs client thread aborting from:
  - `pqrs::karabiner::driverkit::virtual_hid_device_service::client::create_client()`
  - `find_server_socket_file_path()`
  - `glob(...)`
  - `std::__fs::filesystem::__status(...)`

This means the work is now past the original `karabiner_driverkit::is_sink_ready()` coupling, but
the host bridge / passthrough runtime is still indirectly instantiating the direct pqrs client in a
background thread. The next migration step is therefore even more specific:

- stop the host-owned passthrough runtime from constructing the direct pqrs client at all
- keep the user-session host on input capture + remapping only
- reserve all pqrs/VirtualHID client creation for the privileged output bridge

## Architectural implication

The host-runtime spike narrows the remaining design space:

### Rejected: all-user-space bundled host

Rejected because the current pqrs/Karabiner output path is not accessible from an unprivileged
user-session host process.

### Rejected: keep the whole runtime root-owned

Rejected because built-in keyboard capture and Input Monitoring are user-session concerns and the
existing permission mismatch remains unresolved under a single root-owned runtime.

### Preferred: split runtime

#### User-session input host

Responsibilities:

- stable app-bundled runtime identity
- Input Monitoring identity
- built-in keyboard capture
- config validation and runtime orchestration
- TCP server ownership (if kept in-process)

#### Privileged output bridge

Responsibilities:

- access pqrs VirtualHID root-only socket / service boundary
- emit remapped output events on behalf of the user-session input host
- no ownership of Input Monitoring detection or user guidance

## Candidate implementation shapes

### Option A: extend `KeyPathHelper` into an output bridge

Pros:

- existing privileged XPC path already exists
- avoids introducing another privileged binary immediately
- installation/repair ownership already lives here

Cons:

- `KeyPathHelper` is currently request/operation oriented, not a long-lived low-latency runtime
- would mix installer concerns and remapping output concerns into one service
- may complicate helper lifecycle and security boundaries

### Option B: add a dedicated privileged output companion

Pros:

- cleaner separation of runtime output from installer/repair
- easier to model as a narrow privileged bridge
- aligns better with the split-runtime direction in ADR-032

Cons:

- adds one more privileged packaged component
- requires new IPC contract and lifecycle management

## Recommended next step

Prefer **Option B** unless implementation friction proves too high.

Short reason:

- `KeyPathHelper` should stay focused on privileged mutations via `InstallerEngine`
- output bridging is runtime behavior, not installation behavior
- a dedicated privileged output companion gives a clearer boundary:
  - user host owns input/session/TCC
  - privileged companion owns pqrs output

## Latest progress

- The user-session passthru host now starts without constructing the direct pqrs client.
- Injected input successfully produces channel-backed output events in the bundled host.
- Those events now reach the privileged helper bridge and attempt real DriverKit emission.
- The current blocker has narrowed to privileged-side VirtualHID readiness:
  - `DriverKit virtual keyboard not ready (sink disconnected)`
- The helper now mirrors legacy Kanata startup more closely by:
  - activating the VirtualHID manager
  - polling DriverKit output readiness from the Rust bridge for a bounded interval
  - only then attempting bridged emit
- A prep-only signed-app bridge trigger now writes a fresh session/socket to:
  - `/var/tmp/keypath-host-passthru-bridge-env.txt`
- A direct packaged launcher run against that fresh session now proves:
  - forwarded output events reach the privileged bridge
  - explicit DriverKit sink initialization inside the helper bridge was the missing step
  - forwarded keyDown/keyUp events are now acknowledged by the privileged bridge
  - the split-runtime output path is functionally working for injected passthru input
- A later full experimental run against a fresh helper-prepared bridge session now proves the
  entire split path end to end:
  - the bundled user-session host captures real keyboard input
  - the passthrough Kanata runtime processes that input in-process
  - output events are emitted and drained from the passthrough queue
  - those output events cross the privileged helper bridge
  - the privileged bridge acknowledges emitted output events successfully

Example evidence from the packaged launcher:

- `Experimental passthru captured mac keyCode=55 -> usagePage=7 usage=227 value=1`
- `Experimental passthru runtime drained output event: value=1 page=7 code=227`
- `Experimental passthru forwarded output event ... -> acknowledged(sequence: Optional(1))`

and the same run continued successfully through many events, completing with:

- `Experimental passthru capture loop completed with 32 forwarded output event(s)`

This means the split-runtime architecture is no longer just a set of compatible seams. It is now
proven experimentally on this machine as a working end-to-end remapping path.

## Current blocker

- The main remaining gaps are now productionization and lifecycle hardening rather than basic
  feasibility.
- Specifically:
  - replace the rough experimental capture path with the intended long-term host input path
  - harden bridge-session lifecycle so fresh session prep is deterministic
  - decide whether privileged output remains in `KeyPathHelper` or moves to a dedicated companion
  - preserve and validate the legacy path while the split path remains gated
  - add sustained reliability validation before any production switch-over

That next experimental seam now exists too. `kanata-launcher` supports an opt-in host capture mode:

- `KEYPATH_EXPERIMENTAL_HOST_PASSTHRU_CAPTURE=1`

In that mode, the launcher:

- starts the processing-only passthrough runtime in-process
- installs a user-session macOS global keyboard monitor
- translates captured macOS virtual keycodes into HID usage page/code pairs
- injects those input events into `keypath_kanata_bridge_passthru_send_input(...)`
- continues draining and, if requested, forwarding emitted passthrough output through the
  privileged bridge during the same bounded run-loop window

This remains intentionally narrow:

- experimental and off by default
- currently backed by a minimal US ANSI virtual-keycode-to-HID mapping for early validation
- unsupported virtual keycodes are logged and ignored rather than guessed

That means the next phase can stay on the KeyPath side. The host runtime no longer depends only on
synthetic probe input, and there is now a real user-session input path feeding the bundled
passthrough runtime without reintroducing direct pqrs client creation into the host process.

A direct packaged-launcher validation now proves that capture seam is live. Running the signed
launcher with:

- `KEYPATH_EXPERIMENTAL_HOST_RUNTIME=1`
- `KEYPATH_EXPERIMENTAL_HOST_PASSTHRU_RUNTIME=1`
- `KEYPATH_EXPERIMENTAL_HOST_PASSTHRU_ONLY=1`
- `KEYPATH_EXPERIMENTAL_HOST_PASSTHRU_CAPTURE=1`

produced repeated logs of the form:

- `Experimental passthru captured mac keyCode=... -> usagePage=7 usage=... value=...`
- `Experimental passthru runtime drained output event: value=... page=7 code=...`

That establishes the next milestone:

- real user-session keyboard events are now being observed by the bundled host
- those events are translated into passthrough input
- the in-process Kanata runtime emits output in response

The signed-app diagnostics path can now opt into this same mode with:

- `KEYPATH_ENABLE_HOST_PASSTHRU_CAPTURE=1`

so the same host-passthru diagnostic runner can exercise either:

- synthetic injected probe input (default)
- or real user-session capture input (experimental)

One additional integration issue showed up once real capture was combined with privileged
forwarding: a stale helper-prepared bridge socket can fail with:

- `Output bridge socket at /Library/KeyPath/run/kpko/... is stale or not listening. Prepare a fresh bridge session and try again.`

That does **not** indicate that capture or passthrough processing is broken. In the verified run,
the launcher still:

- captured real macOS key events
- injected them into the passthrough runtime
- drained real output events

and only failed at the point of connecting to an old helper bridge socket whose listener was no
longer active.

To make fresh session preparation easier from an already-running signed app, KeyPath now supports a
debug URL action:

- `keypath://system/prepare-host-passthru-bridge`

That action reuses the same helper-backed preparation path as the startup/file-triggered prep
mode and rewrites:

- `/var/tmp/keypath-host-passthru-bridge-env.txt`

with a fresh `session=` / `socket=` pair for the next direct launcher probe.

There is now a second running-app debug action too:

- `keypath://system/run-host-passthru-diagnostic`
- `keypath://system/run-host-passthru-diagnostic?capture=1`

That action runs the signed-app host-passthru diagnostic in place, including fresh bridge-session
preparation, and writes the result to:

- `/var/tmp/keypath-host-passthru-diagnostic.txt`

This reduces the need for relaunch/env-driven validation when exercising the experimental split
runtime from an already-running app.

That running-app diagnostic path has now been verified on the live machine in injected-input mode.
After clearing the prior output file and triggering:

- `keypath://system/run-host-passthru-diagnostic`

the app wrote a fresh diagnostic showing:

- passthrough runtime startup succeeded
- injected keyDown/keyUp input succeeded
- the runtime drained two output events for `A`
- both events were forwarded over the privileged bridge and acknowledged

The resulting stderr block ended with:

- `Experimental passthru forwarded output event ... -> acknowledged(sequence: Optional(1))`
- `Experimental passthru forwarded output event ... -> acknowledged(sequence: Optional(2))`
- `Experimental passthru runtime forwarded 2 output event(s)`

So the running-app diagnostic action is now a valid signed-context validation path for the
experimental split runtime, not only the earlier direct launcher probes.

The helper/session lifecycle has now been hardened slightly too:

- preparing a new bridge session for the same host PID retires any older prepared/active sessions
- preparing a new bridge session also retires sessions whose owning host PID is no longer alive
- retired sessions unlink their old socket path so stale listeners do not accumulate indefinitely
- client-side connect failures now distinguish:
  - missing socket path
  - stale/non-listening socket
  - generic connect failure

That does not eliminate the need for a fresh session before direct launcher probes, but it turns
the failure mode into an explicit bridge-session lifecycle problem instead of an ambiguous transport
error.

## Immediate coding milestones

1. Expand the new session descriptor contract into a real output bridge protocol.
2. Make the experimental bundled host fail by design unless that output bridge is available.
3. Keep the legacy `/Library/KeyPath/bin/kanata` path as fallback while the split path is proven.
4. Once the split bridge can emit output, move Input Monitoring guidance to the bundled host
   identity and stop treating `/Library/KeyPath/bin/kanata` as the long-term permission target.

## Dedicated Companion Milestone (2026-03-08)

The experimental privileged output bridge has now been split out of `KeyPathHelper` into a
dedicated system daemon:

- label: `com.keypath.output-bridge`
- executable:
  `/Applications/KeyPath.app/Contents/Library/HelperTools/KeyPathOutputBridge`
- installed plist:
  `/Library/LaunchDaemons/com.keypath.output-bridge.plist`

The live machine validation for this milestone was:

1. deploy a build with the new `KeyPathOutputBridge` target embedded in the app bundle
2. refresh the embedded privileged helper so its XPC implementation knows how to install/bootstrap
   the new daemon
3. trigger `keypath://system/prepare-host-passthru-bridge`
4. confirm:
   - `/Library/LaunchDaemons/com.keypath.output-bridge.plist` exists
   - `launchctl print system/com.keypath.output-bridge` reports the daemon
5. rerun the signed host-passthru diagnostic and confirm forwarded output is still acknowledged

Verified result:

- the helper now prepares sessions and bootstraps the daemon instead of owning the runtime bridge
- `launchctl print system/com.keypath.output-bridge` reported the service `running`
- the signed host diagnostic still succeeded end to end:
  - passthru runtime startup
  - emitted output events
  - socket forwarding into the privileged daemon
  - privileged acknowledgements

This is the first end-to-end validation of the intended long-term process shape:

- `KeyPath.app`: orchestration, diagnostics, permission UX
- `kanata-launcher`: user-session input host
- `KeyPathOutputBridge`: privileged VirtualHID output daemon
- `KeyPathHelper`: installer/repair/orchestration only

The next remaining work is production hardening rather than basic architecture proof:

- automatic bridge-session refresh
- companion restart/recovery behavior
- inspection/reporting polish
- deciding when the split runtime should become selectable beyond debug flows
- runtime-path selection now requires the dedicated companion to be healthy before choosing split
  runtime; an installed-but-unhealthy companion explicitly falls back to the legacy system binary

The helper-side activation path now also treats daemon startup failure as a recoverable condition:

- if `activateKanataOutputBridgeSession(...)` fails to observe the session socket after kickstart,
  the helper boots the companion out, reinstalls/rebootstraps the launchd service, and retries the
  session activation once before reporting failure

This keeps stale or wedged `com.keypath.output-bridge` state aligned with the same recovery posture
already used for stale install/registration state elsewhere in KeyPath.

The signed host-passthru diagnostic path now also refreshes the reusable bridge-session file on
every run:

- each diagnostic invocation prepares a fresh companion session
- the session/socket used for that invocation is written back to
  `/var/tmp/keypath-host-passthru-bridge-env.txt`

That removes the old requirement to run bridge prep as a separate manual step before direct
launcher probes.

The bridge-session prep logic is now centralized in the app-side companion manager, so both:

- `keypath://system/prepare-host-passthru-bridge`
- `keypath://system/run-host-passthru-diagnostic`

go through the same fresh-session preparation and persistence path instead of maintaining separate
implementations.

The signed host diagnostic no longer owns its own child-process launch logic either. That launch
path is now extracted into an internal app-side split-runtime host service, so diagnostics is using
the same reusable host-launch primitive that future non-diagnostic split-runtime startup can adopt.

There is now also a persistent experimental host mode behind the internal action surface:

- `keypath://system/start-host-passthru?capture=1`
- `keypath://system/stop-host-passthru`

This is not the production startup path yet, but it gives the app its first reusable non-diagnostic
split-runtime host launcher without falling back to the legacy launchd-managed Kanata binary.

The next integration step then moved into the normal runtime coordinator:

- `RuntimeCoordinator` checks the runtime-path evaluator first
- if the evaluator returns split-runtime-ready, the coordinator starts the persistent bundled host
  instead of the old launchd-managed Kanata daemon
- `stopKanata(...)` and `restartKanata(...)` now also understand the persistent split-runtime host
- later cutover work removed the user-facing split-runtime toggle and made split runtime the fixed
  normal architecture in the app rather than an experimental setting

This keeps the production default unchanged while creating the first real app-owned start/stop path
that can exercise split runtime outside of debug-only direct actions.

The main Status tab now also exposes the active runtime path when one is known:

- `Split Runtime Host` when the persistent bundled host is active
- `Legacy Daemon` when the launchd-managed Kanata service is active

That makes the feature-flagged path choice visible in normal app UI instead of only in logs,
diagnostics, or debug actions.

`inspectSystem()` / `SystemContext.services` now also carries the active runtime path when one is
known, so shared status/installer surfaces can distinguish:

- `Split Runtime Host`
- `Legacy Daemon`

without relying on a view-model-only side channel.

The CLI now prints that active runtime path too, so:

- app Status UI
- shared `inspectSystem()` / `SystemContext`
- `keypath-cli status`

all report the same runtime identity vocabulary.

The persistent split-runtime host now also has an explicit unexpected-exit path:

- `KanataSplitRuntimeHostService` posts a `splitRuntimeHostExited` notification with pid, exit code,
  termination reason, expected-vs-unexpected classification, and stderr log path
- `RuntimeCoordinator` consumes that notification, stops `AppContextService`, and surfaces a
  direct recovery error instead of silently reviving the old launchd runtime
- the error explicitly tells the user that KeyPath no longer auto-falls back to the legacy daemon
  and that toggling the service again will restart the split runtime host
- shared status inspection and CLI reporting no longer carry a separate automatic-fallback identity
  because automatic fallback has been removed

The runtime coordinator now has direct regression coverage for split-runtime lifecycle churn too:

- test-only seams can force the runtime-path evaluator to choose split runtime
- test-only seams can simulate a persistent split host PID without starting the real bundled host
- coordinator tests now cover split-runtime `start -> restart -> stop` cycles and verify that:
  - active runtime-path reporting stays on `Split Runtime Host` while the host is active
  - stopping clears the active runtime-path detail cleanly
  - a later successful split-runtime recovery clears the prior exit error cleanly
- expected exits (for example, an intentional stop) do not set a recovery error
- unexpected exits now fail loudly instead of silently switching runtime paths

This is the first automatic recovery path from a live split-runtime failure into the older
launchd-managed runtime, while still keeping the transition visible in UI/CLI status.

To validate real signed-app churn against the persistent split host, the running app now exposes a
small internal exercise action:

- `keypath://system/exercise-host-passthru-cycle`
- `keypath://system/exercise-host-passthru-cycle?capture=0`

That action runs the same `KanataSplitRuntimeHostService` path used by the persistent host launcher,
performs a simple `start -> stop -> start -> stop` sequence, and writes the result to:

- `/var/tmp/keypath-host-passthru-cycle.txt`

This is still a debug/validation surface, not intended user-facing UX, but it provides a live
signed-app churn probe that complements the newer coordinator/unit-test lifecycle coverage.

There is now also a matching companion-side churn probe:

- `keypath://system/exercise-output-bridge-companion-restart`
- `keypath://system/exercise-output-bridge-companion-restart?capture=0`

That action:

- starts the persistent split-runtime host
- restarts the dedicated `com.keypath.output-bridge` daemon through the helper orchestration path
- records companion status before and after restart
- stops the host again

It writes the result to:

- `/var/tmp/keypath-host-passthru-companion-restart.txt`

This is still a validation-only surface. Its purpose is to exercise real signed-app daemon churn
without reintroducing output-runtime ownership into `KeyPathHelper`.

Because the running app can accumulate stale instances during desktop automation, there is also now
a deterministic one-shot startup hook in `App.swift` for the same probe:

- `KEYPATH_EXERCISE_OUTPUT_BRIDGE_COMPANION_RESTART=1`
- optional: `KEYPATH_ENABLE_HOST_PASSTHRU_CAPTURE=1`

When the signed app is launched directly with that environment, it runs the same companion restart
probe and exits, writing:

- `/var/tmp/keypath-host-passthru-companion-restart.txt`

This gives us a validation path that does not depend on `open keypath://...` reaching a healthy
already-running app instance.

There is now also a longer-lived soak probe for the persistent split host:

- `keypath://system/exercise-host-passthru-soak`
- `keypath://system/exercise-host-passthru-soak?capture=0&seconds=30`

That action:

- starts the persistent split host
- keeps it running for the requested duration
- records whether the host was still alive at the end of the soak
- records companion health before and after the soak
- stops the host and writes:

- `/var/tmp/keypath-host-passthru-soak.txt`

This gives us a signed-app validation path for “does the split host stay alive under time” that
is distinct from start/stop churn and daemon-restart recovery.

Live signed-app soak result on March 8, 2026:

```text
host_pid=47971
capture=true
duration_seconds=30
companion_running_before=true
host_alive_at_end=true
host_pid_at_end=47971
companion_running_after=true
host_stopped=1
```

This means the persistent split host survived a 30-second capture-mode run without losing the
dedicated output companion or crashing out of the host-owned runtime path.

There is now also a combined soak + companion-restart validation surface:

- `keypath://system/exercise-output-bridge-companion-restart-soak`
- `keypath://system/exercise-output-bridge-companion-restart-soak?capture=1&seconds=30`

That action:

- starts the persistent split host
- waits through the first half of the requested duration
- restarts the dedicated `com.keypath.output-bridge` daemon
- rehydrates the host onto a fresh bridge session
- waits through the second half of the requested duration
- reports whether the host and companion are still alive at the end
- writes:

- `/var/tmp/keypath-host-passthru-companion-restart-soak.txt`

This gives us a live signed-app probe for “does the split host survive a daemon restart in the
middle of a longer capture run,” which is a closer approximation of production churn than the
earlier instantaneous restart probe.

After fixing deploy order, refreshing the live helper registration, and increasing the app-side
activation timeout for `activateKanataOutputBridgeSession(...)`, the combined restart-soak probe
now passes in the signed app too. Live result on March 8, 2026:

```text
companion_running_before=true
capture=true
duration_seconds=20
host_pid=63501
companion_restarted=1
companion_running_after_restart=true
host_recovered=1
host_pid_after_recovery=63578
host_alive_at_end=true
host_pid_at_end=63578
companion_running_after=true
host_stopped=1
```

This means the split host can now survive:

- a mid-run restart of the dedicated `com.keypath.output-bridge` daemon
- bridge-session invalidation and reactivation
- rehydration onto a fresh persistent host process
- the remainder of the soak window after recovery

The recovery flow is no longer probe-only glue. `KanataSplitRuntimeHostService` now owns a reusable
`restartCompanionAndRecoverPersistentHost()` operation, which:

- restarts the dedicated companion
- confirms companion running state after restart
- restarts and rehydrates the active persistent split host onto a fresh bridge session

That gives the app a real production-oriented seam for “output companion restarted, recover the
split host” rather than keeping that behavior trapped inside `ActionDispatcher` probes.

The next step after proving that recovery path in probes was to wire it into the normal app
lifecycle. `RuntimeCoordinator` now runs a lightweight split-runtime companion monitor while the
app is active:

- if the persistent split host is not running, the monitor does nothing
- if the split host is active and the dedicated output companion reports healthy, the monitor does nothing
- if the split host is active and the companion is no longer running, the coordinator now first tries
  the same `restartCompanionAndRecoverPersistentHost()` flow that the restart-soak probe validated
- only if that recovery fails does the coordinator fall back to the legacy daemon path

So the app now has the first non-probe path for “companion disappeared while split runtime was
active, try split recovery before declaring failure or forcing legacy fallback.”

To validate that this is not just dead code, the app now also exposes a signed-app action that
exercises the real `RuntimeCoordinator.startKanata(...)` path with split runtime enabled, restarts
the dedicated companion, waits for the normal lifecycle handling, and records the result:

- `keypath://system/exercise-coordinator-split-runtime-recovery`
- writes `/var/tmp/keypath-runtime-coordinator-companion-recovery.txt`

Live result on March 8, 2026:

```text
split_runtime_flag_before=false
split_runtime_flag_forced=true
coordinator_start_success=true
runtime_path_after_start=Split Runtime Host
runtime_detail_after_start=Bundled user-session host active (PID 79495) with privileged output companion
companion_running_before=true
companion_restarted=1
runtime_path_after_recovery=Split Runtime Host
runtime_detail_after_recovery=Bundled user-session host active (PID 79495) with privileged output companion
last_error=none
last_warning=none
split_host_running_after_recovery=true
split_host_pid_after_recovery=79495
companion_running_after=true
cleanup_complete=1
```

This is stronger than the earlier service-level probes because it shows the normal coordinator path
can start in split-runtime mode, survive a dedicated output-daemon restart, remain on `Split Runtime Host`,
and finish without surfacing an app error or falling back to the legacy daemon.

To move beyond a single restart event and validate that the normal coordinator-managed path can
survive a longer mid-run recovery window, the app now exposes a second signed-app probe:

- `keypath://system/exercise-coordinator-split-runtime-restart-soak`
- supports `?seconds=20`
- writes `/var/tmp/keypath-runtime-coordinator-companion-restart-soak.txt`

This probe:

- temporarily enables the split-runtime feature flag
- starts Kanata through `RuntimeCoordinator.startKanata(...)`
- waits for the first half of the soak duration
- restarts `com.keypath.output-bridge`
- waits for the second half of the soak duration
- records the active runtime path, companion state, and any recovery warnings/errors
- cleans up via `RuntimeCoordinator.stopKanata(...)`

Live result on March 8, 2026:

```text
split_runtime_flag_before=false
split_runtime_flag_forced=true
duration_seconds=20
coordinator_start_success=true
runtime_path_after_start=Split Runtime Host
runtime_detail_after_start=Bundled user-session host active (PID 83186) with privileged output companion
companion_running_before=true
companion_restarted=1
runtime_path_after_soak=Split Runtime Host
runtime_detail_after_soak=Bundled user-session host active (PID 83186) with privileged output companion
last_error=none
last_warning=none
split_host_running_after_soak=true
split_host_pid_after_soak=83186
companion_running_after=true
cleanup_complete=1
```

This is the strongest split-runtime validation so far. It shows that the normal
`RuntimeCoordinator` path can:

- start in split-runtime mode
- survive a mid-run dedicated output-daemon restart
- remain on `Split Runtime Host` for the rest of a 20-second soak
- avoid surfacing either an app error or a legacy fallback warning
- stop cleanly afterward

The same coordinator-managed restart-soak probe was then rerun with a longer duration:

- `keypath://system/exercise-coordinator-split-runtime-restart-soak?seconds=60`

Live result on March 8, 2026:

```text
split_runtime_flag_before=false
split_runtime_flag_forced=true
duration_seconds=60
coordinator_start_success=true
runtime_path_after_start=Split Runtime Host
runtime_detail_after_start=Bundled user-session host active (PID 83938) with privileged output companion
companion_running_before=true
companion_restarted=1
runtime_path_after_soak=Split Runtime Host
runtime_detail_after_soak=Bundled user-session host active (PID 83938) with privileged output companion
last_error=none
last_warning=none
split_host_running_after_soak=true
split_host_pid_after_soak=83938
companion_running_after=true
cleanup_complete=1
```

This longer run matters because it reduces the chance that the 20-second result was simply
capturing a narrow lucky window around restart timing. The normal coordinator-managed split
runtime remained healthy for a full minute, survived the mid-run companion restart, never dropped
to the legacy daemon path, and exited cleanly.

Given the green clean-install path, the green coordinator-managed recovery probe, and the green
60-second restart-soak run, split runtime was then promoted from “default-on” to “always-on” in
the app:

- the user-facing `Split Runtime Host` toggle was removed
- the old split-runtime feature flag was removed entirely; split runtime is now always on in the app
- ordinary startup and restart no longer use the legacy daemon path when split runtime is enabled
- the legacy daemon remains available only as a narrow recovery seam while final deletion work
  proceeds

This shifts KeyPath from “split runtime is opt-in even on a healthy clean machine” to “split
runtime is the only ordinary runtime path, with legacy retained only as a short-lived emergency
recovery seam.”

The next cleanup pass then removed the last hidden launchd-era fast path from ordinary app and CLI
flows:

- `ProcessCoordinator` was deleted from the main app/runtime code
- CLI repair stopped trying a `KanataService`/`ProcessCoordinator` restart before
  `InstallerEngine`
- tests stopped pretending the split-runtime flag can still be toggled on and off

At this point, the remaining work is no longer proving the architecture. The remaining work is
production-hardening:

- longer soak runs
- more restart/recovery churn
- deciding when the split-runtime feature flag is ready for broader internal enablement
- eventually defining exit criteria for removing the legacy daemon path

To reduce churn from direct app-binary launches during development, normal `KeyPath.app` startup
now enforces a single-instance rule:

- one normal UI app process is allowed
- later duplicate normal launches activate the existing app and terminate immediately
- one-shot probe modes (helper repair, host diagnostics, companion restart probe) remain exempt

This does not clean up previously wedged processes, but it prevents new normal launches from
silently piling on more stale UI instances.

The host-passthru diagnostic also no longer treats `exit_code=0` as sufficient on its own.
It now marks the diagnostic as failed if launcher stderr shows split-runtime forwarding failed,
for example when the output bridge socket is stale or not listening.

Fresh-install wizard retries also exposed a recovery gap in
`PrivilegedOperationsCoordinator.installBundledKanata()`: if Kanata already had
`SMAppService` registration metadata but no live runtime, the installer would reinstall the
binary and then fail strict readiness with:

- `Bundled Kanata install postcondition failed: Kanata did not become running + TCP responsive within readiness timeout`

That path now treats `SMAppService active but runtime down` as a recovery case instead of a
terminal install failure. After installing the bundled binary, it calls
`restartUnhealthyServices()` before readiness verification when the service is already active.
The app log now records the expected recovery markers:

- `Bundled Kanata installed while SMAppService was already active; restarting unhealthy services before readiness verification`
- `Bundled Kanata install recovered runtime via restartUnhealthyServices`

This keeps the installer aligned with the invariant that registration is not liveness:
install/repair flows must converge on a running + TCP-responsive runtime before returning
success.

Promoting split runtime to the default on fresh installs then exposed one real rollout bug:
if the legacy daemon was already running, `RuntimeCoordinator.startKanata(...)` could select
split runtime without actually cutting over. The app would keep the legacy daemon alive and
never hand input/runtime ownership to the bundled host.

That cutover behavior is now fixed. When split runtime is selected and the legacy daemon is
already active, the coordinator now:

- stops the legacy daemon first
- refreshes service state
- stops `AppContextService`
- then starts the persistent bundled host

Live app logging on March 8, 2026 showed the expected cutover sequence:

- `Split runtime host selected: bundled host can own input runtime and privileged output bridge is required ...`
- `Split runtime selected while legacy daemon is active - stopping legacy daemon before cutover`
- `Started split-runtime host (PID 88000)`

That moved default-on split runtime from “preferred in theory” to “actually able to replace the
legacy daemon on a live app instance.”

The next observability gap showed up immediately afterward: the split host could stay green under
coordinator-managed restart-soak, but the app’s TCP event listener still saw repeated
`Connection refused` failures. The root cause was two-part:

- the passthru runtime was being created without a TCP port in the Swift bridge call
- even after plumbing the TCP port through, the passthru start path still started only the
  processing loop and never started the TCP server / notification loop

Both halves are now fixed:

- `KanataSplitRuntimeHostService` passes the normal inherited Kanata arguments to the bundled
  host, including `--cfg` and `--port 37001`
- the Rust passthru runtime now starts the TCP server and notification loop without reintroducing
  the macOS DriverKit event loop in the user-session host

Live validation on March 8, 2026 confirmed the result during a coordinator-managed restart-soak:

```text
COMMAND     PID    USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
kanata-la 98590 malpern    6u  IPv4 ...               0t0  TCP 127.0.0.1:37001 (LISTEN)
```

And the same run completed green:

```text
duration_seconds=20
coordinator_start_success=true
runtime_path_after_start=Split Runtime Host
runtime_detail_after_start=Bundled user-session host active (PID 98590) with privileged output companion
companion_restarted=1
runtime_path_after_soak=Split Runtime Host
last_error=none
last_warning=none
split_host_running_after_soak=true
companion_running_after=true
cleanup_complete=1
```

This is the first point where the split-runtime host satisfied both requirements simultaneously:

- normal runtime-path recovery remained green under coordinator-managed companion restart
- the host also exposed the expected TCP event socket used by the rest of the app

That materially reduces the remaining gap between “experimental architecture that works” and
“runtime path that can plausibly replace the legacy daemon for normal internal use.”

The next question was whether the now-corrected split host would stay healthy for a longer
coordinator-managed run while the rest of the app actually consumed its TCP event stream.

Live validation on March 8, 2026 answered that positively with a 180-second restart-soak run:

```text
duration_seconds=180
coordinator_start_success=true
runtime_path_after_start=Split Runtime Host
runtime_detail_after_start=Bundled user-session host active (PID 455) with privileged output companion
companion_restarted=1
runtime_path_after_soak=Split Runtime Host
runtime_detail_after_soak=Bundled user-session host active (PID 455) with privileged output companion
last_error=none
last_warning=none
split_host_running_after_soak=true
companion_running_after=true
cleanup_complete=1
```

During that same run the bundled host was confirmed to be listening on the normal event port:

```text
COMMAND   PID    USER   FD   TYPE ... NAME
kanata-la 455 malpern    6u  IPv4 ... TCP 127.0.0.1:37001 (LISTEN)
```

And the app-side event listener no longer showed `Connection refused` churn. Instead it
established and held a real session against the split host:

- `Connected to kanata TCP server`
- `EventListener session_start session=105 port=37001 ...`
- `HelloOk ... capabilities ...`
- repeated `CurrentLayerName` responses over the same active session

This matters because it upgrades the split-runtime result from “the host survives and the daemon
recovers” to “the host survives, the daemon recovers, and the rest of the app is actually using
the split host’s live TCP surface successfully during the run.”

At this point the remaining work is not architectural feasibility. The remaining work is rollout
confidence:

- longer-lived soaks
- more real-world churn
- deciding when the legacy daemon should stop being the default fallback for internal use

That longer-lived confidence was then extended to a full 300-second coordinator-managed
restart-soak on March 8, 2026:

```text
duration_seconds=300
coordinator_start_success=true
runtime_path_after_start=Split Runtime Host
runtime_detail_after_start=Bundled user-session host active (PID 2160) with privileged output companion
companion_restarted=1
runtime_path_after_soak=Split Runtime Host
runtime_detail_after_soak=Bundled user-session host active (PID 2160) with privileged output companion
last_error=none
last_warning=none
split_host_running_after_soak=true
companion_running_after=true
cleanup_complete=1
```

The more important runtime signal was not just the green result file. Mid-run verification showed:

- the bundled host still listening on `127.0.0.1:37001`
- the app-side `KanataEventListener` continuously receiving `CurrentLayerName` responses over
  the same active session
- no `Connection refused` churn during the active soak window

That makes the split-runtime path materially more trustworthy than it was even one iteration
earlier:

- runtime selection is now default-on for fresh installs
- live cutover from legacy to split runtime works
- coordinator-managed daemon restart recovery works
- the host exposes the expected TCP surface
- and the rest of the app remains attached to that surface for a sustained 5-minute run

The remaining work now looks much more like product rollout work than runtime invention:

- broader internal enablement
- explicit deprecation criteria for the legacy daemon
- installer/upgrade behavior once split runtime is the normal path rather than a guarded one

Further cutover progress after that milestone:

- Normal startup now fails loudly if split runtime is selected but the split host cannot start.
  Automatic fallback to the legacy daemon has been removed from ordinary startup and from
  unexpected split-host exit handling.
- Ordinary user-facing restart paths now go through `startKanata(...)` / `restartKanata(...)`
  instead of generic legacy-heavy restart helpers. That includes notification retry, wizard
  service start and restart, permission-grant restart, diagnostics auto-fix restart, and
  default-config reload fallback.
- `restartKanata(...)` itself now treats “split runtime is preferred and healthy” as a cutover
  opportunity. Even if the app is currently running on the legacy daemon, an ordinary restart
  now stops the old path and brings the app back up on the split runtime host.
- RecoveryCoordinator restart operations now route through `restartKanata(...)` too, which means
  keyboard-recovery and resume-after-recording flows prefer the split runtime host instead of
  always reviving the legacy daemon.
- Status/reporting vocabulary now reflects the intended role of the old path. UI and installer
  summaries label it as `Legacy Recovery Daemon` instead of `Legacy Daemon`, which better matches
  the current cutover goal: split runtime is the normal path, and launchd-managed Kanata is an
  emergency recovery fallback.
- Wizard/runtime UI status no longer depends on `RecoveryDaemonService.ServiceState` as its primary
  contract. The coordinator now exposes a split-runtime-first `RuntimeStatus`, and pages that
  need to know whether KeyPath is really running query that directly instead of forcing the split
  host through a legacy daemon enum.
- The wizard no longer treats `kanataService` and `launchDaemonServices` as ordinary Kanata
  component issues. Runtime-not-running belongs to the runtime page, and launchd-managed services
  are now described explicitly as legacy recovery services instead of being mixed into the normal
  split-runtime install story.
- Repair action determination no longer treats “runtime not running” as a reason to reinstall
  service configuration. Installer repair only touches the launchd-based recovery seam when those
  recovery services are actually missing or unhealthy.
- Runtime-down issues no longer misdiagnose a stopped split runtime as a recovery-service install
  problem. `SystemContextAdapter` now surfaces `KeyPath Runtime Not Running` without an auto-fix
  action, `IssueGenerator` no longer maps `.kanataService` to
  `.installLaunchDaemonServices`, and the Kanata components page now describes that state as
  `KeyPath Runtime is not running` instead of `background runtime configuration required`.
- Core readiness no longer depends on the legacy recovery daemon. `ComponentStatus.hasAllRequired`
  now requires the real split-runtime prerequisites — Kanata binary, driver, daemon, healthy VHID
  services, and no version mismatch — but intentionally excludes
  `launchDaemonServicesHealthy`. The recovery daemon remains visible for diagnostics and repair,
  but it is no longer embedded in the definition of “system ready.”
- Fresh-install planning is less daemon-first too. `ActionDeterminer.determineInstallActions`
  no longer unconditionally appends `.installLaunchDaemonServices`; it now only adds that action
  when the privileged service layer is actually unhealthy. That keeps the legacy recovery seam
  from being treated as a mandatory first-class install step once the split runtime is the normal
  architecture.

- 2026-03-08: Renamed the remaining planner/action seam from `installLaunchDaemonServices` to `installLegacyRecoveryServices`, so the installer and wizard now describe the old launchd path as recovery-only in code as well as UI.
- 2026-03-08: Renamed the core validator/model field from `launchDaemonServicesHealthy` to `legacyRecoveryServicesHealthy` and renamed the wizard issue/component identifier from `.launchDaemonServices` to `.legacyRecoveryServices`. That pushes the old launchd-managed seam one level deeper out of the normal runtime model: it is still visible for recovery, but it is no longer named like a first-class launch path in system snapshots or wizard issues.
- 2026-03-08: Ordinary install and repair planning no longer schedule `installLegacyRecoveryServices`, and the wizard no longer suggests that action as a normal-path fix. That leaves the old launchd seam as an internal recovery implementation rather than a user-facing install/repair step.
- 2026-03-08: Deleted the explicit `installLegacyRecoveryServices` auto-fix action and installer recipe. The low-level recovery implementation still exists underneath for orphaned-process adoption and replacement, but the planner, wizard, and public installer action surface no longer advertise a first-class “install legacy recovery services” step.
- 2026-03-08: Removed the generic `installLegacyRecoveryServices()` broker/coordinator surface entirely. Ordinary installer logic now uses `installRequiredRuntimeServices()` for normal service install, while orphaned-process handling routes through the narrower remaining recovery hooks instead of a broad legacy launchd install method.
- 2026-03-08: Deleted the orphan adoption/replacement path entirely. External Kanata is now treated as a plain conflicting process to terminate, the `installLegacyRecoveryServicesWithoutLoading()` helper/XPC/coordinator seam is gone, and the focused installer, wizard, runtime, CLI, and diagnostics suites are green with the simplified model.
- 2026-03-08: Removed the last visible `legacyRecoveryServices` issue from the wizard and status model. The split-runtime app no longer routes users through a fake legacy recovery services problem during normal setup or status review; the remaining restart mechanism is now purely an internal recovery implementation detail.
- 2026-03-08: Renamed the remaining internal recovery seam from `legacyRecoveryServicesHealthy` to `recoveryServicesHealthy` and from `restartUnhealthyServices` to `recoverRuntimeServices`. The final stale `legacyRecoveryServices` / `legacyRecoveryServicesUnhealthy` issue identifiers were then deleted entirely. At this point the old launchd path is no longer represented as a normal wizard/runtime issue type at all; what remains is deeper internal recovery logic and naming, not a co-equal runtime model.
- 2026-03-08: Deleted the public `recoverRuntimeServices` installer/wizard action entirely, deleted the dead `ProcessManager` / `PrivilegedOperationsProvider` transitional stack, and then renamed the remaining internal recovery seam to `recoverRequiredRuntimeServices`. At this point the old launchd-era recovery path is no longer part of the public installer/planner model and is only represented as a narrow internal runtime-repair seam.
- 2026-03-08: Deleted the dead generic `installLaunchDaemon` privileged broker/XPC surface and removed the unused private bulk-launchd helpers from `PrivilegedOperationsCoordinator`. The split-runtime architecture no longer carries a public low-level “install arbitrary launchd service” seam from the older runtime model; only the narrower required-runtime and internal recovery operations remain.
- 2026-03-08: Deleted `recoveryServicesHealthy` from `SystemSnapshot.ComponentStatus` too. The field had become dead bookkeeping after readiness, planning, and wizard routing stopped depending on the old launchd path. The remaining recovery seam now lives in explicit recovery operations, not in the core system-readiness model. Runtime/status surfaces also now say `Recovery Daemon` instead of `Legacy Recovery Daemon`.
- 2026-03-08: Deleted the dead `ServiceBootstrapper.installAllServicesWithoutLoading(...)` path and the last unused private `sudoInstallLaunchDaemon(...)` helper. Both were leftovers from the older launchd adoption/install model and had no remaining callers once orphan adoption and generic launchd installation were removed.
- 2026-03-08: Deleted the dead `KanataService.start()` / `restart()` path and the associated cooldown/start-attempt bookkeeping wrappers. `KanataService` is now a much narrower wrapper around legacy recovery-daemon stop/status/health behavior instead of pretending to be a co-equal runtime lifecycle manager.
- 2026-03-08: Moved `ServiceHealthMonitor` ownership out of `KanataService` and into `DiagnosticsManager`. Runtime health checks and VirtualHID connection-failure tracking are now modeled directly around the split host, while `KanataService` is reduced further toward a small on-demand recovery-daemon utility.
- 2026-03-08: Demoted `KanataService` and its state/error types from public API to internal module-only helpers. It is no longer exposed like a first-class runtime service; it now reads more honestly as an internal recovery-daemon utility used by the app itself.
- 2026-03-08: Corrected product naming toward a layered model: the UI now presents the normal path as `KeyPath Runtime`, while keeping `Kanata` visible for engine setup, engine permissions, engine binary/version details, and other low-level technical surfaces where the underlying engine identity is actually useful.
- 2026-03-08: Renamed the remaining wizard/status component identifier from `.kanataService` to `.keyPathRuntime`. The planner and status model no longer carry the old daemon-era component name for “runtime missing”; that concept now matches the split-runtime architecture internally as well as in user-facing text.
