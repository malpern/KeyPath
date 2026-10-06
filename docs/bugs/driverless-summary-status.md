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

## Completion handoff and setup copy

The standalone driverless setup window offers **Open Rules** once the existing
state inspection reports active with no issues. Its callback is queued before
window dismissal and consumed once after window close by the existing completion
owner. It uses the normal Settings/Rules navigation entry point and does not
install a preset or enable the Caps-based tour. Settings retains the requested
Rules tab during asynchronous readiness refresh; the existing disabled view
protects editing until the runtime is healthy, instead of losing navigation to
stale readiness. Incomplete setup does not request
this handoff. Embedded setup without a handoff callback retains **Close Setup**.

The welcome page names Accessibility and Input Monitoring and advertises general
key customization rather than production Caps support. Accessibility guidance
recognizes both `/Applications/` and the current user's `~/Applications/` as
stable locations. Managed Caps remains DEBUG-only with the F18 reservation.

App Store feasibility is deferred in
[the future investigation](../planning/mac-app-store-feasibility.md); it does not
block the signed, notarized direct-download release path. These source changes
require fresh signed UI acceptance before claiming the on-screen handoff works.
