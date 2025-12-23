# LLM Vision UI Automation

This document outlines how KeyPath's private API infrastructure could be combined with LLM vision capabilities to enable intelligent, context-aware UI automation on macOS.

## Overview

KeyPath already has the building blocks for programmatic UI control:

| Component | Capability |
|-----------|------------|
| **AXUIElement APIs** | Read/write window properties, navigate UI hierarchies |
| **CGS Private APIs** | Space enumeration, window-to-space movement |
| **`_AXUIElementGetWindow`** | Bridge AX elements to CGWindowIDs |
| **Screenshot capture** | Via Peekaboo MCP or CGWindowListCreateImage |
| **Window positioning** | Snap, tile, move between displays/spaces |

The missing piece: **understanding what's on screen**. LLM vision models (GPT-4o, Claude, Gemini) can analyze screenshots and provide semantic understanding of UI elements.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        LLM Vision Layer                         │
│  "Click the Submit button" → (x: 450, y: 320, element: button) │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Screenshot Capture                          │
│  Peekaboo MCP / CGWindowListCreateImage / ScreenCaptureKit      │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Action Execution Layer                        │
│  AXUIElement (click, type) │ CGEvent (keyboard) │ CGS (spaces)  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                         macOS UI                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Available Private APIs

### Already Implemented in KeyPath

```swift
// CGSPrivate.swift - Space Management
CGSMainConnectionID() -> CGSConnectionID
CGSCopyManagedDisplaySpaces(_ connection: CGSConnectionID) -> CFArray
CGSManagedDisplayGetCurrentSpace(_ connection: CGSConnectionID, _ displayUUID: CFString) -> CGSSpaceID
CGSAddWindowsToSpaces(_ connection: CGSConnectionID, _ windowIDs: CFArray, _ spaceIDs: CFArray)
CGSRemoveWindowsFromSpaces(_ connection: CGSConnectionID, _ windowIDs: CFArray, _ spaceIDs: CFArray)
CGSCopySpacesForWindows(_ connection: CGSConnectionID, _ mask: Int, _ windowIDs: CFArray) -> CFArray

// AX → CGS Bridge
_AXUIElementGetWindow(_ element: AXUIElement, _ windowID: inout CGWindowID) -> AXError
```

### Additional Private APIs Worth Exploring

| API | Purpose | Stability |
|-----|---------|-----------|
| `SLSSetWindowAlpha` | Set window transparency without ownership | Stable |
| `SLSWindowSetShadowProperties` | Custom window shadows | Stable |
| `CGSSetWindowLevel` | Override window level | Stable |
| `_AXUIElementGetPid` | Get PID from AX element | Stable |
| `CGSSetWindowTransform` | Apply transforms to windows | Less stable |
| `SkyLight` framework | Modern window effects | macOS 10.14+ |

## LLM Vision Integration Patterns

### Pattern 1: Screenshot → Coordinates

```swift
// 1. Capture current screen
let screenshot = captureScreen()

// 2. Send to vision model with prompt
let prompt = """
Find the "Submit" button in this screenshot.
Return JSON: {"x": int, "y": int, "confidence": float}
"""
let response = await visionModel.analyze(screenshot, prompt: prompt)

// 3. Click at coordinates
let point = CGPoint(x: response.x, y: response.y)
performClick(at: point)
```

### Pattern 2: UI Tree + Vision Hybrid

The Accessibility API provides structured UI data, but it's often incomplete or unlabeled. Combine with vision:

```swift
// 1. Get AX UI tree
let axTree = AXUIElementCopyTree(frontApp)

// 2. Get screenshot
let screenshot = captureScreen()

// 3. Ask LLM to correlate
let prompt = """
Given this accessibility tree and screenshot, identify which AX element
corresponds to the red "Delete" button visible in the image.

AX Tree:
\(axTree.description)
"""

// 4. LLM returns AX element path
let elementPath = await visionModel.analyze(screenshot, prompt: prompt)

// 5. Navigate to element and interact
let element = navigateToElement(path: elementPath)
AXUIElementPerformAction(element, kAXPressAction)
```

### Pattern 3: Multi-Step Automation

```swift
struct AutomationStep {
    let description: String      // "Click File menu"
    let verification: String     // "Menu should open showing Save, Open, etc."
}

func executeAutomation(steps: [AutomationStep]) async {
    for step in steps {
        // 1. Capture state
        let before = captureScreen()

        // 2. Ask LLM what to do
        let action = await visionModel.analyze(before, prompt: step.description)

        // 3. Execute
        executeAction(action)

        // 4. Verify
        let after = captureScreen()
        let verified = await visionModel.verify(after, prompt: step.verification)

        guard verified else { throw AutomationError.verificationFailed(step) }
    }
}
```

## Integration with KeyPath

### Via push-msg Protocol

KeyPath already has a `keypath://` URL scheme for triggering actions. Extend for LLM automation:

```lisp
;; In kanata config - trigger AI-assisted action
(defalias
  ai-click (push-msg "ai:click:Submit button")
  ai-type (push-msg "ai:type:search field:hello world")
)
```

### Via MCP (Model Context Protocol)

Create a KeyPath MCP server exposing:

```typescript
// Tools for LLM agents
{
  "name": "keypath_click",
  "description": "Click at screen coordinates or on named element",
  "parameters": {
    "target": "string (element name or 'x,y' coordinates)",
    "button": "left | right | middle"
  }
}

{
  "name": "keypath_type",
  "description": "Type text, optionally into a specific field",
  "parameters": {
    "text": "string",
    "target": "string (optional element name)"
  }
}

{
  "name": "keypath_window",
  "description": "Window management actions",
  "parameters": {
    "action": "left | right | maximize | next-space | ..."
  }
}
```

## Peekaboo Integration

The Peekaboo MCP server (already configured in user's environment) provides:

- `peekaboo_capture_screenshot` - Capture screen/display
- `peekaboo_analyze_screenshot` - Capture + AI analysis in one call

This can be the vision input source:

```swift
// From Claude Code or other MCP client
let analysis = await mcp.call("peekaboo_analyze_screenshot", {
    prompt: "List all clickable buttons with their approximate coordinates"
})
```

## Security Considerations

1. **Accessibility Permission** - Required for AX and CGEvent APIs (same as Kanata)
2. **Screen Recording** - Required for screenshots (if not using AX-based capture)
3. **Local Processing** - Consider local vision models (LLaVA via Ollama) for privacy
4. **Rate Limiting** - Prevent runaway automation loops
5. **Confirmation UI** - For destructive actions, show confirmation before executing

## Future Possibilities

### Voice Control
```
User: "Move this window to the left half"
→ Speech-to-text → LLM intent parsing → keypath://window/left
```

### Automated Testing
```swift
// Describe test in natural language
let test = "Open Safari, navigate to example.com, verify the page title contains 'Example'"
await automationRunner.execute(test)
```

### Accessibility Enhancement
```swift
// Describe what you want to do
let intent = "Find and click the tiny close button on this modal"
// LLM locates it even if AX labels are missing
```

### Cross-App Workflows
```
"Take the selected text from this PDF, paste it into Notes,
and format it as a bulleted list"
```

## Implementation Roadmap

1. **Phase 1: Screenshot + Coordinates** (Simplest)
   - Capture screen via ScreenCaptureKit
   - Send to vision API
   - Execute click at returned coordinates

2. **Phase 2: AX Tree Correlation**
   - Dump AX tree alongside screenshot
   - LLM correlates visual elements to AX elements
   - Use AX APIs for more reliable interaction

3. **Phase 3: MCP Server**
   - Expose KeyPath automation as MCP tools
   - Allow Claude Code / other agents to control UI

4. **Phase 4: Local Vision**
   - Integrate Ollama + LLaVA for privacy
   - Faster response times for simple queries

## References

- [Peekaboo MCP](https://github.com/steipete/peekaboo-mcp) - Screenshot + AI analysis
- [CGSInternal](https://github.com/NUIKit/CGSInternal) - Private CGS API headers
- [alt-tab-macos](https://github.com/lwouis/alt-tab-macos) - Space enumeration patterns
- [Anthropic Computer Use](https://docs.anthropic.com/en/docs/computer-use) - Claude's computer control API
- [Apple Accessibility Programming Guide](https://developer.apple.com/library/archive/documentation/Accessibility/Conceptual/AccessibilityMacOSX/)
