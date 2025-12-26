#!/usr/bin/env python3
"""
Check for missing accessibility identifiers in SwiftUI interactive elements.

This script scans Swift files for Button, Toggle, and Picker declarations
and ensures they have .accessibilityIdentifier() modifiers.
"""

import re
import sys
from pathlib import Path
from typing import List, Tuple

# Colors for terminal output
RED = "\033[0;31m"
YELLOW = "\033[1;33m"
GREEN = "\033[0;32m"
NC = "\033[0m"  # No Color

# Patterns for interactive UI elements
INTERACTIVE_PATTERNS = [
    (r"Button\s*\(", "Button"),
    (r"Toggle\s*\(", "Toggle"),
    (r"Picker\s*\(", "Picker"),
]

# Files/directories to exclude
EXCLUDED_PATTERNS = [
    r".*Test.*\.swift$",
    r".*Preview.*\.swift$",
    r".*\.generated\.swift$",
    r".*/Style/.*",
    r".*TitlebarHeaderAccessory\.swift$",
    r".*WindowControlsView\.swift$",  # System window controls
]

# System components that don't need SwiftUI accessibility identifiers
SYSTEM_COMPONENT_PATTERNS = [
    r"NSButton",
    r"NSToggle",
    r"NSPopUpButton",
    r"NSComboBox",
]


def is_excluded(file_path: Path) -> bool:
    """Check if file should be excluded from checking."""
    file_str = str(file_path)
    for pattern in EXCLUDED_PATTERNS:
        if re.search(pattern, file_str):
            return True
    return False


def has_accessibility_identifier(lines: List[str], start_idx: int, end_idx: int) -> bool:
    """Check if code block has accessibilityIdentifier modifier."""
    block = "\n".join(lines[start_idx:end_idx])
    
    # Check for accessibilityIdentifier modifier
    if re.search(r"\.accessibilityIdentifier\s*\(", block):
        return True
    
    # Check if it's a system component (uses different accessibility APIs)
    for pattern in SYSTEM_COMPONENT_PATTERNS:
        if re.search(pattern, block):
            return True
    
    return False


def find_interactive_elements(file_path: Path) -> List[Tuple[int, str, str]]:
    """Find all interactive UI elements in a Swift file."""
    try:
        content = file_path.read_text(encoding="utf-8")
    except Exception as e:
        print(f"Warning: Could not read {file_path}: {e}", file=sys.stderr)
        return []
    
    lines = content.split("\n")
    issues = []
    
    for line_idx, line in enumerate(lines, start=1):
        # Check if this button is inside an alert closure
        # Look backwards for .alert( pattern
        context_start = max(0, line_idx - 20)
        context = "\n".join(lines[context_start:line_idx])
        
        # Skip if inside alert closure (buttons in alerts are system-managed)
        if re.search(r"\.alert\s*\([^)]*isPresented:", context):
            continue
        
        # Skip if inside sheet/popover (also system-managed)
        if re.search(r"\.(sheet|popover|fullScreenCover)\s*\([^)]*isPresented:", context):
            continue
        
        # Check each interactive pattern
        for pattern, element_type in INTERACTIVE_PATTERNS:
            if re.search(pattern, line):
                # Skip if this is a custom component (component should add identifier internally)
                # Look for custom component names (capitalized, not Button/Toggle/Picker)
                if re.search(r"\b[A-Z][a-zA-Z0-9]*Button\s*\(", line):
                    continue  # Custom button component
                if re.search(r"\b[A-Z][a-zA-Z0-9]*Toggle\s*\(", line):
                    continue  # Custom toggle component
                if re.search(r"\b[A-Z][a-zA-Z0-9]*Picker\s*\(", line):
                    continue  # Custom picker component
                
                # Found an interactive element - check if it has accessibilityIdentifier
                # Look ahead up to 50 lines for the modifier (increased from 30 to catch identifiers added later in modifier chains)
                end_idx = min(line_idx + 50, len(lines))
                
                if not has_accessibility_identifier(lines, line_idx - 1, end_idx):
                    # Check if this is inside a comment or string literal
                    stripped = line.strip()
                    if stripped.startswith("//") or stripped.startswith("/*"):
                        continue
                    
                    # Skip if it's a toolbar item (system component)
                    if re.search(r"ToolbarItem", content[max(0, line_idx - 5):line_idx]):
                        continue
                    
                    # Skip guard statements (not actual UI elements)
                    if re.search(r"guard\s+case\s+let\s+\.(tapHoldPicker|singleKeyPicker)", line):
                        continue
                    
                    # Skip NSAlert buttons (system-managed, use different APIs)
                    # Check if this Button is inside NSAlert context
                    context_before = "\n".join(lines[max(0, line_idx - 15):line_idx])
                    if re.search(r"alert\.addButton|NSAlert\(\)|let alert = NSAlert", context_before):
                        continue
                    
                    issues.append((line_idx, element_type, line.strip()))
    
    return issues


def main():
    """Main execution."""
    project_root = Path(__file__).parent.parent
    ui_dir = project_root / "Sources" / "KeyPathAppKit" / "UI"
    
    if not ui_dir.exists():
        print(f"Error: UI directory not found: {ui_dir}", file=sys.stderr)
        sys.exit(1)
    
    print("🔍 Checking for missing accessibility identifiers...")
    print()
    
    total_issues = 0
    files_checked = 0
    
    # Find all Swift files in UI directory
    for swift_file in sorted(ui_dir.rglob("*.swift")):
        if is_excluded(swift_file):
            continue
        
        files_checked += 1
        issues = find_interactive_elements(swift_file)
        
        if issues:
            rel_path = swift_file.relative_to(project_root)
            for line_num, element_type, line_content in issues:
                print(f"{RED}❌{NC} {rel_path}:{line_num}")
                print(f"   Missing .accessibilityIdentifier() on {YELLOW}{element_type}{NC}")
                # Show first 80 chars of the line
                preview = line_content[:80] + ("..." if len(line_content) > 80 else "")
                print(f"   {preview}")
                print()
                total_issues += 1
    
    print("━" * 80)
    print(f"Checked {files_checked} files")
    print()
    
    if total_issues == 0:
        print(f"{GREEN}✅ All UI elements have accessibility identifiers!{NC}")
        return 0
    else:
        print(f"{RED}❌ Found {total_issues} issue(s){NC}")
        print()
        print("💡 To fix: Add .accessibilityIdentifier(\"unique-id\") modifier")
        print("   See ACCESSIBILITY_COVERAGE.md for examples")
        return 1


if __name__ == "__main__":
    sys.exit(main())
