# Driverless uninstall preserves a backup and resets onboarding

The driverless build had replaced the Settings uninstall action with instructions
to trash the app. That left rules and welcome preferences behind, causing a later
installation to open the visualizer instead of presenting fresh setup.

Settings now invokes InstallerEngine's serialized uninstall entry point with
explicit settings removal. GUI dependencies supply SessionUninstallCoordinator;
CLI dependencies do not register an uninstaller. Shared drivers, helpers, and TCC
are outside its scope. The current bundle must identify as KeyPath before removal.

Order: suppress starts; verify runtime stop and owned Caps mapping restoration;
stop file watching; drain and close configuration write admission; copy all user
settings and preferences to a private unique Downloads backup; remove active data;
clear persistent preferences; move the current app to Trash; verify removal; quit.
Write admission stays closed on success and reopens on failure.

Leaf symlinks are copied through for backup, then detached without touching their
target. Symlinked parent directories are refused before shutdown so cleanup cannot
delete a dotfiles tree through an alias. A failed backup never proceeds to removal;
a later failure reports its preserved backup location. Uninstall does not claim to
remove macOS permission grants or old privileged installations.

Tests use temporary homes, fake app bundles, isolated preference suites, injected
keyboard cleanup and Trash operations. No test uninstalls the host application.

Validation (2026-10-06): focused uninstaller/broker checks passed (9 tests), then
the full run passed 5,385 tests with one obsolete source-contract assertion
prohibiting all uninstall delegation. That assertion was updated to continue
forbidding privileged execution and legacy-uninstaller registration; all 12 tests
in its suite passed on rerun. No product code changed after the full run.
Compiler warnings: zero. Accessibility identifiers: all 380 checked files passed.
Independent safety review passed after adding ancestor-link refusal and draining
file-lease opening as well as queued/admitted writes. Live signed-app uninstall
and reinstall remain to be qualified on a disposable machine.
