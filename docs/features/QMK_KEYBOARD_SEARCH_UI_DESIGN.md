# QMK Keyboard Search UI Design

## Design Philosophy: macOS-Native, Fast, Responsive

This document outlines the UI design for Phase 2: Keyboard Search, focusing on maximum macOS-native feel, performance, and user experience.

## Reference Patterns

### macOS Native Examples
- **System Preferences Search**: Instant filtering, keyboard navigation, clear hierarchy
- **Spotlight**: Fast search, instant results, keyboard shortcuts
- **Xcode File Navigator**: Search with instant filtering, arrow key navigation
- **Finder Search**: Real-time results, clear visual feedback

## UI Architecture

### Component Structure

```
QMKKeyboardSearchView (Popover/Sheet)
├── SearchField (Native macOS search)
├── KeyboardList (Scrollable, keyboard-navigable)
│   └── KeyboardRow (Rich metadata display)
│       ├── Title (Keyboard name)
│       ├── Subtitle (Manufacturer)
│       └── Tags (Badges: split, RGB, ortho, etc.)
└── StatusBar (Result count, loading state)
```

## Visual Design

### Search Field
- **Style**: Native macOS rounded search field with `.roundedBorder` text field style
- **Icon**: SF Symbol `magnifyingglass` (left side, `.secondary` color)
- **Placeholder**: "Search keyboards..." (e.g., "Corne", "split", "RGB", "foostan")
- **Background**: `Color(NSColor.controlBackgroundColor)` for native feel
- **Behavior**: 
  - Instant filtering (debounced 200ms for network)
  - Clear button (X) appears when text entered (native TextField behavior)
  - Keyboard shortcuts: `⌘F` to focus, `Esc` to clear/close popover
  - Auto-focus on popover open

### List Style
- **Base**: `ScrollView` + `LazyVStack` for maximum performance and control
- **Why not List**: Better performance with 2000+ items, more control over styling
- **Row Height**: ~56pt (comfortable for title + subtitle + badges)
- **Spacing**: 1pt between rows (tight, native feel)
- **Padding**: 12pt horizontal, 8pt vertical per row
- **Background**: Transparent (popover background shows through)
- **Scroll Behavior**: Smooth, momentum scrolling

### Keyboard Row Design

```
┌─────────────────────────────────────────────┐
│ Corne (crkbd)                    [split] [RGB]│
│ foostan                                        │
└─────────────────────────────────────────────┘
```

**Layout:**
- **Title**: `.body` font, `.primary` color, bold
- **Subtitle**: `.caption` font, `.secondary` color
- **Tags**: Small rounded badges, right-aligned
- **Hover State**: Subtle background highlight
- **Selected State**: Blue accent background (keyboard nav)

### Tag Badges
- **Style**: Rounded rectangle, subtle background
- **Colors**: 
  - `split`: Blue tint
  - `RGB`: Purple tint  
  - `ortho`: Green tint
  - `OLED`: Orange tint
- **Size**: `.caption2` font, 4pt padding
- **Max per row**: 3 tags (truncate with "..." if more)

## Interaction Patterns

### Keyboard Navigation
- **↑/↓**: Navigate list
- **Enter**: Select keyboard (import)
- **Esc**: Cancel search / Close popover
- **⌘F**: Focus search field
- **⌘K**: Clear search (if focused)

### Mouse/Trackpad
- **Click**: Select keyboard
- **Double-click**: Select and import
- **Hover**: Highlight row
- **Scroll**: Smooth scrolling with momentum

### Search Behavior
- **Instant filtering**: As user types (client-side)
- **Debounced network**: 200ms delay for GitHub API calls
- **Minimum query**: 2 characters before searching
- **Result limit**: Show top 50 matches (lazy load more)

## Performance Optimizations

### Caching Strategy
```swift
actor QMKKeyboardDatabase {
    private var cachedKeyboardList: [KeyboardMetadata]?
    private var cacheTimestamp: Date?
    private let cacheTTL: TimeInterval = 3600 // 1 hour
    
    // Refresh on:
    // - First search
    // - Manual refresh button
    // - Cache expired
    // - App launch (background refresh)
}
```

### Search Algorithm
1. **Client-side filtering** (instant):
   - Filter cached list by name, manufacturer, tags
   - Case-insensitive, fuzzy matching
   - Show results immediately

2. **Network fallback** (if cache miss):
   - Debounce 200ms
   - Fetch from GitHub API
   - Update cache
   - Show results

### Lazy Loading
- **Initial load**: Top 20 keyboards
- **Scroll to bottom**: Load next 20
- **Search results**: Limit to 50 matches

## State Management

### View State
```swift
@State private var searchText = ""
@State private var selectedKeyboard: KeyboardMetadata?
@State private var searchResults: [KeyboardMetadata] = []
@State private var isLoading = false
@State private var errorMessage: String?
@FocusState private var isSearchFocused: Bool
```

### ViewModel (Optional)
```swift
@MainActor
class QMKKeyboardSearchViewModel: ObservableObject {
    @Published var keyboards: [KeyboardMetadata] = []
    @Published var isLoading = false
    @Published var error: Error?
    
    func search(_ query: String) async
    func refreshCache() async
}
```

## Accessibility

### Peekaboo Automation Support ✅

**All interactive elements have accessibility identifiers** following the codebase pattern: `qmk-search-[element-type]-[description]`

**Quick Reference:**
- **Search Field**: `qmk-search-field`
- **Clear Button**: `qmk-search-clear-button`
- **Keyboard Rows**: `qmk-search-keyboard-row-{keyboard-id}`
- **Tag Badges**: `qmk-search-tag-{tag}-{keyboard-id}`
- **Status Bar**: `qmk-search-status-bar`
- **Loading**: `qmk-search-loading-indicator`
- **Error**: `qmk-search-error-message`
- **Empty State**: `qmk-search-empty-state`
- **Trigger Button**: `qmk-search-button` (in KeyboardSelectionGridView)

**Peekaboo Usage:**
```bash
# Open search popover
peekaboo click --element-id qmk-search-button

# Type search query
peekaboo click --element-id qmk-search-field
peekaboo type "corne"

# Select keyboard
peekaboo click --element-id qmk-search-keyboard-row-corne

# Check results count
peekaboo see "How many keyboards are shown?"
```

### VoiceOver
- **Search field**: "Search keyboards, text field"
- **Keyboard row**: "Corne keyboard by foostan, split RGB, button"
- **Tags**: "Split keyboard, tag" (announced separately)
- **Status bar**: "47 keyboards found"
- **Loading**: "Loading keyboards"
- **Error**: "Error loading keyboards: [message]"
- **Empty state**: "No keyboards found matching '[query]'"

### Keyboard Navigation
- **Tab**: Navigate between search field and list
- **Space**: Select keyboard
- **Arrow keys**: Navigate list (when list focused)
- **Enter**: Import selected keyboard
- **Esc**: Close popover

### Peekaboo Automation Support
All interactive elements have accessibility identifiers for automation:
- Search field: `qmk-search-field`
- Keyboard rows: `qmk-search-keyboard-row-{id}`
- Tags: `qmk-search-tag-{tag}-{keyboard-id}`
- Status bar: `qmk-search-status-bar`
- Loading/Error/Empty states: `qmk-search-{state}-{type}`

**Peekaboo Usage Examples:**
```bash
# Focus search field
peekaboo click --element-id qmk-search-field

# Type search query
peekaboo type "corne"

# Click first result
peekaboo click --element-id qmk-search-keyboard-row-corne

# Check status
peekaboo see "How many keyboards are shown?"
```

### Accessibility Identifiers

**Naming Convention:** `qmk-search-[element-type]-[description]`

**Complete List:**

```swift
// Search Field
.accessibilityIdentifier("qmk-search-field")
.accessibilityLabel("Search keyboards")

// Clear Button (in search field)
.accessibilityIdentifier("qmk-search-clear-button")
.accessibilityLabel("Clear search")

// Keyboard Row (dynamic)
.accessibilityIdentifier("qmk-search-keyboard-row-\(keyboard.id)")
.accessibilityLabel("\(keyboard.name) keyboard\(manufacturerText)\(tagsText)")

// Tag Badge (dynamic)
.accessibilityIdentifier("qmk-search-tag-\(tag)-\(keyboard.id)")
.accessibilityLabel("\(tag) keyboard")

// Status Bar
.accessibilityIdentifier("qmk-search-status-bar")
.accessibilityLabel("\(keyboards.count) keyboards found")

// Loading Indicator
.accessibilityIdentifier("qmk-search-loading-indicator")
.accessibilityLabel("Loading keyboards")

// Error Message
.accessibilityIdentifier("qmk-search-error-message")
.accessibilityLabel("Error loading keyboards")

// Empty State
.accessibilityIdentifier("qmk-search-empty-state")
.accessibilityLabel("No keyboards found")

// Refresh Button (if added)
.accessibilityIdentifier("qmk-search-refresh-button")
.accessibilityLabel("Refresh keyboard list")
```

**Dynamic Label Examples:**
- Keyboard Row: "Corne keyboard by foostan, split RGB"
- Tag Badge: "Split keyboard" or "RGB keyboard"
- Status Bar: "47 keyboards found"

## Implementation Details

### SwiftUI Components

```swift
struct QMKKeyboardSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedLayoutId: String
    var onImportComplete: (() -> Void)?
    
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    @State private var keyboards: [KeyboardMetadata] = []
    @State private var isLoading = false
    @State private var selectedIndex: Int?
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 13))
                
                TextField("Search keyboards...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .focused($isSearchFocused)
                    .onSubmit {
                        if let index = selectedIndex, index < keyboards.count {
                            importKeyboard(keyboards[index])
                        }
                    }
                    .accessibilityIdentifier("qmk-search-field")
                    .accessibilityLabel("Search keyboards")
                
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("qmk-search-clear-button")
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Results list
            if isLoading {
                VStack {
                    ProgressView()
                        .scaleEffect(0.8)
                        .accessibilityIdentifier("qmk-search-loading-indicator")
                    Text("Loading keyboards...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Loading keyboards")
            } else if let error = errorMessage {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("qmk-search-error-message")
                .accessibilityLabel("Error loading keyboards: \(error)")
            } else if keyboards.isEmpty {
                emptyState
            } else {
                keyboardList
            }
            
            // Status bar
            if !keyboards.isEmpty {
                Divider()
                HStack {
                    Text("\(keyboards.count) keyboard\(keyboards.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("Press ⌘F to search, ↑↓ to navigate, Enter to import")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor))
                .accessibilityIdentifier("qmk-search-status-bar")
                .accessibilityLabel("\(keyboards.count) keyboard\(keyboards.count == 1 ? "" : "s") found")
            }
        }
        .frame(width: 500, height: 450)
        .onAppear {
            // Auto-focus search field
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isSearchFocused = true
            }
        }
        .onChange(of: searchText) { _, newValue in
            Task {
                await performSearch(query: newValue)
            }
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "keyboard")
                .font(.system(size: 32))
                .foregroundColor(.secondary.opacity(0.5))
            Text(searchText.isEmpty ? "Start typing to search keyboards" : "No keyboards found matching '\(searchText)'")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("qmk-search-empty-state")
        .accessibilityLabel(searchText.isEmpty ? "Start typing to search keyboards" : "No keyboards found matching '\(searchText)'")
    }
}
```

### Keyboard Row Component

```swift
struct KeyboardRow: View {
    let keyboard: KeyboardMetadata
    let isSelected: Bool
    let onSelect: () -> Void
    
    private var accessibilityLabel: String {
        var parts: [String] = [keyboard.name, "keyboard"]
        if let manufacturer = keyboard.manufacturer {
            parts.append("by \(manufacturer)")
        }
        if !keyboard.tags.isEmpty {
            parts.append(keyboard.tags.prefix(3).joined(separator: " "))
        }
        return parts.joined(separator: ", ")
    }
    
    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(keyboard.name)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    if let manufacturer = keyboard.manufacturer {
                        Text(manufacturer)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Tags
                HStack(spacing: 4) {
                    ForEach(keyboard.tags.prefix(3), id: \.self) { tag in
                        TagBadge(tag: tag, keyboardId: keyboard.id)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("qmk-search-keyboard-row-\(keyboard.id)")
        .accessibilityLabel(accessibilityLabel)
    }
}
```

### Tag Badge Component

```swift
struct TagBadge: View {
    let tag: String
    let keyboardId: String
    
    var body: some View {
        Text(tag)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tagColor.opacity(0.15))
            .foregroundColor(tagColor)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .accessibilityIdentifier("qmk-search-tag-\(tag)-\(keyboardId)")
            .accessibilityLabel("\(tag) keyboard")
    }
    
    private var tagColor: Color {
        switch tag.lowercased() {
        case "split": return .blue
        case "rgb", "rgb_matrix": return .purple
        case "ortho": return .green
        case "oled": return .orange
        default: return .secondary
        }
    }
}
```

## Integration Points

### From KeyboardSelectionGridView
- Add "Search QMK" button next to "Import" in Custom section header
- Opens search popover (lightweight, quick access)
- On selection, imports keyboard and adds to custom layouts
- Popover dismisses automatically after import

**Button Accessibility:**
```swift
Button {
    showSearchPopover = true
} label: {
    HStack(spacing: 4) {
        Image(systemName: "magnifyingglass")
        Text("Search QMK")
    }
}
.accessibilityIdentifier("qmk-search-button")
.accessibilityLabel("Search QMK keyboards")
```

### Popover vs Sheet Decision
**Decision: Use Popover**
- **Why**: Quick access, doesn't take over screen, feels native (like Spotlight)
- **Size**: 500x400pt (comfortable for search + results)
- **Position**: Attached to "Search QMK" button
- **Behavior**: Dismisses on selection or outside click

### From QMKImportSheet (Future)
- Keep URL/file picker as advanced option
- Add "Search QMK Keyboards" button as primary method
- Opens same search popover

## Animation & Transitions

### Search Results
- **Appear**: Fade in with slight scale (0.95 → 1.0)
- **Update**: Smooth crossfade between old/new results
- **Loading**: Subtle pulse on progress indicator

### Row Selection
- **Hover**: Smooth background color transition (0.2s)
- **Select**: Instant highlight with slight scale (1.0 → 1.02)

## Error States

### Network Error
- Show inline error message below search field
- "Unable to load keyboards. Check your internet connection."
- Retry button

### Empty Results
- "No keyboards found matching '\(searchText)'"
- Suggest: "Try a different search term" or "Browse all keyboards"

### Loading State
- Progress indicator centered
- "Loading keyboards..." subtitle

## Future Enhancements (Post-MVP)

1. **Favorites**: Star frequently used keyboards
2. **Recent**: Show recently imported keyboards
3. **Categories**: Filter by split, ortho, RGB, etc.
4. **Preview**: Show keyboard layout preview on hover
5. **Keyboard Shortcuts**: Customizable shortcuts
6. **Search History**: Remember recent searches

## Visual Mockup

### Popover Layout
```
┌─────────────────────────────────────────────┐
│  🔍 [Search keyboards...              ]  ✕  │ ← Search field (12pt padding)
├─────────────────────────────────────────────┤
│                                              │
│  Corne (crkbd)              [split] [RGB]   │ ← Row 1 (selected, blue highlight)
│  foostan                                     │
│  ─────────────────────────────────────────── │
│  Zoom65                                      │ ← Row 2
│  Meletrix                                    │
│  ─────────────────────────────────────────── │
│  Planck                          [ortho]     │ ← Row 3
│  OLKB                                        │
│  ─────────────────────────────────────────── │
│  ... (scrollable)                            │
│                                              │
├─────────────────────────────────────────────┤
│  47 keyboards  ⌘F to search, ↑↓ navigate    │ ← Status bar
└─────────────────────────────────────────────┘
```

### Row States

**Normal:**
- Background: Transparent
- Title: `.primary` color
- Subtitle: `.secondary` color

**Hover:**
- Background: `Color.accentColor.opacity(0.08)`
- Smooth transition (0.15s)

**Selected (keyboard nav):**
- Background: `Color.accentColor.opacity(0.15)`
- Border: `Color.accentColor.opacity(0.3)` (left edge, 2pt wide)

**Pressed:**
- Background: `Color.accentColor.opacity(0.2)`
- Slight scale: 0.98

## Styling Specifications

### Colors (macOS Native)
```swift
// Use system colors for native feel
.primary          // Title text
.secondary        // Subtitle, icons
.accentColor      // Selection highlight
Color(NSColor.controlBackgroundColor)  // Search field background
Color(NSColor.separatorColor)         // Dividers
```

### Typography
```swift
// Title
.font(.body)
.fontWeight(.medium)

// Subtitle  
.font(.caption)
.foregroundColor(.secondary)

// Tags
.font(.caption2)
.padding(.horizontal, 6)
.padding(.vertical, 2)
```

### Spacing & Layout
```swift
// Popover
.frame(width: 500, height: 450)

// Search field padding
.padding(12)

// Row padding
.padding(.horizontal, 12)
.padding(.vertical, 8)

// Row spacing
LazyVStack(spacing: 1)
```

## Testing Checklist

### Functionality
- [ ] Search field focuses correctly on popover open
- [ ] Keyboard navigation works (↑↓, Enter, Esc)
- [ ] Search filters instantly (client-side)
- [ ] Network requests debounced properly (200ms)
- [ ] Results update smoothly (no flicker)
- [ ] Tags display correctly (max 3, proper colors)
- [ ] Performance with 2000+ keyboards (<100ms filter)
- [ ] Error states display correctly
- [ ] Empty states display correctly
- [ ] Popover dismisses on outside click
- [ ] Popover dismisses after import
- [ ] Status bar shows correct count
- [ ] Hover states work smoothly
- [ ] Selected state visible during keyboard nav

### Accessibility & Automation
- [ ] All interactive elements have accessibility identifiers
- [ ] VoiceOver announces labels correctly
- [ ] Peekaboo can find search field (`qmk-search-field`)
- [ ] Peekaboo can find keyboard rows (`qmk-search-keyboard-row-{id}`)
- [ ] Peekaboo can find tags (`qmk-search-tag-{tag}-{id}`)
- [ ] Peekaboo can find status bar (`qmk-search-status-bar`)
- [ ] Peekaboo can interact with clear button (`qmk-search-clear-button`)
- [ ] Accessibility labels are descriptive and helpful
- [ ] Dynamic labels include keyboard name, manufacturer, and tags

### Peekaboo Test Script
```bash
# Test search field interaction
peekaboo click --element-id qmk-search-field
peekaboo type "corne"
peekaboo wait --time 0.5

# Test keyboard selection
peekaboo click --element-id qmk-search-keyboard-row-corne

# Test status bar reading
peekaboo see "How many keyboards are shown?"

# Test clear button
peekaboo click --element-id qmk-search-clear-button
```
