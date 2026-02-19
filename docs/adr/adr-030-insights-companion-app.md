# ADR-030: Separate Activity Logging and AI Features into KeyPath Insights Companion App

## Status

Accepted

## Date

2026-02-18

## Context

KeyPath currently bundles Activity Logging (encrypted keyboard usage analytics) and AI Config Repair (Claude API integration) within the core app. While both features are behind opt-in gates, their presence raises privacy and trust concerns:

1. **Permission burden**: Activity Logging requires additional trust that the app won't misuse keystroke access. Even though logging is encrypted (AES-GCM), device-bound, and double opt-in, its mere presence in a keyboard remapper makes privacy-conscious users uncomfortable.

2. **AI perception**: The AI Config Repair feature requires an Anthropic API key and makes network requests. For a tool that intercepts all keystrokes, any network capability creates suspicion — even if the two features are completely unrelated.

3. **Trust model mismatch**: Core keyboard remapping needs deep system trust (Input Monitoring, Accessibility, root access). Adding analytics and cloud AI to that same trust boundary makes the security story harder to tell.

4. **Reddit/community perception**: When evaluated by security-conscious Mac users (r/macapps, r/ErgoMechKeyboards), the combination of "intercepts all keystrokes" + "has logging" + "has AI/cloud features" is a red flag — even if each feature is well-implemented and opt-in.

## Decision

Separate Activity Logging and AI Config Repair into a standalone companion app called **KeyPath Insights**.

### What moves to KeyPath Insights

| Component | Location | Notes |
|-----------|----------|-------|
| `ActivityEvent` | `ActivityLogging/Models/` | Event type definitions |
| `ActivityReport` | `ActivityLogging/Models/` | Report aggregation |
| `ActivityLogger` | `ActivityLogging/Services/` | Core logging actor |
| `ActivityLogStorage` | `ActivityLogging/Services/` | Encrypted file I/O |
| `ActivityLogEncryption` | `ActivityLogging/Services/` | AES-GCM encryption |
| `ActivityLoggingSettingsSection` | `ActivityLogging/UI/` | Settings UI |
| `ActivityOptInFlow` | `ActivityLogging/UI/` | Double opt-in flow |
| `ActivityReportView` | `ActivityLogging/UI/` | Report visualization |
| AI Config Repair services | (future) | Claude API integration |

### What stays in KeyPath (core)

- Keyboard remapping engine (Kanata)
- Service management (LaunchDaemon, InstallerEngine)
- Permission handling (PermissionOracle)
- Configuration management
- In-app help system
- Update checks (Sparkle)
- All UI for remapping, rules, layers

### Integration points to remove from core

| File | Change |
|------|--------|
| `ExperimentalSettingsSection.swift` | Remove Activity Logging settings card |
| `KeyboardCapture.swift` | Remove `activityObserver: KeyboardActivityObserver?` |
| `PreferencesService.swift` | Remove `activityLoggingEnabled` preference |
| `KanataEventListener.swift` | Remove activity event recording |

## Architecture

```
KeyPath.app (core)              KeyPath Insights.app (companion)
├── Remapping engine            ├── Activity Logging
├── Service management          │   ├── Models
├── Permissions                 │   ├── Services (encrypted storage)
├── Configuration               │   └── UI (opt-in, reports)
├── Help system                 ├── AI Config Repair (future)
└── Updates                     └── Separate bundle ID, permissions
```

### SPM structure

```
Package.swift
├── KeyPathCore           (existing shared library)
├── KeyPathAppKit         (core app - minus ActivityLogging)
├── KeyPath               (core executable)
├── KeyPathInsights       (companion executable) ← NEW
└── KeyPathActivityKit    (shared models if needed) ← NEW
```

### Bundle IDs

- Core: `com.keypath.app` (existing)
- Insights: `com.keypath.insights` (new)

## Consequences

### Positive

- **Cleaner privacy story**: Core KeyPath has zero logging, zero AI, zero cloud. The privacy page can say this without asterisks.
- **Lower trust barrier**: Users install a keyboard remapper that does exactly one thing. No "but also..." features.
- **Separate permission model**: Insights can request its own permissions independently.
- **Clearer marketing**: KeyPath = remapping. Insights = analytics for power users.
- **Faster core app**: Less code, fewer features, smaller attack surface.

### Negative

- **Two release artifacts**: Need to build, sign, notarize, and distribute two apps.
- **Discovery problem**: Power users who want analytics need to know Insights exists.
- **Shared data**: If Insights needs to read KeyPath's config or state, we need an IPC mechanism or shared directory.
- **Development overhead**: Two app targets, two sets of tests, two Info.plists.

### Neutral

- Activity Logging is currently behind the Experimental settings flag, so removing it from core has minimal user impact.
- AI Config Repair was planned but not yet shipped, so there's no migration burden.

## Implementation Order

1. Write this ADR (this document)
2. Create `KeyPathInsights` executable target in Package.swift
3. Move `ActivityLogging/` directory to Insights target
4. Remove integration points from core app (4 files)
5. Verify `swift build` and `swift test` pass for both targets
6. Create Insights app entry point and minimal UI
7. Update website docs (already done — FAQ and privacy page reference Insights)
