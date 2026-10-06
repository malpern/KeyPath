# Active driverless testing workflow

Current checkpoint, October5: bounded consolidation and two ordinary physical cycles passed on signed `bd7809dc1` in one prepared guest, with normal mouse-menu Quit, new process/target identities and no repair between cycles. Original profile and process cleanup, canonical disposal and independent provider/template/USB checks passed; no owned VM remains. [Selected receipt](evidence/2026-10-05-repeatability-live-acceptance.json). Freeze infrastructure work except for reproduced blockers; resume product recovery gates.

The handoff owns the latest evidence and source/artifact identities. This file owns the operating procedure; the product plan owns acceptance order; the failure ledger owns historical diagnoses. Do not append another competing “current” status section. Read the current handoff and relevant failure class before adapting an older helper.

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
  --commit bd7809dc1da9b814ac00c826e676c2622d9ab4bd \
  --installer /private/tmp/keypath-caps-checkpoint-bd7809dc1-clean-artifact/keypath-caps-mutation-checkpoint-clean.zip
```

This example names the last live-tested candidate, not a standing authorization to replay CREATE. Before a new run, substitute the reviewed current commit and signed artifact together and verify their manifest hashes. No owned VM remains from that trial. `NEW-TRIAL` is a newly allocated owned0700 directory, not a literal reuse path. Its registry is a private0600 copy of the reviewed keypath tenant mapping. Clear inherited testing, capacity, clone-root, inline-payload and diagnostic overrides; keep the exact selected template and provider settings. Record the returned status unchanged. Unknown completion means reconcile the owned resource, not dispatch CREATE again. Never bypass admission using raw provider creation.

## Selected corrections and completed repeatability check

The four selected corrections below are implemented in existing experimental entry points. [Patch and pinned bases](evidence/2026-10-05-runner-corrections.patch), [local checks/source review](evidence/2026-10-05-runner-corrections.json), and [fresh setup outcome](evidence/2026-10-05-repeatability-setup-acceptance.json) record the exact scope. No new runner, scheduler, adapter hierarchy or general test framework was added. The successor [two-cycle campaign](evidence/2026-10-05-repeatability-live-acceptance.json) passed. The installer is integrated in vm-lab `f2d3b65`; the selected existing commands live in [the maintained scenario](../../Scripts/lab/scenarios/driverless-repeatability/README.md), with `KEYPATH_TRIAL_DIR` separating run data from source.

| Existing boundary | Small correction | Required check |
| --- | --- | --- |
| Packaging / installation | Produce the metadata-free archive already proven to install. Apply the actual installer ZIP policy to the final archive locally; do not maintain a second approximate allowlist. | Original rejected archive fails locally; corrected final archive passes, signature and payload checks pass. |
| Generated guest command | Compile generated payload structure locally before CREATE, then compile the complete payload with fresh guest identity before dispatch, including appended code. Check actual CLI option forms against the selected installed tool's help/documentation. | Previously malformed payload fails locally; corrected executed bytes compile; unsupported `perform-action --app` is absent. |
| Setup caller | Sequence dependent steps with explicit return-status and postcondition checks. Profile preparation requires the profile to exist after normal first launch. | Missing-profile case stops before the dependent launch; existing successful first-launch route remains intact. |
| Failure reporting | Preserve a sanitized child diagnostic with fixed stage, allowlisted reason and numeric exit instead of discarding stderr. Derive operation elapsed time from the intent/result receipts; internal child-stage timing is not claimed. Exclude credential arguments, tokens and generated payload dumps. | Local rejection emits a sanitized broad child-stage reason without secrets. The actual ZIP guard separately rejects the old archive locally; no precise internal archive-stage attribution is claimed. |

Focused local checks and one independent source/receipt review passed. The saved patch was applied to recorded bases in a temporary directory and reproduced all selected hashes. Fresh installation used those corrected bytes. Two-cycle verification passed without repair between cycles; do not reopen broad lab qualification or repeat it before every product case.

## Setup once, then product experiments

1. Before CREATE, declare one product question, observable pass/fail conditions, expected safety refusals, test order and cleanup. Pin the current commit/artifact together and finish local checks above. Freeze the signed artifact during that trial.
2. Use canonical admission/CREATE. Independently verify owned lease/provider, public UID502 account, boot and consent scope. Record cutoff six minutes before lease expiry. Clear inherited overrides as specified above. Unknown command completion requires reconciliation before any further mutation.
3. Establish guest transport prerequisites and install once. Follow **normal first launch → default profile exists → normal Accessibility and Input Monitoring consent → normal Quit & Reopen as required → verify effective runtime access → normal Quit and verify process absence → prepare trial profile**. Stop at the first failed prerequisite. The effective keyboard mask is7168; historical AX-only4096/Oracle-ready is not acceptance. A notification window is optional; inspect current UI and the actual Settings permission state instead of assuming a dialog exists.
4. Generate fresh configuration and verify installed hashes, current identity, ownership, all-up state and required timing. An existing successful recipe is reused with current facts; old receipts never qualify a new scope. Root alone owns VM, UI and HID control.
5. Run compatible cases on this prepared owned guest within its lease, verifying cleanup and fresh scope between cases. The ordinary remap/stop/start recipe has passed two consecutive samples across normal Quit/relaunch; use a scoped positive control for a changed product case and record setup separately from experiment time. This is narrow repeatability evidence, not full reliability certification. Do not repeat already accepted cases across new VMs without a changed dependency or an unresolved concern.
6. Run the selected new product case. Tests that deliberately retain uncertain mutation state, change boot/device identity or leave the guest unsuitable for reuse go **last** and end the guest. Never erase uncertainty to make the next test runnable. A fresh guest is required for clean consent/installer evidence and final clean-machine acceptance.
7. Clean up according to observed ownership/state: verify physical all-up, stop exact owned processes/target, restore only when ownership and current mapping permit it. If restoration is uncertain, preserve journal/marker/profile for disposal. Canonically destroy the lease and independently verify provider absence, retained stopped template and detached nonpersistent ESP32. Keep warning status separate from these postconditions.

## Failure and retry rules

- A known coordinator refusal is an expected product outcome when the case demands refusal; a tool failure or missing observation cannot establish that outcome. Report setup failure, observation failure, expected refusal and product failure separately.
- Never retry a deterministic error unchanged: invalid option, syntax error, archive rejection or missing profile. Correct and validate locally first.
- One bounded read-only retry is reasonable for a transient observation after a relevant state change. A second identical failure ends that route for this trial. Before retrying a mutation, reconcile its postcondition and confirm it did not already execute.
- When Peekaboo reports `activateApplication` permission denied, use the established native console route for the exact owned guest; do not repeat its menu route. After normal Quit, check actual parent/worker absence once with a bounded wait. An inactive parent's exact scoped termination may finish cleanup, but does not count as normal-Quit product acceptance.
- Native host `super+q` is forbidden as the guest Quit route: Parallels intercepted it and suspended the owned VM in the October5 repeatability attempt. Use mouse input on the fresh visible guest application menu → Quit, then independently verify parent/worker absence. This mouse-menu route passed three normal Quit observations in the successor campaign, including both physical cycles. Dismiss the actual setup modal first and verify absence afterwards. Avoid changing host shortcut settings to solve a guest test.
- Two distinct setup/harness faults in one trial stop further input and product cases: preserve evidence, clean up, fix locally. Do not spend the rest of the lease improvising setup. Expected test refusals and a case's deliberate product failure do not count toward this setup threshold.
- Genuine-timeout diagnosis retains its30-active-minute budget. If unresolved, preserve the acceptance gap and advance independent work. No repeated delay escalation, random-crash acceptance, or fresh lab redesign.

## Speed and stability check

Use one short row in the existing trial summary: setup minutes, experiment minutes, cleanup minutes, declared cases/observed outcomes, avoidable harness failures and retries. Time is measured from receipts, not inferred from message count. Target zero recurrences of the named deterministic errors and two consecutive ordinary cycles without setup repair. Compare the next few eligible trials with the recent recorded trials before claiming a speed improvement. Do not create a dashboard or a new telemetry service.

Parallelize only independent source review or inert checks. Keep live control serial and one review for each changed safety boundary. Another reviewer is useful for changed ownership/recovery logic; it is not required for every unchanged command or documentation edit.

## Change discipline

Before a live run, review the actual entry point, actual artifact metadata and source/configuration admission together. Run Python source checks with `-B` (or `PYTHONDONTWRITEBYTECODE=1`) so imports cannot add cache entries to frozen source inventories. Prefer focused checks at that boundary to broad repeated suites. Request a second reviewer only for a specific changed contract. Keep one evidence directory per trial and update the current handoff in place rather than prepending chronological status blocks.

The retained runtime currently still depends on older frozen implementation modules. That debt is explicit: avoid more adapter layers, and consolidate a selected module when a reproduced defect requires changing it. Do not claim this documentation has removed that code.

## Selected console lessons

Use `guest-root` for the prepared public UID502 account; the generic `run` route targets the original QA501 transport and is unsuitable here. The retained SDK shell route requires a leading `true;` to preserve arguments to the intended first command. Use the baseline-pinned extracted Peekaboo path, which differs from the generic skill example. Fresh AX inspection plus `AXPress` worked for guest setup controls. Windowed console coordinate input was unreliable in this trial; switching the exact owned console to full screen allowed normal public test-password entry. This is an observed workaround, not a general focus fix or proof that the host was locked.

## Evidence and supported boundary

Use [the current handoff](permission-exploration-handoff.md) for accepted product cases and remaining gaps, and [the last12 failure review](permission-failure-review-2026-10-05.md) for this procedure's rationale. Accessibility and Input Monitoring remain required. Caps remains DEBUG-only, one selected eligible keyboard with nativeF18 reserved; retained Function handback, concurrent mapping edits and conservative recovery limits remain explicit. Installer/onboarding follows core acceptance; broad compatibility follow-ups must not silently expand that gate.
