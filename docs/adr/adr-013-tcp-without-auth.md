# ADR-013: TCP Communication Without Authentication

> **Note (2026-10-31):** This was written for the root daemon. The runtime now runs
> in a user session that holds the user's input permissions, so this risk needs
> review. See ADR-045.
>
> **Note (2026-11-04):** This was written for the root daemon, which ADR-045
> retired. The session runtime holds the user's input permissions, and from a
> source review the port exposes a keystroke stream and input injection to
> every local process. The review and the proposed replacement are in
> [ADR-046](adr-046-session-engine-control-channel.md); tracked in
> [#1354](https://github.com/malpern/KeyPath/issues/1354).

**Status:** Under review; proposed to be superseded by [ADR-046](adr-046-session-engine-control-channel.md)
**Date:** 2024

## Context

KeyPath communicates with Kanata via TCP for runtime control (layer switching, config reloading, push-msg).

## Decision

Use TCP without authentication for localhost IPC.

## Rationale

- Kanata 1.9.0 TCP server does not support authentication
- Connection is localhost-only (127.0.0.1)
- Same security model as other local IPC (Unix sockets, etc.) *(Wrong: loopback TCP has no peer-uid check and is reachable from other users and sandboxed apps. See ADR-046.)*

## Security Considerations

- Any local process can send commands to Kanata
- This is acceptable for keyboard remapping (low security impact) *(No longer true for the session runtime: the port exposes a keystroke stream and input injection. See ADR-046.)*
- If Kanata adds auth in future versions, we should adopt it

## Implementation

```swift
// TCP connection to Kanata
let connection = TCPConnection(host: "127.0.0.1", port: 37001)
await connection.send("layer-names")
```
