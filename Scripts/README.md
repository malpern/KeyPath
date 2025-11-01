# Scripts

## Supported commands (recommended)
- `./Scripts/build-and-sign.sh` — Build & sign a production-like app
- `./Scripts/run-tests.sh` — Run the full test suite

## Production-like build & deploy
```bash
./Scripts/build-and-sign.sh
mkdir -p ~/Applications
cp -R dist/KeyPath.app ~/Applications/
osascript -e 'tell application "KeyPath" to quit' || true
open ~/Applications/KeyPath.app
```

## Build & Release
- `build-and-sign.sh` - Production build with signing
- `build.sh` - Debug build

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
./Scripts/build-and-sign.sh
./Scripts/run-tests.sh
```
