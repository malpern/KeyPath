#!/usr/bin/env python3
"""
Expand the popular keyboards bundle by checking vendor subdirectories.

This script takes the existing bundle and expands it by checking vendor
subdirectories for more keyboards.
"""

import json
import urllib.request
import urllib.error
from typing import List, Dict, Any

BASE_URL = "https://raw.githubusercontent.com/qmk/qmk_firmware/master/keyboards"
API_BASE = "https://api.github.com/repos/qmk/qmk_firmware/contents/keyboards"
INPUT_FILE = "Sources/KeyPathAppKit/Resources/popular-keyboards.json"
OUTPUT_FILE = "Sources/KeyPathAppKit/Resources/popular-keyboards.json"

# Vendors to check (popular keyboard manufacturers)
VENDORS_TO_CHECK = [
    "zsa",  # ZSA (Moonlander, Ergodox)
    "keyboardio",  # Keyboardio
    "keebio",  # Keebio
    "olkb",  # OLKB (Planck, Preonic)
    "cannonkeys",  # CannonKeys
    "kbdfans",  # KBDFans
    "kbd",  # KBD
    "ai03",  # ai03
    "matrix",  # Matrix
    "rama",  # Rama
    "drop",  # Drop
    "1upkeyboards",  # 1Up Keyboards
    "40percentclub",  # 40% Club
    "dactyl_manuform",  # Dactyl Manuform
    "dactyl",  # Dactyl
    "foostan",  # foostan (Corne)
    "splitkb",  # SplitKB
    "boardsource",  # BoardSource
    "bastardkb",  # BastardKB
    "fingerpunch",  # Fingerpunch
]

# Additional popular keyboards to try (with potential subdirectories)
ADDITIONAL_KEYBOARDS = [
    ("lily58", ["rev1", "rev2", "rev3", "lite_rev3", "glow_enc"]),
    ("kyria", ["rev1", "rev2", "rev3"]),
    ("iris", ["rev1", "rev2", "rev3", "rev4"]),
    ("redox", ["rev1", "rev2"]),
    ("moonlander", []),
    ("ergodox", ["ez"]),
    ("dactyl_manuform", ["4x5", "5x6", "6x6"]),
    ("lets_split", ["sockets", "eh"]),
    ("nyquist", ["rev1", "rev2"]),
    ("viterbi", ["rev1", "rev2"]),
    ("xd75", ["rev3"]),
    ("id75", []),
    ("ortho60", []),
    ("ortho48", []),
    ("minivan", ["rev1"]),
    ("ut47", ["rev2"]),
    ("dz60", ["rev3_60"]),
    ("kbd60", []),
    ("kbd67", ["rev2"]),
    ("kbd75", ["rev1", "rev2"]),
    ("kbd8x", ["mkii"]),
]


def check_keyboard(keyboard_path: str) -> tuple[str | None, Dict[str, Any] | None]:
    """Check if keyboard has info.json."""
    url = f"{BASE_URL}/{keyboard_path}/info.json"
    try:
        with urllib.request.urlopen(url, timeout=5) as response:
            if response.status == 200:
                data = json.loads(response.read())
                return keyboard_path, data
    except:
        pass
    return None, None


def check_vendor_keyboards(vendor: str) -> List[Dict[str, Any]]:
    """Check all keyboards under a vendor directory."""
    keyboards = []
    try:
        api_url = f"{API_BASE}/{vendor}"
        with urllib.request.urlopen(api_url, timeout=10) as response:
            contents = json.loads(response.read())
            keyboard_dirs = [item["name"] for item in contents if item["type"] == "dir"]
            
            for kb_dir in keyboard_dirs[:20]:  # Limit to 20 per vendor
                path = f"{vendor}/{kb_dir}"
                actual_path, info = check_keyboard(path)
                if actual_path and info:
                    keyboards.append({
                        "path": actual_path,
                        "display_name": info.get("keyboard_name") or info.get("name") or kb_dir,
                        "info": info
                    })
    except Exception as e:
        print(f"⚠️  Failed to check vendor {vendor}: {e}")
    
    return keyboards


def main():
    """Expand popular keyboards bundle."""
    # Load existing bundle
    try:
        with open(INPUT_FILE) as f:
            existing = json.load(f)
            existing_paths = {kb["path"] for kb in existing["keyboards"]}
            print(f"📦 Starting with {len(existing_paths)} existing keyboards")
    except FileNotFoundError:
        existing = {"version": "1.0", "keyboards": []}
        existing_paths = set()
    
    all_keyboards = {kb["path"]: kb for kb in existing["keyboards"]}
    
    # Check vendor directories
    print(f"🔍 Checking {len(VENDORS_TO_CHECK)} vendor directories...")
    for vendor in VENDORS_TO_CHECK:
        print(f"  Checking {vendor}...")
        vendor_keyboards = check_vendor_keyboards(vendor)
        for kb in vendor_keyboards:
            if kb["path"] not in existing_paths:
                all_keyboards[kb["path"]] = kb
                print(f"    ✅ Added {kb['path']}")
    
    # Check additional keyboards with variants
    print(f"\n🔍 Checking {len(ADDITIONAL_KEYBOARDS)} additional keyboards...")
    for base_name, variants in ADDITIONAL_KEYBOARDS:
        # Try base name first
        path, info = check_keyboard(base_name)
        if path and info and path not in existing_paths:
            all_keyboards[path] = {
                "path": path,
                "display_name": info.get("keyboard_name") or info.get("name") or base_name,
                "info": info
            }
            print(f"  ✅ Added {path}")
        
        # Try variants
        for variant in variants:
            variant_path = f"{base_name}/{variant}"
            path, info = check_keyboard(variant_path)
            if path and info and path not in existing_paths:
                all_keyboards[path] = {
                    "path": path,
                    "display_name": info.get("keyboard_name") or info.get("name") or variant_path,
                    "info": info
                }
                print(f"  ✅ Added {path}")
    
    # Save updated bundle
    output = {
        "version": "1.0",
        "keyboards": list(all_keyboards.values())
    }
    
    with open(OUTPUT_FILE, "w") as f:
        json.dump(output, f, indent=2)
    
    print(f"\n✅ Updated {OUTPUT_FILE}")
    print(f"📦 Total: {len(all_keyboards)} keyboards")


if __name__ == "__main__":
    main()
