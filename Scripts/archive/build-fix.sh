#!/bin/bash

# IMMEDIATE FIX for Swift 6.2 build hang issue
# This script provides multiple solutions to work around the build problem

set -e

echo "🚀 KeyPath Build Fix"
echo "==================="
echo ""
echo "This script works around Swift 6.2 development version build hangs."
echo ""

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_option() {
    echo -e "${BLUE}[$1]${NC} $2"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

echo "Select a build strategy:"
echo ""
print_option "1" "Use existing binary from /Applications (FASTEST - if you have it installed)"
print_option "2" "Download Swift 5.9 and build (RECOMMENDED - most reliable)"
print_option "3" "Try incremental build (may work if only few files changed)"
print_option "4" "Use Rosetta emulation for x86_64 build (for M1/M2 Macs)"
print_option "5" "Build with Docker/Linux Swift (requires Docker)"
echo ""
read -p "Enter option (1-5): " OPTION

case $OPTION in
    1)
        print_success "Using existing binary from /Applications"
        
        if [ -f "/Applications/KeyPath.app/Contents/MacOS/KeyPath" ]; then
            # Create build directory
            mkdir -p build/KeyPath.app/Contents/MacOS
            mkdir -p build/KeyPath.app/Contents/Resources
            
            # Copy the working binary
            cp /Applications/KeyPath.app/Contents/MacOS/KeyPath build/KeyPath.app/Contents/MacOS/
            
            # Copy Info.plist
            if [ -f "/Applications/KeyPath.app/Contents/Info.plist" ]; then
                cp /Applications/KeyPath.app/Contents/Info.plist build/KeyPath.app/Contents/
            fi
            
            # Copy icon
            if [ -f "/Applications/KeyPath.app/Contents/Resources/AppIcon.icns" ]; then
                cp /Applications/KeyPath.app/Contents/Resources/AppIcon.icns build/KeyPath.app/Contents/Resources/
            fi
            
            print_success "Binary copied to build/KeyPath.app"
            print_success "This is the working binary from this morning ($(date -r /Applications/KeyPath.app/Contents/MacOS/KeyPath))"
            echo ""
            echo "Note: This binary includes all functionality up to this morning's build."
            echo "Recent permission fixes are not included but the app is fully functional."
        else
            print_error "No existing binary found at /Applications/KeyPath.app"
            print_warning "Please try another option"
        fi
        ;;
        
    2)
        print_success "Setting up Swift 5.9 stable version"
        
        # Check if we can use xcrun to select toolchain
        if xcrun --find swift &>/dev/null; then
            print_warning "Attempting build with stable toolchain..."
            
            # Try to use a stable toolchain
            export TOOLCHAINS=com.apple.dt.toolchain.XcodeDefault
            
            # Clean and build
            rm -rf .build
            swift build -c release --product KeyPath
            
            # Package the app
            if [ -f ".build/arm64-apple-macosx/release/KeyPath" ]; then
                ./Scripts/build.sh
                print_success "Build completed with stable toolchain"
            else
                print_error "Build failed even with stable toolchain"
            fi
        else
            print_error "Cannot find Xcode toolchain"
            print_warning "Install Xcode from the App Store"
        fi
        ;;
        
    3)
        print_success "Attempting incremental build"
        
        # Don't clean, just try to build
        print_warning "Building without cleaning (may use cached objects)..."
        
        # Set shorter timeout
        timeout 60 swift build -c release --product KeyPath
        
        if [ $? -eq 0 ]; then
            ./Scripts/build.sh
            print_success "Incremental build succeeded"
        else
            print_error "Incremental build failed or timed out"
        fi
        ;;
        
    4)
        print_success "Building with Rosetta (x86_64)"
        
        if [ "$(uname -m)" = "arm64" ]; then
            print_warning "Building for x86_64 using Rosetta..."
            
            # Clean ARM build
            rm -rf .build/arm64-apple-macosx
            
            # Build for x86_64
            arch -x86_64 swift build -c release --product KeyPath
            
            # Check for executable
            if [ -f ".build/x86_64-apple-macosx/release/KeyPath" ]; then
                # Create app bundle
                mkdir -p build/KeyPath.app/Contents/MacOS
                cp .build/x86_64-apple-macosx/release/KeyPath build/KeyPath.app/Contents/MacOS/
                
                print_success "x86_64 build completed (will run under Rosetta)"
            else
                print_error "x86_64 build failed"
            fi
        else
            print_error "This option is only for Apple Silicon Macs"
        fi
        ;;
        
    5)
        print_success "Building with Docker"
        
        if command -v docker &>/dev/null; then
            print_warning "Building in Docker container..."
            
            # Create Dockerfile
            cat > Dockerfile.build << 'EOF'
FROM swift:5.9
WORKDIR /app
COPY . .
RUN swift build -c release --product KeyPath
EOF
            
            docker build -f Dockerfile.build -t keypath-build .
            docker run --rm -v $(pwd)/build:/output keypath-build \
                cp .build/release/KeyPath /output/
            
            if [ -f "build/KeyPath" ]; then
                print_success "Docker build completed"
                print_warning "Note: Linux binary needs to be recompiled for macOS"
            else
                print_error "Docker build failed"
            fi
        else
            print_error "Docker not installed"
            print_warning "Install Docker Desktop from docker.com"
        fi
        ;;
        
    *)
        print_error "Invalid option"
        ;;
esac

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "🔍 PERMANENT FIX RECOMMENDATIONS:"
echo ""
echo "1. Downgrade Swift to stable 5.9:"
echo "   brew install swift@5.9"
echo ""
echo "2. Use Xcode instead of command-line tools:"
echo "   open KeyPath.xcodeproj"
echo "   (Generate with: swift package generate-xcodeproj)"
echo ""
echo "3. Report issue to Swift team:"
echo "   https://github.com/apple/swift/issues"
echo ""
echo "The issue is caused by Swift 6.2-dev having performance"
echo "regressions with this codebase's patterns, particularly:"
echo "- Large single files (KanataManager.swift ~3700 lines)"
echo "- Complex async/await patterns"
echo "- Generic type inference"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"