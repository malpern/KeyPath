# Tap-timeout admission observability

No accepted delay receipt was captured from the last physical experiment, and the worker's existing report cannot identify the failed admission stage. Receipt-file absence in the guest was not independently established. It carries tap registration, mapped-key and config-hash observations; the hook initializer is assigned through `try?`, the timer-side `prepare()` result is discarded, and the callback's admission guard returns without recording which predicate refused. The saved command's exact schema and config digest were independently accepted by the original decoder, so malformed-command rejection is not an established cause. The failure stage remains unknown.

An earlier `/var` versus `/private/var` path explanation was withdrawn. On the host Foundation resolves the standard temporary URL to the `/var` spelling while libc `realpath` reports `/private/var`; both spellings resolve to the same directory inode. No path fix should be treated as causal without a reproduction of the actual production hook failing to open the command.

The proposed diagnostics add only bounded enum values to the existing experimental worker report: initializer result, latest timer-side preparation result, and the first result for the fixed keycode-11 key-down diagnostic trigger. They contain no event text, arbitrary key values, paths, raw error strings or process arguments. The callback update is memory-only; the existing timer report serializes it. No guard, retry, command writer, event routing, or normal-build behavior is relaxed or changed.

## Inert checks

From the checkout root, compile the hook and admission test with the experimental flag:

```sh
swiftc -DKEYPATH_TAP_TIMEOUT_EXPERIMENT \
  Sources/KeyPathSystemProbes/*.swift \
  Sources/KeyPathCore/SessionRuntime/SessionRuntimeReport.swift \
  Sources/KeyPathAppKit/Services/SessionRuntime/SessionTapTimeoutExperiment.swift \
  Tests/Experiments/TapTimeoutAdmission.swift \
  -o /private/tmp/tap-timeout-admission-test
/private/tmp/tap-timeout-admission-test
```

Compile the report schema compatibility test without the experimental flag:

```sh
swiftc Sources/KeyPathCore/SessionRuntime/SessionRuntimeReport.swift \
  Tests/Experiments/TapTimeoutReportSchema.swift \
  -o /private/tmp/tap-timeout-report-schema-test
/private/tmp/tap-timeout-report-schema-test
```

These tests cover bounded initialization and preparation outcomes, first-refusal stability, strict status/field decoding, and old-report compatibility. They do not exercise physical input, the OS timeout threshold, or a signed app build.

The separate Python startup consumer is strict about its top-level report allowlist. A consumer used by a future experimental artifact must explicitly validate this new optional field under its own reviewed source pin; do not broaden or edit an existing frozen consumer in place.
