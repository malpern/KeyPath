# KeyPath macOS Beta Install (1.0.0-beta1)

## Download
- Grab the signed ZIP from your release page (KeyPath.zip).
- Verify checksum (optional but recommended):
  - `shasum -a 256 KeyPath.zip`
  - Expected: `a73d8bae1bac476bcaa75c5852fc24c7fee4f34b262029a1d62388adf0462daa`

## Install
1) Unzip and drag `KeyPath.app` to `/Applications`.
2) Launch once. If macOS warns it’s from the internet, click **Open** (codesigned & notarized in release builds).
3) In the app, grant permissions when prompted:
   - **Input Monitoring** and **Accessibility** in System Settings.
   - Approve the helper if asked (Login Items).
4) Start the keyboard service from the Setup wizard or menu.
5) (Optional) Add KeyPath to **Login Items** so it starts on login.

## Updating/Uninstalling
- Updating: download the new ZIP and replace `/Applications/KeyPath.app`.
- Uninstall: use **KeyPath → Uninstall KeyPath…** (removes helper & services; config stays unless you delete it).

## Known Beta Notes
- Runs on Apple Silicon macOS 15.0+.
- Sparkle auto-updates are not enabled yet; manual ZIP updates only for this beta.
- If the service doesn’t start after install, choose “Restart Keyboard Service” in the app.

## Reporting Issues
- File on GitHub Issues with logs: `~/Library/Logs/KeyPath/KeyPath.log`.
