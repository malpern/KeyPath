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
extra rows/text, unknown or repeated keys, nulls, and different registry IDs refuse.
The selector puts SerialNumber under `IOPropertyMatch`, as local hidutil help
requires. Argument builders are for `/usr/bin/hidutil` via `Process.arguments`,
never a shell.

Production event-service enumeration and process execution are intentionally not
provided yet: there is no qualified `hidutil list --ndjson` service fixture in this
change. The app must keep this route unavailable until its actual service output
and responsibility/permission behavior are verified. Do not invent a registry ID
from the device section or treat no property output as an empty mapping.

The journal directory must be owned by the caller with mode 0700. Lock and journal
files must be owned, regular, single-link 0600 files. Operations use directory-file
descriptors, no-follow opens, nonblocking exclusive flock, bounded reads, and
fsync of both intent and directory before mutation. An existing journal blocks
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
