# Task Difficulty Breakdown (snapshot: Dec 5, 2025)

This page now tracks three buckets: **Done**, **Deferred**, and **Still To Do**. Details for completed items are intentionally brief.

---
## Done
- **Category 12: RulesSummaryView extraction** – split into reusable components; main file slimmed.
- **Category 13: MapperView extraction** – main view slim (~251 lines) with `MapperViewModel.swift`, `MapperKeycapViews.swift`, and `ResetButton.swift` extracted.
- **Mechanical:**
  - `Task.sleep(nanoseconds:)` → `Task.sleep(for:)` across app/tests (KanataTCPClient and all test waits).
  - `onTapGesture` → `Button` for simulator keycaps, mapper keycaps, wizard UI (status dots, hero icon, permission cards, etc.), and home-row chips; added/kept accessibility labels where applicable.
  - Accessibility sweep for icon-only controls (wizard navigation, mapping rows, modifier picker, setup banner, etc.).
  - Replaced remaining `DispatchQueue.main.async/asyncAfter` timers with `Task` + `Task.sleep` across app, wizard, utilities, and logger (to keep UI work on MainActor).
  - Added validation helpers for key-mapping models (CustomRule, KeyMapping, SimpleMapping, SimpleModPreset).
- **Stability:** Hot-reload tests now stub service health via an injectable provider to keep “service unavailable” path deterministic.

## Deferred
- **Category 14: PrivilegedOperationsCoordinator refactor** – keep as-is until a new privileged-op change or reliability issue justifies the risk (8–10h, critical path).
- **KanataTCPClient codec extraction** – remains low-value; defer unless new parsing work appears.

## Still To Do
- **Complex:**
  - Split **ConfigurationService** into focused files (largest remaining “god” class).
- **Housekeeping:** Commit/clean pending workspace changes when ready.
- **Maintenance:** VHID driver install path updated to bundled installer (deprecated download path removed).

## Order of Operations (recommended)
1) Write a small plan for ConfigurationService extraction (file boundaries, ownership) and execute with tests.
2) Re-assess need for PrivilegedOperationsCoordinator refactor; schedule only if upcoming work touches it.

## Verification Status
- `swift test -q` reports all 181 tests passing (the runner exits non-zero occasionally; logs confirm pass).
