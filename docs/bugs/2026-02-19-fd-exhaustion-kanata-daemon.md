# File Descriptor Exhaustion: Kanata LaunchDaemon

**Date:** 2026-02-19
**Severity:** Intermittent reliability risk
**Status:** Investigated, two actionable findings

## Problem

The Kanata stderr log (`/var/log/com.keypath.kanata.stderr.log`) showed "Too many open files" errors. The LaunchDaemon plist hardcodes `NumberOfFiles: 256` — the macOS default soft limit. This is tight for a process that:
- Accepts TCP connections from KeyPath.app (EventListener, health checks, commands)
- Opens keyboard device file descriptors
- Maintains config file handles and log output

## Finding 1: Plist FD Limit Is Too Low

**Files:**
- `Sources/KeyPathApp/com.keypath.kanata.plist` (line 46)
- `Sources/KeyPathAppKit/InstallationWizard/Core/PlistGenerator.swift` (line 123)

Both hardcode:
```xml
<key>SoftResourceLimits</key>
<dict>
    <key>NumberOfFiles</key>
    <integer>256</integer>
</dict>
```

KeyPath.app can open multiple simultaneous connections to Kanata's TCP server:
- 1 persistent `KanataEventListener` connection (always active)
- `ServiceHealthMonitor` health check connections
- User-triggered command connections (`KanataTCPClient` for reload, layer change, fakekey, etc.)
- Wizard communication page checks

Each accepted TCP connection consumes a file descriptor on the Kanata side. Combined with device fds, config fds, and logging, 256 is insufficient under sustained operation.

**Recommendation:** Raise to 1024 in both the static plist and PlistGenerator.

## Finding 2: AppContextService Leaks TCP Connections

**File:** `Sources/KeyPathAppKit/Services/AppContextService.swift`

- `stop()` (line 104) sets `tcpClient = nil` without calling `cancelInflightAndCloseConnection()`
- `setTCPPort()` (line 223) replaces `tcpClient` with a new instance without closing the old one

Each stop/restart or port change leaks one `NWConnection` fd on the app side. Over time this accumulates.

**Recommendation:** Call `await tcpClient?.cancelInflightAndCloseConnection()` before setting to nil.

## Findings: What's Already Working Well

The investigation found that most TCP connection management is correct:

| Component | Pattern | Verdict |
|-----------|---------|---------|
| `KanataEventListener` | `defer { connection.cancel() }` on every connectAndStream() | Properly managed |
| `KanataTCPClient` | Connection reuse via `ensureConnectionCore()` | Good pooling |
| All ephemeral `KanataTCPClient` callers | Explicit `cancelInflightAndCloseConnection()` on all paths | Good (11 of 12 sites correct) |
| `ServiceHealthMonitor` | Shared `healthCheckClient` instance, skips TCP if EventListener recently active | Good optimization |
| `TCPProbe` | POSIX socket with `close()` on every path | Correct |

## Not a Concern

- **KanataEventListener 500ms polling** — This polls over a *single persistent connection*, not new connections per poll. The connection is properly cleaned up on reconnect via `defer`.
- **Ephemeral KanataTCPClient usage** — 11 of 12 call sites properly close connections. Only `AppContextService` is missing cleanup.

## Summary

The fd exhaustion is primarily a Kanata-side issue caused by the 256 limit being too low for the number of concurrent connections KeyPath maintains. The app-side leak in `AppContextService` is a minor contributor. The fix is straightforward: raise the limit and add the missing close call.
