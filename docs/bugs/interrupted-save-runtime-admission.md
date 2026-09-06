# Runtime recovery before the next editor callback

Interrupted rule/app writes were restored from their journals during preparation,
but app and raw editors could then reject a candidate or cancel a callback before
reloading the restored files. The disk could contain the previous revision while
the keyboard service still used the interrupted one. A manager-local retry flag
also could not follow recovery performed by another save coordinator.

ConfigurationService now owns the in-process requirement to apply recovered files.
Rule and app recovery set it; only an applied or explicitly pending reload clears
it. Headless calls retain it, and failed reloads can be retried through another save
coordinator using that service after the journal has been removed. Recovery runs
through existing reload callbacks without inheriting the editor task's cancellation.

App and raw save entry points recover before invoking a mutation/transform callback
or validating a candidate. Rule and pack editors check app journals before early
returns. A rule recovery revision lets a manager refresh its arrays when recovery
was performed by another editor sharing its configuration service.

This does not make raw saves crash-atomic or coordinate caches across distinct
ConfigurationService instances/processes. The runtime retry marker is in-process;
startup still needs to establish runtime readiness. Preferences, managed-pack
snapshots, and revision-aware watching remain separate boundaries.
