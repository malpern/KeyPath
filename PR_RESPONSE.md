# Response to Maintainer Question

**Re: UDP in PR**

Hey! Just to clarify — we're **not adding UDP** at all. This PR is purely TCP improvements.

## What We're Proposing to Add

We're proposing to integrate Kanata's **TCP Status endpoint** (`{"Status":{}}`) into our diagnostics system. Specifically:

1. **Wire TCP status into diagnostics** — Check engine readiness, uptime, and last reload status via TCP instead of parsing logs
2. **Health monitoring improvements** — Better detection of when Kanata is actually ready vs just running
3. **Log monitoring polish** — Better handling of VirtualHID connection state changes

All code uses `NWConnection` with `.tcp` protocol and `KanataTCPClient` — no UDP anywhere.

## Why This Matters for Our Tooling

Right now we have to:
- Poll log files to detect when `driver_connected 1` appears (race conditions, slow)
- Shell out to `kanata --check` for validation (slow, error-prone)
- Guess if the engine is "ready" based on process state alone

With the Status endpoint:
- **Instant readiness checks** — Know immediately if engine is ready to remap (no log parsing)
- **Better UX** — Show users accurate engine state in real-time
- **Reliable diagnostics** — Surface issues like "last reload failed" directly from the engine

The Status endpoint already exists in Kanata — we're proposing to use it properly instead of scraping logs.

The only UDP mention is a comment suggesting future TCP auth could mirror UDP's approach. That's just a note, not implementation.

Hope that clarifies things! Happy to answer any other questions.

