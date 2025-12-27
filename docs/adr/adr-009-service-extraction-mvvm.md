# ADR-009: Service Extraction & MVVM Pattern

**Status:** Accepted
**Date:** 2024

## Context

`KanataManager` was a monolithic class handling too many responsibilities: runtime coordination, UI state, configuration, health monitoring.

## Decision

Break down `KanataManager` into focused components:

| Component | Responsibility |
|-----------|---------------|
| `KanataManager` | Runtime Coordinator - orchestrates service, NOT ObservableObject |
| `KanataViewModel` | UI Layer (MVVM) - ObservableObject with @Published properties |
| `ConfigurationService` | Config file management |
| `ServiceHealthMonitor` | Health checking, restart cooldown |

## Consequences

### Positive
- Clear separation of concerns
- Testable components
- SwiftUI reactivity isolated to ViewModel

### Negative
- More classes to navigate
- Need to understand which component owns what

## Implementation Note

`KanataManager` is NOT an ObservableObject. All SwiftUI-reactive state lives in `KanataViewModel`.
