# Runtime health does not prove runtime freshness

## Symptom

KeyPath could report a responsive helper and a running, TCP-responsive Kanata
service without saying whether those live processes matched the currently
installed app. A healthy process left running across an app replacement was
therefore ambiguous in diagnostics.

## Root cause

The helper already returned its shared compatibility version over XPC, but
status exposed only the raw value. Kanata health read `launchctl print` output
only for PID evidence and discarded the SMAppService identity fields:

- `program identifier`
- `parent bundle identifier`
- `parent bundle version`

SMAppService does not expose the absolute executable path in this output. Path
fixtures are therefore not reliable freshness evidence for this service.

## Durable rule

Keep liveness and freshness separate. Runtime readiness continues to depend on
process, TCP, and input-capture evidence. Freshness is a non-blocking diagnostic
classification:

- helper: compare the XPC-reported compatibility version with the shared helper
  contract;
- Kanata: compare the live SMAppService identity tuple with the current app's
  expected program identifier, bundle identifier, and build version;
- missing or incomplete identity evidence is `unknown`, never inferred from
  registration or liveness alone.
