# Device-scoped Caps mapping intent

`SessionCapsMappingLease` is the shared parent/worker ownership boundary for an
experimental Caps-to-F18 substitution. Inject a transport that enumerates keyboard
**IOHID event services**, reads one exact service's full ordered `UserKeyMapping`
array, and performs a device-scoped write. An IOHIDDevice or USB ancestor registry
ID cannot stand in for an event-service ID.

The owned 2026-10-03 physical-fixture guest's Caps trial recorded property output
with a `RegistryID Key Value` header, a hexadecimal registry ID, and an OpenStep
array of dictionaries containing decimal source/destination values. The strict
parser accepts that grammar, including an explicit empty array; empty stdout,
extra rows/text, unknown or repeated keys, and different registry IDs refuse.
A fresh October 5 public-UID502 guest also witnessed `(null)`; this means an
effectively empty mapping. Restoration to `[]` preserves effective behavior,
without claiming to restore the literal nil representation.
The selector puts SerialNumber under `IOPropertyMatch`, as local hidutil help
requires. Argument builders are for `/usr/bin/hidutil` via `Process.arguments`,
never a shell.

`SessionCapsHIDUtilTransport.backend()` now provides bounded `/usr/bin/hidutil`
execution and strict NDJSON service enumeration. It accepts the witnessed physical
`AppleUserHIDEventService` identity, ignores device rows and the witnessed Parallels
`AppleVirtualPlatformHIDBridge` virtual keyboard, and refuses ambiguous selectors
or unsupported physical-service shapes. Useful execution has a two-second deadline and
64 KiB combined output limit. Failure kills the child and confirms exit before
releasing the lease lock; OS termination latency is not claimed to be bounded. This helper is not yet connected to the app lifecycle;
Caps profiles remain unavailable by default. Do not substitute USB device IDs or
interpret missing output as an empty mapping.

The journal directory must be owned by the caller with mode 0700. Lock and journal
files must be owned, regular, single-link 0600 files. Operations use directory-file
descriptors, no-follow opens, nonblocking exclusive flock, bounded reads, and
fsync of both intent and directory before mutation. FIFO journals refuse promptly;
file metadata and the directory entry are rechecked before restore mutation and
journal deletion, so a replaced journal is retained. An existing journal blocks
acquisition. Failed writes/readbacks retain intent. The exact recorded owner is
required for restoration; a recovery caller first reads intent and independently
proves that its recorded owner processes are dead. The same boot and same
unambiguous device instance must still be present.

Restore clears intent only after explicitly reading the exact original array, or
after reading our exact applied array, writing the original, and verifying it.
Any other array retains intent and refuses. This preserves unrelated mappings
without deleting foreign changes. There is no HID compare-and-set: a foreign
write between read and write, or an identical replacement (ABA), cannot be
excluded by this lease. It is guarded best-effort restoration, not atomic HID
ownership.

Run `Scripts/test-session-caps-mapping-lease.sh` for focused fake-transport and
strict-parser checks. It uses only temporary directories and never invokes
hidutil or changes host HID state.

October 5 live qualification: the source-built helper acquired Caps→F18 on the
ESP32's exact service, read back one applied row, restored the original effective
empty map, and cleared intent under public UID502 without administrator access.
An independent hidutil read found an empty map, no journal remained, and the probe
had exited. VM deletion, retained stopped template, and detached nonpersistent
fixture were independently verified. Raw receipt: `/private/tmp/keypath-caps-transport-live-01`.
This proves one transport cycle, not runtime Caps input or crash/reconnect recovery.

Final source-review hardening checks the descriptor-derived journal identity both
before acquisition mutation and after readback; removal/replacement refuses
instead of publishing successful ownership. Focused acquisition negatives pass.
These hardening changes were source-reviewed and tested after the live cycle;
they have not received a separate fresh live mapping trial.
