# Kanata TCP Reload Crash - Debugging Progress

**Date:** November 17, 2025  
**Status:** Instrumentation added, ready for testing

## Summary

Added comprehensive logging instrumentation to Kanata's TCP reload path to help identify where the ~43-second delay occurs before the crash.

## Changes Made

### 1. TCP Server Reload Handler (`src/tcp_server.rs`)

**Added timing instrumentation:**
- Track total elapsed time from reload command receipt to completion
- Log when `handle_client_command` is called and when it returns
- Detailed wait loop logging:
  - Log every 20 polls or when elapsed > 1 second
  - Track poll count and elapsed time
  - Log when readiness is detected
  - Log final wait loop completion status
- Log when ReloadResult response is sent

**Key logging points:**
```rust
- "tcp server Reload action (wait=..., timeout_ms=...)" - Command received
- "Reload: calling handle_client_command" - Starting command processing
- "Reload: handle_client_command returned Ok" - Command completed
- "Reload: Starting wait loop (timeout=Xms)" - Wait loop begins
- "Reload: wait loop poll #N: elapsed=Xms" - Periodic progress updates
- "Reload: wait loop detected ready=true" - Readiness achieved
- "Reload: wait loop completed: ready=..., elapsed=..., polls=..." - Wait loop finished
- "Reload: ReloadResult sent successfully" - Response sent
- "Reload: Complete wait path finished: total_elapsed=..., wait_elapsed=..." - Final summary
```

### 2. Live Reload Function (`src/kanata/mod.rs`)

**Added phase-by-phase timing:**
- Track config file parsing time
- Track `update_kbd_out` execution time
- Track total reload duration
- Log when `last_reload_time` is set (critical for `is_ready()`)

**Key logging points:**
```rust
- "do_live_reload: Starting reload of <path>" - Reload begins
- "do_live_reload: Config parsed in Xms" - Parse phase complete
- "do_live_reload: update_kbd_out completed in Xms" - Update phase complete
- "do_live_reload: Reload completed successfully in Xms, last_reload_time set, is_ready() should now return true" - Reload complete
```

## Expected Behavior

With these logs, we should be able to see:

1. **If crash happens during wait loop:**
   - Last log will show wait loop progress
   - Will see poll count and elapsed time before silence
   - Can determine if timeout was reached or crash happened mid-loop

2. **If crash happens after wait loop completes:**
   - Will see "Reload: Complete wait path finished" log
   - Can measure time between wait completion and crash
   - Can verify if ReloadResult was successfully sent

3. **If crash happens during do_live_reload:**
   - Will see which phase of reload was executing
   - Can identify if it's config parsing, kbd_out update, or state mutation

4. **Timing analysis:**
   - Can correlate TCP handler timing with processing loop timing
   - Will reveal if the 43-second delay is:
     - Accumulated wait loop timeouts
     - Delay between wait completion and crash
     - Delay in processing loop before reload executes

## Next Steps

### 1. Build and Deploy Instrumented Kanata

```bash
cd External/kanata
cargo build --release --features tcp_server
# Deploy the built binary to replace current kanata daemon
```

### 2. Reproduce the Crash

- Trigger the TCP reload with `wait=true` as before
- Monitor logs at `/var/log/com.keypath.kanata.stdout.log`
- Capture full log output during crash window

### 3. Analyze Logs

Look for:
- **Last log entry before crash** - identifies crash location
- **Timing gaps** - where does the 43-second delay occur?
- **Wait loop behavior** - does it timeout? Does readiness ever become true?
- **Reload execution** - does `do_live_reload` complete? How long does it take?

### 4. Additional Debugging (if needed)

If logs don't reveal the issue:

**A. Address Sanitizer Build:**
```bash
cd External/kanata
RUSTFLAGS="-Z sanitizer=address" cargo build --release --features tcp_server
```

**B. LLDB Debugging:**
```bash
lldb /path/to/kanata
(lldb) process handle -p true -s false SIGSEGV
(lldb) run
# Trigger reload, wait for crash
(lldb) bt  # Backtrace when crash occurs
```

**C. Test with wait=false:**
- Verify crash only occurs with `wait=true`
- Helps isolate whether issue is in wait path or reload itself

## Files Modified

- `External/kanata/src/tcp_server.rs` - TCP reload handler instrumentation
- `External/kanata/src/kanata/mod.rs` - Live reload function instrumentation

## Git Commits

- Kanata submodule: `7cf84d5` - "debug: add detailed logging to TCP reload path"
- KeyPath repo: `fa097f57` - "chore: update kanata submodule with reload debugging instrumentation"

## Notes

- All logging uses `log::debug!` or `log::info!` - ensure debug logging is enabled
- Timing uses `std::time::Instant` for millisecond precision
- Logs are thread-safe and won't affect performance significantly
- Can be removed after root cause is identified

---

**Status:** Ready for testing. Next action: Build instrumented kanata and reproduce crash with logging enabled.


