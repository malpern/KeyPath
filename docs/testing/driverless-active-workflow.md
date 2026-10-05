# Active driverless testing workflow

## Operating rule

Use one canonical lab route and one signed product artifact. Root owns all VM/UI/HID actions. Agents may independently review source or run inert checks. Do not add a wrapper when an existing command already handles the operation. Keep historical packets immutable, but do not require obsolete historical hashes as current caller configuration.

The supported setup is admitted macOS26 / Parallels / unmanaged-ui / desktop, prepared runtime template, one-hour TTL. Lab checkout: `/private/tmp/vm-lab-reusable-setup`. Product checkout: `/private/tmp/keypath-tap-timeout-hook-build`.

## Fixed CREATE route

Run canonical `keypath list` and `keypath preflight` first. Root records an exclusive durable CREATE intent in a new private evidence directory before its single invocation. Use the existing CLI directly with these settings; do not add another maintained launcher:

```sh
VM_LAB_REGISTRY=/private/tmp/NEW-TRIAL/tenants.tsv \
KEYPATH_LAB_PARALLELS_TEMPLATE_26_DESKTOP=keypath-macos-26-runtime-v1-7285826ed9f6 \
KEYPATH_LAB_CREATE_POSIX_REQUIRED=1 \
KEYPATH_LAB_CREATE_POSIX_BINARY_FILE=/private/tmp/keypath-create-posix-sdk-build-ada4b9f/crabbox-create-posix-sdk \
KEYPATH_LAB_CREATE_POSIX_BINARY_SHA256=fd2671373f626f8e762559f6e58c06b04277f32ac02db670d41b4803be63a179 \
/private/tmp/vm-lab-reusable-setup/bin/vm-lab --host malpern@mini keypath create \
  --macos 26 --lane unmanaged-ui --desktop --ttl 1h \
  --commit d9fcf9785ee3e544be800982068141271cb24901 \
  --installer /private/tmp/keypath-terminal-gate-d9fcf9785-artifact/keypath-terminal-gate-d9fcf9785-artifact-clean.zip
```

`NEW-TRIAL` is a newly allocated owned0700 directory, not a literal reuse path. Its registry is a private0600 copy of the reviewed keypath tenant mapping. Clear inherited testing, capacity, clone-root, inline-payload and diagnostic overrides; keep the exact selected template and provider settings. Record the returned status unchanged. Unknown completion means reconcile the owned resource, not dispatch CREATE again. Never bypass admission using raw provider creation.

## Setup once, then product experiments

1. Independently verify exact owned lease, provider, public account and boot. Record cutoff six minutes before lease expiry.
2. Check required guest setup/consent, then install the exact signed artifact once. A read-only preflight refusal before an installation claim permits a distinct preflight after normal consent. An uncertain installation is reconciled, never replayed.
3. Grant normal guest Accessibility **and** Input Monitoring. Confirm the fresh worker reports rawListenEvent=granted and registered mask7168; AX alone produced mask4096 and a startup refusal in the latest trial, even while the Oracle said ready. Use normal macOS Quit & Reopen after IM consent. Quit and independently verify installed hashes, profile, process/report absence and identity.
4. Create fresh runtime configuration with current canonical source pins. Obtain no-input positive timing and complete its cleanup before the explicit hardware gate. Old identity, timing, scope or configuration cannot qualify a new VM.
5. Run one declared product hypothesis. Record infrastructure, harness and product outcomes separately. Successful setup does not require broad lab requalification on every product-test refusal.
6. Restore profile, verify all-up, retire exact owned processes/target, destroy the lease, and independently verify provider absence/template retention/ESP32 detachment. Preserve warnings and actual statuses.

## Experiment stop rules

The latest fresh committed-route setup/positive/cleanup passed, but its local physical-release handoff failed before hardware input. Diagnostic observability is now source-reviewed; the original cause remains unproven. Stop broad lab work. Use an existing owned prepared guest for runtime debugging where verified cleanup permits a new scope; never replay a spent or uncertain mutation. Reserve new clean guests for installation/consent evidence and final clean-machine acceptance. The product question remains whether a one-second callback stall produces a genuine OS timeout and safe recovery. The source retains a strict two-second timing safety budget. If no genuine timeout occurs, preserve the evidence and research the trigger before another VM run; do not repeatedly increase delays. If a transport or harness fault prevents observation, fix that layer and add one focused regression before returning to the product question.

Time-box the next local handoff/timeout diagnosis to 30 minutes of active investigation. If unresolved, preserve genuine-timeout recovery as an explicit unverified acceptance gap and advance the independent restart/session and Caps Lock work. This is not a timeout pass or release approval. Then revisit reduced-permission installer/onboarding UX. Report completed milestones and unresolved questions; do not use milestone count as an estimate of elapsed work remaining.

## Change discipline

Before a live run, review the actual entry point, actual artifact metadata and source/configuration admission together. Run Python source checks with `-B` (or `PYTHONDONTWRITEBYTECODE=1`) so imports cannot add cache entries to frozen source inventories. Prefer focused checks at that boundary to broad repeated suites. Request a second reviewer only for a specific changed contract. Keep one evidence directory per trial and update the current handoff in place rather than prepending chronological status blocks.

The retained runtime currently still depends on older frozen implementation modules. That debt is explicit: avoid more adapter layers, and consolidate a selected module when a reproduced defect requires changing it. Do not claim this documentation has removed that code.

## Selected console lessons

Use `guest-root` for the prepared public UID502 account; the generic `run` route targets the original QA501 transport and is unsuitable here. The retained SDK shell route requires a leading `true;` to preserve arguments to the intended first command. Use the baseline-pinned extracted Peekaboo path, which differs from the generic skill example. Fresh AX inspection plus `AXPress` worked for guest setup controls. Windowed console coordinate input was unreliable in this trial; switching the exact owned console to full screen allowed normal public test-password entry. This is an observed workaround, not a general focus fix or proof that the host was locked.

## Proven narrow product path

October 5 trial `cbx_d54246816bd3` passed physical q→a, the app menu’s **Quit KeyPath**, observed parent/worker absence, ordinary LaunchServices relaunch, and a second physical q→a. Both samples had exactly one captured down/up and worker input/output increments of two; all held-key ledgers were empty. Root used a small trial-local coordinator, not the timeout driver or the retired QA501 scripts. A fresh capture target is necessary after menu focus changes because `focusLost` is sticky. Original profile restoration, process/report absence, VM deletion, retained stopped template and detached nonpersistent USB all passed. The hydration-stop255 warning is preserved separately from successful deletion. [Selected receipt](evidence/2026-10-05-normal-restart.json).

This single cycle earns a narrow product pass. It does not qualify held-key quit, console/session transitions, genuine timeout recovery or sustained reliability. Keep those gates separate. The first next product correction is the observed AX-only readiness false positive, followed by session continuity and Caps Lock ownership.
