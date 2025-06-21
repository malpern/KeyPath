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
- **Test mode**: Try rules temporarily using hot reload

#### Phase 3: Smart Resolution  
- **Context awareness**: App-specific rules
- **Layer-first design**: Treat layers as primary organization
- **Conflict wizard**: Guided resolution UI
- **Hot reload conflict testing**: Real-time conflict detection via temporary rule application

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

### Hot Reload Testing for Conflict Detection

#### The Concept: "Try Before You Buy"
Leverage Kanata's hot reload capability (SIGUSR1/SIGUSR2) to detect conflicts by actually testing rule combinations:

1. **Save current config** as backup
2. **Apply new rule** to temporary config
3. **Hot reload** Kanata with combined config  
4. **Test behavior** programmatically or with user feedback
5. **Detect conflicts** based on actual vs expected behavior
6. **Revert or confirm** based on results

#### What This Could Detect

**Silent Conflicts:**
- Two rules mapping same key → test which one wins
- Example: "5→6" + "5→7" → send "5", see if output is 6 or 7

**Broken Dependencies:**
- Rules using undefined aliases → Kanata validation fails
- Missing layer references → runtime errors

**Layer Conflicts:**  
- Multiple rules using same activation key → test which layer activates
- Performance degradation → measure response time

#### Implementation Approaches

**1. Automated Testing**
- Create test config, hot reload, send synthetic keystrokes
- Capture outputs via macOS APIs, compare expected vs actual
- Fully automated but requires input simulation permissions

**2. User-Guided Testing**
- Apply rule temporarily, prompt user to test manually
- Show "Keep" or "Revert" buttons after user testing
- Simple but relies on user understanding

**3. Hybrid Analysis**
- Static analysis for obvious conflicts
- Hot reload testing for ambiguous cases  
- User confirmation for complex scenarios

#### User Experience Flow Example

**Scenario: Adding "5→7" when "5→6" exists**
1. Pre-check: "Key 5 already mapped to 6. Test new mapping?"
2. Apply temporarily: Config updated, Kanata reloaded
3. Test prompt: "Press 5 to test. You should see '7'"
4. User tests: Sees 7 appear
5. Decision: "Keep this rule? (replaces 5→6)"
6. Confirm or revert

#### Technical Challenges
- **Synthetic input**: macOS security restrictions on keystroke simulation
- **State management**: Kanata internal state, layer persistence
- **Rollback complexity**: Handling reload failures, ensuring clean state
- **Race conditions**: User input during testing, timing issues

#### Benefits vs Limitations

**Benefits:**
- Real conflict detection vs guessing
- User education through immediate feedback  
- Confidence building before committing rules
- Catches edge cases static analysis misses

**Limitations:**
- Not all conflicts testable (app-specific, timing-dependent)
- Performance overhead from extra reload cycles
- Security considerations with automated input injection

### Open Questions

1. Should some conflicts be allowed intentionally?
2. How to handle different keyboard layouts?
3. Automatic vs manual resolution?
4. How to leverage LLM for conflict suggestions?
5. Should we adopt layer-first architecture?
6. How complex should hot reload testing be in MVP vs future phases?
7. What's the right balance between automated testing vs user-guided testing?

### Recommendations

**For MVP**:
- Warn on direct key conflicts only
- Add basic rule reordering  
- Document conflict types in help
- Simple hot reload after rule installation (no conflict testing yet)

**Phase 2**:
- User-guided conflict testing: "Test this rule before keeping it?"
- Basic conflict badges on overlapping rules
- Manual rollback capabilities

**Future**:
- Comprehensive conflict analysis engine
- Automated testing with synthetic input
- Visual conflict graph showing rule interactions
- Smart resolution suggestions powered by LLM
- Rule templates/bundles for common patterns
- Performance impact testing and optimization suggestions


---

## 🔄 Future Enhancement Backlog

### Key Name Normalization Improvements

**Problem**: Current system only handles ~50 English key variations with hardcoded mappings and LLM fallback.

**Current Limitations:**
- No international keyboard support (German "leertaste", French "barre d'espace")
- No fuzzy matching for typos ("sapce" → "space")
- No natural language handling ("the space bar", "right control key")
- LLM calls block UI thread
- No left/right modifier distinction consistency

**Proposed 3-Phase Solution:**
1. **Expand hardcoded dictionary**: Add ~150 common variations, international terms, left/right modifiers
2. **Smart pre-processing**: Remove articles ("the"), handle common typos with fuzzy matching
3. **Performance optimization**: Async LLM calls with caching layer

**Expected Impact**: 90%+ success rate for natural key input vs current ~70%

### Advanced Conflict Detection

**Problem**: Users can create overlapping keyboard rules that interfere with each other.

**Conflict Types to Detect:**
- Direct key conflicts (5→6, 5→7)
- Tap-hold overlaps (space tap/hold defined twice)
- Layer namespace collisions
- Modifier chain conflicts (caps→ctrl affects caps+A)
- Sequence prefix conflicts ("email" vs "emailwork")

**Implementation Approach:**
1. **Static analysis**: Parse existing config, build conflict graph
2. **Hot reload testing**: Apply rules temporarily, test actual behavior
3. **User-guided resolution**: "Keep new rule? (replaces existing 5→6)"

**Technical Challenges**: macOS input simulation permissions, state management, rollback complexity

### LLM Response Parsing Robustness

**Problem**: Current parsing can fail on edge cases, malformed JSON, or unexpected LLM output formats.

**Improvements Needed:**
- Better error recovery for malformed code blocks
- Fallback parsing strategies for JSON variations
- Graceful handling of LLM hallucinations
- Retry mechanisms with refined prompts
- Validation of generated Kanata syntax before installation

**Expected Impact**: Reduced rule generation failures, better error messages for users

### Conflict Resolution UI Patterns

**Problem**: When conflicts are detected, users need intuitive ways to resolve them without technical knowledge.

**UI Design Challenges:**
- Explaining conflicts in non-technical terms
- Providing clear resolution options
- Maintaining workflow momentum
- Educational value vs simplicity

**Proposed UI Patterns:**
1. **Conflict badges**: Visual indicators on rules showing overlaps
2. **Resolution wizard**: Step-by-step guided conflict resolution
3. **Preview mode**: "Test rule before keeping" with temporary application
4. **Visual conflict graph**: Show rule relationships and dependencies
5. **Smart suggestions**: LLM-powered resolution recommendations

**Implementation Considerations:**
- Progressive disclosure (simple → advanced options)
- Undo/redo support for resolution actions
- Integration with existing rule management UI
- Accessibility for screen readers

### Privileged Helper Tool for Distribution Readiness

**Problem**: Current hot reload requires manual sudo commands, and distribution (App Store/signed installer) needs proper privilege management.

**Two-Birds-One-Stone Solution**: A single privileged helper tool that handles both Kanata management AND hot reload capabilities.

#### **Current Distribution Challenges:**
1. **Kanata installation** - Needs root privileges for low-level keyboard access
2. **Hot reload** - Needs root privileges to send SIGUSR1 signals to Kanata
3. **App Store distribution** - Apps can't request arbitrary root access
4. **User trust** - Manual sudo commands create security concerns

#### **Proposed Architecture:**

```
┌─────────────────┐    XPC     ┌─────────────────┐
│   KeyPath.app   │ ◄────────► │ KeyPathHelper   │
│  (User space)   │            │  (Root space)   │
│                 │            │                 │
│ • UI/UX         │            │ • Kanata mgmt   │
│ • Rule gen      │            │ • Hot reload    │
│ • Config mgmt   │            │ • File access   │
└─────────────────┘            └─────────────────┘
```

#### **KeyPathHelper Responsibilities:**
```swift
class KeyPathPrivilegedHelper {
    func installKanata() -> Bool           // Download/install Kanata binary
    func startKanata(configPath: String) -> Bool   // Launch with root privileges  
    func stopKanata() -> Bool              // Clean process termination
    func reloadKanata() -> Bool            // Send SIGUSR1 for hot reload
    func checkKanataStatus() -> KanataStatus // Process monitoring
    func updateKanataConfig(newConfig: String) -> Bool // Secure config updates
}
```

#### **User Experience Flow:**

**First Install:**
1. User downloads KeyPath.dmg (signed installer)
2. Drags KeyPath.app to Applications
3. First launch: "KeyPath needs to install keyboard management components"
4. User enters password **once** to install privileged helper
5. Helper automatically installs Kanata, starts it, everything works seamlessly

**Daily Usage:**
1. User creates rule in KeyPath.app (no special permissions)
2. Rule installed → automatic hot reload via helper (no password needed)
3. Completely seamless experience

**Uninstall:**
1. Helper provides clean removal of all components
2. No system residue left behind

#### **Distribution Benefits:**

**For Signed Distribution:**
- ✅ **One-time installation** of privileged helper during app setup
- ✅ **Code signed helper** that users trust (from same developer certificate)
- ✅ **Clean uninstall** (helper can remove itself and all components)
- ✅ **User permission flow** managed by macOS security framework
- ✅ **Notarization compatible** for Gatekeeper approval

**For App Store Distribution:**
- ✅ **Sandboxed main app** (no special entitlements needed in main bundle)
- ✅ **Privileged operations** isolated to separate, auditable helper
- ✅ **Apple's security model** - helper installation requires explicit user approval
- ✅ **Automatic updates** of both app and helper through standard mechanisms
- ✅ **Security review friendly** - clear separation of concerns

#### **Security Benefits:**
- **Principle of least privilege** - Helper only performs specific Kanata operations
- **Code signing chain** - Both app and helper signed by same developer identity
- **macOS managed permissions** - System handles helper installation/authorization
- **Auditable codebase** - Helper code is minimal, focused, and reviewable
- **Sandboxed main app** - UI/logic runs with normal user permissions
- **Secure communication** - XPC provides encrypted, authenticated inter-process communication

#### **Real-World Examples Using This Pattern:**
- **Little Snitch** (network monitoring - privileged network access)
- **Bartender** (menu bar management - system UI manipulation)  
- **CleanMyMac** (system maintenance - file system access)
- **Karabiner-Elements** (keyboard remapping - low-level input access)
- **1Password** (browser integration - privileged browser communication)

This is the **industry standard approach** for Mac apps requiring system-level access while maintaining security and distribution compatibility.

#### **Implementation Phases:**

**Phase 1 (Current):** 
- Keep manual reload approach for development
- Document current limitations in user documentation

**Phase 2 (Pre-distribution):**
1. Create `KeyPathHelper` privileged tool with XPC interface
2. Implement secure communication between main app and helper
3. Add helper installation flow to main app startup
4. Implement helper-based Kanata management (install/start/stop/reload)
5. Test signing, notarization, and installation flow
6. Add clean uninstall capabilities

**Phase 3 (Distribution Ready):**
- Ready for signed distribution via website
- Ready for Mac App Store submission
- Professional installation experience
- Enterprise deployment capable

#### **Technical Requirements:**
- **Helper tool** written in Swift/Objective-C with minimal dependencies
- **XPC service** for secure inter-process communication
- **Launch daemon** registration for system startup if needed
- **Code signing** with Developer ID or Mac App Store certificates
- **Installer package** (.pkg) for helper deployment
- **Privileged helper management** using ServiceManagement framework

#### **User Trust & Transparency:**
- Clear explanation during installation of what privileges are needed and why
- Open source helper code for security auditing
- Minimal privilege scope (only Kanata management, no broader system access)
- Optional: Allow users to review exact operations before helper installation

---

*Last updated: 2025-06-21*
*Added comprehensive conflict analysis, hot reload testing strategy, and future enhancement backlog*