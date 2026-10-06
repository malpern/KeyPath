# Driverless CLI command surface and fixed session endpoint

The driverless package omits the helper and LaunchDaemon, but its CLI registered
legacy service start/stop/restart/status commands and their root shortcuts.
Those registrations are removed; parsing rejects them before any façade or
service operation. The implementation types and privileged lifecycle remain
untouched. Root/service help now directs runtime control and live readiness to
KeyPath.app, and curated examples/completions no longer advertise these commands.

System uninstall is explicitly refused by the driverless InstallerEngine.
Install/repair generate only session recipes, but the CLI bootstrap deliberately
has no RuntimeCoordinator; its runtime-start recipe cannot complete. These three
unsupported mutating registrations are removed too. The app's File > Install
Command Line Tool operation is independent and remains available.

Read-only `system inspect` remains local diagnostics. Its session issue formatter
already omits helper/driver blockers, but the CLI cannot observe the separate
UI coordinator's retained worker/report. Help, human output and guides explicitly
state that inspection does not qualify live app-session readiness; no status JSON
is repurposed as an attestation. Config and simulator commands remain registered.

`service reload` still uses ConfigFacade/KanataTCPClient and its existing TCP
reload response contract; `service logs` reads
`~/Library/Logs/KeyPath/keypath-debug.log`, the current app logger's normal path.
These are reload/log operations, not readiness checks. Live execution against the
final signed candidate is still required; this source work launches no app and
performs no host reload.

The worker launch fixed its port at 37001 while app/CLI clients could dial a saved
custom preference. The existing PreferencesService port getter now derives from
`KeyPathConstants.Networking.defaultTCPPort`; the worker launch uses the same
constant. All existing consumers—including CLI config/layer clients, app reload,
monitoring, system checks and action dispatch—therefore share the session
endpoint. The port is read-only and historical stored values are preserved but
ignored. No individual client patch, new protocol, dual backend or production
migration is introduced.

Prepared regression coverage rejects every removed registration with normal,
JSON and dry-run arguments; confirms config/simulator/inspect/reload/log parsing;
checks generated completions and curated JSON examples; and varies saved valid,
invalid and historical port values while asserting effective port 37001 and
unchanged storage. Existing preference/launch-argument tests now assert the fixed
endpoint. No remaining source/test setter or SwiftUI binding writes the port.

Validation before integration: pinned SwiftFormat 0.61.1, whitespace checks,
accessibility inspection and the twelve existing shell verifier tests. Swift
package compilation and the affected suites are delegated to the root agent's
single build slot; they are not claimed passed by this workstream. Required
focused suites: CommandStructureTests, CLISmokeTests, CLIErrorTests,
HelpOutputContractTests, PreferencesServiceTests, PreferencesServicePersistenceTests,
KeychainServiceTests, ServiceLifecycleCoordinatorTests and SessionLifecycleInterleavingTests.
