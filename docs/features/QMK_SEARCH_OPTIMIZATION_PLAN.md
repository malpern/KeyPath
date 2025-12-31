# QMK Keyboard Search Optimization Plan

## How VIA/VIAL Handle Keyboard Discovery

### VIA's Approach
1. **Bundled Database**: VIA bundles a curated JSON database (~2000 keyboards) with the app
   - Repository: `github.com/the-via/keyboards`
   - Structure: `v3/vendor/keyboard/keyboard.json`
   - Format: Custom JSON (not QMK info.json)
   - Size: ~10-20MB bundled

2. **USB Auto-Detection**: Uses VID/PID matching (not relevant for our use case)

3. **Manual Load**: Users can load JSON files if keyboard not in database

### VIAL's Approach
1. **Embedded JSON**: Stores `vial.json` directly in firmware
2. **Unique ID**: Each keyboard has `VIAL_KEYBOARD_UID`
3. **Real-time**: Reads from connected keyboard (not applicable to us)

## Key Lessons

### ✅ What Works Well
- **Bundled database** = instant results, no network delay
- **Structured format** = easy to search/filter
- **Curated list** = quality over quantity

### ❌ What Doesn't Scale
- **Fetching all keyboards upfront** = 2000+ HTTP requests = 30+ seconds
- **Fetching info.json for every keyboard** = unnecessary overhead
- **No progressive loading** = user waits for everything

## Our Current Problem

**Issue**: We're fetching `info.json` for every keyboard directory upfront, which means:
- 2000+ HTTP requests
- 30+ seconds initial load time
- User sees nothing until all requests complete
- Network failures block entire search

## Recommended Solution: Two-Tier Lazy Loading

### Phase 1: Directory List (Fast - <1 second)
```
1. Fetch GitHub API: /repos/qmk/qmk_firmware/contents/keyboards
2. Parse directory names only (no info.json fetching)
3. Show keyboard names immediately
4. Cache directory list (changes rarely)
```

### Phase 2: Details on Demand (Fast - <200ms per keyboard)
```
1. User types/search → filter directory names (instant)
2. User selects keyboard → fetch info.json (one request)
3. Cache individual keyboard details
```

### Benefits
- **Instant search**: Filter directory names (no network)
- **Fast results**: Show keyboard names immediately
- **Progressive**: Load details only when needed
- **Resilient**: One keyboard failure doesn't block others
- **Efficient**: Only fetch what user wants

## Implementation Strategy

### Option A: Directory-Only Search (Recommended)
```swift
// Step 1: Fetch directory list (fast)
let directories = try await fetchKeyboardDirectories() // <1s

// Step 2: Search directory names (instant)
let matches = directories.filter { $0.name.contains(query) }

// Step 3: Fetch details on selection (fast)
let keyboard = try await fetchKeyboardDetails(directoryName)
```

**Pros:**
- Instant search results
- Minimal network usage
- Fast initial load

**Cons:**
- No manufacturer/tags in search (only names)
- Need to fetch details to show metadata

### Option B: Hybrid Approach (Best UX)
```swift
// Step 1: Fetch directory list + basic metadata (fast)
// Use GitHub API to get directory names + commit info

// Step 2: Fetch popular keyboards' info.json in background
// (Top 50-100 keyboards, cached)

// Step 3: Search shows names immediately, metadata loads progressively
```

**Pros:**
- Fast initial results
- Rich metadata for popular keyboards
- Progressive enhancement

**Cons:**
- More complex implementation
- Still need background fetching

### Option C: Bundled Popular List (VIA-Style)
```swift
// Step 1: Bundle top 100-200 popular keyboards in app
// Step 2: Show bundled list instantly
// Step 3: Fetch from network for others (lazy)
```

**Pros:**
- Instant results for common keyboards
- Works offline
- Best UX

**Cons:**
- App size increase (~1-2MB)
- Needs curation/maintenance
- Stale data (but can refresh)

## Recommendation: **Option A (Directory-Only) + Progressive Enhancement**

### Implementation Plan

1. **Immediate (Fix Current Issue)**:
   - Change `refreshKeyboardList()` to fetch directory names only
   - Remove info.json fetching from initial load
   - Show keyboard names immediately

2. **Search Enhancement**:
   - Filter directory names client-side (instant)
   - Show "Loading details..." when user selects
   - Fetch info.json on selection

3. **Future Enhancement**:
   - Cache popular keyboards' info.json
   - Pre-fetch top 50 keyboards in background
   - Show metadata progressively

### Code Changes

```swift
// OLD: Fetches info.json for all keyboards
func refreshKeyboardList() async throws -> [KeyboardMetadata] {
    // Fetches 2000+ info.json files = SLOW
}

// NEW: Fetch directory names only
func refreshKeyboardList() async throws -> [KeyboardMetadata] {
    // 1. Fetch directory list (fast)
    let directories = try await fetchDirectories() // <1s
    
    // 2. Return lightweight metadata (name only)
    return directories.map { KeyboardMetadata(name: $0.name, ...) }
}

// NEW: Fetch details on demand
func fetchKeyboardDetails(_ directoryName: String) async throws -> KeyboardMetadata {
    // Fetch info.json for one keyboard (fast)
    let info = try await fetchInfoJSON(directoryName)
    return KeyboardMetadata(directoryName: directoryName, info: info, ...)
}
```

## Performance Comparison

| Approach | Initial Load | Search Speed | Network Requests |
|----------|-------------|--------------|-----------------|
| **Current** | 30+ seconds | N/A (blocks) | 2000+ |
| **Option A** | <1 second | Instant | 0 (search), 1 (select) |
| **Option B** | 2-3 seconds | Instant | 50-100 (background) |
| **Option C** | Instant | Instant | 0 (bundled), 1 (others) |

## Recommendation Summary

**Start with Option A** (directory-only search):
- ✅ Fastest to implement
- ✅ Solves immediate problem
- ✅ Good UX (instant search)
- ✅ Minimal network usage

**Enhance later with Option C** (bundled popular list):
- Bundle top 100-200 keyboards
- Instant results for common cases
- Network fallback for others

This gives us:
1. **Instant search** (filter directory names)
2. **Fast details** (fetch on selection)
3. **Progressive enhancement** (bundle popular later)
