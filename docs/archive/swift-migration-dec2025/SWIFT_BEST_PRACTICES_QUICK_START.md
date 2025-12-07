# Swift Best Practices Migration - Quick Start Guide

## Start Here

You have 53 actionable issues identified across the KeyPath codebase via comprehensive agent-based review. This guide helps you prioritize and get started immediately.

**Time to Review:** 5 minutes
**Time to First Fix:** 15 minutes

---

## The 4-Week Plan

### Week 1: Quick Wins (5 hours)
- [ ] Task.sleep(nanoseconds:) → Task.sleep(for:) (35 instances, 1 hour)
- [ ] DispatchQueue.main.async/asyncAfter → async/await (8 instances, 2-3 hours)
- [ ] Task.sleep in UI Layer (2 instances, 0.5 hour)
- [ ] onTapGesture → Button (12 instances, 1-2 hours)
- **Build, test, commit**

**Result:** All deprecated APIs modernized, accessibility improvements start

### Week 2: Concurrency Fixes (10-12 hours)
- [ ] Eliminate @unchecked Sendable in HelperManager (4-6 hours)
- [ ] Simplify XPC error handling (4-5 hours)
- [ ] Add model validation (2-3 hours)
- **Comprehensive testing, commit**

**Result:** Thread-safety improved, XPC handling cleaner

### Week 3: First God Class (6-8 hours)
- [ ] Choose ONE: ConfigurationService or RulesSummaryView
- [ ] Plan extraction
- [ ] Extract and test
- **Comprehensive testing, commit**

**Result:** One major file refactored

### Week 4: More God Classes (12-15 hours)
- [ ] Extract remaining 2-3 god classes based on priority
- [ ] Refactor PrivilegedOperationsCoordinator
- [ ] Add state machine documentation
- **Comprehensive testing, commit**

**Result:** Codebase significantly improved, god classes eliminated

---

## Quick Decision Tree

### "I have 1 hour"
**Do this:**
1. Replace all `Task.sleep(nanoseconds:)` with `Task.sleep(for:)`
2. Run tests
3. Commit

**Files to modify:**
- Services layer: 12 files with 30 instances
- Core/Infrastructure: 5 instances

**Command:**
```bash
# Find all Task.sleep(nanoseconds: calls
grep -r "Task.sleep(nanoseconds:" Sources/

# Manual fix (verify with each change)
# OLD: try? await Task.sleep(nanoseconds: UInt64(500 * 1_000_000))
# NEW: try? await Task.sleep(for: .milliseconds(500))
```

### "I have 2-3 hours"
**Do this:**
1. Task.sleep modernization (1 hour)
2. onTapGesture → Button (12 instances, 1-2 hours)
3. Test and commit

**Start with these files for onTapGesture:**
- RulesSummaryView.swift
- CustomRuleEditorView.swift
- MapperView.swift

### "I have a day (8 hours)"
**Do this:**
1. Week 1 quick wins (5 hours)
2. Choose one god class (RulesSummaryView recommended, 3 hours)
3. Plan extraction with simple PR

### "I have a week"
**Do this:**
1. Entire Week 1 plan (5 hours)
2. Concurrency fixes (4-6 hours)
3. Start Week 3 god class (6-8 hours)
4. Create focused PRs for each

---

## The 10 Highest Impact Changes

### Ranked by Impact/Effort Ratio

| Rank | Change | Impact | Effort | Time | Files |
|------|--------|--------|--------|------|-------|
| 1 | Task.sleep(nanoseconds:) → Task.sleep(for:) | HIGH | 1 hr | 1 hr | 17 files |
| 2 | onTapGesture → Button (12 instances) | HIGH | 2 hrs | 2 hrs | 12 locations |
| 3 | Eliminate @unchecked Sendable | CRITICAL | 5 hrs | 6 hrs | 2 files (HelperManager) |
| 4 | DispatchQueue.main.async → async/await | MEDIUM | 3 hrs | 3 hrs | 6 files |
| 5 | Add accessibility labels (20 buttons) | HIGH | 2 hrs | 2 hrs | 8 files |
| 6 | ConfigurationService extraction | CRITICAL | 8 hrs | 8 hrs | 1 file → 5 files |
| 7 | RulesSummaryView extraction | CRITICAL | 6 hrs | 6 hrs | 1 file → 13 files |
| 8 | PrivilegedOperationsCoordinator refactor | HIGH | 10 hrs | 10 hrs | 1 file → 4 files |
| 9 | Model validation addition | MEDIUM | 3 hrs | 3 hrs | 4 files |
| 10 | KanataTCPClient extraction | MEDIUM | 5 hrs | 5 hrs | 1 file → 2 files |

---

## File Reference Guide

### Task.sleep Files (35 instances to fix)
**Services (30 instances):**
- KanataTCPClient.swift (8)
- KanataService.swift (4)
- SimpleModsService.swift (3)
- KarabinerConflictService.swift (2)
- KanataErrorMonitor.swift (1)
- KanataEventListener.swift (2)
- MainAppStateController.swift (2)
- ConfigFileWatcher.swift (2)
- SafetyTimeoutService.swift (1)
- PermissionGate.swift (2)
- PermissionRequestService.swift (1)
- ServiceHealthMonitor.swift (1)

**Core/Infrastructure (5 instances):**
- PrivilegedOperationsCoordinator.swift (4)
- ConfigurationService.swift (1)

**UI (2 instances):**
- ContentView.swift (1)
- KanataViewModel.swift (1)

### onTapGesture Files (12 instances to fix)
Scattered across multiple views. Use Xcode Find → "onTapGesture" to locate all.

**Priority files:**
- RulesSummaryView.swift (multiple)
- CustomRuleEditorView.swift (multiple)
- MapperView.swift (multiple)

### God Classes (6 files to extract)
**CRITICAL (1,700+ lines):**
- ConfigurationService.swift (1,738 lines) → Extract into 5 files
- RulesSummaryView.swift (2,049 lines) → Extract 12 nested structs

**HIGH (1,000-1,700 lines):**
- MapperView.swift (1,714 lines) → Extract components + ViewModel
- PrivilegedOperationsCoordinator.swift (991 lines) → Extract 3 types
- HelperManager.swift (947 lines) → Extract state machine + timeout logic
- KanataTCPClient.swift (1,214 lines) → Extract message codec

---

## How to Use the Swift Best Practices Skill

The comprehensive skill is at: `~/.claude/commands/swift-best-practices.md`

### When Fixing onTapGesture

**Reference:** Section 3 - Accessibility Issues → onTapGesture → Button

```swift
// From the skill (exactly what you need)

// ❌ BAD - Breaks VoiceOver
HStack {
    Image(systemName: "heart")
    Text("Like")
}
.onTapGesture {
    toggleLike()
}

// ✅ GOOD - Accessible
Button(action: toggleLike) {
    Label("Like", systemImage: "heart")
}

// ✅ GOOD - With custom styling
Button(action: toggleLike) {
    HStack {
        Image(systemName: "heart")
        Text("Like")
    }
}
.buttonStyle(.plain)
```

### When Modernizing Task.sleep

**Reference:** Section 2 - Deprecated API Replacements → Task.sleep(nanoseconds:) → Task.sleep(for:)

```swift
// From the skill

// ❌ OLD
try await Task.sleep(nanoseconds: UInt64(5 * 1_000_000_000))

// ✅ NEW
try await Task.sleep(for: .seconds(5))
try await Task.sleep(for: .milliseconds(500))
```

### When Refactoring with DispatchQueue

**Reference:** Section 4 - Performance & Architecture → DispatchQueue.main.async → async/await

```swift
// From the skill

// ❌ OLD
DispatchQueue.main.async {
    self.isLoading = false
}

// ✅ NEW
@MainActor
func updateUI() {
    isLoading = false
}

// ✅ NEW - In async context
Task { @MainActor in
    isLoading = false
}
```

### When Extracting God Classes

**Reference:** Section 6 - Code Organization

Key principle from the skill:
- One major type per file
- Supporting types in extensions or small utility files
- Max ~500 lines per file (maintainability limit)
- Consider preview providers as separate files in large projects

**Extraction Strategy:**
1. Identify the main responsibility (keep it in primary file)
2. Extract supporting types to separate files
3. Use extensions for grouping related functionality
4. Aim for ~200-300 lines per file

---

## Getting Started: Your First Fix

### Right Now (5 minutes)

1. **Open the comprehensive review:**
   ```bash
   open /Users/malpern/local-code/KeyPath/docs/SWIFT_BEST_PRACTICES_COMPREHENSIVE_REVIEW.md
   ```

2. **Review Phase 1 issues:**
   - 35 Task.sleep calls
   - 8 DispatchQueue calls
   - 2 Task.sleep in UI

3. **Pick one file:**
   - Start with KanataTCPClient.swift (8 instances)
   - Or ConfigurationService.swift (1 instance)
   - Or SimpleModsService.swift (3 instances)

### In the next 30 minutes

1. **Open the file in Xcode**
2. **Find all Task.sleep(nanoseconds: calls**
   - Use Cmd+F to find `Task.sleep(nanoseconds:`
3. **Calculate the duration:**
   - 500,000,000 nanoseconds = 0.5 seconds = 500 milliseconds
   - Use online converter if needed
4. **Replace with Task.sleep(for:)**
   - `try await Task.sleep(for: .milliseconds(500))`
5. **Test locally:**
   ```bash
   swift test
   ```
6. **Commit:**
   ```bash
   git add Sources/KeyPathAppKit/Services/KanataTCPClient.swift
   git commit -m "refactor: modernize Task.sleep API (KanataTCPClient)"
   ```

---

## Common Nanosecond Conversions

Keep this handy:

| Nanoseconds | Milliseconds | Duration Code |
|-------------|-------------|---------------|
| 100,000,000 | 100 | `.milliseconds(100)` |
| 500,000,000 | 500 | `.milliseconds(500)` |
| 1,000,000,000 | 1,000 | `.seconds(1)` |
| 2,000,000,000 | 2,000 | `.seconds(2)` |
| 3,000,000,000 | 3,000 | `.seconds(3)` |
| 5,000,000,000 | 5,000 | `.seconds(5)` |

**Math:**
- `nanoseconds ÷ 1,000,000 = milliseconds`
- `nanoseconds ÷ 1,000,000,000 = seconds`

---

## Tracking Progress

### Create a checklist in CLAUDE.md

```markdown
## Swift Best Practices Migration Progress

### Phase 1: Quick Wins (Week 1)
- [ ] Task.sleep(nanoseconds:) → Task.sleep(for:) (35 instances)
- [ ] DispatchQueue.main.async/asyncAfter → async/await (8 instances)
- [ ] onTapGesture → Button (12 instances)

### Phase 2: Concurrency (Week 2)
- [ ] Eliminate @unchecked Sendable (2 instances)
- [ ] Simplify XPC error handling (1 instance)
- [ ] Add model validation (multiple)

### Phase 3-4: God Classes (Weeks 3-4)
- [ ] ConfigurationService extraction
- [ ] RulesSummaryView extraction
- [ ] MapperView extraction
- [ ] PrivilegedOperationsCoordinator refactoring
```

---

## When You Get Stuck

### Problem: "I don't know the nanosecond value"

**Solution:** Use Python to convert
```bash
python3 -c "print(f'{2500000000 / 1_000_000_000} seconds')"
# Output: 2.5 seconds
```

Or search the file for context:
```bash
grep -B2 -A2 "2500000000" Sources/KeyPathAppKit/Services/KanataTCPClient.swift
```

### Problem: "This is a complex change"

**Solution:** Focus on one file at a time. Create small PRs:
- One file = one commit
- One task type = one PR
- Test thoroughly before committing

### Problem: "Tests are failing"

**Solution:**
1. Check the test output carefully
2. The change should be mechanical (no logic changes)
3. If tests fail, you may have converted nanoseconds incorrectly
4. Verify the math: 500,000,000 ns = 500 ms = 0.5 seconds

### Problem: "The @unchecked Sendable is complex"

**Solution:** Skip it for now, focus on Phase 1-2. Return to concurrency issues after quick wins.

---

## Success Metrics

### After Week 1 (5 hours)
- ✅ All Task.sleep calls modernized
- ✅ All onTapGesture converted to Button
- ✅ All DispatchQueue.main calls modernized
- ✅ Tests still passing
- ✅ 38 issues closed

### After Week 2 (10-12 hours)
- ✅ Concurrency issues fixed
- ✅ Model validation added
- ✅ 48 issues closed
- ✅ Code quality significantly improved

### After Week 4 (32-40 hours)
- ✅ All god classes extracted
- ✅ Codebase significantly refactored
- ✅ 53 issues closed
- ✅ Technical debt reduced by 80%
- ✅ Build and test times improved

---

## References

- **Full Review:** `docs/SWIFT_BEST_PRACTICES_COMPREHENSIVE_REVIEW.md`
- **Swift Skill:** `~/.claude/commands/swift-best-practices.md`
- **Kanata Integration:** `docs/PETE_STEIPETE_INTEGRATION.md`
- **Index:** `docs/SWIFT_BEST_PRACTICES_INDEX.md`

---

## Next Steps

1. **Read this guide** (done!)
2. **Open the comprehensive review** (5 min)
3. **Pick Week 1 task** (5 min)
4. **Start with Task.sleep modernization** (1 hour)
5. **Move to onTapGesture fixes** (2 hours)
6. **Celebrate quick wins** (commit and test!)

**Estimated time to complete Week 1: 4-5 hours**
**Estimated time to complete all phases: 65-85 hours (2-3 weeks)**

---

**Ready to start? Pick a file and go! 🚀**

**Generated with Claude Code**
**December 5, 2025**
