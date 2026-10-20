# Remove Full Disk Access and browser-history suggestions

Status: Accepted for the driverless experimental branch, 2026-10-06.

The user chose simpler onboarding and less data access over automatic website
suggestions and legacy permission-database inspection.

## Decision

Remove Full Disk Access acquisition from onboarding, Settings, permission status,
and permission helpers. Delete the protected TCC database reader and the browser
history scanner, including the scanner's launcher entry points. This supersedes
ADR-016. Do not merely hide these features behind an experimental flag.

Use app and session-runtime capability reports for permission readiness. Missing
or inconclusive evidence remains unknown. Accessibility and Input Monitoring
remain the consent flow; this decision does not claim Input Monitoring removal.

Preserve manually entered launcher URLs, app/folder/script actions, starter sets,
and existing saved shortcut configuration. No migration should delete mappings
that originally came from history suggestions.

## Tradeoff

Users add website shortcuts themselves. Legacy standalone Kanata permission
state cannot be inferred from protected databases. The driverless session runtime
continues to report its own effective access.

Previously granted macOS Full Disk Access is not automatically revoked. Existing
uninstaller cleanup for old grants remains useful and does not acquire access.

## Scope

This is a source change, not a production release. Caps Lock production admission,
first-success tour restoration, remaining driverless Settings polish, and broader
runtime acceptance remain separate work. Historical experiment receipts are not
rewritten.

## Validation

The app build and focused permission, wizard, CLI, and saved-launcher tests
passed. Accessibility identifiers and whitespace checks passed. Independent
source review confirmed session capability evidence and manual launcher paths
remain intact. The build used the existing verified cached Metal artifact; it
does not establish fresh Metal compilation, signing, notarization, or live VM
acceptance for this source revision.
