# Scripts

Essential scripts for building, testing, and maintaining KeyPath.

## Build Scripts

- **build-and-sign.sh** - Build, sign, and notarize the app for distribution
- **build.sh** - Simple debug build
- **sign-kanata.sh** - Sign the Kanata binary

## Testing Scripts

- **run-tests.sh** - Run all tests
- **test-hot-reload.sh** - Test config hot reloading
- **test-installer.sh** - Test installation wizard
- **test-service-status.sh** - Test service status checking

## System Management

- **diagnose-kanata.sh** - Comprehensive Kanata diagnostics
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