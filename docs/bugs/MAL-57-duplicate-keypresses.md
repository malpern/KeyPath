# MAL-57: Duplicate Key Presses Under Load

**Status:** Active investigation

The earlier work in this document likely fixed at least one duplicate-notification issue in
KeyPath's TCP/UI observation path. It did **not** conclusively close the real user-facing
symptom of extra typed characters under load. Treat the historical "resolved" sections below
as previous conclusions, not final truth.

Latest investigation summary:

- [`docs/analysis/2026-03-07-duplicate-key-under-load-investigation.md`](/Users/malpern/local-code/KeyPath/.worktrees/duplicate-key-investigation/docs/analysis/2026-03-07-duplicate-key-under-load-investigation.md)

## Problem Statement

Users report duplicate key presses "especially under load" - the same keypress appears twice in rapid succession in the Recent Keypresses view and keyboard visualization overlay.

## Root Cause Analysis

### Critical Issues Identified

#### 1. **Broadcast Draining Timeout (HIGH SEVERITY)**
**Location**: `KanataTCPClient.swift:920`

```swift
let maxDrainAttempts = 10 // Prevent infinite loop
```

**Problem**: Under load, 10 attempts (10 x 5s timeout = 50s max) may exhaust before finding the correct response, especially when:
- Many unsolicited broadcasts (LayerChange, MessagePush) are interleaved
- Multiple requests are queued
- Network latency increases buffer accumulation

**Evidence**: Lines 967-969 throw `invalidResponse` when attempts exhausted, potentially leaving responses unread in the TCP buffer.

---

#### 2. **Weak Request ID Fallback (HIGH SEVERITY)**
**Location**: `KanataTCPClient.swift:954-959`

```swift
} else {
    // We sent request_id but response doesn't have one
    // This might be an old server - accept it as the response
    AppLogger.shared.debug(
        "⚠️ [TCP] Response missing request_id (old server?), accepting anyway")
    break
}
```

**Problem**: This "old server" fallback can **accept broadcasts as responses**:
1. Send `Reload` with `request_id=42`
2. Kanata emits unsolicited `LayerChange` broadcast (no request_id)
3. Broadcast passes `isUnsolicitedBroadcast()` check (line 931)
4. Code accepts it as the Reload response (line 959)
5. Actual Reload response remains in buffer
6. Next request gets stale Reload response
7. State desync causes duplicate events

---

#### 3. **No Event Deduplication (HIGH SEVERITY)**
**Location**: `RecentKeypressesService.swift:85-99`

```swift
private func addEvent(key: String, action: String) {
    let event = KeypressEvent(
        key: key,
        action: action,
        timestamp: Date(),
        layer: currentLayer
    )

    events.insert(event, at: 0)  // No duplicate check!

    if events.count > maxEvents {
        events = Array(events.prefix(maxEvents))
    }
}
```

**Problem**: Every notification is added immediately without checking if:
- Same key was just pressed within 100ms (likely duplicate)
- Same (key, action, layer) tuple already exists in last N events
- Event is a replay after reconnection

**Impact**: Duplicate notifications = duplicate UI events = double keypresses shown to user.

---

#### 4. **No Reconnection Replay Protection (MEDIUM SEVERITY)**
**Location**: `KanataEventListener.swift:425-444`

```swift
var buffer = Data()  // Fresh buffer on each connection

while !Task.isCancelled {
    guard let chunk = try await receiveChunk(on: connection) else {
        throw ListenerError.connectionClosed
    }
    if chunk.isEmpty { continue }
    buffer.append(chunk)

    while let newlineIndex = buffer.firstIndex(of: 0x0A) {
        // ... process line ...
        await handleLine(line)
    }
}
```

**Problem**: When EventListener reconnects:
1. New TCP connection established to Kanata
2. Fresh buffer created (line 425)
3. **No "seen events" cache** across connections
4. If Kanata replays recent events (state sync), KeyPath processes them again
5. Duplicate events posted to NotificationCenter

**Scenario**:
- User types "hello" fast
- Connection drops after "hel"
- Reconnect occurs
- Kanata re-sends "hel" + "lo" for state consistency
- UI shows: "helhello"

---

### Secondary Contributing Factors

#### 5. **Concurrent TCP Connections (MEDIUM RISK)**
- `KanataTCPClient`: Command/response pattern
- `KanataEventListener`: Streaming event pattern
- Both connect to same port 37001 with independent buffers
- No coordination if broadcasts are sent to both connections

#### 6. **Poll Task Interference (LOW RISK)**
**Location**: `KanataEventListener.swift:415-423`

```swift
pollTask = Task(priority: .background) { [weak self, weak connection] in
    while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 500_000_000)  // Every 500ms
        try? await send(
            jsonObject: ["RequestCurrentLayerName": [:] as [String: String]], over: connection
        )
    }
}
```

**Problem**: This poll runs every 500ms and expects a response. If under load:
- Poll response might be consumed by main event loop
- Or main event might be mistaken for poll response
- No request_id coordination between poll and main stream

---

## Reproduction Steps

### Minimal Repro

1. **Configure fast remapping:**
   ```
   (defremap test
     a b
     b c
     c d
     ... (50+ mappings)
   )
   ```

2. **Generate load:**
   - Hold down a key for 5+ seconds (generates ~50-100 KeyInput events)
   - OR use `xdotool` / AppleScript to send rapid keypresses
   - OR open Recent Keypresses view and type quickly

3. **Observe:**
   - Recent Keypresses view shows duplicate entries
   - Same key appears twice with timestamps within milliseconds
   - Example: `a (press) 12:34:56.123` followed by `a (press) 12:34:56.124`

### Advanced Repro (Reconnection)

1. Start KeyPath with Kanata running
2. Open Recent Keypresses view
3. Type a sequence: "test"
4. Kill Kanata daemon: `sudo killall kanata`
5. Restart Kanata: `sudo launchctl kickstart -k system/com.keypath.kanata`
6. Type "test" again quickly
7. **Expected**: 8 events (4 + 4)
8. **Actual**: 12-16 events (duplicates from replay)

---

## Proposed Fixes

### P0: Event Deduplication in RecentKeypressesService

**File**: `Sources/KeyPathAppKit/Services/RecentKeypressesService.swift`

**Change**:
```swift
private func addEvent(key: String, action: String) {
    let event = KeypressEvent(
        key: key,
        action: action,
        timestamp: Date(),
        layer: currentLayer
    )

    // DEDUPLICATION: Skip if identical event exists within last 100ms
    let deduplicationWindow: TimeInterval = 0.1  // 100ms
    let now = event.timestamp

    if let lastEvent = events.first,
       lastEvent.key == event.key,
       lastEvent.action == event.action,
       lastEvent.layer == event.layer,
       now.timeIntervalSince(lastEvent.timestamp) < deduplicationWindow {
        AppLogger.shared.debug("🚫 [Keypresses] Skipping duplicate: \(key) \(action) within \(Int(now.timeIntervalSince(lastEvent.timestamp) * 1000))ms")
        return
    }

    events.insert(event, at: 0)

    if events.count > maxEvents {
        events = Array(events.prefix(maxEvents))
    }
}
```

**Rationale**: Physical key presses cannot occur within <100ms realistically. Any event within this window is likely a duplicate from:
- TCP buffer replay
- Broadcast draining confusion
- Reconnection replay

**Testing**:
- Unit test: Verify duplicate within 100ms is skipped
- Unit test: Verify different key within 100ms is accepted
- Unit test: Verify same key after 100ms is accepted

---

### P0: Fix Request ID Fallback Logic

**File**: `Sources/KeyPathAppKit/Services/KanataTCPClient.swift`

**Change** (lines 954-960):
```swift
} else {
    // We sent request_id but response doesn't have one
    // This could be:
    // 1. An unsolicited broadcast that slipped through (REJECT)
    // 2. An old server (unlikely - all recent versions support request_id)

    // For safety, REJECT responses without request_id when we sent one
    if let msgStr = String(data: responseData, encoding: .utf8) {
        AppLogger.shared.warning(
            "⚠️ [TCP] Response missing request_id when we sent \(sentId) - likely broadcast, skipping: \(msgStr.prefix(100))"
        )
    }
    continue  // Changed from 'break' to 'continue'
}
```

**Rationale**: Modern Kanata versions support `request_id`. Accepting responses without it creates ambiguity. Better to:
- Skip the response and wait for the real one
- If maxDrainAttempts exhausts, throw error (existing behavior line 967)
- User gets error instead of silent state corruption

**Testing**:
- Integration test: Send command with request_id, inject broadcast without request_id, verify command response is found
- Integration test: Verify timeout if response never arrives

---

### P1: Increase Broadcast Drain Attempts

**File**: `Sources/KeyPathAppKit/Services/KanataTCPClient.swift`

**Change** (line 920):
```swift
let maxDrainAttempts = 50  // Increased from 10 - under load, many broadcasts can arrive
```

**Rationale**: Under load, Kanata emits:
- LayerChange broadcasts (every layer switch)
- MessagePush broadcasts (custom actions, TCP commands)
- KeyInput broadcasts (if event listener is also connected)

10 attempts may exhaust quickly. 50 attempts = 250s max timeout (unlikely to need that long, but provides safety margin).

**Alternative**: Make configurable via environment variable:
```swift
let maxDrainAttempts = Int(ProcessInfo.processInfo.environment["KEYPATH_MAX_DRAIN_ATTEMPTS"] ?? "50") ?? 50
```

---

### P1: Add Reconnection Event Cache

**File**: `Sources/KeyPathAppKit/Services/KanataEventListener.swift`

**Change** (add as class property):
```swift
/// Cache of recently seen events to prevent replay after reconnection
/// Key: "\(key)|\(action)|\(timestamp_rounded_to_100ms)"
/// Evict entries older than 5 seconds
private var seenEventsCache: [String: Date] = [:]
private let seenEventsCacheDuration: TimeInterval = 5.0
```

**Change** (in handleLine method, before posting notification):
```swift
// Generate cache key (round timestamp to 100ms buckets)
let timestampBucket = Int(Date().timeIntervalSince1970 * 10)  // 100ms buckets
let cacheKey = "\(key)|\(action)|\(timestampBucket)"

// Check cache
if let lastSeen = seenEventsCache[cacheKey],
   Date().timeIntervalSince(lastSeen) < seenEventsCacheDuration {
    AppLogger.shared.debug("🚫 [EventListener] Skipping replay: \(key) \(action)")
    return
}

// Add to cache
seenEventsCache[cacheKey] = Date()

// Evict old entries (run every 100 events or so)
if seenEventsCache.count > 1000 {
    let cutoff = Date().addingTimeInterval(-seenEventsCacheDuration)
    seenEventsCache = seenEventsCache.filter { $0.value > cutoff }
}

// Post notification (existing code)
NotificationCenter.default.post(...)
```

**Rationale**: Prevents duplicate notifications from being posted when:
- Reconnection causes Kanata to replay state
- TCP buffers contain old events
- Network issues cause retransmission

**Testing**:
- Unit test: Verify same event within 5s is cached
- Unit test: Verify cache eviction after 5s
- Integration test: Simulate reconnection, verify no duplicate notifications

---

### P2: Unify TCP Connection Management

**Goal**: Use a single persistent connection for both commands and events, eliminating concurrent connection interference.

**Design**:
1. `KanataTCPClient` becomes the single TCP connection owner
2. `KanataEventListener` becomes a consumer of events from `KanataTCPClient`
3. `KanataTCPClient` dispatches incoming messages:
   - Command responses → Return to caller (existing)
   - Unsolicited broadcasts → Forward to `KanataEventListener`

**Benefits**:
- No broadcast draining needed (events go to listener, not command handler)
- Simpler request/response correlation
- Reduced network overhead (one connection instead of two)

**Risks**:
- Larger refactor, more testing needed
- Possible breaking changes to API

**Defer to P2** - Fix P0/P1 issues first, evaluate if P2 is still needed.

---

## Testing Strategy

### Unit Tests

1. **RecentKeypressesService deduplication:**
   - Test duplicate within 100ms is skipped
   - Test different key within 100ms is accepted
   - Test same key after 101ms is accepted
   - Test deduplication respects layer changes

2. **KanataTCPClient request_id handling:**
   - Test response with matching request_id is accepted
   - Test response with mismatched request_id is skipped
   - Test broadcast without request_id is skipped when request_id was sent
   - Test maxDrainAttempts timeout behavior

3. **KanataEventListener replay cache:**
   - Test cache prevents duplicate within 5s
   - Test cache allows duplicate after 5s
   - Test cache eviction after threshold

### Integration Tests

1. **Load test:** Generate 100 keypresses in 1 second, verify no duplicates in Recent Keypresses
2. **Reconnection test:** Disconnect/reconnect during typing, verify no event replay
3. **Broadcast storm test:** Trigger many layer changes while sending commands, verify responses are correct

### Manual Testing

1. **User repro:** Hold down a key for 5 seconds, check Recent Keypresses for duplicates
2. **Network stress:** Use `tc` to add latency/packet loss, verify robustness
3. **Kanata restart:** Kill/restart Kanata during active typing, verify graceful recovery

---

## Telemetry & Observability

Add counters to track:
1. **Duplicates detected and skipped** (in RecentKeypressesService)
2. **Broadcast drain attempts** (average/max per command in KanataTCPClient)
3. **Reconnection event replays skipped** (in KanataEventListener)
4. **maxDrainAttempts exhausted** (error rate in KanataTCPClient)

Expose via:
- Debug logs (existing)
- Stats endpoint (future)
- Crashlytics/Sentry custom metrics (future)

---

## Rollout Plan

1. **Week 1**: Implement P0 fixes (deduplication + request_id)
2. **Week 1**: Unit tests + integration tests
3. **Week 2**: Internal dogfooding with telemetry
4. **Week 2**: Analyze metrics, adjust deduplication window if needed
5. **Week 3**: Beta release to affected users
6. **Week 4**: Monitor for 1 week, then promote to stable

---

## Success Criteria

1. ✅ No duplicate events in Recent Keypresses view during normal typing
2. ✅ No duplicate events during 100 keypress/sec load test
3. ✅ No duplicate events after Kanata daemon restart
4. ✅ All unit tests pass
5. ✅ No user reports of duplicate keypresses in beta testing

---

## Related Issues

- [ADR-023: No Config Parsing](../adr/adr-023-no-config-parsing.md) - We rely on TCP events, not config parsing
- [ADR-022: No Concurrent Pgrep](../adr/adr-022-no-concurrent-pgrep.md) - Concurrency lessons apply here

---

## Open Questions

1. **Q**: Should deduplication window be user-configurable?
   **A**: No - 100ms is safe for all typing speeds. Advanced users can adjust via code if needed.

2. **Q**: Should we add telemetry for duplicate rate?
   **A**: Yes (P2) - helps detect regressions and understand real-world duplicate frequency.

3. **Q**: Does Kanata itself emit duplicates?
   **A**: Unknown - need to test Kanata in isolation. If yes, fix should go upstream.

4. **Q**: Should reconnection cache be per-layer or global?
   **A**: Global - layer change itself is an event that could duplicate.

---

## Timeline

- **Analysis**: 2026-01-11 (completed)
- **P0 Implementation**: 2026-01-11 (completed)
- **Unit Testing**: 2026-01-11 (completed - 12/12 tests passing)
- **Ready for Deployment**: 2026-01-11
- **Validation Testing**: 2026-02-18 (completed - see below)

## Implementation Status

### ✅ Completed (P0)

1. **Event Deduplication in RecentKeypressesService** - `Sources/KeyPathAppKit/Services/RecentKeypressesService.swift:85-115`
   - Added 100ms deduplication window
   - Checks last 10 events for (key, action, layer) tuple matches
   - Safely allows double letters (e.g., "tt" in "letter")
   - Prevents TCP duplicate/replay scenarios

2. **Fixed Request ID Fallback** - `Sources/KeyPathAppKit/Services/KanataTCPClient.swift:954-964`
   - Changed from accepting broadcasts without request_id to skipping them
   - Prevents broadcasts from being mistaken as command responses
   - Uses `AppLogger.shared.warn()` for visibility

3. **Increased Broadcast Drain Attempts** - `Sources/KeyPathAppKit/Services/KanataTCPClient.swift:920`
   - Increased from 10 to 50 attempts
   - Handles high-load scenarios with many interleaved broadcasts

4. **Comprehensive Unit Tests** - `Tests/KeyPathTests/Services/RecentKeypressesServiceTests.swift`
   - 12 tests covering all deduplication scenarios
   - Tests double letter typing (legitimate doubles)
   - Tests TCP replay scenarios
   - Tests layer changes, recording toggle, edge cases
   - All tests passing ✅

---

## ⚠️ Validation Attempt #1 (2026-02-18) — INVALID

Automated validation using `Scripts/run-duplicate-key-test.sh` with osascript auto-typing.

### Results (not trustworthy)

| Test | Preset | Result |
|------|--------|--------|
| Phase 1: Pipeline (repro harness) | baseline | 0 alerts |
| Phase 1: Pipeline (repro harness) | high (compile loop + 6 CPU hogs) | 0 alerts |
| Phase 2: Keystroke fidelity (auto-type into Zed, diff expected vs actual) | high | 575/575 match |

### Why These Results Are Invalid

**osascript `keystroke` bypasses Kanata entirely.** osascript injects CGEvents at the
Accessibility/Core Graphics layer, which is above Kanata's IOKit HID intercept point. Kanata
grabs the physical keyboard device and reads raw USB HID reports — software-generated keystrokes
never reach it.

**Evidence:** Kanata CPU was **0.0% across every sample** during all test runs. If Kanata were
processing those keystrokes, it would show non-zero CPU usage.

**What the tests actually proved:**
- Text can be typed into Zed via osascript without corruption (trivially true)
- The system doesn't crash under CPU load

**What they did NOT prove:**
- That Kanata handles physical keystrokes without duplication under load
- That tap-hold timing is stable under CPU starvation
- That the HID event path is clean

### Lesson Learned

There is no userspace API on macOS to inject events at the IOKit HID device level. All
software keystroke injection (osascript, CGEventPost, cliclick, peekaboo) enters above
Kanata's intercept point. Valid testing requires physical keyboard input.

### Status: **REOPENED** — awaiting manual typing validation (Phase 3)

---

## ⚠️ Validation #2 (2026-02-18) — VALID PHYSICAL INPUT, BUT NOT DECISION-COMPLETE

Manual typing test using `Scripts/manual-keystroke-test.sh` with physical keyboard input
through Kanata's real IOKit HID intercept → engine → virtual HID pipeline.

### Test Configuration

- **Preset:** high (Swift compile loop + 6 CPU hog processes)
- **Reference passage:** 184 words, 1182 chars (prose + Swift code + numbers + punctuation)
- **Input method:** Physical keyboard (human typing)
- **Duplicate detection:** `RecentKeypressesService` consecutive-key diagnostic with nav/modifier
  keys excluded (backspace, arrows, shift, space, enter, etc.)

### Results

| Metric | Value |
|--------|-------|
| Key events processed by Kanata | **2,388** |
| Layer events | 854 |
| DUPLICATE DETECTION alerts (text keys) | **0** |
| Dedup filter skips | **0** |
| Ignored nav/modifier repeats | 0 |
| Reference chars | 1,182 |
| Typed chars | 1,123 |
| Difference | -59 (normal typing variation — fewer chars typed, not extra) |

### HID Path Validation

Kanata processed **2,388 key events** — confirming the physical keyboard HID path was fully
exercised. This contrasts with Validation #1 where Kanata showed 0.0% CPU and ~2 events
(proving osascript bypassed it entirely).

### Key Findings

1. **Zero duplicate detection alerts.** Under high CPU load, Kanata did not produce a single
   instance of the same text key being pressed 3+ times within 500ms.

2. **Zero dedup filter activations.** The 100ms dedup safety net in `RecentKeypressesService`
   was not triggered at all — meaning clean, non-duplicate events are coming through the TCP
   pipeline. The P0 request_id and drain fixes resolved the notification-layer duplicates.

3. **Kanata's HID processing is stable under load.** Tap-hold timing, event debouncing, and
   key remapping all functioned correctly with 6 CPU hogs + a compile loop running.

4. **The -59 char difference is human typing variation** (skipped words, typos), not dropped
   keystrokes. No characters were added — ruling out duplicate HID output.

### Historical Conclusion

This run strongly suggested the notification-layer duplicate issue had improved, but it did not
rule out sporadic real typed-output duplication. The detector only flagged 3x same-key streaks,
and the single manual session was not enough to conclusively close an intermittent under-load
typing complaint.

### Revised Status: **ACTIVE INVESTIGATION**

## Investigation Phase 2 (2026-03-07)

### Narrowed Hypotheses

1. **Observation-only duplication** — KeyPath's TCP/UI layer still duplicates or replays events,
   but real typed output is clean.
2. **Real HID/output duplication** — extra characters are being produced in the actual remap path
   under load.
3. **Reconnect/replay duplication** — duplicates cluster around `KanataEventListener`
   reconnects or Kanata restarts rather than steady-state typing.

### Investigation Additions

- `Scripts/manual-keystroke-test.sh` is now the primary manual harness and supports:
  - a `compile` preset for realistic repeated rebuild pressure
  - `--reconnect-after` to force a Kanata restart mid-typing
  - artifact output focused on inserted-text analysis, not just 3x same-key streaks
- `KanataEventListener` now emits investigation markers in debug mode:
  - session start
  - reconnect pending
  - session end
  - per-event `KeyInput` lines with session ID and Kanata timestamp when available
- `RecentKeypressesService` now records listener session metadata so duplicate correlations can be
  classified as same-session vs cross-session without changing production behavior
- `ConfigHotReloadService` and `RuntimeCoordinator.triggerConfigReload()` now emit reload-boundary
  investigation markers with held-key snapshots
- `KanataEventListener` now classifies low-level key transitions so we can distinguish:
  - fresh press
  - press while already held
  - release after hold
  - release without tracked press
  - repeat while held
- `InvestigationEventTapService` now installs an investigation-only passive CGEvent tap so each run
  can compare:
  - Kanata TCP `KeyInput` events
  - macOS session-level key down/up/repeat events
  - final editor text

### Required Artifact Bundle Per Run

Each manual run should save:

- `reference.txt`
- `actual-output.txt`
- `diff-report.txt`
- `word-diff.txt`
- `log-slice.txt`
- `session-markers.txt`
- `addition-windows.txt`
- `repeated-char-windows.txt`
- `repeated-word-windows.txt`
- `suspicious-additions-summary.txt`
- `analysis.txt`
- `verdict.txt`

### What Counts As Suspicious Now

- Any unintended inserted text in the output
- Any repeated-character insertion window
- Any repeated-word insertion window
- Any duplicate cluster that crosses listener session boundaries

The burden of proof is now higher: one clean manual run is not enough to close the bug.

### Phase 2 Findings So Far

- Real repeated output has now been reproduced under `compile` load in manual runs.
- A reconnect-control run also reproduced the issue, but reconnect was not required.
- One run showed a real external `ConfigHotReload` event mid-typing. That likely explains a
  visible pause, but it does not explain the entire bug because a separate compile-load run
  reproduced repeated characters without any reload marker in the artifact window.

### Next Manual Review Focus

For the next repro runs, inspect:

- `log-slice.txt` for `ReloadBoundary`
- `session-markers.txt` for `KeyTransition` and `SystemKeyEvent`
- whether repeated characters line up with:
  - `press-while-held`
  - `release-without-tracked-press`
  - reload boundaries with held keys present
  - `SystemKeyEvent is_autorepeat=true` without a matching Kanata `repeat`

---

## References

- `Sources/KeyPathAppKit/Services/KanataTCPClient.swift` - Lines 892-983
- `Sources/KeyPathAppKit/Services/KanataEventListener.swift` - Lines 384-450
- `Sources/KeyPathAppKit/Services/RecentKeypressesService.swift` - Lines 60-99
- Kanata TCP Protocol: https://github.com/jtroo/kanata/blob/main/docs/tcp_server.md
