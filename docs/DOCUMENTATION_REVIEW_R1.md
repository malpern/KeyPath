# Documentation Review for R1 Release

**Date:** December 2025  
**Reviewer:** Claude Code  
**Release:** R1 (Installer + Custom Rules only)

## Executive Summary

Reviewed all 20+ documentation files in `docs/` folder. Found **3 files to remove**, **5 files needing updates**, and **12 files that are accurate** for R1.

**R1 Features (from FeatureFlags.swift):**
- ✅ Installation Wizard, Permissions, VHID Driver
- ✅ LaunchDaemon, Privileged Helper  
- ✅ Rules Tab with Custom Rules only (no Rule Collections)
- ✅ Config Generation, Hot Reload, Validation
- ✅ Tap-Hold & Tap-Dance support

**R2 Features (NOT in R1):**
- ❌ Rule Collections (Vim, Caps Lock, Home Row Mods)
- ❌ Live Keyboard Overlay
- ❌ Mapper UI
- ❌ Simulator Tab
- ❌ Virtual Keys Inspector

---

## Files to Remove (3)

### 1. `docs/KANATA_SETUP.md` ⚠️ **REMOVE**

**Reason:** Severely outdated and duplicates content from other files.

**Issues:**
- References old paths (`/usr/local/etc/kanata/keypath.kbd`) - should be `~/Library/Application Support/KeyPath/keypath.kbd`
- Mentions `install-system.sh` script that doesn't exist
- References `test-kanata-system.sh` scripts that don't exist
- Describes old architecture (direct LaunchDaemon management vs InstallerEngine)
- Claims "Ready for Production" but describes outdated system
- Duplicates content from `KANATA_MACOS_SETUP_GUIDE.md` and `DEBUGGING_KANATA.md`

**Action:** Delete this file. Users should refer to:
- `KANATA_MACOS_SETUP_GUIDE.md` for setup instructions
- `DEBUGGING_KANATA.md` for troubleshooting
- `KEYPATH_GUIDE.adoc` for user-facing documentation

### 2. `docs/Plans/REFACTOR_WIZARD_VIEW_MODEL.md` ⚠️ **REMOVE**

**Reason:** Implementation plan document that's no longer relevant.

**Issues:**
- Describes refactoring task that may or may not be completed
- Contains implementation details, not user/developer documentation
- Should be in GitHub issues or project management tool, not docs folder
- Creates confusion about current state vs planned state

**Action:** Move to GitHub issue or archive. Not appropriate for public docs folder.

### 3. `docs/KEYBOARD_VISUALIZATION_MVP_PLAN.md` ⚠️ **REMOVE**

**Reason:** Future planning document, not R1 documentation.

**Issues:**
- Describes MVP plan for keyboard overlay (R2 feature)
- Contains implementation details and mockups
- Not relevant for R1 release
- Should be in GitHub issues or project management tool

**Action:** Move to GitHub issue or archive. Can be restored when R2 development begins.

---

## Files Needing Updates (5)

### 1. `docs/README.md` ✅ **UPDATE NEEDED**

**Current State:** Good overview but missing R1/R2 distinction.

**Issues:**
- Doesn't clearly indicate which features are R1 vs R2
- Lists `KANATA_SETUP.md` (should be removed)
- Could better organize by user vs developer docs

**Recommended Changes:**
```markdown
## Getting Started

**For Users:**
- [KEYPATH_GUIDE.adoc](KEYPATH_GUIDE.adoc) - Complete user guide
- [FAQ.md](FAQ.md) - Frequently asked questions
- [SAFETY_FEATURES.md](SAFETY_FEATURES.md) - Safety information

**For Developers:**
- [NEW_DEVELOPER_GUIDE.md](NEW_DEVELOPER_GUIDE.md) - Start here if you're new
- [ARCHITECTURE.md](ARCHITECTURE.md) - System architecture
- [DEBUGGING_KANATA.md](DEBUGGING_KANATA.md) - Debugging guide

**Note:** KeyPath uses release milestones. R1 includes Installer + Custom Rules only. 
R2 adds Rule Collections, Overlay, Mapper, and Simulator. See FeatureFlags.swift for details.
```

### 2. `docs/ACTION_URI_SYSTEM.md` ⚠️ **UPDATE NEEDED**

**Current State:** Comprehensive but mentions R2 features without clear labeling.

**Issues:**
- Documents Virtual Keys Inspector (R2 feature) without indicating it's R2-only
- Should add note at top: "Some features (Virtual Keys Inspector) are R2-only"

**Recommended Changes:**
Add header note:
```markdown
# KeyPath Action URI System

**Note:** Virtual Keys Inspector (see below) is an R2 feature and not available in R1.
R1 includes: launch, layer, rule, notify, open, fakekey actions.
```

### 3. `docs/KEYPATH_GUIDE.adoc` ⚠️ **UPDATE NEEDED**

**Current State:** Excellent user guide but mentions R2 features.

**Issues:**
- Mentions "Rule Collections" tab (R2 feature) without indicating it's R2-only
- References Virtual Keys Inspector (R2 feature)
- Should clarify R1 vs R2 features

**Recommended Changes:**
- Add note in "Rule Collections" section: "Available in R2 release"
- Add note in "Virtual Keys Inspector" section: "Available in R2 release"
- Or add a "Release Milestones" section explaining R1 vs R2

### 4. `docs/TAP_HOLD_TAP_DANCE.md` ✅ **UPDATE NEEDED**

**Current State:** Good documentation but mentions conflict detection that may be R2.

**Issues:**
- Documents conflict detection - verify this is in R1
- References "Rule Collections" in conflict examples (R2 feature)

**Recommended Changes:**
- Verify conflict detection is R1 feature (likely is, since Custom Rules exist)
- Update conflict examples to use Custom Rules only, not Rule Collections
- Add note if conflict detection between Custom Rules and Collections is R2-only

### 5. `docs/ARCHITECTURE.md` ⚠️ **MINOR UPDATE**

**Current State:** Excellent architecture guide.

**Issues:**
- Mentions "Rule Collections" in component descriptions
- Should clarify which components are R1 vs R2

**Recommended Changes:**
Add note:
```markdown
## Release Milestones

KeyPath uses feature gating via `ReleaseMilestone`:
- **R1:** InstallerEngine, Custom Rules, Configuration Service
- **R2:** Adds Rule Collections Manager, Overlay, Mapper, Simulator
```

---

## Files That Are Accurate (12)

### ✅ Core Documentation

1. **`docs/NEW_DEVELOPER_GUIDE.md`** - Excellent onboarding guide
   - Accurate architecture overview
   - Correct file references
   - Good critical rules section
   - No R2-specific content

2. **`docs/ARCHITECTURE.md`** - Comprehensive architecture guide
   - Accurate component descriptions
   - Correct patterns and principles
   - Minor update needed (see above) but mostly accurate

3. **`docs/ARCHITECTURE_DIAGRAM.md`** - Visual diagrams
   - Accurate Mermaid diagrams
   - Good component relationships
   - No R2-specific content

4. **`docs/DEBUGGING_KANATA.md`** - Excellent debugging guide
   - Comprehensive troubleshooting
   - Accurate command references
   - Real-world debugging insights
   - No R2-specific content

5. **`docs/FAQ.md`** - Concise FAQ
   - Accurate answers
   - No R2-specific content

6. **`docs/SAFETY_FEATURES.md`** - Safety information
   - Accurate safety features
   - Good emergency procedures
   - No R2-specific content

7. **`docs/KANATA_MACOS_SETUP_GUIDE.md`** - macOS setup guide
   - Accurate setup instructions
   - Correct paths and commands
   - Good troubleshooting section

8. **`docs/linting.md`** - Linting guide
   - Accurate SwiftLint instructions
   - No R2-specific content

9. **`docs/troubleshooting-helper.md`** - Helper troubleshooting
   - Accurate diagnostic information
   - Good troubleshooting steps

10. **`docs/kanata-push-msg-docs.adoc`** - Technical reference
    - Accurate Kanata push-msg documentation
    - No R2-specific content

### ✅ Planning Documents (Keep for Reference)

11. **`docs/SPARKLE_INTEGRATION_PLAN.md`** - Future plan
    - Clearly marked as "Planned" status
    - Good to keep for future reference
    - Not misleading about current state

12. **`docs/PETE_STEIPETE_INTEGRATION.md`** - Internal integration guide
    - Developer-focused, not user-facing
    - Accurate integration information
    - Good to keep for team reference

13. **`docs/Plans/multi-keyboard-targeting.md`** - Future plan
    - Clearly marked as "Planned" status
    - Good to keep for future reference
    - Not misleading about current state

---

## Summary of Actions

### Immediate Actions

1. **Delete:**
   - `docs/KANATA_SETUP.md` (outdated, duplicates other docs)
   - `docs/Plans/REFACTOR_WIZARD_VIEW_MODEL.md` (implementation plan, not docs)
   - `docs/KEYBOARD_VISUALIZATION_MVP_PLAN.md` (R2 planning doc)

2. **Update:**
   - `docs/README.md` - Add R1/R2 distinction, remove KANATA_SETUP.md reference
   - `docs/ACTION_URI_SYSTEM.md` - Add R2 feature notes
   - `docs/KEYPATH_GUIDE.adoc` - Add R1/R2 feature notes
   - `docs/TAP_HOLD_TAP_DANCE.md` - Verify conflict detection, update examples
   - `docs/ARCHITECTURE.md` - Add release milestone section

### Optional Improvements

- Consider adding a "Release Milestones" section to main README.md
- Consider creating `docs/R1_FEATURES.md` listing exactly what's in R1
- Consider adding R1/R2 badges to feature documentation

---

## Files Not Reviewed (Image Assets)

The `docs/images/` folder contains screenshots and assets. These should be reviewed separately to ensure:
- Screenshots match current UI
- No outdated UI elements shown
- All referenced images exist

---

## Conclusion

**Overall Assessment:** Documentation is in good shape for R1 release. Most files are accurate and up-to-date. The main issues are:

1. **Outdated file** (`KANATA_SETUP.md`) that should be removed
2. **Planning documents** that should be moved out of docs folder
3. **R2 feature mentions** that need R1/R2 labeling

After these updates, the documentation will be accurate and clear for R1 release.

