# Preserve activity history across failures and concurrent mutations

ActivityLogStorage is an actor, but append suspended while invoking its encryption actor. Two appends could read the same month snapshot and overwrite one another, and Reset could delete history while an earlier append was waiting for encryption, only for that append to recreate it afterwards. ActivityLogger can issue overlapping flushes from its threshold, timer, disable and termination paths.

Serialize each entire read/decrypt/append/encrypt/write transaction with FIFO ownership that is retained across suspension, and use the same ownership for clearAll. A queued reset then runs after earlier writes and removes them before returning. Readers continue using atomic file snapshots.

A separate data-loss path treated every failed existing-file read as an empty month. A decryption or read failure must propagate so ActivityLogger retains its buffer; it must never authorize replacing history. Missing files already return an empty event array from readEventsFromFile.

Regression tests use an isolated directory and injected identity encryption, never Keychain. A controlled encryption suspension proves overlapping append and reset ordering; an injected read failure proves the original bytes remain untouched.

Malformed UTF-8 and malformed JSON lines also propagate errors. Silently dropping undecodable lines would otherwise erase valid older events on the next write. Tests preserve the original bytes for both cases.
