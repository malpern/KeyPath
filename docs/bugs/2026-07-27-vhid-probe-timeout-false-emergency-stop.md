# VHID probe timeouts caused false emergency stops

## Symptom

KeyPath could stop an otherwise healthy Kanata runtime while the VirtualHID
daemon and DriverKit extension remained available. The debug log showed the
safety monitor treating a timed-out `systemextensionsctl list` probe as proof
that VirtualHID was unhealthy.

## Root cause

The runtime safety path reused a Boolean health API. That API intentionally
collapsed an inconclusive system-extension query to `false`, which is useful
for ordinary status display but unsafe as destructive evidence. On macOS 27,
`systemextensionsctl list` can outlive KeyPath's subprocess timeout and ignore
the initial termination signal, making the inconclusive state reproducible
under system load.

The safety monitor then converted the single `false` observation directly into
an emergency stop. It did not distinguish a missing service from a failed
probe, and it did not require confirmation.

## Durable rule

Runtime safety decisions use tri-state evidence:

- `healthy` means the DriverKit extension is enabled and launchd reports a live
  VirtualHID daemon;
- `confirmedUnhealthy` means current evidence affirmatively shows the extension
  or daemon is absent or in a recognized stopped state;
- `unknown` preserves timeouts, command failures, and malformed responses.

Only two `confirmedUnhealthy` observations may stop Kanata. `unknown` neither
advances nor erases that evidence; only `healthy` resets the confirmation
sequence. This keeps the fail-safe invariant while preventing an observability
failure from becoming a service mutation.

An unknown system-extension result does not short-circuit the independent
launchd probe. A missing or recognized stopped daemon can therefore still be
confirmed during a `systemextensionsctl` outage. If both evidence sources are
inconclusive, KeyPath deliberately leaves the result `unknown` rather than
turning loss of observability into a destructive action.
