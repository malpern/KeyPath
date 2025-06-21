# KeyPath Architecture Guidelines

## 🚨 CRITICAL: LLM-First Design Philosophy

**KeyPath follows an LLM-first architecture. This means:**

### ❌ DO NOT ADD HARDCODED LOGIC WITHOUT APPROVAL

Before adding any of the following, you MUST get explicit approval:
- Hardcoded key mappings or dictionaries
- Fixed validation patterns or regex
- Static error messages
- Hardcoded suggestions or corrections
- Fixed lists of "valid" values
- Switch statements with hardcoded cases

### ✅ INSTEAD, USE LLM INTELLIGENCE

1. **For Key Recognition**: Use `KanataKeyValidator` with LLM provider
2. **For Error Messages**: Generate contextual messages via LLM
3. **For Validation**: Let LLM understand intent, not rigid patterns
4. **For Suggestions**: Use LLM to provide intelligent recommendations

### 📋 Required Pattern for New Features

```swift
// ❌ WRONG - Hardcoded logic
let validKeys = ["caps", "esc", "ctrl", "shift"]
if !validKeys.contains(userInput) {
    return "Invalid key"
}

// ✅ CORRECT - LLM-powered intelligence
let validator = KanataKeyValidator(llmProvider: llmProvider)
if !validator.isValidKeyName(userInput) {
    let suggestion = validator.suggestKeyCorrection(userInput)
    return suggestion.isEmpty ? 
        "Let me help you with that key name" : 
        "Did you mean '\(suggestion)'?"
}
```

### 🔍 Code Review Checklist

Before merging any PR, check:
- [ ] No new hardcoded key mappings
- [ ] No fixed validation patterns
- [ ] No static error messages
- [ ] Uses LLM for understanding user intent
- [ ] Maintains flexibility for edge cases

### 💡 Why This Matters

1. **User Experience**: Natural language input should "just work"
2. **Maintenance**: No need to update code for new key names
3. **Flexibility**: Handles variations and edge cases gracefully
4. **Intelligence**: Understands context and user intent

### 🚀 Implementation Guidelines

1. **Validation**: Always prefer understanding over rejection
2. **Error Messages**: Make them helpful and contextual
3. **Suggestions**: Provide intelligent alternatives
4. **Fallbacks**: Use hardcoded values only as last resort with LLM unavailable

### 📝 Documentation Requirements

When adding any validation or processing logic:
1. Add a comment explaining why it can't be LLM-powered
2. Document the approval from the project owner
3. Include a TODO to migrate to LLM when possible

```swift
// HARDCODED LOGIC NOTICE: Approved by @owner on 2024-01-20
// Reason: Performance-critical path needs <5ms response
// TODO: Migrate to cached LLM responses when available
```

### 🎯 Our Goal

KeyPath should understand what users mean, not force them to learn exact syntax. Every hardcoded rule is a barrier to that goal.

---

**Remember**: If you're about to add `if userInput == "exact_string"`, stop and think: "Could LLM handle this more intelligently?"