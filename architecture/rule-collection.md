---
layout: default
title: Rule Collection Pattern
description: How KeyPath organizes keyboard remapping rules
---

# Rule Collection Pattern

KeyPath uses a "Rule Collection" pattern to organize keyboard remapping rules into logical groups.

## What is a Rule Collection?

A **Rule Collection** is a group of related keyboard remappings that can be enabled or disabled together. Examples:

- **Vim Navigation** - hjkl arrow keys
- **Caps Lock Modifiers** - Caps Lock as Control/Escape
- **macOS Function Keys** - F-keys for brightness, volume, etc.

## Collections in KeyPath

### Built-in Collections

KeyPath includes several built-in collections:

- **macOS Function Keys** - Always enabled, provides F-key functionality
- **Custom Mappings** - Your personal remappings
- **App-Specific Rules** - Per-application keymaps

### Custom Collections

You can create custom collections for:

- Work-specific shortcuts
- Gaming keymaps
- Language-specific layouts
- Temporary experimental mappings

## How It Works

### Data Model

Collections are stored as JSON:

```json
{
  "id": "vim-navigation",
  "name": "Vim Navigation",
  "enabled": true,
  "rules": [
    {
      "input": "h",
      "output": "left"
    },
    {
      "input": "j",
      "output": "down"
    }
  ]
}
```

### Config Generation

When you save, KeyPath:

1. Reads enabled collections from JSON
2. Generates Kanata config sections
3. Writes to `keypath.kbd`
4. Hot-reloads via TCP

### Generated Config Structure

```lisp
;; === Collection: Vim Navigation (enabled) ===
(deflayer vim-nav
  h left
  j down
  k up
  l right
)

;; === Collection: Custom Mappings (enabled) ===
(deflayer base
  caps esc
)
```

## Benefits

### Organization

- Group related rules together
- Easy to understand what each collection does
- Clear separation of concerns

### Flexibility

- Enable/disable collections without deleting
- Test new collections safely
- Share collections with others

### Maintainability

- Update collections independently
- Version control friendly (JSON format)
- Easy to backup and restore

## Creating Custom Collections

### Via UI

1. Open KeyPath
2. Go to **Collections** tab
3. Click **New Collection**
4. Add rules to the collection
5. Enable/disable as needed

### Via Config File

For power users, you can edit collections directly in the JSON store:

```bash
# Location
~/.config/keypath/collections.json
```

## Best Practices

1. **Keep collections focused** - One purpose per collection
2. **Name clearly** - Use descriptive names
3. **Document purpose** - Add notes about what the collection does
4. **Test before enabling** - Verify rules work as expected

## Advanced: Collection Dependencies

Some collections depend on others. For example, a "Vim Mode" collection might depend on "Vim Navigation" being enabled.

KeyPath handles dependencies automatically when enabling collections.

## Further Reading

- [Architecture Overview](/architecture/overview)
- [Configuration Management ADR](/adr/adr-025-config-management)
