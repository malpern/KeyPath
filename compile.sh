#\!/bin/bash
echo "Compiling KeyPath..."
swiftc -o KeyPath \
  -whole-module-optimization \
  -O \
  Sources/KeyPath/*.swift \
  Sources/KeyPath/**/*.swift \
  Sources/KeyPath/**/**/*.swift \
  -framework SwiftUI \
  -framework AppKit \
  -framework Foundation \
  2>&1 | tail -10
