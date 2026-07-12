# macOS 27 Regression Matrix

Run this matrix on every significant macOS 27 beta seed and again on the GM.
Keep automated evidence separate from approval interactions that require a clean
or disposable account.

## Automated capture

```bash
Scripts/qa-macos-27-regression.sh
```

The capture fails unless the host is running macOS 27 and the installed app
passes code-signature, Gatekeeper, stapling, and TCP-readiness checks. It records
the canonical `keypath-cli system inspect --json` snapshot rather than reading
TCC databases directly.

| Area | Evidence |
| --- | --- |
| Exact beta seed | `sw-vers.txt`, `captured-at.txt` |
| Permission/runtime state | `system-inspect.json` |
| Driver approval | `system-extensions.txt` |
| SMAppService/runtime jobs | `kanata-launchd.txt`, `vhid-*-launchd.txt` |
| XPC and bundle signing | `codesign.txt` |
| Distribution trust | `gatekeeper.txt`, `stapler.txt` |
| Keyboard runtime | process files, `tcp-readiness.txt`, logs |

## Operator matrix

Use a disposable desktop VM or clean local account. Capture screenshots before
and after each approval, then rerun the automated capture after reboot.

| State | Expected KeyPath result |
| --- | --- |
| Accessibility denied | Exact Accessibility action; no false runtime success |
| Accessibility newly granted | Current state appears after the supported refresh/relaunch path |
| Input Monitoring denied | `PermissionOracle` reports denial and identifies KeyPath precisely |
| Input Monitoring newly granted | Current IOHID result wins over stale fallback evidence |
| Background App Activity pending | Pending approval is distinct from installation/runtime failure |
| VirtualHID extension disabled | Driver Extension action opens the macOS 27 settings surface |
| Karabiner app installed, grabber stopped | No conflict is reported |
| `karabiner_grabber` running | A specific conflict and recovery action are reported |
| All approvals granted | `planStatus=ready`, `isOperational=true`, TCP responding |
| Reboot after healthy setup | Helper, daemon, permissions, and TCP readiness persist |

Do not reset or copy TCC databases as part of artifact collection. Do not store
credentials, Apple IDs, private keys, or passwords in the evidence bundle.

## Current beta checkpoint

On 2026-07-11, the non-destructive capture ran on macOS 27.0 build `26A5378j`
against the installed local build. With distribution-trust checks explicitly
disabled for harness development, it reported:

- `planStatus=ready`
- `driverCompatible=true`
- `isOperational=true`
- VirtualHID `[activated enabled]`
- KeyPath and Kanata processes present
- TCP ready on `127.0.0.1:37001`
- bundle code signature valid

This checkpoint validates the harness and current healthy-runtime path. It does
not satisfy the clean-account approval matrix or the signed/notarized trust
gate; those require a release-candidate artifact with the default strict mode.
