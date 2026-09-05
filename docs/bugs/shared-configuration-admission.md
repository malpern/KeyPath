# Shared configuration mutation admission

A generated save could wait for an engine reload while a collection edit changed
its source state and wrote another configuration. Rejection of the first save
then restored its earlier file over the second edit. The coordinator's local FIFO
queue protected only its own callers; a second coordinator and the collection
manager did not share that queue.

Admission now belongs to the shared ConfigurationService. Public collection
mutations acquire it before reading snapshots or staging state. SaveCoordinator
holds it across reload and recovery. Explicit, expiring permits identify trusted
nested work; callbacks cannot use inherited task context as automatic permission
to reenter a save.

`SharedConfigurationAdmissionTests` covers a collection edit waiting behind a
rejected generated save, two coordinators sharing that service, cancellation
before collection mutation, callback reentry and expired nested permits. Existing
SaveCoordinator tests retain coverage of FIFO ordering, recovery and callback
cycles.

Pack install/uninstall/settings operations and bootstrap now acquire the same
queue before staging state. Their nested toggle/save/remove calls pass the
active permit explicitly. Regression tests cover callback attempts to install
visual-only metadata or bootstrap, and cancellation before pack metadata writes.

Standalone regeneration and persistence now acquire admission as well. Conflict
retries, prerequisite application and snapshot restoration accept explicit nested
permits, so normal recovery does not reacquire its own queue. Tests hold a
standalone reload open while another edit queues, and verify that callbacks
cannot regenerate or restore a snapshot inside the active save.

Direct service writers, backups and journal recovery now acquire admission.
Trusted restore and missing-file self-healing calls forward the permit. Tests
exercise direct writer attempts from reload callbacks, observer-held saves and
restoring persisted rules after a rejected save with a missing initial file.

CLI operation ownership and cross-instance/process concurrency still require
migration. The durable journal and runtime
rollback also remain distinct boundaries. Do not treat this queue as proof of
whole-operation rollback or protection against external editors.
