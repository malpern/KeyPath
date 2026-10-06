# Driverless onboarding summary status

The setup summary uses a backend-specific checklist. The driverless session
backend shows only Accessibility, Input Monitoring, and KeyPath Runtime; the
helper, Karabiner/VHID, and DriverKit rows describe the legacy backend and are
omitted for a session runtime. Full Disk Access has been removed from every
checklist, along with its prompts, probes, and browser-history suggestions.

Permission readiness comes from the canonical `PermissionOracle.Snapshot` used
for that wizard result. It is carried through `SystemStateResult` and
`WizardSnapshotRecord`, including the state-detection operation's result
reconstruction. Incomplete captures and synthetic timeout results have no
permission snapshot, so absent permission issues do not imply a grant: those
rows remain unresolved. A complete snapshot can show permissions as ready even
when the runtime itself is stopped. Explicit permission issues remain visible
and route to their existing consent pages. The summary's issue count is derived
from the same visible rows.

This is a presentation correction, not a new permission check or grant. It does
not query TCC from the summary, alter consent flows, or change runtime startup.
