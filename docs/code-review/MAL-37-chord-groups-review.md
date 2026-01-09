# MAL-37 Chord Groups - Code Review

**Date**: 2026-01-08
**Reviewer**: Claude
**Status**: ⚠️ Issues Found - Requires Fixes

## Executive Summary

The chord groups implementation is **functionally complete** and passes all existing tests (33 tests). However, there are **critical input validation gaps** and **missing edge case tests** that could lead to invalid Kanata config generation.

**Severity Breakdown:**
- 🔴 **Critical**: 3 issues (invalid config generation)
- 🟡 **Warning**: 5 issues (robustness, edge cases)
- 🔵 **Info**: 4 issues (code quality, documentation)

**Recommendation**: Fix critical issues before merging to production.

---

## 🔴 Critical Issues

### 1. No Validation for Group Names with Spaces/Special Characters

**File**: `KanataConfigurationGenerator.swift:1107`

```swift
let output = "(chord \(group.name) \(key))"
```

**Problem**: If `group.name` contains spaces or special characters, generates invalid Kanata syntax:
- Input: `name = "My Group"`
- Output: `(chord My Group a)` ❌ Invalid!
- Expected: `(chord My-Group a)` or reject with validation

**Impact**: Kanata will fail to parse the config file.

**Fix**: Add validation in `ChordGroup.init()`:
```swift
public init(...) {
    precondition(!name.isEmpty, "Group name cannot be empty")
    precondition(!name.contains(" "), "Group name cannot contain spaces")
    precondition(name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" },
                 "Group name must be alphanumeric with - or _")
    // ...
}
```

**Test Coverage**: Missing

---

### 2. No Validation for Empty Keys Array

**File**: `ChordGroupsConfig.swift:393`

```swift
let keys = chord.keys.joined(separator: " ")
lines.append("  (\(keys)) \(chord.output)")
```

**Problem**: If `chord.keys` is empty, generates `() output` which is invalid Kanata syntax.

**Impact**: Broken config file.

**Fix**: Add validation in `ChordDefinition.init()`:
```swift
public init(...) {
    precondition(!keys.isEmpty, "Chord must have at least one key")
    precondition(keys.allSatisfy { !$0.isEmpty }, "Keys cannot be empty strings")
    // ...
}
```

**Test Coverage**: Missing

---

### 3. Cross-Group Key Conflicts Create Duplicate Mappings

**File**: `KanataConfigurationGenerator.swift:1097-1118`

**Problem**: If two chord groups use the same key, `generateChordGroupsMappings` creates duplicate `KeyMapping` entries:

```swift
Group1: "Navigation" uses keys [s, d, f]
Group2: "Editing" uses keys [a, s, f]

Generated mappings:
  s → (chord Navigation s)
  d → (chord Navigation d)
  f → (chord Navigation f)
  a → (chord Editing a)
  s → (chord Editing s)  // Duplicate! Last wins
  f → (chord Editing f)  // Duplicate! Last wins
```

**Impact**: Silent conflicts, unpredictable behavior. Later group silently overrides earlier group.

**Fix**: Detect cross-group conflicts and either:
1. **Reject**: Add validation to detect and prevent
2. **Document**: Add comment explaining last-wins behavior
3. **Merge**: Generate single mapping that references both chord groups (advanced)

**Recommended**: Option 1 (reject) for safety.

**Test Coverage**: Missing

---

## 🟡 Warning Issues

### 4. No Timeout Range Validation

**File**: `ChordGroupsConfig.swift:67-81`

**Problem**: No validation that `timeout` is in a reasonable range.
- Negative timeout: `-100ms` → Invalid
- Zero timeout: `0ms` → Probably invalid
- Huge timeout: `999999ms` → Impractical

**Impact**: Generates technically valid but nonsensical configs.

**Fix**:
```swift
public init(...) {
    precondition(timeout >= 50 && timeout <= 2000,
                 "Timeout must be between 50-2000ms")
    // ...
}
```

**Test Coverage**: Missing

---

### 5. `areAdjacent` Returns True for Empty Array

**File**: `ChordGroupsConfig.swift:172-184`

```swift
private func areAdjacent(_ keys: [String]) -> Bool {
    let homeRowOrder = ["a", "s", "d", "f", "g", "h", "j", "k", "l", ";"]
    let positions = keys.compactMap { homeRowOrder.firstIndex(of: $0) }
    guard positions.count == keys.count else { return false }

    let sorted = positions.sorted()
    for i in 0..<(sorted.count - 1) {  // If count == 0, loop doesn't run
        // ...
    }
    return true  // Returns true for empty array!
}
```

**Impact**: Empty keys array incorrectly scores as "adjacent home row" (excellent ergonomic score).

**Fix**: Add guard at the beginning:
```swift
guard !keys.isEmpty else { return false }
```

**Test Coverage**: Missing

---

### 6. No Validation for Special Characters in Output

**File**: `KanataConfigurationGenerator.swift:394`

```swift
lines.append("  (\(keys)) \(chord.output)")
```

**Problem**: If `output` contains unbalanced parens or special chars, could break Kanata syntax:
- Output: `"esc)"` → `(s d) esc)` ❌ Unbalanced parens

**Impact**: Invalid config, hard to debug.

**Fix**: Either:
1. Validate output against allowed Kanata actions
2. Escape special characters
3. Document that users are responsible for valid Kanata syntax

**Recommended**: Option 3 with defensive checks for obviously bad inputs like `)` alone.

**Test Coverage**: Partial (testChordGroupsWithSpecialCharactersInOutput tests macros, but not malformed syntax)

---

### 7. Duplicate Keys in Same ChordDefinition

**File**: `ChordGroupsConfig.swift:120`

**Problem**: No validation that `keys` array has unique elements:
- Input: `keys: ["s", "s", "d"]`
- Generates: `(s s d) esc` (possibly invalid or unexpected behavior)

**Impact**: Unclear semantics, possibly invalid Kanata syntax.

**Fix**:
```swift
public init(...) {
    precondition(Set(keys).count == keys.count, "Keys must be unique")
    // ...
}
```

**Test Coverage**: Missing

---

### 8. Overlapping Chord Prefixes Not Detected

**File**: `ChordGroupsConfig.swift:94-114`

**Problem**: Conflict detection only checks for exact matches, not overlapping prefixes:
- Chord 1: `["s", "d"]` → `esc`
- Chord 2: `["s", "d", "f"]` → `C-x`

In Kanata, if you press `s`, `d`, `f` simultaneously, the shorter chord `sd` might trigger first (depending on timing/implementation).

**Impact**: Unpredictable behavior with overlapping chords.

**Fix**: Add overlapping detection:
```swift
// Check if one chord's keys are a subset of another
let keys1Set = Set(chord1.keys)
let keys2Set = Set(chord2.keys)
if keys1Set.isSubset(of: keys2Set) || keys2Set.isSubset(of: keys1Set) {
    if keys1Set != keys2Set {  // Not exact match (already handled)
        conflicts.append(ChordConflict(chord1: chord1, chord2: chord2,
                                      type: .overlapping))
    }
}
```

**Test Coverage**: Missing

---

## 🔵 Info Issues

### 9. Missing Documentation for Public APIs

**Files**: Multiple

**Missing doc comments for:**
- `ChordConflict` init
- `ChordSpeed.nearest(to:)` tie-breaking behavior
- `ChordGroup.detectConflicts()` - what types of conflicts?
- `ChordGroupsConfig.activeGroupID` - purpose unclear

**Fix**: Add comprehensive doc comments.

---

### 10. No Validation for renderUIChordGroupsBlock Output Order

**File**: `KanataConfigurationGenerator.swift:391-395`

**Problem**: Chords are rendered in array order. In Kanata, defchords are processed in order, so if you have overlapping chords, order matters. This isn't documented.

**Fix**: Add comment explaining ordering, or sort chords by key count (longer first) to ensure most specific chords are checked first.

---

### 11. Inconsistent Error Handling Strategy

**Observation**: Some places use `precondition` (crashes), some use validation methods (`isValid`), some silently accept invalid input.

**Recommendation**: Choose consistent strategy:
- **Model validation**: Use `precondition` in init for truly invalid states
- **UI validation**: Use `isValid` properties for user-correctable errors
- **Config generation**: Fail loudly with `precondition` or return `Result` type

---

### 12. No Performance Consideration for Large Configs

**File**: `ChordGroupsConfig.swift:94-114`

**Problem**: `detectConflicts()` is O(n²) where n = number of chords. For large chord groups (100+ chords), could be slow.

**Impact**: Minimal (unlikely anyone has >100 chords in a single group).

**Fix**: If needed, optimize with HashMap/Set-based lookup. Not urgent.

---

## Missing Test Coverage

### Unit Tests (ChordGroupsConfigTests.swift)

**Missing tests:**

1. **Validation Edge Cases:**
   ```swift
   func testEmptyGroupName()
   func testGroupNameWithSpaces()
   func testGroupNameWithSpecialCharacters()
   func testNegativeTimeout()
   func testZeroTimeout()
   func testHugeTimeout()
   func testEmptyKeysArray()
   func testDuplicateKeysInChord()
   func testEmptyOutputString()
   ```

2. **Ergonomic Score Edge Cases:**
   ```swift
   func testErgonomicScoreEmptyKeys()
   func testErgonomicScoreSingleKey()
   func testErgonomicScoreNonHomeRowAdjacent()
   ```

3. **Conflict Detection:**
   ```swift
   func testDetectOverlappingChordPrefixes()
   func testDetectOverlappingChordSuffixes()
   func testMultipleConflictsSameChord()
   ```

4. **areAdjacent Helper:**
   ```swift
   func testAreAdjacentEmptyArray()
   func testAreAdjacentSingleKey()
   func testAreAdjacentNonHomeRowKeys()
   func testAreAdjacentWithGaps()
   ```

5. **Special Characters:**
   ```swift
   func testUnicodeInGroupName()
   func testUnicodeInKeys()
   func testUnicodeInOutput()
   func testParenthesesInOutput()
   ```

### Integration Tests (ChordGroupsIntegrationTests.swift)

**Missing tests:**

1. **Cross-Group Conflicts:**
   ```swift
   func testCrossGroupKeyConflicts()
   func testMultipleGroupsSameKeys()
   ```

2. **Invalid Syntax Generation:**
   ```swift
   func testGroupNameWithSpacesGeneratesInvalidConfig()
   func testEmptyKeysGeneratesInvalidConfig()
   ```

3. **Ordering:**
   ```swift
   func testChordDefinitionOrderingInOutput()
   func testOverlappingChordsRenderingOrder()
   ```

4. **Performance:**
   ```swift
   func testLargeConfigPerformance()  // 100+ chords
   ```

---

## Recommended Test Additions

Let me create a test file with all the missing critical tests:

### Priority 1: Critical Validation Tests

```swift
// Add to ChordGroupsConfigTests.swift

// MARK: - Input Validation Tests

func testGroupNameCannotBeEmpty() {
    // After adding precondition, this should trap
    // For now, test that empty name generates bad config
}

func testGroupNameWithSpacesIsInvalid() {
    // Should either reject or sanitize
}

func testNegativeTimeoutIsInvalid() {
    // Should reject negative timeouts
}

func testEmptyKeysArrayIsInvalid() {
    // Should reject empty keys
}

func testDuplicateKeysInChordDefinition() {
    let chord = ChordDefinition(id: UUID(), keys: ["s", "s", "d"], output: "esc")
    // Should either reject or deduplicate
}

// MARK: - Cross-Group Conflict Tests

func testCrossGroupKeyConflicts() {
    let group1 = ChordGroup(
        id: UUID(),
        name: "Nav",
        timeout: 250,
        chords: [ChordDefinition(id: UUID(), keys: ["s", "d"], output: "esc")]
    )
    let group2 = ChordGroup(
        id: UUID(),
        name: "Edit",
        timeout: 300,
        chords: [ChordDefinition(id: UUID(), keys: ["s", "d"], output: "bspc")]
    )

    // Both groups use "s" and "d" keys
    // Config generation should either:
    // 1. Reject this
    // 2. Document last-wins behavior
    // 3. Detect and warn
}

// MARK: - Overlapping Chord Tests

func testOverlappingChordPrefixes() {
    let group = ChordGroup(
        id: UUID(),
        name: "Test",
        timeout: 300,
        chords: [
            ChordDefinition(id: UUID(), keys: ["s", "d"], output: "esc"),
            ChordDefinition(id: UUID(), keys: ["s", "d", "f"], output: "C-x")
        ]
    )

    // "sd" and "sdf" overlap - should warn user
    // Currently not detected as conflict
}

// MARK: - areAdjacent Edge Cases

func testAreAdjacentEmptyArray() {
    let chord = ChordDefinition(id: UUID(), keys: [], output: "esc")
    // Currently returns true incorrectly
}

func testAreAdjacentSingleKey() {
    let chord = ChordDefinition(id: UUID(), keys: ["s"], output: "esc")
    // Single key cannot be "adjacent"
}
```

---

## Action Items

### Must Fix (Before Merge)

1. ✅ **Add input validation for group names** (no spaces, valid chars)
2. ✅ **Add validation for empty keys array**
3. ✅ **Add cross-group conflict detection** or document behavior
4. ✅ **Fix areAdjacent empty array bug**
5. ✅ **Add timeout range validation** (50-2000ms)

### Should Fix (Next Sprint)

6. ⚠️ Add overlapping chord detection
7. ⚠️ Add duplicate keys validation
8. ⚠️ Improve documentation
9. ⚠️ Add output syntax validation

### Nice to Have

10. 💡 Optimize detectConflicts for large configs
11. 💡 Add chord ordering logic for overlapping chords
12. 💡 Unicode support testing

---

## Test Coverage Summary

**Current Coverage:**
- Unit tests: 21 tests ✅
- Integration tests: 12 tests ✅
- **Total: 33 tests**

**Recommended Addition:**
- Critical validation tests: **10 tests**
- Edge case tests: **8 tests**
- Cross-group conflict tests: **3 tests**
- **Total: 21 additional tests → 54 total**

**Coverage Gaps:**
- Input validation: ❌ 0%
- Cross-group conflicts: ❌ 0%
- Edge cases (empty, special chars): ❌ 0%
- Normal flow: ✅ 90%+

---

## Conclusion

The implementation is **solid for happy path** but **vulnerable to invalid input**. The critical fixes are straightforward preconditions and validation checks. Adding these will make the feature production-ready.

**Estimated effort to fix critical issues:** 2-3 hours
**Estimated effort for all recommended fixes:** 1 day
