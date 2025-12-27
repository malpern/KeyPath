# ADR-013: TCP Communication Without Authentication

**Status:** Accepted (with caveats)
**Date:** 2024

## Context

KeyPath communicates with Kanata via TCP for runtime control (layer switching, config reloading, push-msg).

## Decision

Use TCP without authentication for localhost IPC.

## Rationale

- Kanata 1.9.0 TCP server does not support authentication
- Connection is localhost-only (127.0.0.1)
- Same security model as other local IPC (Unix sockets, etc.)

## Security Considerations

- Any local process can send commands to Kanata
- This is acceptable for keyboard remapping (low security impact)
- If Kanata adds auth in future versions, we should adopt it

## Implementation

```swift
// TCP connection to Kanata
let connection = TCPConnection(host: "127.0.0.1", port: 9999)
await connection.send("layer-names")
```
