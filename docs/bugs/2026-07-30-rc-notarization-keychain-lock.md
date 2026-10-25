# RC notarization failed mid-build on locked data-protection keychain; recovery left an unstapleable install

**Date:** 2026-07-30 · **Area:** release scripts (notarization, deploy)

## What happened

A `Scripts/release-candidate.sh` run started at 23:38 local. `release-doctor.sh`
validated the `KeyPath-Profile` notarytool profile at the start of the run, but
nine minutes later — after the build finished — `notarytool submit` failed with
exit 69: `No Keychain password item found for profile: KeyPath-Profile`
(recorded in `dist/KeyPath.notary-submission.json` as `submit-client-failed`).
The RC script aborted correctly at that point (`set -euo pipefail`); nothing
was deployed by the RC run.

The installed app went bad through a different path: a later `ui-deploy.sh`
run replaced `/Applications/KeyPath.app` with a locally re-signed build. When
the notarization was manually resubmitted and accepted the next day, the
ticket could not be stapled onto the installed copy because the local re-sign
had changed the cdhash. Recovery required extracting `dist/KeyPath.zip`,
stapling the extracted app, and swapping it into `/Applications`.

## Root causes

1. **Keychain credential is lock-state dependent.** notarytool (Xcode 26.x)
   stores keychain profiles in the *data-protection* keychain — the item is not
   in `login.keychain-db` at all. Data-protection items are only readable while
   the login session is unlocked, so the profile "disappears" when the screen
   locks mid-build. `security unlock-keychain` cannot help (it only unlocks
   file keychains), and the doctor preflight passes because the user is still
   present when it runs.
2. **No resume path.** After a notarization failure there was no scripted way
   to finish the submission, staple `dist/`, and deploy; ad-hoc recovery mixed
   in dev-deploy scripts that re-sign, which detaches the app from its ticket.

## Fixes (PR)

- Notarization now prefers the file-based App Store Connect API key
  (`kp_notary_default_auth_from_environment` in `Scripts/lib/signing.sh`),
  which has no keychain/lock-state dependency. `release-doctor.sh` validates
  whichever auth path the build will actually use.
- `Scripts/release-candidate.sh --resume-notarization` /
  `Scripts/notarize-resume.sh`: finish the recorded submission (or resubmit the
  identical archive), staple `dist/KeyPath.app`, and deploy it verbatim.
- `build-and-sign.sh` refuses to deploy a bundle without a stapled ticket when
  notarization was requested, and both deploy paths go through
  `Scripts/lib/deploy-app.sh`, which copies with `ditto` and never re-signs.

## Lessons

- Registration-time validation is not runtime validation: a credential check at
  the start of a long build says nothing about availability at submit time.
  Prefer credentials with no session/lock dependency for anything that runs
  unattended (same lesson as the gws keychain saga).
- Never re-sign a notarized artifact. The stapled `dist/` bundle is the only
  thing that may be copied to `/Applications` for a release candidate; if a dev
  deploy (`quick-deploy.sh`/`ui-deploy.sh`) overwrote it, re-deploy the stapled
  bundle rather than trying to staple the installed copy.
