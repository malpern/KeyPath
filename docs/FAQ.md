# KeyPath FAQ

- **What macOS version is required?** macOS 15.0 or later.
- **Do I need internet?** No. Notarized builds run offline. Optional AI config requires an API key.
- **Why a privileged helper?** To install/manage LaunchDaemons and system paths without repeated prompts.
- **Why does the GUI not create CGEvent taps?** The root daemon owns taps to avoid conflicts and lockups.
- **Where is the kanata binary run from?** `/Library/KeyPath/bin/kanata` for stable TCC permissions.
- **How do I build?** Run `./build.sh` — it builds, signs, notarizes, deploys to `~/Applications`, and restarts the app.

