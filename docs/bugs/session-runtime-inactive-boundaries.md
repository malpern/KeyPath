# Driverless worker retirement at OS/session boundaries

The driverless worker previously checked Secure Input and tap health but could
continue draining old queued output after real system sleep or departure from
its active console. It now registers IOKit system power callbacks, workspace
will-sleep/session-resign notifications and the documented CGSession notify
names. Current public Quartz UID/on-console/login-done evidence gates startup,
input and every queued output. Missing evidence fails open with a specific cause.

Will-sleep disables the tap, releases only owned outputs, publishes its terminal
ledger, acknowledges the power message, unregisters observers and exits. An
event allocation failure during shutdown retains the unposted output in the
ledger and cannot recursively exit before the acknowledgement. Can-sleep is
acknowledged without veto or retirement. Wake observed by a surviving worker
retires it rather than draining its old queues. Session return never restarts
this worker; explicit lifecycle recovery is required. Existing Secure Input
recovery remains separately owned by the parent coordinator.

Tests inject selected console observations and terminal callbacks; they never
register OS observers, post events, launch apps, sleep, log out or exit. They
exercise the production observer checks and shutdown ordering. Physical guest
acceptance must independently prove actual sleep/wake/session transitions and
delivered releases. Workspace delivery and console polling may follow a session
boundary, so these checks cannot prove key-up delivery in the departed session.
They make no Caps mapping-ownership or lock-screen coverage claim.
