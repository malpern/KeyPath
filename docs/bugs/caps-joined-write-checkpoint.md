# Caps joined-write checkpoint

The DEBUG-only `KEYPATH_EXPERIMENTAL_CAPS_TERMINATE_AFTER_JOINED_APPLY`
environment value must equal the exact decimal selected registry entry ID. It is
inert with a missing, malformed, or different value. Admission also requires UID
502, the recorded current worker PID (never the parent), the ESP32 fixture VID
51966 / PID 16400, the existing exact managed-Caps selection and F18 reservation.
No nonce injection or new launch protocol is required: the validated lease and
already durable marker record the actual nonce and generation.

The worker emits one bounded diagnostic and kills only itself immediately after
the initial applied mapping write returns, before removing its durable mutation
marker. The real transport has joined its hidutil child and parsed its mapping
response by then. The intended live case is death **after a joined real write**;
death while a child is in flight remains a separate gap. Restore writes never enter this checkpoint. Release builds
exclude the admission function and termination branch.

Live acceptance must independently verify the exact selected service, applied
mapping, dead recorded worker, byte-identical retained intent, and owner-bearing
mutation marker, then verify normal recovery refuses without changing either
artifact or mapping. The diagnostic alone is insufficient. Disposal must use the
owned guest's canonical cleanup; this hook never clears uncertainty. The fake
lease runner tests admission and existing durable-marker refusal without sending
signals or writing HID state. Run `Scripts/test-session-caps-mapping-lease.sh`.
