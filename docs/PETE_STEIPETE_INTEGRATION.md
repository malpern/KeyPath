# Integration with Pete Steinmeyer's Agent Rules

## Overview

Your enhanced Swift best practices skill now incorporates guidance from Pete Steinmeyer's comprehensive agent-rules repository, creating a complete knowledge system for modern Swift development.

## Pete's Agent Rules (~/agent-rules/)

Pete maintains a comprehensive collection of rules and best practices for working with AI coding assistants:

**Repository**: https://github.com/steipete/agent-rules

**Your Local Copy**: `/Users/malpern/agent-rules/`

### Global Rules (~agent-rules/global-rules/)

Core development practices:
- **code-consolidation-dry.mdc** - DRY principles and code consolidation
- **dependency-management.mdc** - Smart dependency choices
- **github-issue-creation.mdc** - Structured issue analysis
- **mcp-peekaboo-setup.mdc** - Screenshot & vision analysis
- **unit-tests-and-documentation.mdc** - Testing and documentation guidance
- **permission-checking-architecture.mdc** - macOS permission patterns

### Project Rules (~agent-rules/project-rules/)

24 project-specific command rules for:
- Workflow commands (commit, analyze, implement, etc.)
- Code quality (check, clean, analyze, improve)
- Specialized tasks (MCP debugging, automation, accessibility)
- **modern-swift.mdc** - The source of your skill enhancement ✨

## Integration: Three-Layer Architecture

### Layer 1: Pete's Philosophy (modern-swift.mdc)

**Foundation for modern SwiftUI development:**
- State management (use built-in, avoid unnecessary abstractions)
- View ownership (state lives in views, not ViewModels)
- Async patterns (async/await, not Combine)
- View composition (small, focused views)
- Feature-based organization (not type-based)

### Layer 2: Paul Hudson's Anti-patterns (Hacking with Swift)

**Specific API modernizations and mistakes to avoid:**
- 15+ deprecated API replacements
- Accessibility issues (onTapGesture, button labels)
- Performance problems (Font sizes, GeometryReader, etc.)
- Code quality patterns

### Layer 3: Your Integrated Skill (swift-best-practices.md)

**Complete practical guidance with 60+ examples:**

```
Section 1: Modern SwiftUI Architecture (Pete's patterns)
Section 2: Deprecated API Replacements (Paul's patterns)
Section 3: Accessibility Issues
Section 4: Performance & Architecture
Section 5: Modern APIs
Section 6: Code Organization
Section 7: Important Notes
Section 8: 14-Item Pre-Ship Checklist
```

## Enhanced Skill Content

### What You Have Now

**File**: `~/.claude/commands/swift-best-practices.md`
**Size**: 16 KB | 694 lines | 8 sections
**Examples**: 60+ code snippets

### Section 1: Modern SwiftUI Architecture (NEW)

Directly from Pete's modern-swift.mdc with real examples:

1. **State Management Philosophy**
   - Show anti-pattern: Over-engineered with ViewModel
   - Show pattern: Direct @State in views
   - "Let SwiftUI handle the state"

2. **Shared State: @Observable Pattern (iOS 17+)**
   - Modern @Observable macro
   - Legacy @ObservableObject
   - Using with @environment

3. **State Ownership Principles**
   - State high in hierarchy (wrong)
   - State in views (right)
   - Extract only when necessary

4. **Async/Await Pattern**
   - Combine with .onReceive (avoid if possible)
   - async/await with .task (preferred)
   - Complete ProfileView example

5. **View Composition Over ViewModels**
   - Wrong: ViewModel for every view
   - Right: Small, focused views with @State
   - ItemList + ItemRow example

6. **Code Organization: By Feature, Not Type**
   - Wrong: Views/, ViewModels/, Models/
   - Right: Items/, Users/ (feature-based)

7. **Summary of Pete's Philosophy**
   - Quote: "Write SwiftUI code that looks like SwiftUI"
   - 7 key principles

### Sections 2-8: Original Content (Retained)

All Paul Hudson patterns plus accessibility and performance guidance.

## How to Use This Integration

### For Code Review

1. **Check Architecture First** (Pete's section)
   - Is state properly placed?
   - Are ViewModels necessary?
   - Is view composition clean?

2. **Check APIs Second** (Paul's section)
   - deprecated APIs in use?
   - Accessibility issues?
   - Performance problems?

3. **Use Checklist** (Section 8)
   - 14-item pre-ship verification

### For Phase 2-5 Refactoring

**Phase 2: Replace onTapGesture with Button**
- Reference accessibility section
- Use button patterns from Pete's examples

**Phase 4: Migrate ObservableObject → @Observable**
- Use Pete's @Observable examples
- Understand state ownership principles
- Apply feature-based organization

**Phase 5: Design system consistency**
- Reference view composition patterns
- Use feature-based folder organization

### For Team Training

1. **Start with Pete's Philosophy**
   - Show modern SwiftUI approach
   - Explain state ownership
   - Demonstrate view composition

2. **Then Add Paul's Anti-patterns**
   - Show deprecated APIs
   - Explain why they're problematic
   - Use examples for learning

3. **Apply to KeyPath**
   - Show how it's implemented
   - Reference specific files
   - Track progress through phases

## Knowledge Hierarchy

```
Pete's modern-swift.mdc (Philosophy & Architecture)
           ↓
Paul Hudson's Article (API & Anti-patterns)
           ↓
Your Swift Skill (Integrated Guidance + Examples)
           ↓
KeyPath Codebase (Applied Patterns)
           ↓
Team Knowledge (Shared Understanding)
```

## Key Files to Reference

### Pete's Rules
- `~/agent-rules/project-rules/modern-swift.mdc` - Source of architecture section
- `~/agent-rules/project-rules/ui-accessibility.mdc` - Accessibility patterns
- `~/agent-rules/global-rules/unit-tests-and-documentation.mdc` - Testing guidance
- `~/agent-rules/global-rules/code-consolidation-dry.mdc` - DRY principles

### Your Integration
- `~/.claude/commands/swift-best-practices.md` - The unified skill
- `docs/SWIFT_BEST_PRACTICES_INDEX.md` - Quick reference
- `docs/SWIFT_BEST_PRACTICES_SKILL.md` - Integration guide

### Original Sources
- Paul Hudson's Article: https://www.hackingwithswift.com/articles/281/what-to-fix-in-ai-generated-swift-code
- Pete's Repo: https://github.com/steipete/agent-rules

## Connection to KeyPath Phases

### Completed (Phase 1 & 3)
✅ Used Pete's DRY and consolidation principles
✅ Applied Paul's API migrations
✅ Fixed 532 deprecated APIs

### Phase 2: onTapGesture → Button
- Reference: Pete's ui-accessibility.mdc
- Use: Accessibility section of your skill
- Pattern: Button examples with labels

### Phase 4: ObservableObject → @Observable
- Reference: Pete's modern-swift.mdc
- Use: Modern SwiftUI Architecture section
- Pattern: @Observable examples and state ownership

### Phase 5: Design System & Organization
- Reference: Pete's code organization guidance
- Use: View composition examples
- Pattern: Feature-based folder structure

## Best Practices Moving Forward

1. **Before Writing Code**
   - Check Pete's architecture guidance
   - Reference your skill examples
   - Plan state ownership

2. **During Code Review**
   - Use Pete's philosophy as foundation
   - Check Paul's anti-patterns
   - Verify with 14-item checklist

3. **After Merging**
   - Document patterns used
   - Update skill if new patterns emerge
   - Share with team

4. **Continuous Improvement**
   - Follow Pete's continuous-improvement.mdc workflow
   - Update skill as Swift evolves
   - Keep knowledge synchronized

## Summary

You now have a complete, integrated knowledge system:

- **Architecture Foundation**: Pete's modern SwiftUI approach
- **API Modernization**: Paul Hudson's anti-patterns
- **Practical Application**: 60+ real examples
- **Quality Checklist**: 14-item pre-ship list
- **Team Knowledge**: Ready to share

This creates a single source of truth for Swift best practices in your workflow.

---

**Last Updated**: December 5, 2025
**Created by**: Claude Code + Integration with Pete Steinmeyer's Rules
**Status**: Ready for team use
