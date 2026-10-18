# KeyPath production handoff — October 18, 2026

## Start here

User wants a polished production-ready Apple Silicon driverless KeyPath with minimal permissions. Latest request: install the updated offline-Help build on the Air, identify exactly what remains, and hand work to another agent. Installation and launch completed. Canonical verifier PASSED: Apple Silicon payloads, signature, Gatekeeper, stapled ticket, owned parent PID79520, worker PID79935 and TCP127.0.0.1:37001. Startup log reports validation SUCCESS/no blocking issues. Evidence: `/Users/malpern/keypath-review-evidence/20261018-offline-help/air-install/install.log` and `verification.log`. No physical key output was asserted by this readiness check.

Do not restart research or redesign the VM lab. We have substantial passing product evidence. Finish the finite acceptance and integration gates below. Never equate notarization/process readiness with physical keyboard acceptance or claim all configurations are bug-free.

## Machines, code and candidate

- Work host: Mac mini, `malpern`. Active worktree: `/Users/malpern/local-code/keypath-driverless-caps-ui`, branch `design/driverless-caps-ui` (pushed).
- `/Users/malpern/local-code/keypath` is integration-only on master. Do not edit/build there. Preserve experimental worktrees. Original `/private/tmp/keypath-permission-footprint` is historical; current work is in the active worktree above.
- Read repo `AGENTS.md`, `docs/ITERATION_WORKFLOW.md`, `docs/testing/driverless-release-signoff.md` first. The latter has dated history; its updated opening and this handoff define current backlog.
- SSH Air: `ssh -o ControlPath=none -o BatchMode=yes -o ConnectTimeout=5 air` (Tailscale). Offline is a bounded wait, not a product failure.
- Installed Air app: `/Applications/KeyPath.app`; source **`5d5612023`**, version **1.0.2 (13)**, BuildDate `2026-10-18T16:08:00Z`.
- Installed executable SHA-256 **`1d55e260b70993b5813b6a917d4bf3f4dca8e43ff47b676a02698e4f0769fd75`**.
- Final DMG on Air: `/Users/malpern/Downloads/KeyPath-20261018-offline-help.dmg`.
- Mini DMG: `/Users/malpern/keypath-review-evidence/20261018-offline-help/final/KeyPath-20261018-offline-help.dmg`.
- Final stapled DMG SHA-256 **`d0a319a8066bc772e483d599baef67e4553c99e4e7e03697614d8d14b10777ea`**.
- Previous Air app backed up as `/Users/malpern/Downloads/KeyPath-before-offline-help-20261018.zip`. ZIP tested and prior executable verified against the displaced bundle. Redundant extracted backup removed to avoid duplicate-app discovery. Rules/preferences were retained; do not uninstall or clear them for ordinary upgrades.
- App notarization `e953c530-e012-4f9f-813f-807db12c7e59`; DMG `6fd2a093-fd0c-421b-860f-9f1931013407`, accepted. Both stapled/validated, Gatekeeper passed.

## Decisions to preserve

- Driverless path is the product direction; Apple Silicon only. No Karabiner driver or root helper required for ordinary remapping. Host may have historical helpers installed; don't interpret that as a new requirement or remove unrelated services.
- Accessibility is the primary permission; separate Input Monitoring only if effective access still requires it. No Full Disk Access and no automatic browser-history suggestions.
- Caps Lock uses managed, compatible-device Caps Lock → F18 mapping and reserves F18. Preserve ownership/all-keys-up safety, recovery and rollback. No automatic alternate carrier selection. User-visible name is Caps Lock.
- Caps Lock can tap Escape and hold Hyper/other configured action. Native Caps Lock output supported. Secure Input/password fields and login/prelaunch behavior have driverless limits; do not promise driver equivalence. See `guides/driverless-caps-lock.md` and maintained gap docs.
- Installer/onboarding starts runtime automatically and presents repair only on real failure. Four-page Metal tour is restored. Splash/loading, About, Help and branded DMG use **“Keys that do more.”** (exact punctuation). Do not restore “Tap. Remap. Done.” or “Your keyboard your way.”
- Existing-version migration is explicitly out of scope. App Store distribution is a documented future investigation, not this release.
- Minimize overengineering; use existing lifecycle/config owners. No new recovery manager, polling framework or lab overhaul.

## Recent fixes and their evidence

- Genuine Air sleep/wake originally broke Caps Lock. Recovery/startup ownership and TCP handoff were fixed; stale setup/TCP warnings during normal recovery were fixed. User subsequently confirmed immediate and 30-second Caps Lock success without warnings.
- October 18 tour-fix Air test passed sleep/wake by user, but logs showed transient `physicalKeysHeld` could fail ordinary startup. Source `9a2a7f9d9` routes that precise condition into existing readiness/retry after verified cleanup. It preserves all-up guard and cancellation. See `docs/bugs/2026-10-18-held-key-startup.md`.
- Held-key change full safe suite: **5,525 passed, 105 seconds**, plus dedicated interleaving and diagnostic regression tests. **Physical held-key/release acceptance is still pending.** Later branding and Help changes do not supersede that requirement.
- Clean VM onboarding, normal Accessibility consent, automatic progression, full four-page tour, rule lifecycle, Quit/reopen, uninstall backup/removal, reinstall and reboot passed prior candidate(s). Current sign-off lists exact evidence; don't reopen old resolved capacity/provisioning failures.
- Physical ESP32 Caps Lock tap Escape and hold Hyper passed on tour candidate. Authoritative receipts: `/Users/malpern/keypath-review-evidence/20261018-tour-final/caps-live/physical/caps-tap-keyup.json` and `caps-hold-keyup.json`. Hyper+F was configured in tour, but physical oracle used Hyper+A, not app-launch acceptance.
- Owned VM `cbx_6a7d61356f4e` was destroyed after evidence collection. **No VM is being handed over.** Genuine MacBook sleep cannot be established by a VM; user must exercise Air.

## Offline Help implementation (latest completed work)

Commits `95a24503a`, `b1dca7df0`, `5d5612023`; QA commit `27aebe43c` precedes this handoff.

- Same Markdown source as website: `guides/*.md`, `migration/*.md`, `assets/css/help-theme.css`.
- `Scripts/build-offline-help.py` generates self-contained HTML, CSS and images via build-time pandoc. Signed baseline: **43 guides, 106 files (~54 MiB)** in `Contents/Resources/OfflineHelp`.
- `OfflineHelpStore` actor opens bundled/cached files immediately, refreshes compatible major.minor content quietly via HTTPS, validates paths/schema/coverage/hashes/sizes, stages immutable generations and atomically switches a pointer. Failed/incomplete updates retain usable Help. No added permission, runtime renderer dependency or uploaded keyboard/config/log data.
- Cache: `~/Library/Application Support/KeyPath/Help/1.0`. Feed: `https://malpern.github.io/KeyPath/offline-help/1.0/manifest.json`.
- Latest revision **`b6c89de219bb62272283ce6c59e46d41050cc5f7f421cdee62ec5943d6b7d53c`**; live manifest equals signed bundle.
- WebKit loads local files, JS disabled, CSP prevents network subresources. External sites open browser and need internet. Current Installation topic uses `installation-wizard`, not stale getting-started installation.
- Fixes caught during QA: outer view needed full-size frame; generation identity must compare directory names rather than trailing-slash URL equality; publication filters manifest files rather than stale staging extras. Regression checks retained.
- Native fresh nonpersistent WebKit with all HTTP(S) blocked passed **43 articles / 66 image references**; production view setup/Privacy/cross-links checked. Real default-transport HTTPS updater probe installed revised Privacy from old baseline and retained it through offline restart. **12 focused Swift tests** passed; lint/accessibility/bundle contracts passed.
- Evidence: `/Users/malpern/keypath-review-evidence/20261018-offline-help/`, especially `native-qa/offline-report.json`, `live-probe.log`, `final-tests.log`, `final-build.log`, `final/`, `air-install/`.
- `docs/architecture/offline-help.md` has maintenance/testing commands. `Scripts/test-offline-help.sh OUTPUT` builds Help-only QA app, never KeyPath runtime.
- Documentation-only feed was published to gh-pages (`d9ea895e2`) from separate worktree `/Users/malpern/local-code/keypath-offline-help-feed`, branch `docs/offline-help-feed-20261018`. Never rewrite a published revision. No public app release occurred.

## Exact remaining acceptance before production

Ask user to run these on installed final Air build; capture timestamps, collect logs afterward. Batch into one short checklist, then fix only reproduced defects.

1. **Held-key startup (required):** Quit KeyPath normally. Hold an ordinary key such as Shift while reopening; release it. Must automatically reach Ready/remap without restart, permanent orange error, stuck keys or rerunning setup. Then test physical Caps Lock → Escape.
2. **Wake regression:** Apple menu → Sleep, wait one minute, wake/unlock. Caps Lock → Escape immediately and after 30 seconds, configured hold action, ordinary modifiers/typing; no false setup/TCP warning. Record local time. Correlate `pmset -g log` to real sleep: lid close alone and Transmission assertions previously invalidated tests. Don't alter power/network settings or quit unrelated apps unasked.
3. **Quit/reopen and reboot/login:** normal menu Quit/reopen preserves rules/remapping. One reboot/login respects existing Launch at Login setting (do not enable it just to pass). No stuck keys or surprise setup replay.
4. **Rule lifecycle:** add/edit/disable/delete one temporary simple remap via UI; verify actual output and cleanup in both JSON and generated config. Existing rules stay intact. Launcher edits use canonical configuration transaction; never hand-edit JSON only.
5. **Visual acceptance:** branded splash, no janky orange loading page/stranded splash; About tagline; four tour preview pages (nonmutating Help → Preview KeyPath Tour), drawer toggle, top-right hover/layer picker at small size and light/dark mode.
6. **Offline Help:** Wi-Fi off, open Installation, Privacy, illustrated guide and internal cross-link. Text/style/images must work without errors. Restore Wi-Fi. Automated coverage already strong; this is installed-shell sanity acceptance.

These are pending **manual confirmations**, not known current failures. Automated existing evidence need not be rerun wholesale for a doc or visual-only change. If user has already explicitly accepted an exact build/scenario, carry it forward with its limit rather than ask repeatedly.

After acceptance: freeze candidate, review entire branch against current origin/master, reconcile release notes/version/release-doctor, perform required full gate/review/CI/integration workflow, then public release **only when authorized**. Latest Help focused tests do not claim a fresh full-suite pass of the final binary. Before merge follow repo AGENTS/review gate; isolate merge conflicts and revalidate affected shared code. Do not blindly merge/rebase the long experiment during manual QA. No public PR/release was created by this handoff task.

## Fast continuation / constraints

- Active approval policy this turn: **never**, unrestricted filesystem/network. Recheck current policy in new session. Never ask for secrets in chat; Add Secret/sops wrappers only. Signing secrets must not appear in argv/logs.
- User wants regular compact progress updates, finish authorized work, use reduced models when appropriate; don't spend hours rebuilding infrastructure. Parallel review only if requested and isolated, never simultaneous runtime owners or builds in same worktree.
- **Do not install/launch KeyPath on mini host.** Keep host settings/TCC/network unchanged. Air install is authorized; preserve config and previous app archive. Always copy verified installer to Air Downloads when ready for more testing.
- Build: `KEYPATH_DEV_XCODE_DEVELOPER_DIR=/Applications/Xcode-27.app/Contents/Developer SKIP_NOTARIZE=1 SKIP_DEPLOY=1 SKIP_SPARKLE=1 SKIP_SNAPSHOTS=1 SKIP_WEBSITE=1 Scripts/build-and-sign.sh`. Stable pinned Xcode26.6 absent; override is deliberate. Stop Poltergeist first; no concurrent Swift build in same `.build`.
- SwiftFormat 0.61.1 at `/Users/malpern/.local/share/mise/installs/swiftformat/0.61.1/swiftformat`; do not use installed Homebrew0.64. Python/pandoc are build tools only.
- Prefer focused tests; full safe gate near integration, not every UI iteration. Keep `.build`, no broad cleans.
- Air logs: `~/Library/Logs/KeyPath/keypath-debug.log`. Read logs first. Canonical readonly readiness: `Scripts/verify-installed-app.sh` + sibling `verify-apple-silicon.sh`, `verify-session-runtime.py`. Air scratch copies exist under `/private/tmp/keypath-offline-help-verification/`.
- Verify actual parent/worker UID, nonce-bound private report and owned TCP listener; generic pgrep or legacy CLI service status isn't enough. Use untruncated `ps -axww -o pid=,args=` if diagnosing processes.
- If clean VM is necessary: read vm-lab skill and `docs/testing/remote-installer-lab.md`; managed admission only (`vm-lab keypath ...`), never raw provider creation, never mutate foreign leases, destroy owned lease after artifacts. Don't assume guest automation permissions/tools. Amortize setup across same-candidate scenarios.

## Ready-to-paste next-agent prompt

> Continue KeyPath production sign-off in `/Users/malpern/local-code/keypath-driverless-caps-ui` on `design/driverless-caps-ui`. Read AGENTS.md, `docs/testing/production-handoff-2026-10-18.md`, and the updated opening/current checklist of `docs/testing/driverless-release-signoff.md`. Verify active approval mode. The final notarized offline-Help build (source5d5612023, executable SHA1d55e260b70993b5813b6a917d4bf3f4dca8e43ff47b676a02698e4f0769fd75) is installed and launched on Air, with config preserved; DMG is in Downloads. Check the handoff's install-verification result. Give me the short remaining manual Air checklist, correlate my results with logs, fix any reproduced defects with focused regression tests, and finish release review/integration gates. Do not rebuild the lab, repeat completed research, uninstall my settings, install KeyPath on the mini, or publish a public release without authorization. Preserve the brand/tagline “Keys that do more.” and minimal driverless permissions. Keep regular concise updates and distinguish physical acceptance, automated checks, and public-release readiness.
