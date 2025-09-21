# Repository Guidelines

This guide keeps contributions fast, predictable, and shippable for the KeyPath Swift package and macOS app. Paths are relative to the repo root.

## Project Structure & Module Organization
- `Sources/KeyPath` — SwiftUI app code. Subfolders: `Core`, `Managers`, `Services`, `Infrastructure`, `Utilities`, `UI`, `Models`, `InstallationWizard`.
- `Sources/KeyPathCLI` — `main.swift` launcher and simple harness.
- `Tests/KeyPathTests` — XCTest suites (e.g., `KeyboardCaptureTests.swift`).
- `Scripts/` — build, sign, test, and maintenance scripts.
- `dist/` — created app bundle for local installs.
- Docs: `README.md`, `ARCHITECTURE.md`, `docs/`.

## Build, Test, and Development Commands
- `swift build` — Debug build of packages.
- `./Scripts/build.sh` — Quick dev build of the app.
- `./Scripts/build-and-sign.sh` — Produce a signed app bundle into `dist/`.
- `./run-tests.sh` — Full suite (unit + integration wrappers).
- `./run-tests-workaround.sh` — Test runner for Xcode 26 beta toolchains.
- `.github/workflows/test-ci-locally.sh` — Preview CI locally.

## Coding Style & Naming Conventions
- Swift 6, macOS 14+. Use Swift Concurrency; mark UI-bound code `@MainActor`.
- Indentation 4 spaces; prefer 120–200 char lines (see `.swiftlint.yml`).
- Names: Types `UpperCamelCase`; methods/vars/constants `lowerCamelCase`.
- Lint/format with SwiftLint (configured) and optional SwiftFormat.
- Avoid `print()`; use the logging utility. No force unwraps in `Managers/`.

## Testing Guidelines
- Framework: XCTest. Place tests under `Tests/KeyPathTests`.
- Naming: files `*Tests.swift`; methods `test…`.
- Prefer deterministic tests; mock services; mark UI tests `@MainActor`.
- Run locally with `./run-tests.sh` (or the workaround script on beta toolchains).
- Coverage: no hard gate; prioritize `Managers/`, installer paths, and UDP client behavior.

## Commit & Pull Request Guidelines
- Commits: imperative mood (e.g., “Fix permission detection”), optional prefixes `fix:`, `feat:`, `docs:`.
- PRs: link issues, describe scope/approach, add repro/validation steps, and screenshots for UI changes. Ensure `./run-tests.sh` passes.

## Security & Configuration Tips
- App requires Input Monitoring and Accessibility; never bypass macOS TCC checks.
- Keep entitlements in `KeyPath.entitlements`; avoid hardcoded privileged paths.
- Use `Scripts/` helpers for Kanata/daemon tasks.

## Agent-Specific Instructions
- Keep diffs minimal and focused; preserve directory layout and script entry points.
- Update docs when behavior or commands change; prefer adding tests over ad hoc fixes.
