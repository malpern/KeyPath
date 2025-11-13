# Scripts

## Supported commands (recommended)
- `./build.sh` — Canonical build & sign entry
- `./Scripts/run-tests.sh` — Run the full test suite

## Production-like build & deploy
```bash
./build.sh
cp -R dist/KeyPath.app /Applications/
osascript -e 'tell application "KeyPath" to quit' || true
open /Applications/KeyPath.app
```

## Build & Release
- `build.sh` - Canonical build (signing included)

## Testing
- `run-tests.sh` - All tests
- `test-*.sh` - Individual test suites

## Development Setup
Run `./setup-passwordless-testing.sh` for testing setup. Grant Accessibility and Input Monitoring permissions to Terminal/Xcode in System Settings.
- **clean-reinstall-kanata.sh** - Clean reinstall of Kanata system
- **reinstall-kanata.sh** - Reinstall Kanata integration
- **reset-kanata-permissions.sh** - Reset Kanata permissions
- **uninstall.sh** - Complete uninstall

## Maintenance

- **cleanup-old-services.sh** - Clean up old service files
- **setup-git.sh** - Set up git configuration
- **validate-project.sh** - Validate project structure

## Usage

All scripts should be run from the project root:

```bash
./build.sh
./Scripts/run-tests.sh
```
