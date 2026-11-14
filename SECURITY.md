# Security Policy

## Supported Versions

KeyPath is under active development. Security fixes are applied to the latest
release on the default branch.

## Reporting a Vulnerability

Do not open public GitHub issues for security vulnerabilities.

Use one of the private channels below:

- GitHub Security Advisory (preferred):
  https://github.com/malpern-labs/KeyPath/security/advisories/new
- Email fallback: malpern@gmail.com

Please include:

- A clear description of the issue
- Reproduction steps or proof-of-concept
- Impact assessment
- Environment details (macOS version, KeyPath version, install mode)

## Response Expectations

- Initial acknowledgement: within 5 business days
- Triage and severity assessment: as quickly as possible after acknowledgement
- Coordinated disclosure timeline: shared after triage

## Disclosure Process

1. Report is received privately.
2. Maintainers validate and scope the issue.
3. Fix is prepared and tested.
4. New release is published.
5. Advisory and credits are published when safe.

## Scope Notes

KeyPath holds Accessibility permission and sees keyboard input. Current builds
run the remapping engine as an ordinary process in the user's session, with no
privileged helper, LaunchDaemon or driver. KeyPath 1.0.1 and earlier did
install a privileged helper and a LaunchDaemon; reports against those versions
are still welcome.

Reports involving:

- unauthorized key capture or injection, including through the local engine
  control port, the CLI control socket, or `keypath://` URLs
- another process borrowing KeyPath's Accessibility permission
- running commands or scripts without the user's consent
- privilege escalation
- signing, notarization or update bypass

are treated as high priority.

The engine's control channel is a Unix-domain socket that admits only the app
that launched the session worker (uid, PID and PID version on every
connection; [ADR-046](docs/adr/adr-046-session-engine-control-channel.md)).
It replaced an unauthenticated port on `127.0.0.1:37001`. The engine also
checks the connecting process's code signature: its running code must satisfy
KeyPath's own designated requirement, so code injected into KeyPath, or a
program posing as it, is refused. Any way to reach the engine from another
process is worth reporting.
