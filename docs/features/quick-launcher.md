# Quick Launcher

The Quick Launcher allows you to instantly open apps, websites, folders, and run scripts with a single keystroke.

## Activation

By default, the Quick Launcher is activated by holding your **Hyper key** (Caps Lock when held) and pressing a shortcut key.

You can configure the activation mode:
- **Hold Hyper** (default) - Hold Caps Lock, press a key
- **Leader→L Sequence** - Press Space, then L, then the shortcut key

## Target Types

The Quick Launcher supports four types of targets:

### 1. Applications

Launch any installed macOS application by name or bundle ID.

**Examples:**
- `S` → Safari
- `F` → Finder
- `V` → VS Code

**Configuration:**
- **App Name**: The display name (e.g., "Safari")
- **Bundle ID** (optional): The app's bundle identifier (e.g., "com.apple.Safari")

**Tips:**
- Bundle ID is optional but recommended for reliability
- Find bundle IDs using: `osascript -e 'id of app "AppName"'`

### 2. Websites & Documentation

Open any URL in your default browser.

**Examples:**
- `1` → github.com
- `G` → chatgpt.com
- `I` → claude.ai

**Configuration:**
- **URL**: The website address (protocol optional)
  - `github.com` → Opens `https://github.com`
  - `localhost:3000` → Opens `http://localhost:3000`

**Use Cases:**
- Frequently visited websites
- Web-based documentation (React docs, MDN, etc.)
- Local development servers
- Internal tools/dashboards

### 3. Folders

Open any folder in Finder.

**Examples:**
- `5` → ~/Documents
- `6` → ~/Downloads
- `7` → ~/Desktop

**Configuration:**
- **Folder Path**: Absolute or home-relative path
  - Use `~` for home directory: `~/Projects/KeyPath`
  - Or absolute paths: `/Applications`
- **Display Name** (optional): Friendly name shown in UI

**Tips:**
- Use the **Browse...** button to select folders visually
- Tilde (`~`) expands to your home directory
- Path validation shows warnings for non-existent folders

**Use Cases:**
- Project directories
- Frequently accessed folders
- Network shares (e.g., `/Volumes/Share`)
- Hidden folders (e.g., `~/.config`)

### 4. Scripts

Execute shell scripts, AppleScript, Python, Ruby, Perl, and more.

**Examples:**
- `8` → `~/Scripts/backup.sh` - Daily backup script
- `9` → `~/Scripts/toggle-dark-mode.applescript` - Theme toggle
- `0` → `~/Scripts/screenshot.py` - Custom screenshot tool

**Configuration:**
- **Script Path**: Absolute or home-relative path
- **Display Name** (optional): Friendly name shown in UI

**Security Requirements:**
1. **Enable Script Execution** in Settings > Security
2. **First-run Confirmation** - Scripts require explicit approval on first execution
3. **Executable Permissions** - Scripts must be executable (`chmod +x script.sh`)

**Supported Script Types:**
- **Shell scripts**: `.sh`, `.bash`, `.zsh`, no extension
- **AppleScript**: `.applescript`, `.scpt`
- **Python**: `.py` (requires Python installed)
- **Ruby**: `.rb` (requires Ruby installed)
- **Perl**: `.pl` (requires Perl installed)
- **Lua**: `.lua` (requires Lua installed)
- **Binary executables**: Any executable file

**Tips:**
- Use the **Browse...** button to select scripts
- Scripts run in the background (no terminal window)
- Check logs in Console.app if scripts don't behave as expected
- Output is logged to System Log under "KeyPath"

**Security Best Practices:**
- Review scripts before approving execution
- Store scripts in a dedicated folder (e.g., `~/Scripts`)
- Use version control for critical automation scripts
- Never execute untrusted scripts

## Default Configuration

KeyPath includes preconfigured shortcuts to get you started:

**Home Row (asdfghjkl):**
- `A` → Calendar
- `S` → Safari
- `D` → Terminal
- `F` → Finder
- `G` → ChatGPT
- `H` → YouTube
- `J` → X (Twitter)
- `K` → Messages
- `L` → LinkedIn

**Top Row (qwertyuiop):**
- `E` → Mail
- `R` → Reddit
- `U` → Music
- `I` → Claude
- `O` → Obsidian
- `P` → Photos

**Bottom Row (zxcvbnm):**
- `Z` → Zoom
- `X` → Slack
- `C` → Discord
- `V` → VS Code
- `N` → Notes

**Number Row (1234567890):**
- `1` → GitHub
- `2` → Google
- `3` → Notion
- `4` → Stack Overflow
- `5` → Documents folder
- `6` → Downloads folder
- `7` → Desktop folder

**All shortcuts are fully customizable!**

## Configuration UI

### Adding a Shortcut

1. Enable the Quick Launcher collection in Rules
2. Click **Add Shortcut** in the drawer
3. Or click any key on the keyboard visualization
4. Select target type: App, Website, Folder, or Script
5. Enter target details
6. Click **Save**

### Editing a Shortcut

1. Click the shortcut in the drawer list
2. Or click the key on the keyboard visualization
3. Modify target details
4. Click **Save**

### Deleting a Shortcut

1. Hover over the shortcut in the drawer list
2. Click the trash icon
3. Or edit the shortcut and click **Delete**

### Import from Browser History

1. Click **Import from Browser** in the drawer
2. Select frequently visited sites
3. Available number keys are auto-assigned

**Supported Browsers:**
- Safari (via History.db)
- Chrome (via History database)
- Firefox (via places.sqlite)

## Visual Feedback

When the Quick Launcher is active:
- **Overlay shows** your configured shortcuts
- **App icons** for applications
- **Favicons** for websites
- **Folder icons** for folders
- **Script icons** for scripts

The overlay disappears automatically after launching a target.

## Advanced Tips

### Organizing Shortcuts

**By Frequency:**
- Home row → Most used
- Top/bottom rows → Moderate use
- Number row → Occasional use

**By Category:**
- Group similar apps together (all dev tools, all communication apps)
- Use number row for websites
- Reserve letters for applications

### Script Examples

**Quick Screenshot to Clipboard:**
```bash
#!/bin/bash
# ~/Scripts/screenshot.sh
screencapture -i -c
```

**Toggle Dark Mode:**
```applescript
-- ~/Scripts/toggle-dark-mode.applescript
tell application "System Events"
    tell appearance preferences
        set dark mode to not dark mode
    end tell
end tell
```

**Open Project in VS Code:**
```bash
#!/bin/bash
# ~/Scripts/open-project.sh
cd ~/Projects/my-app && code .
```

**Morning Routine (Open Multiple Apps):**
```applescript
-- ~/Scripts/morning-routine.applescript
tell application "Calendar" to activate
tell application "Mail" to activate
tell application "Slack" to activate
tell application "Safari" to activate
```

### URL Tricks

**Query Parameters:**
- `github.com/search?q=swiftui` - GitHub search for "swiftui"
- `google.com/search?q=weather` - Google search for "weather"

**Local Development:**
- `localhost:3000` - React dev server
- `localhost:8080/admin` - Backend admin panel
- `127.0.0.1:5173` - Vite dev server

**Bookmarklets:**
- `javascript:alert(document.title)` - Run JavaScript
- `javascript:window.location='https://github.com'` - Redirect

## Keyboard Shortcuts

- **Hyper + [key]** - Launch shortcut (default activation)
- **Space, L, [key]** - Launch shortcut (sequence activation)
- **Click key** - Edit shortcut
- **Hover + trash** - Delete shortcut

## Troubleshooting

### Script Won't Execute

1. **Check script execution is enabled**: Settings > Security > Script Execution
2. **Verify executable permissions**: `ls -l ~/path/to/script.sh` (should show `-rwxr-xr-x`)
3. **Add shebang line**: First line should be `#!/bin/bash` or `#!/usr/bin/env python3`
4. **Review logs**: Open Console.app, filter for "KeyPath"

### Folder Won't Open

1. **Verify path exists**: Open Terminal and run `ls -la ~/path/to/folder`
2. **Check permissions**: Ensure you have read access to the folder
3. **Use absolute paths**: If `~` doesn't work, use full path like `/Users/yourname/Documents`

### Website Opens Wrong Browser

The Quick Launcher uses your **default browser** set in System Settings.

To change:
1. System Settings > Desktop & Dock > Default web browser

### App Doesn't Launch

1. **Verify app is installed**: Open Spotlight, search for the app name
2. **Use Bundle ID**: More reliable than app name
3. **Check app name spelling**: Case-sensitive

## Related Features

- **Window Snapping** - Position windows after launching apps
- **Vim Navigation** - Navigate within launched apps
- **Custom Rules** - Create more complex automation

## Feedback

Have a great Quick Launcher workflow? Share it with us!

- File feature requests: [KeyPath Issues](https://github.com/malpern/keypath/issues)
- Join discussions: [KeyPath Discussions](https://github.com/malpern/keypath/discussions)
