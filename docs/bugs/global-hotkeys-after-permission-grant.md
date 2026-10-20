# Resume global shortcuts after first-run consent

GlobalHotkeyService initially refuses to create event monitors before Accessibility and Input Monitoring are granted. CompositionRoot invokes startMonitoring once during deferred startup, before a clean install finishes its wizard. No subsequent consent transition previously retried that start, so overlay shortcuts remained inactive until application relaunch or preference toggling.

While monitoring is requested, observe application activation and repeat the existing nonprompting permission check after the user returns from System Settings. Existing handles make this idempotent. stopMonitoring removes the activation observer as well as event monitors so an explicit stop cannot be undone by a later activation.

Injected permission and monitor factories allow behavioral tests to reproduce denied startup, later grant and activation, repeated activation, and stop-before-grant without installing OS event monitors or changing TCC.

Monitor installation can partially fail. Global and local handles are retried independently so a failed global installation never overwrites or leaks the local monitor token. The partial-failure test verifies both retained handles are removed at Stop.
