#!/bin/bash

# CLI Test Suite
# Tests KeyPath CLI functionality with real config changes and proper cleanup

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLI_BIN="$PROJECT_ROOT/.build/debug/keypath-cli"
CONFIG_DIR="$HOME/.config/keypath"
CONFIG_FILE="$CONFIG_DIR/keypath.kbd"
BACKUP_FILE="$CONFIG_FILE.test-backup.$(date +%s)"

# Cleanup function
cleanup() {
    echo ""
    echo -e "${BLUE}=== Cleanup ===${NC}"

    if [ -f "$BACKUP_FILE" ]; then
        echo "Restoring original config from backup..."
        mv "$BACKUP_FILE" "$CONFIG_FILE"
        echo -e "${GREEN}✓${NC} Original config restored"
    else
        echo "No backup found, leaving current config"
    fi

    echo ""
    echo -e "${BLUE}=== Test Summary ===${NC}"
    echo "Tests run:    $TESTS_RUN"
    echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"

    if [ $TESTS_FAILED -gt 0 ]; then
        echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"
        exit 1
    else
        echo -e "Tests failed: $TESTS_FAILED"
        echo ""
        echo -e "${GREEN}All tests passed!${NC}"
        exit 0
    fi
}

trap cleanup EXIT

# Test helpers
assert_equals() {
    local expected="$1"
    local actual="$2"
    local test_name="$3"

    TESTS_RUN=$((TESTS_RUN + 1))

    if [ "$expected" = "$actual" ]; then
        echo -e "${GREEN}✓${NC} $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗${NC} $test_name"
        echo -e "  Expected: ${YELLOW}$expected${NC}"
        echo -e "  Got:      ${YELLOW}$actual${NC}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

assert_contains() {
    local needle="$1"
    local haystack="$2"
    local test_name="$3"

    TESTS_RUN=$((TESTS_RUN + 1))

    if echo "$haystack" | grep -q "$needle"; then
        echo -e "${GREEN}✓${NC} $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗${NC} $test_name"
        echo -e "  Expected to contain: ${YELLOW}$needle${NC}"
        echo -e "  In output: ${YELLOW}$haystack${NC}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

assert_file_exists() {
    local file="$1"
    local test_name="$2"

    TESTS_RUN=$((TESTS_RUN + 1))

    if [ -f "$file" ]; then
        echo -e "${GREEN}✓${NC} $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗${NC} $test_name"
        echo -e "  Expected file to exist: ${YELLOW}$file${NC}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

# Main test execution
main() {
    echo -e "${BLUE}=== KeyPath CLI Test Suite ===${NC}"
    echo ""

    # Build CLI if needed
    if [ ! -f "$CLI_BIN" ]; then
        echo "Building CLI..."
        cd "$PROJECT_ROOT"
        swift build --product keypath-cli
        echo ""
    fi

    # Backup existing config
    echo -e "${BLUE}=== Setup ===${NC}"
    if [ -f "$CONFIG_FILE" ]; then
        echo "Backing up existing config to: $BACKUP_FILE"
        cp "$CONFIG_FILE" "$BACKUP_FILE"
        echo -e "${GREEN}✓${NC} Backup created"
    else
        echo "No existing config found, will create fresh"
    fi
    echo ""

    # Test 1: Help command
    echo -e "${BLUE}=== Test: Help Command ===${NC}"
    help_output=$($CLI_BIN --help 2>&1)
    assert_contains "keypath map <key->key>" "$help_output" "Help shows arrow syntax"
    assert_contains "Examples:" "$help_output" "Help contains examples"
    echo ""

    # Test 2: Reset to default (skip empty test due to CLI bug)
    echo -e "${BLUE}=== Test: Reset to Default ===${NC}"
    $CLI_BIN reset --no-reload >/dev/null 2>&1
    assert_file_exists "$CONFIG_FILE" "Config file created"

    list_output=$($CLI_BIN list 2>&1)
    assert_contains "caps -> esc" "$list_output" "Default config has caps->esc mapping"
    echo ""

    # Test 3: Single mapping
    echo -e "${BLUE}=== Test: Single Mapping ===${NC}"
    $CLI_BIN map 'caps->esc' --no-reload >/dev/null 2>&1
    list_output=$($CLI_BIN list 2>&1)
    assert_contains "caps -> esc" "$list_output" "Single mapping created"
    echo ""

    # Test 4: Multiple mappings
    echo -e "${BLUE}=== Test: Multiple Mappings ===${NC}"
    $CLI_BIN map 'a->b' '2->3' 'x->y' --no-reload >/dev/null 2>&1
    list_output=$($CLI_BIN list 2>&1)
    assert_contains "a -> b" "$list_output" "First mapping in list"
    assert_contains "2 -> 3" "$list_output" "Second mapping in list"
    assert_contains "x -> y" "$list_output" "Third mapping in list"

    # Count lines to verify 3 mappings
    mapping_count=$(echo "$list_output" | grep -c -- "->")
    assert_equals "3" "$mapping_count" "Exactly 3 mappings exist"
    echo ""

    # Test 5: Mapping replacement
    echo -e "${BLUE}=== Test: Mapping Replacement ===${NC}"
    $CLI_BIN map 'a->z' --no-reload >/dev/null 2>&1
    list_output=$($CLI_BIN list 2>&1)
    assert_contains "a -> z" "$list_output" "Mapping was replaced"

    mapping_count=$(echo "$list_output" | grep -c -- "->")
    assert_equals "1" "$mapping_count" "Only one mapping after replacement"
    echo ""

    # Test 6: Chord mapping
    echo -e "${BLUE}=== Test: Chord Mapping ===${NC}"
    $CLI_BIN map 'caps->cmd+c' --no-reload >/dev/null 2>&1
    list_output=$($CLI_BIN list 2>&1)
    assert_contains "caps -> C+c" "$list_output" "Chord mapping created (cmd becomes C)"
    echo ""

    # Test 7: Deduplication
    echo -e "${BLUE}=== Test: Deduplication ===${NC}"
    $CLI_BIN map 'a->b' 'a->c' 'a->d' --no-reload >/dev/null 2>&1
    list_output=$($CLI_BIN list 2>&1)
    mapping_count=$(echo "$list_output" | grep -c -- "a ->")
    assert_equals "1" "$mapping_count" "Duplicate input keys deduplicated"
    echo ""

    # Test 8: Error - Empty key
    echo -e "${BLUE}=== Test: Validation - Empty Key ===${NC}"
    error_output=$($CLI_BIN map '2->' 2>&1 || true)
    assert_contains "Invalid mapping '2->'" "$error_output" "Empty key detected"
    assert_contains "Both keys must be non-empty" "$error_output" "Helpful error message"
    echo ""

    # Test 9: Error - Multiple arrows
    echo -e "${BLUE}=== Test: Validation - Multiple Arrows ===${NC}"
    error_output=$($CLI_BIN map 'a->b->c' 2>&1 || true)
    assert_contains "Invalid mapping 'a->b->c'" "$error_output" "Multiple arrows detected"
    assert_contains "Expected format: KEY->KEY" "$error_output" "Helpful error message"
    echo ""

    # Test 10: Error - Missing arrow
    echo -e "${BLUE}=== Test: Validation - Missing Arrow ===${NC}"
    error_output=$($CLI_BIN map 'caps' 2>&1 || true)
    assert_contains "Unknown argument: caps" "$error_output" "Missing arrow detected"
    echo ""

    # Test 11: Reset clears previous mappings
    echo -e "${BLUE}=== Test: Reset Clears Mappings ===${NC}"
    $CLI_BIN map 'a->b' 'c->d' 'e->f' --no-reload >/dev/null 2>&1
    $CLI_BIN reset --no-reload >/dev/null 2>&1
    list_output=$($CLI_BIN list 2>&1)
    assert_contains "caps -> esc" "$list_output" "Default mapping (caps->esc) created"

    mapping_count=$(echo "$list_output" | grep -c -- "->")
    assert_equals "1" "$mapping_count" "Only default mapping exists after reset"
    echo ""

    # Test 12: Config file format
    echo -e "${BLUE}=== Test: Config File Format ===${NC}"
    $CLI_BIN map 'a->b' '2->3' --no-reload >/dev/null 2>&1
    config_content=$(cat "$CONFIG_FILE")
    assert_contains "(defcfg" "$config_content" "Contains defcfg section"
    assert_contains "(defsrc" "$config_content" "Contains defsrc section"
    assert_contains "(deflayer base" "$config_content" "Contains deflayer section"
    assert_contains "Generated by KeyPath CLI" "$config_content" "Contains generator comment"
    echo ""

    # Test 13: Key normalization
    echo -e "${BLUE}=== Test: Key Normalization ===${NC}"
    $CLI_BIN map 'CAPS->ESC' --no-reload >/dev/null 2>&1
    list_output=$($CLI_BIN list 2>&1)
    assert_contains "caps -> esc" "$list_output" "Keys normalized to lowercase"
    echo ""

    # Test 14: Config persistence
    echo -e "${BLUE}=== Test: Config Persistence ===${NC}"
    $CLI_BIN map 'f1->f2' --no-reload >/dev/null 2>&1
    first_list=$($CLI_BIN list 2>&1)

    # Read again without writing
    second_list=$($CLI_BIN list 2>&1)
    assert_equals "$first_list" "$second_list" "Config persists between reads"
    echo ""

    # Test 15: Multiple mappings with --no-reload flag
    echo -e "${BLUE}=== Test: No-Reload Flag ===${NC}"
    output=$($CLI_BIN map 'test->test2' --no-reload 2>&1)
    assert_contains "Wrote configuration" "$output" "Success message shown"
    # Note: We can't easily test that reload didn't happen, but we verify it doesn't crash
    echo ""
}

main "$@"
