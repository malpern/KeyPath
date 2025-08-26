# PLAN.md vs ARCHITECTURE.md Conflict Analysis

**Created:** August 26, 2025  
**Purpose:** Identify conflicts between refactoring plan and existing architecture constraints  
**Status:** Critical Review Required  

## 🚨 CRITICAL CONFLICTS IDENTIFIED

### 1. CGEvent Tap Handling - MAJOR CONFLICT

**ARCHITECTURE.md (ADR-006):**
> **Decision:** Move all event tap creation to root daemon only, eliminate GUI event taps  
> **Status:** In Progress ⚠️ (Week 3)  
> **Rationale:** Multiple event taps cause keyboard freezing, violates macOS "one event tapper" rule  
> **Implementation:** TCP-based key recording instead of GUI CGEvent taps

**PLAN.md Violation:**
- **Milestone 3:** Proposes TapSupervisor to "coordinate multiple taps without consolidating"
- **EventTag system:** Assumes multiple taps will continue to exist
- **KeyboardCapture integration:** Plans to keep GUI taps running alongside daemon taps

**RESOLUTION NEEDED:**
- ❌ **PLAN.md approach violates the "one event tapper" rule**
- ✅ **Must follow ARCHITECTURE.md: eliminate GUI taps entirely**
- ✅ **Replace KeyboardCapture CGEvent taps with TCP-based key recording**

### 2. KanataManager Consolidation - ARCHITECTURAL VIOLATION

**ARCHITECTURE.md (ADR-004):**
> **Decision:** Keep legacy KanataManager, add SimpleKanataManager for new features  
> **Dual KanataManager Architecture - DO NOT MERGE THESE CLASSES**

**PLAN.md Violation:**
- **Milestone 6:** Plans to consolidate lifecycle logic via LifecycleOrchestrator
- **Milestone 8:** Plans to slim KanataManager through delegation to unified services
- **Target:** Reduce KanataManager to thin facade over orchestrated services

**RESOLUTION NEEDED:**
- ⚠️ **Refactoring plan may conflict with dual architecture intention**
- ✅ **Can split KanataManager internally while preserving dual public APIs**
- ✅ **SimpleKanataManager should remain separate and modern**

### 3. PermissionOracle Integration - POTENTIAL CONFLICT

**ARCHITECTURE.md (Critical):**
> **DO NOT REPLACE** PermissionOracle - Single source of truth  
> **Every Permission Check Must Use Oracle**

**PLAN.md Assumption:**
- **Milestone 7:** Plans to create AccessibilityPermissionService
- **Service extraction:** May duplicate permission logic outside Oracle

**RESOLUTION NEEDED:**
- ❌ **AccessibilityPermissionService would bypass Oracle**
- ✅ **Permission services must delegate to Oracle, not replace it**
- ✅ **Oracle remains single source of truth**

## ⚠️ MODERATE CONFLICTS

### 4. State Machine Complexity - ARCHITECTURAL WARNING

**ARCHITECTURE.md:**
> **DO NOT SIMPLIFY wizard state machine** - handles 50+ edge cases automatically

**PLAN.md Approach:**
- **Milestone 6:** Consolidates lifecycle logic into LifecycleOrchestrator
- **4-state vs 14-state:** SimpleKanataManager vs LifecycleStateMachine

**RESOLUTION NEEDED:**
- ✅ **Keep wizard state machine complex as required**
- ✅ **LifecycleOrchestrator can coexist with wizard state machine**
- ⚠️ **Ensure no overlap in state management responsibilities**

### 5. System Interface Abstraction - ARCHITECTURE CONCERN

**ARCHITECTURE.md Pattern:**
- Established patterns for system integration
- LaunchDaemon management through specific interfaces
- Service health monitoring with proven logic

**PLAN.md Addition:**
- **SystemInterface protocol:** New abstraction layer over system calls
- **Mock implementations:** For testing system interactions

**RESOLUTION NEEDED:**
- ✅ **SystemInterface can be additive, not replacing existing patterns**
- ⚠️ **Must not interfere with proven service management logic**
- ✅ **Mocking is acceptable for testing, not production**

## ✅ COMPATIBLE APPROACHES

### 6. File Organization - NO CONFLICT

**PLAN.md Milestone 1:** Split KanataManager into extensions
- ✅ **Compatible:** Pure code organization, no architectural changes
- ✅ **Preserves:** Existing functionality and API surface

### 7. Protocol Extraction - COMPATIBLE IF CAREFUL

**PLAN.md Milestone 2:** Introduce protocol contracts
- ✅ **Compatible:** If protocols don't bypass Oracle or conflict with existing patterns
- ⚠️ **Must ensure:** Protocols delegate to existing systems, not replace them

### 8. Configuration Service Extraction - COMPATIBLE

**PLAN.md Milestone 4:** Extract ConfigurationService
- ✅ **Compatible:** Configuration handling is not architecturally protected
- ✅ **Preserves:** Existing configuration patterns through delegation

## 📋 REQUIRED PLAN.md UPDATES

### Critical Changes Required

1. **Remove TapSupervisor and EventTag System (Milestone 3)**
   - Replace with TCP-based key recording approach
   - Follow ARCHITECTURE.md ADR-006 guidance
   - Eliminate GUI CGEvent taps entirely

2. **Revise Permission Service Strategy (Milestone 7)**
   - AccessibilityPermissionService must delegate to PermissionOracle
   - No direct permission checking outside Oracle
   - Services can wrap Oracle calls but not bypass them

3. **Clarify KanataManager Approach (Milestone 6-8)**
   - Internal refactoring acceptable
   - Must preserve dual KanataManager/SimpleKanataManager architecture
   - Cannot merge the two manager approaches

### Recommended Additions

4. **Add TCP-based Key Recording System**
   - Replace KeyboardCapture CGEvent taps with TCP communication
   - Implement recording via kanata daemon instead of GUI
   - Follow proven Karabiner-Elements pattern

5. **Preserve Wizard Architecture**
   - Ensure LifecycleOrchestrator doesn't conflict with wizard state machine
   - Keep wizard navigation deterministic and comprehensive
   - Don't simplify wizard complexity

## 🔄 UPDATED MILESTONE APPROACH

### Modified Milestone 3: TCP-based Key Recording (not Event Taps)
**Original:** TapSupervisor and EventTag system  
**Updated:** TCP-based key recording system following ADR-006  
**Implementation:** 
- Remove KeyboardCapture CGEvent taps
- Implement key recording via kanata TCP API
- Follow single event tapper rule

### Modified Milestone 7: Oracle-Delegated Services (not Independent Services)
**Original:** Extract independent permission services  
**Updated:** Create service facades that delegate to PermissionOracle  
**Implementation:**
- AccessibilityPermissionService calls Oracle.shared.currentSnapshot()
- No direct system API calls outside Oracle
- Services provide convenience APIs over Oracle

### Modified Milestone 8: Internal KanataManager Refactoring Only
**Original:** Slim KanataManager to thin facade  
**Updated:** Internal refactoring while preserving dual architecture  
**Implementation:**
- Split KanataManager internal logic into services
- Preserve KanataManager vs SimpleKanataManager distinction
- Don't merge or consolidate the dual approach

## 🚨 CRITICAL DECISION POINTS

### 1. CGEvent Tap Strategy
**Decision Required:** Follow ARCHITECTURE.md ADR-006 and eliminate GUI taps?
- **Impact:** Major change to PLAN.md Milestone 3
- **Benefits:** Fixes keyboard freezing, follows proven pattern
- **Effort:** Significant - requires TCP-based recording implementation

### 2. KanataManager Consolidation Level  
**Decision Required:** How much internal consolidation is acceptable?
- **Impact:** Affects PLAN.md Milestones 6-8
- **Constraint:** Must preserve dual architecture concept
- **Approach:** Internal services OK, external API preservation required

### 3. Oracle Delegation vs Independent Services
**Decision Required:** Service extraction through Oracle delegation only?
- **Impact:** Affects PLAN.md Milestone 7
- **Constraint:** Oracle must remain single source of truth
- **Approach:** Facade services that delegate to Oracle

## 🎯 RECOMMENDATIONS

### Immediate Actions
1. **Update PLAN.md** to remove CGEvent tap coordination approach
2. **Research TCP-based key recording** implementation in kanata
3. **Clarify dual KanataManager preservation** strategy
4. **Ensure Oracle delegation pattern** in all permission services

### Architecture Validation
1. **Re-read ADR-006** for CGEvent tap elimination details
2. **Review SimpleKanataManager** as the modern approach to preserve
3. **Confirm Oracle integration requirements** for all permission checking
4. **Test wizard state machine preservation** during refactoring

### Updated Timeline
- **Milestone 3 complexity increased:** TCP implementation > Event tap coordination
- **Milestone 7 approach changed:** Oracle delegation > Independent services  
- **Overall timeline impact:** +1-2 weeks for ADR-006 compliance

---

**CONCLUSION:** PLAN.md has several critical conflicts with established ARCHITECTURE.md constraints. The refactoring is still valuable and achievable, but must be modified to respect the proven architectural decisions, particularly around CGEvent tap elimination and PermissionOracle centralization.