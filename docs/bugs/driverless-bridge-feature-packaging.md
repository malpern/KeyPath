# Driverless bridge feature must be verified in the packaged library

A signed managed-Caps test artifact failed driverless startup for every config,
including a baseline q-to-a mapping. Its Rust cdylib came from a default-feature
debug build. `passthru-output-spike` was enabled for a test executable, but not
for the copied cdylib. Default builds export passthru creation stubs that report
`passthru output spike feature is not enabled in this bridge build` and return
null. Successful signing, loading, and ordinary config validation do not prove
driverless runtime creation works.

`build-kanata-host-bridge.sh` now checks both cache hits and newly built libraries
using `Scripts/test-fixtures/configs/host-bridge-passthru.kbd` and `--passthru`.
The verifier requires the complete session ABI, including the input-map symbol,
and refuses failed config validation, ordinary or passthru runtime creation, or
output-channel reads. It creates and destroys an unstarted memory-only runtime
with TCP port zero; it installs no event tap and posts no OS events.

When assembling an artifact outside the builder, run the same verification
against its actual packaged dylib before signing/archive acceptance:

```sh
python3 Scripts/verify-kanata-host-bridge.py \
  KeyPath.app/Contents/Library/KeyPath/libkeypath_kanata_host_bridge.dylib \
  Scripts/test-fixtures/configs/host-bridge-passthru.kbd --passthru
```

Load-only checks remain available without `--passthru`. Supplying `--passthru`
without a config now exits 2 rather than silently skipping creation. Any failed
requested verification exits 1. Tests run without a Rust or Swift build:

```sh
python3 -m unittest Scripts.tests.test_verify_kanata_host_bridge
```
