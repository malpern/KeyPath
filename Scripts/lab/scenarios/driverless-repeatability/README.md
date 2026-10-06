# Driverless repeatability scenario

These are the selected existing experimental commands, now maintained separately
from trial data. Historical copies are evidence, not templates for the next run.
No new scheduler, transport or automatic UI framework is introduced.

Set `KEYPATH_TRIAL_DIR` to a newly created, owned mode700 directory. Put a mode600
`tenants.tsv` there containing the reviewed KeyPath tenant mapping. Run these
commands from this source directory with Python `-B`. Missing environment fails
before dispatch. Keep this environment on every invocation; never substitute a
previous trial directory. Source and artifact bindings currently select signed
`bd7809dc1` and its metadata-free archive.

1. Run canonical `vm-lab keypath list` and `preflight`. Check capacity. Locally
   validate `create_once.verify_inputs`, both archives through the installer's
   actual `zip_guard`, and fully generated installer/route payload compilation.
2. `create_once.py` invokes canonical CREATE exactly once and preserves its
   exclusive claim/result. `owned_status_once.py` verifies the returned provider,
   artifact, expiry and ownership, then records `owned-lease.json`.
3. Open the exact owned console from Parallels Control Center; do not launch an
   unbound macvm application. Log in normally as the existing public disposable
   UID502 account. `observe_post_login02_once.py identity` publishes fresh guest
   identity only after independent before/after observations agree.
4. `stage_current.py preflight connection01` checks the transfer route. A normal
   guest local-network consent prompt may appear; inspect and approve the actual
   prompt, then use `preflight connection02`. If the first probe succeeds, use
   the distinct read-only `connection02` probe to produce the install prerequisite.
   `check_install_absence.py` writes the matching `install-absence02` receipt.
   `stage_current.py install install01` performs the one installation. An uncertain
   mutation is reconciled, never replayed.
5. `action.py initialize01 initialize` performs normal first launch and default
   profile creation. Complete actual guest setup UI and normal Accessibility /
   Input Monitoring consent with fresh UI observations, including Quit & Reopen.
   `action.py permissions01 inspect` must show the fresh owned worker running,
   active tap, effective permissions and no held outputs.
6. Activate the guest app. **Use mouse input on the visible guest KeyPath menu →
   Quit KeyPath; never send native `super+q` to Parallels.** Verify absence with
   `action.py stopped01 inspect` before `action.py profile01 profile`.
7. Attach only the ESP32 temporarily through the owned console Devices menu.
   For cycle1: `action.py launch01 launch`, verify ready runtime, then
   `action.py target01 target`. Immediately run `verify_attached_fresh.py cycle1`
   followed by `sample_once.py cycle1 "$KEYPATH_TRIAL_DIR/attached-cycle1.json"`.
   The latter requires fresh ownership, all-up/focus/identity and control timing;
   exact physical trace, target events and worker counters must agree.
8. Retire the target with `action.py retire01 retire-target '{"pid":ACTUAL,
   "nonce":"ACTUAL"}'` using the observed target identity. Quit normally through
   the visible guest menu; verify parent/worker absence. Repeat step7 with fresh
   labels ending02 / cycle2, requiring new parent/worker/target identities. Retire
   that target and verify a second normal Quit. No repair between cycles counts
   as a repeatability pass.
9. `action.py restore01 restore` verifies stopped processes and restores only
   the exact backed-up original profile. Canonically destroy the owned lease
   with exclusive intent/result receipts. `verify_closed_vm02.py` independently
   checks provider absence, retained stopped template and detached/nonpersistent
   ESP32 using this trial's actual provider UUID.

The root agent is the sole live/UI/HID controller. Keep normal UI actions visible
and verify their postconditions; a click success is not consent or process exit.
Two distinct controller faults stop dependent input in that trial. Reconcile and
fix the specific cause within authorization; do not require a new user approval
for a safe correction, and do not rebuild the lab. Preserve failed receipts.

Remaining debt: the selected SDK guest-root transport, identity observer,
short transfer loader and physical client/baseline remain pinned external
experimental dependencies. This consolidation does not claim to remove them.
Do not migrate unchanged dependencies merely to expand this task. The installer
correction is integrated in the maintained vm-lab `rig/artifact-stage.py`.
