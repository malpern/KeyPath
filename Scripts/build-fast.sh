#!/bin/bash

# Fast build script for KeyPath that avoids Swift 6.2 performance issues
# This script implements several optimizations to work around build bottlenecks

set -e

echo "🚀 KeyPath Fast Build Script"
echo "=============================="

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

# 1. Clean build artifacts if requested
if [[ "$1" == "--clean" ]]; then
    print_status "Cleaning build artifacts..."
    rm -rf .build
    rm -rf DerivedData
    rm -rf ~/Library/Developer/Xcode/DerivedData/KeyPath-*
fi

# 2. Set optimized compiler flags
export SWIFT_BUILD_FLAGS="-c release"
export SWIFT_COMPILER_FLAGS=""

# Add flags to help with build performance
SWIFT_COMPILER_FLAGS+=" -Xswiftc -O"  # Optimize
SWIFT_COMPILER_FLAGS+=" -Xswiftc -whole-module-optimization"  # WMO for faster builds
SWIFT_COMPILER_FLAGS+=" -Xswiftc -num-threads -Xswiftc 8"  # Parallel compilation
SWIFT_COMPILER_FLAGS+=" -Xswiftc -disable-batch-mode"  # Disable batch mode that can hang

# Reduce type-checking complexity
SWIFT_COMPILER_FLAGS+=" -Xswiftc -solver-memory-threshold -Xswiftc 18000000"
SWIFT_COMPILER_FLAGS+=" -Xswiftc -solver-shrink-unsolved-threshold -Xswiftc 1000"

# 3. Try to use stable Swift if available
SWIFT_CMD="swift"
if command -v swift-5.9 &> /dev/null; then
    print_warning "Found Swift 5.9, using stable version..."
    SWIFT_CMD="swift-5.9"
elif [[ -d "/Library/Developer/Toolchains/swift-latest.xctoolchain" ]]; then
    print_warning "Using latest stable toolchain..."
    export TOOLCHAINS=swift-latest
fi

# 4. Create build directory
mkdir -p build

# 5. Build with optimizations
print_status "Building KeyPath with optimizations..."
echo "Using Swift: $($SWIFT_CMD --version | head -1)"

# Set a timeout to prevent infinite hangs
BUILD_TIMEOUT=300  # 5 minutes

# Function to run build with timeout
run_build() {
    timeout $BUILD_TIMEOUT $SWIFT_CMD build $SWIFT_BUILD_FLAGS $SWIFT_COMPILER_FLAGS --product KeyPath
}

# Try different build strategies
BUILD_SUCCESS=false

# Strategy 1: Normal optimized build
print_status "Attempting optimized build..."
if run_build 2>&1 | tee build.log; then
    BUILD_SUCCESS=true
    print_status "Build completed successfully!"
else
    print_warning "Optimized build failed, trying fallback strategies..."
    
    # Strategy 2: Build without WMO
    print_status "Attempting build without whole-module-optimization..."
    SWIFT_COMPILER_FLAGS="${SWIFT_COMPILER_FLAGS//-Xswiftc -whole-module-optimization/}"
    if run_build 2>&1 | tee build.log; then
        BUILD_SUCCESS=true
        print_status "Build completed successfully (without WMO)!"
    else
        # Strategy 3: Incremental build by compiling in stages
        print_warning "Trying incremental compilation..."
        
        # First compile core dependencies
        print_status "Building core modules..."
        $SWIFT_CMD build $SWIFT_BUILD_FLAGS --target KeyPath 2>&1 | tee build.log
        
        if [[ $? -eq 0 ]]; then
            BUILD_SUCCESS=true
            print_status "Build completed successfully (incremental)!"
        fi
    fi
fi

# 6. Copy built product to build directory
if [[ "$BUILD_SUCCESS" == true ]]; then
    print_status "Copying built app to build directory..."
    
    # For a Swift Package Manager macOS app, the executable is built directly
    ARCH=$(uname -m)
    
    # Primary location for executable based on architecture
    BUILT_EXEC=".build/${ARCH}-apple-macosx/release/KeyPath"
    
    # Fallback locations
    if [[ ! -f "$BUILT_EXEC" ]]; then
        BUILT_EXEC=".build/release/KeyPath"
    fi
    
    # Bundle location (if it exists)
    BUILT_BUNDLE=".build/${ARCH}-apple-macosx/release/KeyPath_KeyPath.bundle"
    
    # Check if we have a bundle or executable
    if [[ -d "$BUILT_BUNDLE" ]] || [[ -f "$BUILT_EXEC" ]]; then
        # Create app bundle structure
        APP_BUNDLE="build/KeyPath.app"
        rm -rf "$APP_BUNDLE"
        mkdir -p "$APP_BUNDLE/Contents/MacOS"
        mkdir -p "$APP_BUNDLE/Contents/Resources"
        
        # If we have a bundle, copy from there
        if [[ -d "$BUILT_BUNDLE" ]]; then
            print_status "Found app bundle at $BUILT_BUNDLE"
            cp -R "$BUILT_BUNDLE/Contents/"* "$APP_BUNDLE/Contents/" 2>/dev/null || true
        fi
        
        # Copy executable if found
        if [[ -f "$BUILT_EXEC" ]]; then
            print_status "Found executable at $BUILT_EXEC"
            cp "$BUILT_EXEC" "$APP_BUNDLE/Contents/MacOS/KeyPath"
        fi
        
        # Ensure we have an executable
        if [[ ! -f "$APP_BUNDLE/Contents/MacOS/KeyPath" ]]; then
            # Try to find any executable in the build directory
            FOUND_EXEC=$(find .build -name "KeyPath" -type f -perm +111 2>/dev/null | head -1)
            if [[ -n "$FOUND_EXEC" ]]; then
                print_status "Found executable at $FOUND_EXEC"
                cp "$FOUND_EXEC" "$APP_BUNDLE/Contents/MacOS/KeyPath"
            fi
        fi
        
        # Copy Info.plist if it exists
        if [[ -f "Resources/Info.plist" ]]; then
            cp "Resources/Info.plist" "$APP_BUNDLE/Contents/"
        fi
        
        # Copy icon if it exists
        if [[ -f "Resources/AppIcon.icns" ]]; then
            cp "Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"
        elif [[ -f ".build/${ARCH}-apple-macosx/release/AppIcon.icns" ]]; then
            cp ".build/${ARCH}-apple-macosx/release/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"
        fi
        
        if [[ -f "$APP_BUNDLE/Contents/MacOS/KeyPath" ]]; then
            print_status "App bundle created at: $APP_BUNDLE"
            
            # Show build stats
            echo ""
            echo "Build Statistics:"
            echo "-----------------"
            echo "Executable size: $(du -h "$APP_BUNDLE/Contents/MacOS/KeyPath" | cut -f1)"
            echo "Build time: Check build.log for details"
            
            # Offer to install
            echo ""
            read -p "Install to /Applications? (y/n) " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                print_status "Installing to /Applications..."
                sudo rm -rf /Applications/KeyPath.app
                sudo cp -r "$APP_BUNDLE" /Applications/
                print_status "KeyPath installed to /Applications"
            fi
        else
            print_error "Could not find or create executable in app bundle"
            print_warning "The build completed but executable packaging failed"
            print_warning "You may need to use the standard build script: ./Scripts/build.sh"
            exit 1
        fi
    else
        print_error "Built product not found at expected locations"
        print_warning "Looking for build artifacts..."
        find .build -name "*KeyPath*" -type f -o -type d | head -10
        exit 1
    fi
else
    print_error "Build failed. Check build.log for details"
    
    # Show last few lines of error
    echo ""
    echo "Last 20 lines of build log:"
    echo "----------------------------"
    tail -20 build.log
    
    exit 1
fi

echo ""
print_status "Build complete!"