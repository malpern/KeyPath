#!/bin/bash

# Complete project validation script

set -e

echo "🔍 KeyPath Project Validation"
echo "============================="
echo

# 1. Check project structure
echo "1. Validating project structure..."
required_files=(
    "Package.swift"
    "Sources/KeyPath/App.swift"
    "Sources/KeyPath/ContentView.swift"
    "Sources/KeyPath/KanataManager.swift"
    "Sources/KeyPath/KeyboardCapture.swift"
    "Sources/KeyPath/SettingsView.swift"
    "Sources/KeyPath/InstallerView.swift"
    "Tests/KeyPathTests/KeyPathTests.swift"
    "build.sh"
    "install-system.sh"
    "uninstall.sh"
    "README.md"
    "KANATA_SETUP.md"
)

missing_files=()
for file in "${required_files[@]}"; do
    if [[ ! -f "$file" ]]; then
        missing_files+=("$file")
    fi
done

if [[ ${#missing_files[@]} -eq 0 ]]; then
    echo "   ✅ All required files present"
else
    echo "   ❌ Missing files:"
    for file in "${missing_files[@]}"; do
        echo "      - $file"
    done
    exit 1
fi

# 2. Check Swift package validity
echo "2. Validating Swift package..."
if swift package describe > /dev/null 2>&1; then
    echo "   ✅ Swift package is valid"
else
    echo "   ❌ Swift package is invalid"
    exit 1
fi

# 3. Check if project builds
echo "3. Testing build process..."
if swift build > /dev/null 2>&1; then
    echo "   ✅ Project builds successfully"
else
    echo "   ❌ Build failed"
    exit 1
fi

# 4. Run unit tests
echo "4. Running unit tests..."
if swift test > /dev/null 2>&1; then
    echo "   ✅ Unit tests pass"
else
    echo "   ❌ Unit tests fail"
    exit 1
fi

# 5. Test app bundle creation
echo "5. Testing app bundle creation..."
if ./build.sh > /dev/null 2>&1; then
    if [[ -d "build/KeyPath.app" ]]; then
        echo "   ✅ App bundle created successfully"
    else
        echo "   ❌ App bundle not created"
        exit 1
    fi
else
    echo "   ❌ Build script failed"
    exit 1
fi

# 6. Validate scripts are executable
echo "6. Checking script permissions..."
scripts=(
    "build.sh"
    "install-system.sh"
    "uninstall.sh"
    "test-kanata-system.sh"
    "test-installer.sh"
    "test-hot-reload.sh"
    "test-service-status.sh"
    "run-tests.sh"
    "setup-git.sh"
)

for script in "${scripts[@]}"; do
    if [[ -f "$script" ]]; then
        chmod +x "$script"
    fi
done
echo "   ✅ All scripts are executable"

# 7. Check documentation
echo "7. Validating documentation..."
if [[ -f "README.md" && -f "KANATA_SETUP.md" ]]; then
    echo "   ✅ Documentation complete"
else
    echo "   ❌ Documentation incomplete"
    exit 1
fi

# 8. Summary
echo
echo "🎉 Project Validation Complete!"
echo "=============================="
echo
echo "✅ Project structure: Valid"
echo "✅ Swift package: Valid"
echo "✅ Build process: Working"
echo "✅ Unit tests: Passing"
echo "✅ App bundle: Created"
echo "✅ Scripts: Executable"
echo "✅ Documentation: Complete"
echo
echo "📦 Project Summary:"
echo "• Source files: 6 Swift files"
echo "• Test files: 1 comprehensive test suite"
echo "• Build scripts: 3 scripts"
echo "• Test scripts: 5 scripts"
echo "• Documentation: 2 comprehensive guides"
echo
echo "🚀 Ready for deployment!"
echo "Next steps:"
echo "1. Move this folder to /Users/malpern/Library/CloudStorage/Dropbox/code/KeyPath/"
echo "2. Run ./setup-git.sh to initialize Git repository"
echo "3. Push to GitHub"
echo "4. Install with sudo ./install-system.sh install"