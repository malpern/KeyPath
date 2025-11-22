# Contract Test Checklist

**Status:** ✅ DEFINED - Behaviors we must test

**Date Defined:** 2025-11-17

---

## SystemContext Contract Tests

### What SystemContext Must Contain

**For CLI:**
- [ ] Can determine if system is healthy (all services running)
- [ ] Can determine if system needs repair (services unhealthy)
- [ ] Can determine if system needs install (services missing)
- [ ] Can list all missing permissions
- [ ] Can list all conflicts

**For GUI:**
- [ ] Can render current status (active/needs help/stopped)
- [ ] Can show missing permissions list
- [ ] Can show conflict details
- [ ] Can show service health status

**For Tests:**
- [ ] Can create mock SystemContext with known state
- [ ] Can verify SystemContext contains expected fields
- [ ] Can compare two SystemContexts for equality

**Test Cases:**
- [ ] Healthy system → SystemContext shows all services running, permissions granted
- [ ] Broken system → SystemContext shows unhealthy services, missing permissions
- [ ] Conflict scenario → SystemContext shows conflicts detected
- [ ] Empty system → SystemContext shows services missing, components missing

---

## InstallPlan Contract Tests

### When InstallPlan.status Should Be `.blocked` vs `.ready`

**Plan should be `.blocked` when:**
- [ ] Admin privileges not available (cannot write to `/Library/LaunchDaemons`)
- [ ] SMAppService approval pending (user hasn't approved in System Settings)
- [ ] Helper not registered (required for some operations)
- [ ] Writable directory check fails (cannot create files)

**Plan should be `.ready` when:**
- [ ] All requirements met
- [ ] At least one recipe to execute
- [ ] Dependencies resolved (no circular dependencies)

**Test Cases:**
- [ ] Missing admin → Plan status is `.blocked(requirement: .adminPrivileges)`
- [ ] All requirements met → Plan status is `.ready`
- [ ] Empty plan (nothing to do) → Plan status is `.ready` (but recipes list is empty)
- [ ] Circular dependency → Plan generation fails (error, not blocked)

---

## InstallerReport Contract Tests

### What InstallerReport Must Include

**For Logging:**
- [ ] Timestamp of execution
- [ ] Overall success/failure status
- [ ] List of executed recipes with results
- [ ] Error messages for failures

**For Debugging:**
- [ ] Which requirement blocked execution (if blocked)
- [ ] Final system state (if available)
- [ ] Duration of execution
- [ ] Per-recipe timing

**For UI:**
- [ ] Human-readable success message
- [ ] Human-readable failure message
- [ ] List of unmet requirements (if any)
- [ ] Actionable next steps

**Test Cases:**
- [ ] Successful execution → Report shows success=true, all recipes succeeded
- [ ] Blocked execution → Report shows success=false, unmetRequirements populated
- [ ] Partial failure → Report shows success=false, some recipes succeeded, some failed
- [ ] Empty plan → Report shows success=true, no recipes executed

---

## Requirement Failure Propagation

### How Requirement Failures Flow Through Plan → Report

**Flow:**
1. `makePlan()` checks requirements → Sets `plan.status = .blocked(requirement)` if unmet
2. `execute()` checks plan status → If blocked, immediately returns report with `unmetRequirements`
3. `InstallerReport` includes → `unmetRequirements` array with all blocking requirements

**Test Cases:**
- [ ] Requirement missing → Plan is blocked → Execute returns immediately → Report shows requirement
- [ ] Multiple requirements missing → Plan shows first blocking one → Report shows all unmet
- [ ] Requirement met during execution → Plan was ready → Execution proceeds → Report shows success

---

## Integration Contract Tests

### Façade Must Preserve Existing Behavior

**Service Dependency Order:**
- [ ] Services installed in order: VHID Daemon → VHID Manager → Kanata
- [ ] Plan recipes respect this order
- [ ] Execution respects this order

**Privilege Escalation:**
- [ ] Uses helper if available
- [ ] Falls back to Authorization Services if helper fails
- [ ] Falls back to osascript if Authorization Services fails

**SMAppService vs LaunchDaemon:**
- [ ] Detects if SMAppService is managing Kanata
- [ ] Skips LaunchDaemon plist creation if SMAppService active
- [ ] Uses SMAppService path when appropriate

**Version Checks:**
- [ ] Checks Kanata version before upgrade
- [ ] Checks driver version compatibility
- [ ] Generates upgrade recipes when needed

---

## Error Propagation Contract Tests

### How Errors Flow Through the Façade

**Error Sources:**
- [ ] Detection errors → `inspectSystem()` returns SystemContext with error state
- [ ] Planning errors → `makePlan()` returns blocked plan or throws
- [ ] Execution errors → `execute()` stops at first failure, returns report with error

**Error Handling:**
- [ ] First failure stops execution (doesn't continue)
- [ ] Error context captured (which recipe failed, why)
- [ ] Error messages are human-readable
- [ ] Errors include recovery suggestions

**Test Cases:**
- [ ] Detection fails → SystemContext has error state → Plan generation handles gracefully
- [ ] Recipe execution fails → Execution stops → Report shows which recipe failed
- [ ] Privilege escalation fails → Execution stops → Report shows privilege error

---

## Summary

**Must Test:**
1. ✅ SystemContext contains required fields
2. ✅ InstallPlan blocking logic works correctly
3. ✅ InstallerReport includes all required information
4. ✅ Requirement failures propagate correctly
5. ✅ Existing behavior preserved (service order, privilege paths, etc.)
6. ✅ Errors handled and propagated correctly

**Test File:** `Tests/KeyPathTests/InstallationEngine/InstallerEngineTests.swift`

**Priority:** Start with contract tests (verify types work), then add integration tests (verify behavior preserved)

