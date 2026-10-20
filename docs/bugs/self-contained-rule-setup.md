# Self-contained rule activation setup

Implemented an interactive prerequisite setup sheet for enabling rules. Recommended provider is Leader Key when available, otherwise the first available provider; alternate providers are selectable inside a disclosure. Preview uses the configured leader key and Hold/Tap trigger. No enable-anyway button is offered in this path.

The sheet owns the in-flight attempt until a successful save or explicit cancellation. Failures preserve the selected provider and show inline; selecting another provider or retrying reuses the same operation lease. A proposal enables the candidate and its selected supporting rules in one retained save, including pack metadata and leader preference when applicable. Each attempt validates allowed provider IDs, coverage, the selected rules' own dependencies and conflicts against current enabled rules before committing. Conflicts instruct the user to select another activation method without disabling existing rules. Existing headless prerequisite policy and save-edit prerequisite dialogs remain unchanged.

20 prerequisite-resolution tests pass, including selected ambiguous provider, missing selection rejection, conflicting provider then alternate selection, Window Snapping + Leader atomic save, and rejected reload followed by retry. No compiler warnings. Accessibility source check passed 381 files. App-product build passed. Live Air verification is pending: the machine remains locked.

## Air installation and live verification — 2026-10-12
Installed the signed candidate at /Applications/KeyPath.app; executable SHA-256 c2de3d718ca12c70dde0974d495ea15565c06f3722762a89de0ebff3e94c7e39. Previous app preserved at outputs/rule-setup/KeyPath-before-setup.app.

Live CUA checks passed: General visual key previews and native segmented recording controls, grouped Keyboard Setup, collapsed Advanced sections and Logs disclosure; Window Snapping setup opens with Hold Space → W preview, alternative selection changes the planned-rule summary, and Cancel (direct pointer) / Escape dismiss the sheet with Leader and Window Snapping still off. AX-targeted Cancel did not reliably activate through the automation tool; direct pointer click succeeded. Existing three active rules remain enabled. Status reports Everything's Working.

Installed-app verification passed signature, architecture, bundled CLI, owned driverless worker and TCP readiness (127.0.0.1:37001). Notarization/stapling checks intentionally skipped for this development build. Save/reload rollback and retry were verified by the 20 focused tests, not by changing the Air's live rules during this visual check.

Observed automation limitation: SwiftUI disclosure identifiers propagate to their descendants (Logs and alternative provider choices); accessible labels remain distinct and pointer interaction works. Unique descendant automation identifiers remain a follow-up.
