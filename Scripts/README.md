# Scripts

## Build & Release
- `build-and-sign.sh` - Production build with signing
- `build.sh` - Debug build

## Testing
- `run-tests.sh` - All unit and integration tests (requires sudo)
- `test-cli.sh` - CLI functional test suite (no sudo required)
- `test-*.sh` - Individual test suites

### CLI Testing
The `test-cli.sh` script provides comprehensive functional testing of the CLI without requiring the GUI:

```bash
./Scripts/test-cli.sh
```

**Features:**
- 27 tests covering all CLI commands
- Tests real config file operations
- Automatic backup and restore of your config
- No sudo required
- Perfect for CI/CD or quick validation after changes

**Tests Include:**
- Help command
- Single and multiple mappings
- Mapping replacement
- Chord mappings
- Deduplication
- Validation errors (empty keys, multiple arrows, missing arrow)
- Reset functionality
- Config file format
- Key normalization
- Config persistence

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
```# Updated pre-commit hook to build, sign, deploy
