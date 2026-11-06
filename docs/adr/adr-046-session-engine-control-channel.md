# ADR-046: Session Engine Control Channel

**Status:** Proposed
**Date:** 2026-11-04
**Supersedes (when accepted):** [ADR-013](adr-013-tcp-without-auth.md)
**Tracking:** [#1354](https://github.com/malpern/KeyPath/issues/1354) (release-blocker)

## Context

ADR-013 accepted an unauthenticated JSON control port on `127.0.0.1:37001`. The
engine behind it was a root daemon, and the risk was written up as "any local
process can send commands … low security impact".

ADR-045 retired that daemon. The engine now runs inside the session worker, an
unprivileged process in the user's session that holds the user's Accessibility
and Input Monitoring grants. It still opens the same port:
`Rust/KeyPathKanataHostBridge` passes the port to
`kanata_state_machine::SocketAddrWrapper::from_str`, which binds
`127.0.0.1:<port>`, and starts the fork's `TcpServer` and notification loop.

Loopback TCP is not scoped to a user, to a code signature, or to the App Sandbox.
Any process on the Mac that can open a socket can connect. That includes
processes of other logged-in users and sandboxed apps that hold
`com.apple.security.network.client`. The server does no authentication of any
kind. Every accepted connection joins the broadcast set before it has sent a
byte.

As of 2026-11-04, facts below were read from the fork at `External/kanata`, at `d9085a9`, the
commit KeyPath `master` (`e42ffea0`) pins, and from KeyPath at that commit.
`d9085a9` is on `keypath/bundled`: the branch tip `54cdba9` merges it, with
an identical tree. They were not exercised on a
live install for this ADR.

### What a connected client can do

Commands the server accepts (`tcp_protocol/src/lib.rs`, `ClientMessage`):

| Command | Effect | Used by KeyPath |
|---|---|---|
| `Hello` | Version and capability list | Yes |
| `RequestLayerNames`, `RequestFakeKeyNames`, `RequestCurrentLayerName` | Read layer and virtual-key names | Yes |
| `RequestCurrentLayerInfo` | Returns the current layer's **config text** | Yes (overlay/inspector) |
| `RequestInputGrab` | Read whether input is seized, and which devices | Yes |
| `ChangeLayer { new }` | Switch the active layer | Yes |
| `ActOnFakeKey { name, action }` | Press, release, tap or toggle any virtual key defined in the loaded config. A virtual key runs whatever the config binds to it: key output, macros, layer changes, `push-msg` | Yes (`keypath://fakekey`, inspector) |
| `SetMouse { x, y }` | Move the pointer to absolute coordinates | No |
| `Reload`, `ReloadNext`, `ReloadPrev`, `ReloadNum` | Reload or switch between known configs | `Reload` only |
| `ReloadFile { path }` | Load **any existing file the worker can read** as the active config (`request_live_reload_file`) | No |

Anything else, including KeyPath's own `SubscribeHrmTrace`, fails to
deserialize and closes the connection. That request is sent only when `Hello`
advertises `hrm-trace`, which this fork does not.

Events broadcast to **every** connected client (`Kanata::start_notification_loop`):

- `KeyInput { key, action, t }` for every physical key press, release and repeat
  (`emit_key_input`, called for every event in the processing loop). Together
  with timestamps this is a keystroke log of everything typed outside
  Secure Input contexts.
- `LayerChange`, `HoldActivated`, `TapActivated`, `ChordResolved`,
  `TapDanceResolved`, `InputGrab`, and `MessagePush`, which carries the
  `keypath://…` action URIs the config emits.

`cmd` is compiled out (`Scripts/build-kanata.sh`, #879), so a config cannot run
shell commands inside the engine.

### What KeyPath does with the port

| Client | What it sends or reads |
|---|---|
| `KanataEventListener` (app) | Persistent connection. Reads `KeyInput`, layer and tap-hold events, `InputGrab`. Dispatches every `MessagePush` that parses as a `keypath://` URI to `RuleCollectionsManager.handleActionURI`, which calls `ActionDispatcher.shared.dispatch` |
| `KanataTCPClient` via `ConfigReloadCoordinator`, `ConfigHotReloadService`, `ReloadSafetyMonitor` | `Hello`, `Reload { wait }` |
| `ActionDispatcher` (`keypath://fakekey/…`, `keypath://layer/…`) | `ActOnFakeKey`, `ChangeLayer` |
| `VirtualKeysInspectorView`, `RuleCollectionsManager`, `AppContextService`, `HrmObservabilityService` | Virtual-key names, `ActOnFakeKey`, layer state |
| `ServiceHealthMonitor`, `DiagnosticsService`, `SystemValidator`, `WizardCommunicationPage` | `Hello`/health probes |
| `keypath-cli` (`ConfigFacade.tcpReload`, `tcpGetCurrentLayer`) | Opens its **own** TCP connection, unlike `status/start/stop/doctor`, which use the owner-checked Unix socket in `docs/architecture/cli-runtime-control.md` |
| `Scripts/verify-installed-app.sh` | Checks with `lsof` that the listener on the port belongs to the expected worker |

The app never sends `ReloadFile`, `ReloadNext/Prev/Num` or `SetMouse`.

## Threat model

**Asset:** the user's keystrokes, and the authority of a process that holds
Accessibility and Input Monitoring: it can emit input, and KeyPath runs actions
on its behalf.

**Attackers considered:**

1. **A process of another macOS user** on the same Mac (fast user switching,
   a shared Mac, a service account). Today it can connect.
2. **A sandboxed app with the network-client entitlement.** The sandbox keeps
   it out of `~/Library`, but not off loopback TCP. Today it can connect.
3. **A same-user, unsandboxed process with no TCC grants**, such as a script, a
   package postinstall, or a compromised developer tool. Today it can connect.
   It can already do a lot as the user, but not read global keystrokes or post
   input without its own grants. This port gives it both.
4. **A process that binds `127.0.0.1:37001` before the worker does** (any user,
   for example at login or during a restart). The worker uses the bridge's
   passthru entry point, which has no bind probe, so the fork's
   `TcpListener::bind(...).expect` panics inside an `extern "C"` function and
   aborts the worker. (`keypath_kanata_bridge_run_runtime` does probe and
   return an error, but the probe drops its listener before the server binds,
   so it is a check-then-use race.) KeyPath's own clients then connect to the
   squatter. KeyPath does not check who owns the listener; only
   `verify-installed-app.sh` does. The retired stack's
   `detectKanataTCPPortConflict` matched on a process name containing
   "kanata", which a squatter can avoid.

Web pages are out of scope: browsers speak HTTP or WebSocket to that port, the
first line is not valid JSON, and the server disconnects.

**Out of scope:** root, and a same-user process that can already inject code
into KeyPath or the worker. Those defeat any channel design.

### Concrete attacks today

| From | Attack | Impact |
|---|---|---|
| 1, 2, 3 | Connect and read `KeyInput` | **Keystroke logging** of the active user, including another user's keystrokes (1) and from inside a sandbox (2) |
| 1, 2, 3 | `RequestCurrentLayerInfo`, `RequestFakeKeyNames` | Read the user's config and the names of every virtual key |
| 1, 2, 3 | `ActOnFakeKey` | Trigger any virtual-key action: output keys and macros into the focused app, change layers, emit `push-msg` |
| 1, 2, 3 | `ActOnFakeKey` on a key bound to `push-msg` | KeyPath's event listener receives the resulting `keypath://` URI and runs it: launch apps, open any URL, `system` actions, `runtime/stop`, and `script` when the user has enabled scripts. If the user also turned off the confirmation dialog, the script runs without a prompt |
| 1, 2, 3 | `ReloadFile` with an attacker-written `.kbd` | Replace the user's mappings with arbitrary ones: key injection, swallowing keys, `push-msg` actions of the attacker's choosing, which reach `ActionDispatcher` as above. 2 cannot plant a readable file outside its container easily; 1 and 3 can |
| 1, 2, 3 | `SetMouse` | Move the pointer |
| 1, 2, 3 | Open many connections, or connect and never read | One OS thread per connection with no limit. The notification loop writes to every client with blocking `write_all` while holding the client lock, so one stalled reader can delay events, including `push-msg` actions, for KeyPath. Not tested |
| 4 | Squat the port | Runtime fails to start. KeyPath's listener connects to the squatter and dispatches any `MessagePush` it sends as `keypath://` actions |

So ADR-013's note "Limited attack surface: only config reloads, not arbitrary
code execution" (repeated in `KanataTCPClient.swift`) is wrong for the session
runtime. The port exposes a keystroke stream, input injection, config
replacement, and an indirect path to KeyPath's action dispatcher.

## Options

### A. Keep TCP, narrow the commands

Remove `ReloadFile`, `ReloadNext/Prev/Num` and `SetMouse` from the fork (KeyPath
uses none of them). Make `KeyInput` opt-in per connection. Cap connections and
give notification writes a timeout.

- Removes config replacement and pointer control.
- **Does not** remove keystroke logging, virtual-key injection or the
  `push-msg` path, because KeyPath itself needs `KeyInput`, `ActOnFakeKey` and
  `ChangeLayer`. Opt-in `KeyInput` only means the attacker has to ask.
- Does nothing for attackers 1, 2 or 4.
- Cost: small fork change (one to two days).

Not enough on its own. Worth doing anyway as defence in depth.

### B. Keep TCP, add a per-launch token

The app generates a random token per worker launch, passes it to the worker,
and writes it to a 0600 file for the CLI. The server requires a valid
`Authenticate { token }` as the first message before anything else.

- Stops 1, 2 and 3 from issuing commands or receiving events, if the server is
  restructured so that a connection joins the broadcast set and gets its
  initial `LayerChange` only after authenticating. Today it joins on accept.
- Does not stop squatting (4) unless the client also authenticates the server
  (the server proves it knows the token). That is a challenge-response, not a
  bearer token.
- Unauthenticated connections still cost a thread each until they time out.
- Token handling is new code with the usual hazards: constant-time compare,
  never logged, rotated per launch, delivered to the CLI by file permissions,
  the same protection a Unix socket gets for free.
- Cost: fork change of similar size to C, plus a token lifecycle in the app,
  worker and CLI.

### C. Move engine control to a Unix-domain socket with a peer check

Replace the TCP listener with a Unix stream socket in a per-user directory,
using the pattern `RuntimeControlServer` already ships
(`docs/architecture/cli-runtime-control.md`): a 0700 directory checked to be a
real directory owned by this user, the socket created under umask 0177, and
every connection refused unless `getpeereid` returns the worker's uid. Release
builds start the worker with no TCP port at all.

Then narrow who may connect: the only legitimate peer is the KeyPath app that
launched this worker. The worker already receives that app's PID (`ownerPID` in
`SessionRuntimeWorker`, recorded as `parentPID` in its report). The server checks the peer's PID and PID version (from `LOCAL_PEERTOKEN`) against
it, and can additionally check the peer's code signature through
`LOCAL_PEERTOKEN` and `SecCodeCreateWithAuditToken` against KeyPath's
designated requirement (team `X2RKZ5TG99`). The CLI stops talking to the engine
directly and asks the app over the existing runtime-control socket, as
`status/start/stop` already do.

- Stops 1 and 2 outright: another uid fails `getpeereid` and directory
  permissions, and a sandboxed app cannot reach the path.
- Stops 4: the path is inside a directory only this user owns, so nobody else
  can pre-create it, and a stale socket is replaced the same way
  `RuntimeControlServer` replaces one.
- Stops 3 from talking to the engine when the peer-PID or signature check is in
  place. A uid check alone does not stop 3. The PID check is weaker than the
  signature check: it holds only while the launching app is alive (its PID
  cannot be reused until then, so the worker must exit when the app does), and
  it trusts whatever code runs in that PID. The peer token also identifies the
  process that connected, so a connection the app opens and then hands to a
  forked or exec'd child still passes. The phase 4 signature check is the real
  fix for both. Today the worker notices the app
  has gone by polling `isProcessAlive(ownerPID)` in its 5 ms tick
  (`SessionRuntimeWorker.tick`), and a dead PID can be reused inside that
  window. A liveness re-check on accept cannot tell a reused PID from the
  owner, so phase 1 compares identity, not liveness: the app passes its PID
  and its PID version (`audit_token_to_pidversion` on its own
  `TASK_AUDIT_TOKEN`) at launch, and the server reads the peer's audit token
  from the accepted socket (`LOCAL_PEERTOKEN`) and requires both to match. The
  PID version changes when a PID is reused, which closes the race. Confirm
  during implementation that `LOCAL_PEERTOKEN` and `audit_token_to_pidversion`
  are usable on KeyPath's minimum macOS (15), as for `NWEndpoint.unix`; if
  not, phase 1 needs another way to bind a connection to the owner. The worker
  also watches the owner with a kqueue `NOTE_EXIT` source so it stops
  listening the moment the app exits. Until phase 4 ships, attacker 3 is
  stopped from connecting directly but not from injecting into or impersonating
  the app, which this ADR treats as out of scope.
- Removes the cross-process trust problem for `MessagePush`: KeyPath only
  dispatches actions it received from its own worker.
- Cost: see Migration below. The largest of the three. With phase 4 it is the
  only option that closes every case in the threat model. At release (phases 1
  to 3) it closes 1, 2 and 4 and stops direct connections from 3, leaving
  injection into or impersonation of the app.

## Decision (proposed)

Adopt **C**, and do **A** in the same fork change.

The first public session-runtime release ships only after phases 1 to 3 below.
Phase 4 can follow in a point release. Shipping before phase 4 accepts one
residual risk on purpose: a same-user, unsandboxed process that injects into
or impersonates the app (attacker 3, partly mitigated in the table below).
That process already runs as the user, and closing the gap needs the
signature check. Accepting this ADR means accepting that risk for the first
release; if it is not acceptable, phase 4 joins the release gate.

| Attacker | Today | After phases 1–3 (release) | After phase 4 |
|---|---|---|---|
| 1. Another macOS user | Full access | Blocked (uid check, 0700 directory) | Blocked |
| 2. Sandboxed app | Full access | Blocked (cannot reach the path) | Blocked |
| 3. Same user, unsandboxed | Full access | Partly mitigated: direct connection blocked (PID check), but injecting into or impersonating the app is still possible | Blocked unless it injects code into KeyPath (out of scope) |
| 4. Port squatter | Takes over the channel | Blocked (no TCP port; socket in a directory only this user owns) | Blocked |

Before this ADR is accepted, confirm the main claims on a live install in a
lab VM: a second macOS user, and a sandboxed app with the network-client
entitlement, each connect to the port and receive `KeyInput`. In the same VM,
check that `LOCAL_PEERTOKEN` returns the peer's audit token on an `AF_UNIX`
stream socket on macOS 15, since the attacker-3 mitigation depends on it. This
ADR was written from source alone.

## Migration

1. **Phase 1, fork (`malpern/kanata`, a new branch merged into `keypath/bundled` by
   fast-forward; never force-push it).**
   - Make the server generic over a stream type and add a Unix listener
     (`std::os::unix::net::UnixListener`), selected by the bridge. Keep the
     TCP path for kanata's own binary and upstream users of the fork's code.
   - Check the peer before the connection joins the broadcast set: uid via
     `getpeereid`, and PID plus PID version via `LOCAL_PEERTOKEN` when the bridge supplies an
     expected PID.
     Both are read from the accepted socket itself, never from a later
     lookup, and the PID must equal the launching app's PID, not merely belong
     to a process of this user.
   - **Acceptance criterion:** the worker watches its owner with a kqueue
     `NOTE_EXIT` source and, when the app exits, stops listening and exits, and the
     server matches the peer's PID and PID version against the owner's on
     every accept. Without both, the PID check is not meaningful. Required test: start the worker, kill the owner app,
     and assert the socket refuses new connections and the worker exits. A
     second test connects after the owner has exited but before the exit
     watch fires, from a process given the owner's PID number but a
     different PID version (simulated in the check), and asserts it is
     refused. If the owner has already exited when the watch is registered,
     registration fails with `ESRCH`; the worker treats that as owner exit and
     stops at once. A third test covers that case. A
     connection the app hands to a child process is a known gap at this phase
     (see Option C); phase 4 closes it and adds its test.
   - Return an error instead of panicking when the listener cannot be created,
     by binding once and keeping that listener, not by probing first. The
     bridge returns the error through its existing error buffer, and
     `SessionRuntimeWorker` ends with a failed report naming the cause (for
     example, socket directory not owned by this user), which the app shows.
     It does not retry in a loop.
   - Option A: drop `ReloadFile`, `ReloadNext/Prev/Num` and `SetMouse` from the
     session build (feature flag), cap connections, and put a write timeout on
     notification sockets so a stalled client is dropped rather than blocking
     the loop.
   - Rust tests for the peer check and the removed commands.
   Estimate: roughly 300 to 500 lines of new code and tests, plus rewriting
   the bridge's existing passthru TCP test (`Rust/KeyPathKanataHostBridge/src/lib.rs`).
   Phases 1 and 2 land together. The fork change merges to `keypath/bundled`
   first, but KeyPath only picks it up in one KeyPath PR that bumps the
   submodule and changes the bridge (`Rust/KeyPathKanataHostBridge`, which
   lives in this repository) and the worker. No KeyPath commit pins the new
   fork without the matching bridge change, so no build has the Unix socket
   while still panicking on, or probing, a TCP bind. Before pushing to
   `keypath/bundled`, confirm the push is a fast-forward
   (`git log --oneline origin/keypath/bundled..<branch>` lists only the new
   commits, and `git merge-base --is-ancestor origin/keypath/bundled <branch>`
   succeeds). Before accepting this ADR, re-check the claims above against the
   fork commit that will ship, if it is no longer `d9085a9`. CI today only
   builds the fork and the bridge (`cargo build` in `.github/workflows/ci.yml`);
   it runs no Rust tests. The KeyPath PR that lands phases 1 and 2 adds a
   `cargo test` step for the bridge and the fork's peer-check tests to a
   required CI job, so the acceptance tests above cannot be skipped.
2. **Phase 2, bridge and worker.** `keypath_kanata_bridge_create_passthru_runtime` takes a
   socket path (and expected peer PID) instead of `tcp_port`. The expected PID
   is the app that launched this worker, passed on every launch, so a relaunch
   or a new app instance never inherits an old PID. This keeps today's
   adoption rule: `adoptRunningSession` only re-supervises a worker launched by
   the same app process (`currentSessionReport` needs that process's
   `sessionApplication` and nonce), and a worker whose owner has exited already
   stops itself (`owner-exited`). Nothing adopts a worker across app launches,
   and the owner watch makes that impossible by design. Keep the path short:
   macOS limits `sun_path` to 104 bytes, so reuse the runtime-control directory
   (`~/Library/Application Support/KeyPath/control/`) with a short file name and
   never truncate. If a long home path exceeds it, fall back to a short
   directory under the per-user temporary directory
   (`confstr(_CS_DARWIN_USER_TEMP_DIR)`, which macOS creates 0700 for this
   user), with the same ownership and mode checks. Because the location can
   vary, the app, the CLI and `verify-installed-app.sh` take the path from the
   worker's report, never from an assumed directory. Tests: a home path that
   pushes the primary path past 104 bytes uses the fallback, and one that
   overflows both fails with the clear error. Fail with a clear error only
   if both are too long. The worker creates
   and validates the directory (reuse `RuntimeControlServer`'s checks) and
   reports the socket path in its owned report instead of `tcpPort`.
3. **Phase 3, Swift clients.** One transport change: `KanataTCPClient+Connection` and
   `KanataEventListener.connectAndStream` build `NWConnection`s from host and
   port. They move to `NWEndpoint.unix(path:)` (confirm availability on the
   minimum macOS during implementation; fall back to a POSIX socket if not).
   The other callers listed above go through those two types and need no
   protocol change. `ConfigFacade.tcpReload`/`tcpGetCurrentLayer` move to a
   runtime-control request handled by the app. `PreferencesService.tcpServerPort`
   and the legacy port migration retire. `verify-installed-app.sh` checks the
   socket's owner and the connecting worker instead of a TCP listener.
   Estimate: two to four days including tests.
4. **Phase 4, signature check.** Add the `LOCAL_PEERTOKEN` code-signing check against
   KeyPath's designated requirement. Debug builds signed with another identity
   need an explicit, logged development override.
5. **Phase 5, docs.** Mark ADR-013 superseded, rewrite the TCP section of
   `guides/privacy.md` (it says key events cross the connection, but not that
   any other local process receives them, and calls the risk low) and publish it, update
   `docs/architecture/overview.md` and `cli-runtime-control.md`, and fix the
   `KanataTCPClient` security note. Withdraw or redesign
   `docs/architecture/context-integration-architecture.md`, whose unimplemented
   design has tmux, vim and shell hooks send `ContextUpdate` JSON to
   `nc 127.0.0.1 37001`.

**Compatibility:** anyone scripting `localhost:37001` directly (for example
from Hammerspoon) loses that. So does the context-integration design above:
third-party processes feeding context to the engine is exactly what the peer
check forbids, so if it is revived it goes through the app (a `keypath://` URL
or runtime-control request), which can validate what it forwards. The supported routes are `keypath://` URLs and
`keypath-cli`. Phase 5 adds a release-notes entry for the release that ships
this, and an item in `docs/process/release-process.md` to check it is there.

**Fork divergence:** this widens the difference from upstream kanata's TCP
server. A Unix-socket listener is generally useful on Linux and macOS, so offer
it upstream; the peer-PID check stays KeyPath-specific.

## Consequences

- Until this lands, the session runtime exposes a keystroke stream and input
  injection to every local process, including other users and sandboxed apps.
  #1354 stays a release-blocker. The release process needs a check that fails
  while open `release-blocker` issues exist; nothing enforces that today
  (`release-doctor.sh` does not look at issues).
- The engine socket and the runtime-control socket share one directory model,
  so a fix to either applies to both.
- KeyPath's `MessagePush` handling can then assume its sender. Until then, any
  hardening of `ActionDispatcher` (for example requiring confirmation for
  `script`, `open` with non-http schemes, and `runtime/stop` when they arrive
  from the engine) reduces the impact of the `push-msg` path.

## Related, not decided here

The `keypath://` URL scheme is also an unauthenticated local entry point: any
process can `open keypath://script/…`, `keypath://fakekey/…` or
`keypath://runtime/stop`. Scripts are still gated by the user's script setting.
It deserves its own review, because moving the engine to a Unix socket does
not change it.
