# KeyPath Project TODO

## 🔧 Current Status: Overall Good Shape

The project is in relatively good condition with:
- ✅ **12,123 lines of clean Swift code**
- ✅ **All tests passing** (106+ tests)
- ✅ **Proper dependency injection** implemented
- ✅ **Modern Swift Testing framework** in use
- ✅ **Good documentation** in `/docs`

## ⚠️ Areas Needing Attention

### 1. Code Quality Issues

#### Swift Compiler Warnings
- [ ] Fix nil comparison warnings in test files
- [ ] Address deprecated URLSession usage in `AnthropicModelProviderTests.swift`
- [ ] Fix implicitly unwrapped optional warnings in test files

#### TODO/FIXME Items
- [ ] Review and address TODO items in `KanataExecutableFinder.swift`
- [ ] Review and address FIXME items in `KanataServiceManager.swift`

### 2. Test Coverage Gaps

#### Skipped Tests
- [ ] Implement proper mocking for network/API scenarios
- [ ] Enable skipped tests marked as `.enabled(if: false)`
- [ ] Add integration tests for API-dependent functionality

#### Mock Dependencies
- [ ] Implement proper URLSession mocking
- [ ] Create isolated test environments for all external dependencies
- [ ] Add comprehensive error scenario testing

### 3. Documentation & Project Structure

#### Missing Configuration
- [ ] Re-create `CLAUDE.md` with project-specific AI rules
- [ ] Add project automation rules for consistent development

#### File Organization
- [ ] Move loose test files from root directory:
  - `cli-test.swift`
  - `keypath-cli.swift`
  - `test-karabiner.swift`
  - `test-keypath.sh`
  - `test_rule_generation.swift`
  - `test_rule_generation_inline.swift`
- [ ] Organize or remove temporary/experimental files

### 4. Production Readiness

#### API Key Management
- [ ] Implement secure API key storage (Keychain)
- [ ] Add API key validation and error handling
- [ ] Create user-friendly API key setup flow

#### Error Handling
- [ ] Add comprehensive error handling patterns
- [ ] Implement user-friendly error messages
- [ ] Add retry mechanisms for network operations

#### Security
- [ ] Security audit of Kanata rule injection mechanisms
- [ ] Validate user input for malicious code patterns
- [ ] Add sandboxing for rule execution

## 🎯 Recommended Implementation Order

### High Priority (Do First)
1. **Fix Swift warnings** in test files
2. **Address TODO/FIXME** items in service files  
3. **Re-create CLAUDE.md** with project rules for better AI assistance

### Medium Priority (Do Next)
4. **Clean up root directory** - move loose test files to appropriate locations
5. **Implement proper mocking** for network-dependent tests
6. **Add comprehensive error handling** patterns

### Low Priority (Nice to Have)
7. **Security audit** of rule injection mechanisms
8. **Performance optimization** if needed
9. **Additional documentation** for contributors

## 📝 Notes

- Recent accomplishments include successful dependency injection implementation and comprehensive test suite
- Project structure follows modern Swift/SwiftUI best practices
- Build system issues have been resolved (SPM artifacts cleanup completed)
- All core functionality is working and tested

## 🏁 Success Criteria

### Code Quality
- [ ] Zero Swift compiler warnings
- [ ] All TODO/FIXME items resolved or documented
- [ ] 100% test coverage for core functionality

### User Experience
- [ ] Seamless onboarding flow
- [ ] Robust error handling with helpful messages
- [ ] Secure credential management

### Developer Experience
- [ ] Clean project structure
- [ ] Comprehensive documentation
- [ ] Consistent development workflow with AI assistance

---

## 🎨 Architecture: Rule Conflicts and Ordering Considerations

### The Core Challenge
When multiple keyboard remapping rules can be active simultaneously, conflicts are inevitable. Unlike simple applications where the last rule wins, keyboard remapping has nuanced interactions that can lead to unexpected behavior, silent failures, and confusing user experiences.

### Types of Conflicts in Kanata

#### 1. Direct Key Conflicts
- **Scenario**: Two rules map the same key (e.g., "5 -> 6" and "5 -> 7")
- **Current behavior**: Last rule in config wins
- **Challenge**: User intent unclear

#### 2. Tap-Hold Conflicts
- **Scenario**: Multiple tap-hold definitions for same key
- **Example**: Space as both "tap=space, hold=shift" and "tap=tab, hold=control"
- **Complexity**: User might want both in different contexts

#### 3. Layer Conflicts
- **Scenario**: Multiple rules define different layers with same activation key
- **Example**: Hold F for navigation vs hold F for symbols
- **Challenge**: Layer namespace collisions

#### 4. Sequence/Combo Conflicts
- **Scenario**: Overlapping sequences (e.g., "email" -> expansion vs "emailwork" -> different expansion)
- **Issue**: Prefix matching can trigger wrong rule

#### 5. Modifier Chain Conflicts
- **Scenario**: Rules that remap modifiers affect other rules
- **Example**: Caps->Ctrl conflicts with Caps+A binding
- **Complexity**: Order-dependent resolution

### Why Order Matters

1. **Alias definitions** must precede usage
2. **Layer definitions** process sequentially
3. **Defsrc order** affects key priority
4. **Macro expansions** can trigger other rules

### Proposed Solutions

#### Phase 1: MVP Conflict Detection
- **Pre-install warnings**: Alert on direct key conflicts
- **Visual indicators**: Show already-mapped keys
- **Simple resolution**: "Replace existing mapping?" dialog

#### Phase 2: Rule Management
- **Manual ordering**: Drag to reorder rules (like Karabiner)
- **Conflict badges**: Visual indicators on conflicting rules
- **Test mode**: Try rules temporarily

#### Phase 3: Smart Resolution
- **Context awareness**: App-specific rules
- **Layer-first design**: Treat layers as primary organization
- **Conflict wizard**: Guided resolution UI

### Implementation Considerations

#### Needed Data Structures
```swift
struct RuleConflict {
    let type: ConflictType
    let affectedRules: [KanataRule]
    let severity: Severity
    let suggestions: [Resolution]
}

enum ConflictType {
    case directKey
    case tapHold
    case layer
    case sequence
    case modifier
}
```

#### Analysis Requirements
1. Build conflict graph from active rules
2. Detect overlapping bindings
3. Validate layer references
4. Check sequence prefixes
5. Trace modifier chains

### User Experience Goals

1. **Predictability**: Clear what happens when rules combine
2. **Discoverability**: Why isn't my rule working?
3. **Recovery**: Easy conflict resolution
4. **Education**: Teach layer-based thinking

### Open Questions

1. Should some conflicts be allowed intentionally?
2. How to handle different keyboard layouts?
3. Automatic vs manual resolution?
4. How to leverage LLM for conflict suggestions?
5. Should we adopt layer-first architecture?

### Recommendations

**For MVP**:
- Warn on direct key conflicts only
- Add basic rule reordering
- Document conflict types in help

**Future**:
- Comprehensive conflict analysis
- Visual conflict graph
- Smart resolution suggestions
- Rule templates/bundles

---

*Last updated: 2025-06-21*
*Added comprehensive conflict and ordering analysis*