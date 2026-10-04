# CREATE/HOME phase candidate — source only

The repeated setup failure is the same missing-home case, rather than a new
credential or permission problem. The ordinary account command can publish the
directory-service account before a home exists. Both frozen bootstrap observers
then call `os.lstat(home)` unconditionally (`guest_observer.py:51`), so they lose
otherwise available account/admin/token evidence. Their protocol combines account
and home verification (`bootstrap_protocol.py:205–227`) and their wrapper refuses
any pending-create reconciliation (`wrapper.py:223–226`). The known normal
`createhomedir -c -l -u <exact-owned-user>` repair remained a separate script, so
subsequent lease copies reproduced the same failure.

Evidence: `/private/tmp/keypath-public-bootstrap-883343c6-attempt/state.json`
retains `creation-attempted` and pending `create`; the separate
`/private/tmp/keypath-883343c6-home-result.txt` records home completion.
`/private/tmp/keypath-ef2006f9-create-home-intent.json` again records the separate
home operation. `/Users/malpern/local-code/vm-lab/docs/automation-lessons.md:38`
requires account/home proof but does not encode the missing-home phase. No frozen
packet or original journal was changed for this candidate.

## Small reusable fix

* `selected_account.py` represents only FileNotFoundError as `homeKind=absent`,
  `homeOwner=null`, `homeSymlink=false` for the lease-derived new account. It still
  queries UID, exact home/name, admin membership, and SecureToken status. Missing
  QA501 home, permission errors, and symlinks cannot become readiness proof.
* `create_home.py` consumes an original sole pending-create journal, its baseline
  absence proof, and SHA256 provenance. Scope is parameterized by its lease, UUID,
  expiry, boot, and loginwindow; UID502 and home/name derive from that lease.
  `account-created` and `home-ready` are different phases. No account creation,
  password, authentication, autologin, reboot, or QA501 mutation is emitted.
* A separately persisted `home-attempted` claim precedes the single 30-second
  normal home command. Lost response never permits replay. Read-only reconciliation
  can accept an actual directory owned by UID502 without changing the original
  unknown account-command exit or pretending a home command returned successfully.
  Already complete homes require no mutation. Missing homes after an attempt remain
  unverified. Guest/provider expiry and QA/login-preference preservation are required.

## Integration contract and limitations

This is an inert reusable helper, not a released VM executor. `complete_once`
requires explicit adapters for canonical provider inventory ownership verification,
complete selected snapshot observation, durable private journal publication, and
one guarded dispatch. The provider adapter must derive `ownedReady` from the real
canonical inventory check; diagnostics/stage markers do not confer authority.
The selected observer adapter must use `allow_missing_home=True` only for the new
account, and preserve full before/after boot/console checks and bounded freshness.

The journal adapter must pin and validate the original private journal bytes and
source, use exclusive admission, refuse symlink/foreign-owner files, and fsync the
new journal and parent namespace before dispatch. The original journal stays
bytewise unchanged. A helper state is separately durable. The dispatch adapter
must freshly validate the same owned lease and selected guest state immediately
before the actual syscall, enforce the 30-second bound, and never retry transport
or mutation. These live adapters are intentionally not implemented here; root can
reuse the reviewed transport/private-state primitives without copying obsolete
activation phases. No present lease's existing journal is implicitly migrated.

Ten inert tests exercise actual observer missing-home versus permission-error and
symlink behavior; reconstruction after lost account/home response; already-ready
homes; strict identity, uniqueness, token, QA and preference refusals; persistence
failure sending nothing; expiry after a second read; and exactly one dispatch on a
lost response. These tests establish source behavior, not guest execution proof.

Run: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest -v test_create_home.py`.
