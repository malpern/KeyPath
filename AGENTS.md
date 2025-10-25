# Repository Guidelines

## Project Structure & Module Organization
- `Sources/KeyPath` — Swift 6 executable app (SwiftUI). Key areas: `Core/`, `Managers/`, `Services/`, `Infrastructure/`, `Utilities/`, `UI/`, `Models/`, `InstallationWizard/`, `Resources/`.
- `Tests/KeyPathTests` — XCTest suites and helpers.
- `Scripts/` — build, test, and diagnostics (e.g., `build-and-sign.sh`, `run-tests.sh`, `run-core-tests.sh`).
- `dist/` — signed release artifacts.  Docs in `README.md`, `ARCHITECTURE.md`, `docs/`.

## Build, Test, and Development Commands
- `swift build` — Debug build of all targets.
- `swift test` — Run full XCTest suite locally.
- `./run-core-tests.sh` — CI‑friendly Unit + Core tests. Add integration: `CI_INTEGRATION_TESTS=true ./run-core-tests.sh`.
- `./Scripts/build-and-sign.sh` — Release build and sign to `dist/`.
- `./Scripts/setup-git-hooks.sh` — Optional pre‑commit hooks (SwiftLint/SwiftFormat checks).

## Coding Style & Naming Conventions
- Language: Swift 6; target `.macOS(.v15)`. Prefer async/await; mark UI code `@MainActor`.
- Indentation: 4 spaces. Line length: aim ≤ 120, warn at 200 (see `.swiftlint.yml`).
- Naming: Types `UpperCamelCase`; functions/vars/constants `lowerCamelCase`.
- Lint/format: `swiftlint` (configured) and optional `swiftformat`.
- Avoid `print`; use the logging utilities in `Utilities/`.

## Testing Guidelines
- Framework: XCTest. Place tests under `Tests/KeyPathTests`.
- Naming: files end with `*Tests.swift`; methods start with `test…`.
- Use `MockSystemEnvironment` for deterministic tests; mark UI‑bound tests `@MainActor`.
- Coverage focus: `Managers/`, installer flows, UDP/TCP client behavior, error paths.

## Commit & Pull Request Guidelines
- Commits follow Conventional Commits: `feat:`, `fix:`, `docs:`, `refactor:`, `perf:`, `ci:`; imperative mood and concise subject.
- PRs include: purpose, user impact, test plan (commands run), linked issues, and screenshots/GIFs for UI changes.
- Require green `./run-core-tests.sh` locally before request for review; keep diffs minimal and scoped.

## Security & Configuration Tips
- Do not bypass macOS TCC: app requires Input Monitoring and Accessibility.
- Keep entitlements in `KeyPath.entitlements`; avoid privileged hard‑coded paths. Use `Scripts/` for service/daemon operations.
