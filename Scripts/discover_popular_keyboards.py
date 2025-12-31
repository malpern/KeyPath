#!/usr/bin/env python3
"""
Discover popular keyboards that actually have info.json files in QMK.

This script uses the GitHub API to find keyboards with info.json files
and creates a curated list of popular ones.
"""

import json
import urllib.request
import urllib.error
from typing import List, Dict, Any, Set

BASE_URL = "https://raw.githubusercontent.com/qmk/qmk_firmware/master/keyboards"
API_BASE = "https://api.github.com/repos/qmk/qmk_firmware/contents/keyboards"
OUTPUT_FILE = "Sources/KeyPathAppKit/Resources/popular-keyboards.json"

# Known popular keyboard names (we'll check if they exist)
POPULAR_NAMES = {
    "crkbd", "sofle", "helix", "planck", "preonic", "ergodox_ez",
    "lily58", "kyria", "iris", "redox", "atreus", "atreus62", "atreus64",
    "lets_split", "nyquist", "viterbi", "xd75", "id75", "ortho60", "ortho48",
    "minivan", "jd40", "jd45", "ut47", "dz60", "gh60", "tada68", "kbd60",
    "gk64", "kbd67", "dz65", "cajal", "kbd75", "xd84", "id80", "kbd8x",
    "xd87", "kbd19x", "macropad", "plaid", "kinesis", "advantage", "advantage2",
    "advantage360", "dactyl_manuform", "dactyl", "zeal60", "zeal65",
    "satisfaction75", "space65", "key65", "think65"
}


def has_info_json(keyboard_path: str) -> tuple[str | None, Dict[str, Any] | None]:
    """Check if keyboard has info.json and return path + data."""
    # Try root level
    url = f"{BASE_URL}/{keyboard_path}/info.json"
    try:
        with urllib.request.urlopen(url, timeout=5) as response:
            if response.status == 200:
                data = json.loads(response.read())
                return keyboard_path, data
    except:
        pass
    
    # Try common subdirectories
    for variant in ["rev1", "rev2", "rev3", "v1", "v2", "default", "standard", "lite_rev3", "glow_enc"]:
        variant_path = f"{keyboard_path}/{variant}"
        url = f"{BASE_URL}/{variant_path}/info.json"
        try:
            with urllib.request.urlopen(url, timeout=5) as response:
                if response.status == 200:
                    data = json.loads(response.read())
                    return variant_path, data
        except:
            continue
    
    # List subdirectories and check each
    try:
        api_url = f"{API_BASE}/{keyboard_path}"
        with urllib.request.urlopen(api_url, timeout=5) as response:
            contents = json.loads(response.read())
            dirs = [item["name"] for item in contents if item["type"] == "dir" and item["name"] not in ["keymaps", "lib"]]
            
            for subdir in dirs[:5]:  # Check first 5 subdirectories
                variant_path = f"{keyboard_path}/{subdir}"
                url = f"{BASE_URL}/{variant_path}/info.json"
                try:
                    with urllib.request.urlopen(url, timeout=5) as response:
                        if response.status == 200:
                            data = json.loads(response.read())
                            return variant_path, data
                except:
                    continue
    except:
        pass
    
    return None, None


def discover_keyboards() -> List[Dict[str, Any]]:
    """Discover keyboards from QMK repository."""
    print("🔍 Discovering keyboards from QMK repository...")
    
    # Get list of all keyboard directories
    try:
        with urllib.request.urlopen(f"{API_BASE}?per_page=100", timeout=10) as response:
            contents = json.loads(response.read())
            keyboard_dirs = [item["name"] for item in contents if item["type"] == "dir"]
            print(f"📦 Found {len(keyboard_dirs)} keyboard directories")
    except Exception as e:
        print(f"❌ Failed to fetch keyboard list: {e}")
        return []
    
    # Filter to popular ones first
    popular_dirs = [d for d in keyboard_dirs if d.lower() in POPULAR_NAMES]
    other_dirs = [d for d in keyboard_dirs if d.lower() not in POPULAR_NAMES]
    
    # Check popular ones first
    keyboards = []
    all_dirs = popular_dirs + other_dirs[:50]  # Check popular + 50 others
    
    print(f"🔍 Checking {len(all_dirs)} keyboards for info.json...")
    for i, keyboard_dir in enumerate(all_dirs, 1):
        if len(keyboards) >= 100:  # Limit to 100 keyboards
            break
        
        if i % 10 == 0:
            print(f"📊 Progress: {i}/{len(all_dirs)}, found {len(keyboards)} keyboards")
        
        path, info = has_info_json(keyboard_dir)
        if path and info:
            keyboards.append({
                "path": path,
                "display_name": info.get("keyboard_name") or info.get("name") or keyboard_dir,
                "info": info
            })
    
    return keyboards


def main():
    """Generate popular keyboards bundle."""
    keyboards = discover_keyboards()
    
    output = {
        "version": "1.0",
        "keyboards": keyboards
    }
    
    with open(OUTPUT_FILE, "w") as f:
        json.dump(output, f, indent=2)
    
    print(f"\n✅ Generated {OUTPUT_FILE}")
    print(f"📦 Included {len(keyboards)} keyboards")


if __name__ == "__main__":
    main()
