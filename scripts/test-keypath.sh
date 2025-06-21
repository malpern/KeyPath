#!/bin/bash

# KeyPath Test Runner
# Quick script to run various KeyPath tests

set -e

echo "🔧 KeyPath Test Runner"
echo "====================="

# Check if we're in the right directory
if [ ! -f "keypath-cli.swift" ]; then
    echo "❌ Error: keypath-cli.swift not found. Please run this script from the KeyPath directory."
    exit 1
fi

# Function to print section headers
print_section() {
    echo ""
    echo "📋 $1"
    echo "$(printf '=%.0s' {1..50})"
}

# Quick status check
print_section "Quick Status Check"
swift keypath-cli.swift status

# Run comprehensive tests
print_section "Comprehensive Test Suite"
swift keypath-cli.swift test

# Test specific rule validation
print_section "Testing Sample Rules"
echo "Testing caps to escape:"
swift keypath-cli.swift validate --rule "(defalias caps esc)"

echo ""
echo "Testing space to shift (tap-hold):"
swift keypath-cli.swift validate --rule "(defalias spc (tap-hold 200 200 spc lsft))"

echo ""
echo "Testing invalid rule (should fail):"
swift keypath-cli.swift validate --rule "(invalid rule)" || echo "✅ Invalid rule correctly rejected"

# Show current config (first 20 lines)
print_section "Current Configuration (first 20 lines)"
swift keypath-cli.swift config | head -20

echo ""
echo "🎉 All tests completed!"
echo ""
echo "💡 Usage examples:"
echo "   ./test-keypath.sh                                    # Run this test suite"
echo "   swift keypath-cli.swift status                       # Check system status"
echo "   swift keypath-cli.swift validate --rule \"<rule>\"   # Validate a rule"
echo "   swift keypath-cli.swift config                       # Show configuration"
echo "   swift keypath-cli.swift --help                       # Show help"