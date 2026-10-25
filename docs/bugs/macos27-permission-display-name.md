# macOS 27 permission display name

macOS 27 displays the Accessibility authorization pane as **Device Control and
Data Access**. Guidance must use the pane name users actually see. The shared
AccessibilityPermissionPresentation selects display copy from the OS major
version; it does not change AX authorization, TCC service names, readiness,
internal permission identifiers, or the existing Settings URL.

Evidence: user-provided macOS 27 Settings screenshot and
https://pasteapp.io/help/paste-directly-to-other-applications (macOS 27 note).

Regression coverage includes 26/27 copy and the real CLI issue producer for both
session and legacy contexts, preserving severity and remediation URL. Native
macOS 27 navigation and minimum-width long-label layout remain unverified.
The status action uses concise button text with the full permission name in its
accessibility label; this does not substitute for native layout validation. Lab pane
matching is a separate change requiring actual AX title/body evidence.

Validation (isolated follow-up, not the frozen live candidate): restoring the
pre-fix constant Accessibility label produced three expected regression failures
(27 copy, Issue title, real CLI guidance), with 24 other focused tests passing.
The corrected implementation passed all 27 focused tests. The accessibility
identifier checker passed across 381 files. No full suite or native UI run was
performed for this follow-up.
