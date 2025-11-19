# Phase 0 Explained: Beginner-Friendly Guide

This document explains Phase 0 steps in simple terms, assuming you're new to Swift and this codebase.

---

## What is Phase 0?

**Phase 0 = "Write down what we're going to build BEFORE we build it"**

Think of it like planning a road trip:
- You don't just start driving
- You write down: where you're going, what route you'll take, what you'll pack
- That's Phase 0 - planning and documentation

---

## Step 1: Freeze API Signatures

### What does "freeze" mean?
**Freeze = "decide and write down, don't change later"**

### What is an "API signature"?
An **API signature** is like a function's "business card" - it tells you:
- The function name
- What inputs it takes
- What it returns

**Example from existing code:**
```swift
// This is a function signature:
func createAllLaunchDaemonServices() async -> Bool

// Breaking it down:
// - Name: createAllLaunchDaemonServices
// - Takes: nothing (empty parentheses)
// - Returns: Bool (true/false)
// - Is async: yes (runs in background)
```

### What we're doing:
We're writing down the **exact** function signatures we'll create, so everyone knows what the façade will look like.

**Example:**
```swift
// We're committing to this exact signature:
func inspectSystem() -> SystemContext

// NOT this (different name):
func checkSystem() -> SystemContext

// NOT this (different return type):
func inspectSystem() -> SystemSnapshot
```

**Why?** So when we start coding, we don't keep changing our minds about names/types.

**Practical task:**
1. Open `docs/InstallerEngine-Design.html`
2. Copy the 4 method signatures exactly
3. Write them in a file called `API_CONTRACT.md`
4. That's it - we've "frozen" them

---

## Step 2: Define Type Contracts

### What is a "type"?
A **type** is like a blueprint for data. Think of it like a form:

**Example:**
```swift
// This is a type (struct):
struct InstallerReport {
    let timestamp: Date
    let success: Bool
    let failureReason: String?
}

// It's like a form with 3 fields:
// - timestamp: when did this happen?
// - success: did it work? (true/false)
// - failureReason: if it failed, why? (optional)
```

### What is a "contract"?
A **contract** = "promise of what fields/properties this type MUST have"

### What we're doing:
We're writing down what fields each type needs, so when we create it, we know what to include.

**Example for `SystemContext`:**
```swift
// We need to decide: what should SystemContext contain?
struct SystemContext {
    // Should it have permissions? YES
    let permissions: PermissionState
    
    // Should it have service status? YES
    let services: ServiceStatus
    
    // Should it have conflicts? YES
    let conflicts: ConflictState
    
    // Should it have the user's favorite color? NO (not relevant)
    // let favoriteColor: String  // ❌ Don't add this
}
```

**Practical task:**
1. Look at existing code that creates similar data
2. Write down: "SystemContext must have: permissions, services, conflicts"
3. Write down: "InstallPlan must have: recipes list, status enum"
4. That's the "contract" - what we promise to include

---

## Step 3: Create Contract Test Checklist

### What is a "contract test"?
A **contract test** = "test that checks if our code does what we promised"

### What is a "checklist"?
A **checklist** = "list of things to verify"

### What we're doing:
We're writing down what behaviors we need to test, so we know what to verify later.

**Example checklist item:**
```
☐ When SystemContext is created, it must include:
  - Current permission state (granted/denied)
  - Service health (running/stopped/missing)
  - Conflict detection (any conflicts found?)
```

**Another example:**
```
☐ When InstallPlan.status is .blocked, it means:
  - A requirement is missing (e.g., no admin rights)
  - Execution should NOT proceed
  - Report should explain which requirement failed
```

**Practical task:**
1. For each type, write: "What must it contain?"
2. For each method, write: "What should it do in success case? Failure case?"
3. That's your test checklist - you'll write actual tests later

---

## Step 4: Capture Current Test Outputs

### What does "capture" mean?
**Capture = "save/record what happens right now"**

### What are "test outputs"?
**Test outputs** = "what the tests currently check/assert"

### What we're doing:
We're looking at existing tests and writing down what they currently verify, so we know what behavior we must preserve.

**Example:**
```swift
// This is an existing test in LaunchDaemonInstallerTests.swift:
func testServiceDependencyOrder() {
    // It checks that services are installed in this order:
    // 1. VirtualHID Daemon
    // 2. VirtualHID Manager  
    // 3. Kanata
    
    // We need to write down: "Services MUST be installed in this order"
    // So our new façade preserves this behavior
}
```

**Practical task:**
1. Open `Tests/KeyPathTests/LaunchDaemonInstallerTests.swift`
2. Read through the tests
3. Write down: "Current behavior: services installed in order X, Y, Z"
4. Do the same for other test files
5. This becomes our "baseline" - what we must not break

---

## Step 5: Create System State Fixtures

### What is a "fixture"?
A **fixture** = "sample/test data saved in a file"

Think of it like a photo:
- You take a photo of your room (current state)
- Later, you compare: "Is my room still like this photo?"
- A fixture is like that photo - saved state to compare against

### What is "system state"?
**System state** = "what the computer looks like right now"
- Are services running?
- Are permissions granted?
- Are there conflicts?

### What we're doing:
We're saving examples of different system states, so we can test our façade against them.

**Example scenarios:**

**Scenario 1: Healthy System**
```swift
// Save this as a fixture file: healthy_system.json
{
    "permissions": {
        "inputMonitoring": "granted",
        "accessibility": "granted"
    },
    "services": {
        "kanata": "running",
        "vhid": "running"
    },
    "conflicts": []
}
```

**Scenario 2: Broken System**
```swift
// Save this as: broken_system.json
{
    "permissions": {
        "inputMonitoring": "denied",  // ❌ Missing
        "accessibility": "granted"
    },
    "services": {
        "kanata": "stopped",  // ❌ Not running
        "vhid": "running"
    },
    "conflicts": []
}
```

**Practical task:**
1. Run the app on a healthy system
2. Call `inspectSystem()` (once we build it)
3. Save the output to `fixtures/healthy_system.json`
4. Repeat for broken system, conflict scenario, etc.
5. These become test data we can reuse

---

## Step 6: Document Current Behavior

### What does "document" mean?
**Document = "write down what code currently does"**

### What is "current behavior"?
**Current behavior** = "what the existing code does right now"

### What we're doing:
We're reading existing code and writing down what it does, so we know what our façade needs to replicate.

**Example:**

**Reading `SystemSnapshotAdapter.swift`:**
```swift
// Looking at this code:
static func adapt(_ snapshot: SystemSnapshot) -> SystemStateResult {
    // It converts SystemSnapshot → SystemStateResult
    // It checks conflicts first
    // Then checks if kanata is running
    // Then checks permissions
    // Then checks components
}

// We write down:
// "SystemSnapshotAdapter.adapt() does:
//  1. Checks conflicts first (highest priority)
//  2. If kanata running → returns .active
//  3. If permissions missing → returns .missingPermissions
//  4. If components missing → returns .missingComponents
//  5. Otherwise → returns .serviceNotRunning"
```

**Practical task:**
1. Open `SystemSnapshotAdapter.swift`
2. Read the `adapt()` function
3. Write down in plain English: "This function does X, Y, Z"
4. Repeat for other key functions
5. This helps us understand what to replicate in the façade

---

## Step 7: Identify Collaborators

### What is a "collaborator"?
A **collaborator** = "another class/object that our façade will use"

Think of it like asking for help:
- You're building a house (the façade)
- You need a plumber (SystemSnapshotAdapter)
- You need an electrician (PrivilegedOperationsCoordinator)
- Those are your "collaborators"

### What we're doing:
We're making a list of existing code that our façade will call, so we know what dependencies we have.

**Example:**
```swift
// Our façade will need to call:
class InstallerEngine {
    // To inspect the system, we'll call:
    // - SystemSnapshotAdapter (to get system state)
    // - SystemRequirements (to check macOS version)
    // - ServiceStatusEvaluator (to check service health)
    
    // To make a plan, we'll call:
    // - WizardAutoFixer (to get auto-fix actions)
    // - LaunchDaemonInstaller (to know service recipes)
    
    // To execute, we'll call:
    // - PrivilegedOperationsCoordinator (to do privileged operations)
}
```

**Practical task:**
1. Look at the design doc - it lists what each method "wraps"
2. Make a list: "These are the classes we'll call"
3. That's it - just a list for reference

---

## Summary: What Are We Actually Doing?

**Phase 0 = Documentation and Planning**

1. **Write down** the exact function signatures we'll create
2. **Write down** what fields each type needs
3. **Write down** what behaviors we need to test
4. **Write down** what existing tests currently verify
5. **Save examples** of different system states
6. **Write down** what existing code does
7. **Make a list** of code we'll call

**Why?** So when we start coding in Phase 1, we have a clear plan and don't waste time deciding things on the fly.

**Think of it like:**
- Phase 0 = Writing the recipe
- Phase 1+ = Actually cooking

You wouldn't start cooking without a recipe, right? Same idea.

---

## How Long Should Phase 0 Take?

**For a beginner:** 2-4 hours
- Most of it is reading and writing notes
- No complex coding required
- Just documentation

**Tips:**
- Don't overthink it - just write down what you see
- Use simple language - you're documenting for yourself
- It's okay if it's not perfect - you can refine later

---

## Common Beginner Questions

**Q: Do I need to understand all the existing code?**
A: No! Just understand enough to write down what it does. You'll learn more as you go.

**Q: What if I don't know what a type should contain?**
A: Look at similar existing types. For example, look at `LaunchDaemonInstaller.InstallerReport` to see what a report looks like.

**Q: What if the design doc and existing code don't match?**
A: That's okay - write down both, note the differences. We'll figure it out during implementation.

**Q: Can I skip Phase 0 and just start coding?**
A: You could, but you'll waste time changing your mind later. Phase 0 is quick and saves time overall.

---

**Ready to start?** Begin with Step 1 - just copy the API signatures from the design doc into a new file. That's it!


