# SwiftUI Previews (Xcode)

This project is SwiftPM-based. Open `/Users/malpern/local-code/KeyPath/Package.swift` in Xcode and use canvas previews for fast UI iteration.

## Shared fixtures

Use `PreviewFixtures` in `/Users/malpern/local-code/KeyPath/Sources/KeyPathAppKit/UI/Previews/PreviewFixtures.swift`.

What to put there:
- Deterministic sample models (`CustomRule`, `AppKeymap`, `WizardIssue`)
- Small helpers for repeated preview setup

What not to put there:
- Live service calls
- File/network/system state dependencies

## Required preview scenarios

For high-change views, include named scenarios:
- `Missing` or `Error`
- `Partial` or `Loading`
- `Ready` or `Success`

For list/card views, include:
- Empty state
- Populated state
- One edge case (disabled/conflict/unusual content)

## Conventions

- Prefer `#Preview("Name")` over unnamed previews.
- Keep previews local to the view file when practical.
- Use `#if DEBUG` blocks for preview-only helpers.
- Keep preview dimensions explicit for complex layouts.

## Quick checklist

- Preview has no side effects.
- State variants are represented.
- Data is stable across runs.
- Interactive controls have `.accessibilityIdentifier()`.
