# Collection setting recovery

Several collection setting methods persisted configuration and source stores
before classifying the reload result. They could leave edited settings enabled
after a rejected reload and return newly-enabled success. Prerequisite-aware
settings used a second regeneration to roll back, which could overwrite a later
external revision and did not retain exact file contents.

Simple setting methods now share preparation and settlement. Interrupted journal
recovery precedes candidate lookup. Failed application restores the source/config
transaction and in-memory snapshot, and only committed changes can return newly
enabled. Existing Auto Shift/repeat enable policies and catalog fallback remain.

Home Row, Launcher, and window activation prerequisite saves use the same retained
transaction for both candidate and confirmed providers. Callers recover before
constructing the candidate, so settings cannot be derived from discarded state.
The shared helper also independently recovers for direct admitted callers.

Temporary-store regressions cover rejection, provider rollback, pending saves,
disabled-state preservation, catalog fallback, and interrupted source recovery.
Leader preferences, collection toggles, and external-write watching remain open.
