---
layout: default
title: Your First Mapping
description: Create your first keyboard remapping with KeyPath
---

# Your First Mapping

This guide walks you through creating your first keyboard remapping with KeyPath. In just a few clicks, you'll remap a key to do something different.

## Step 1: Open KeyPath

Launch KeyPath from your Applications folder. If this is your first time, complete the setup wizard first.

## Step 2: Record Input Key

1. Click the **Record Input** button (or the microphone icon)
2. Press the key you want to remap
   - For example: **Caps Lock** (a common choice)
   - Or: **Right Option** key
   - Or: Any key combination like **Cmd+Space**

You'll see the key appear in the input field. KeyPath shows exactly what it detected.

## Step 3: Record Output Key

1. Click the **Record Output** button
2. Press what you want the key to do
   - For example: **Escape** (turning Caps Lock into Esc is popular)
   - Or: **Delete** 
   - Or: A key combination like **Cmd+C**

Again, KeyPath shows what it detected in the output field.

## Step 4: Save

Click the **Save** button. Your remapping is now active!

Try pressing your input key — it should now trigger the output you specified.

## Example: Caps Lock to Escape

A very common remapping is turning Caps Lock into Escape (popular with vim users):

1. **Input**: Press Caps Lock
2. **Output**: Press Escape
3. **Save**

Now Caps Lock acts as Escape throughout your system.

## Example: Right Option to Delete

Another useful remapping:

1. **Input**: Press Right Option
2. **Output**: Press Delete
3. **Save**

This gives you a Delete key in a convenient location.

## Advanced: Key Sequences

You can also remap sequences of keys:

1. **Input**: Press A, then B, then C
2. **Output**: Type "Hello World"
3. **Save**

Now typing "ABC" will output "Hello World".

## Advanced: Key Combinations

Remap key combinations:

1. **Input**: Press Cmd+Space
2. **Output**: Press Cmd+C
3. **Save**

Now Cmd+Space triggers Copy instead of Spotlight.

## What's Next?

- **[Tap-Hold & Tap-Dance](/guides/tap-hold)** - Make keys do different things when tapped vs held
- **[Action URI System](/guides/action-uri)** - Trigger system actions via URL scheme
- **[Window Management](/guides/window-management)** - Different keymaps for different apps

## Troubleshooting

### The remapping isn't working

1. Check that KeyPath shows green checkmarks (service is running)
2. Verify permissions are granted in System Settings
3. Try clicking "Fix Issues" in KeyPath
4. Check logs: `tail -f /var/log/com.keypath.kanata.stdout.log`

### I want to undo a remapping

1. Select the remapping in KeyPath's list
2. Click Delete or Remove
3. Save

### I want to edit a remapping

1. Select the remapping
2. Modify the input or output
3. Save

Changes apply immediately — no restart needed!
