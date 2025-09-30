# Repository Guidelines

## Project Structure & Module Organization
- `Sources/KeyPath` — SwiftUI app code: `Core`, `Managers`, `Services`, `Infrastructure`, `Utilities`, `UI`, `Models`, `InstallationWizard`.
- `Sources/KeyPathCLI` — CLI entry (`main.swift`).
- `Tests/KeyPathTests` — XCTest suites (e.g., `KeyboardCaptureTests.swift`).
- `Scripts/` — build, sign, test, and maintenance helpers.
- `dist/` — signed app bundle output.
- Docs: `README.md`, `ARCHITECTURE.md`, `docs/`.

## Build, Test, and Development Commands
- `swift build` — Debug build of all packages.
- `./Scripts/build.sh` — Fast developer build of the app.
- `./Scripts/build-and-sign.sh` — Create signed bundle in `dist/`.
- `./run-tests.sh` — Run full unit + integration wrappers.
- `./run-tests-workaround.sh` — Use when on Xcode 26 beta toolchains.
- `.github/workflows/test-ci-locally.sh` — Preview CI locally.

## Coding Style & Naming Conventions
- Swift 6, macOS 14+. Use Swift Concurrency; mark UI-bound code `@MainActor`.
- Indentation 4 spaces; target 120–200 char lines (see `.swiftlint.yml`).
- Names: Types `UpperCamelCase`; methods/vars/constants `lowerCamelCase`.
- Lint/format with SwiftLint (configured) and optional SwiftFormat.
- Avoid `print()`; use the logging utility. No force-unwraps in `Managers/`.

## Testing Guidelines
- Framework: XCTest. Place tests under `Tests/KeyPathTests`.
- Naming: files `*Tests.swift`; methods `test…`.
- Prefer deterministic tests; mock services; mark UI tests `@MainActor`.
- Run locally with `./run-tests.sh` (or the workaround script on beta toolchains).
- Coverage: no hard gate; prioritize `Managers/`, installer paths, and UDP client behavior.

## Commit & Pull Request Guidelines
- Commits: imperative mood; optional prefixes `fix:`, `feat:`, `docs:`.
- PRs: link issues, describe scope/approach, add repro/validation steps, and screenshots for UI changes.
- Ensure `./run-tests.sh` passes before requesting review.

## Security & Configuration Tips
- App requires Input Monitoring and Accessibility; never bypass macOS TCC checks.
- Keep entitlements in `KeyPath.entitlements`; avoid hardcoded privileged paths.
- Use `Scripts/` helpers for Kanata/daemon tasks.

## Agent-Specific Instructions
- Keep diffs minimal and focused; preserve directory layout and script entry points.
- Update docs when behavior or commands change; prefer adding tests over ad hoc fixes.

