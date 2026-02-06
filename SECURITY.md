# Security Policy

## Supported Versions

KeyPath is under active development. Security fixes are applied to the latest
release on the default branch.

## Reporting a Vulnerability

Do not open public GitHub issues for security vulnerabilities.

Use one of the private channels below:

- GitHub Security Advisory (preferred):
  https://github.com/malpern/KeyPath/security/advisories/new
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

KeyPath includes privileged helper and LaunchDaemon flows. Reports involving:

- privilege escalation
- unauthorized key capture/injection
- signing/notarization bypass
- unsafe service lifecycle behavior

are treated as high priority.
