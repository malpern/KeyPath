---
layout: default
title: Your First Mapping
description: Step-by-step guide to creating your first keyboard remapping
---

# Your First Mapping

This guide walks you through creating your first keyboard remapping with KeyPath.

## Step 1: Open KeyPath

After installation, open KeyPath from your Applications folder. The app will show the main interface with options to create new mappings.

## Step 2: Create a New Mapping

Click the **"Create Mapping"** or **"+"** button to start a new remapping.

## Step 3: Record Input Key

1. Click the **"Record Input"** button
2. Press the key you want to remap (e.g., `Caps Lock`)
3. The key will appear in the input field

You can record:
- **Single keys**: `a`, `caps`, `esc`
- **Key combos**: `cmd+c`, `shift+tab`
- **Sequences**: Press `a`, then `b`, then `c`

## Step 4: Record Output Key

1. Click the **"Record Output"** button
2. Press what you want the key to do (e.g., `Escape`)
3. The output will appear in the output field

You can output:
- **Single keys**: `esc`, `ret` (Return)
- **Key combos**: `cmd+c` (Copy)
- **Text**: Type "hello world"

## Step 5: Save

Click **"Save"** to activate your mapping. KeyPath will:

1. Generate the Kanata configuration
2. Write it to the config file
3. Hot-reload via TCP
4. Your mapping is now active!

## Example: Caps Lock to Escape

A common first mapping is remapping Caps Lock to Escape (useful for Vim users):

1. **Input**: Record `Caps Lock`
2. **Output**: Record `Escape`
3. **Save**

Now pressing Caps Lock sends Escape instead.

## Example: Command+Q to Command+W

Prevent accidental app quitting:

1. **Input**: Record `Command+Q`
2. **Output**: Record `Command+W` (close window instead)
3. **Save**

## Testing Your Mapping

After saving:

1. Try pressing your input key
2. Verify it produces the expected output
3. Check the status indicator (green checkmark = working)

## Troubleshooting

### Mapping not working

1. **Check status** - Look for green checkmarks
2. **Verify permissions** - Input Monitoring and Accessibility must be granted
3. **Check logs** - `tail -f /var/log/com.keypath.kanata.stdout.log`
4. **Use Fix button** - Click "Fix Issues" in the app

### Key not recording

1. Ensure KeyPath has Input Monitoring permission
2. Try a different key
3. Check for conflicts with other remappers

## Next Steps

- **[Tap-Hold & Tap-Dance]({{ '/guides/tap-hold' | relative_url }})** - Advanced key behaviors
- **[Action URI System]({{ '/guides/action-uri' | relative_url }})** - Trigger actions from Kanata
- **[Window Management]({{ '/guides/window-management' | relative_url }})** - App-specific keymaps
