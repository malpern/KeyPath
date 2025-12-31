#!/usr/bin/env python3
"""
Generate a bundled JSON file with popular QMK keyboards for instant search.

This script fetches info.json files for popular keyboards and creates a bundled
database that can be included in the app for instant search results.
"""

import json
import urllib.request
import urllib.error
from typing import List, Dict, Any

# Popular keyboards to include in bundle
# Based on: community popularity, already in app, common form factors
# Format: (directory_path, display_name)
POPULAR_KEYBOARDS = [
    # Already in app (these we know work)
    ("crkbd", "Corne (crkbd)"),
    ("sofle", "Sofle"),
    ("helix", "Helix"),
    ("planck", "Planck"),
    ("preonic", "Preonic"),
    ("ergodox_ez", "Ergodox EZ"),
    
    # Popular splits (checking common paths)
    ("lily58", "Lily58"),
    ("kyria", "Kyria"),
    ("iris", "Iris"),
    ("redox", "Redox"),
    ("dactyl_manuform/4x5", "Dactyl Manuform 4x5"),
    ("dactyl_manuform/5x6", "Dactyl Manuform 5x6"),
    ("dactyl_manuform/6x6", "Dactyl Manuform 6x6"),
    ("atreus", "Atreus"),
    ("atreus62", "Atreus62"),
    ("atreus64", "Atreus64"),
    
    # Popular ortho
    ("xd75", "XD75"),
    ("id75", "ID75"),
    ("ortho60", "Ortho60"),
    ("ortho48", "Ortho48"),
    ("lets_split", "Let's Split"),
    ("lets_split_eh", "Let's Split EH"),
    ("nyquist", "Nyquist"),
    ("viterbi", "Viterbi"),
    
    # Popular 40%
    ("minivan", "Minivan"),
    ("jd40", "JD40"),
    ("jd45", "JD45"),
    ("ut47", "UT47"),
    
    # Popular 60%
    ("dz60", "DZ60"),
    ("gh60", "GH60"),
    ("tada68", "TADA68"),
    ("kbd60", "KBD60"),
    ("gk64", "GK64"),
    
    # Popular 65%
    ("kbd67", "KBD67"),
    ("dz65", "DZ65"),
    ("cajal", "Cajal"),
    
    # Popular 75%
    ("kbd75", "KBD75"),
    ("xd84", "XD84"),
    ("id80", "ID80"),
    
    # Popular TKL/80%
    ("kbd8x", "KBD8X"),
    ("xd87", "XD87"),
    
    # Popular full-size
    ("kbd19x", "KBD19X"),
    
    # Popular macro pads
    ("macropad", "Macropad"),
    ("plaid", "Plaid"),
    
    # Popular custom (checking vendor subdirectories)
    ("zsa", "ZSA Keyboards"),  # Moonlander, Ergodox
    ("matrix", "Matrix Keyboards"),
    ("ai03", "ai03 Keyboards"),
    
    # More ergo
    ("kinesis", "Kinesis"),
    ("advantage", "Kinesis Advantage"),
    ("advantage2", "Kinesis Advantage2"),
    ("advantage360", "Kinesis Advantage360"),
]

BASE_URL = "https://raw.githubusercontent.com/qmk/qmk_firmware/master/keyboards"
OUTPUT_FILE = "Sources/KeyPathAppKit/Resources/popular-keyboards.json"


def find_info_json_path(keyboard_path: str) -> str | None:
    """Find the actual path to info.json (may be in subdirectories)."""
    # Try root level first
    url = f"{BASE_URL}/{keyboard_path}/info.json"
    try:
        with urllib.request.urlopen(url, timeout=5) as response:
            if response.status == 200:
                return keyboard_path
    except:
        pass
    
    # List subdirectories and check each
    try:
        api_url = f"https://api.github.com/repos/qmk/qmk_firmware/contents/keyboards/{keyboard_path}"
        with urllib.request.urlopen(api_url, timeout=5) as response:
            contents = json.loads(response.read())
            dirs = [item["name"] for item in contents if item["type"] == "dir"]
            
            # Try each subdirectory
            for subdir in dirs[:10]:  # Limit to first 10 to avoid too many requests
                variant_path = f"{keyboard_path}/{subdir}"
                url = f"{BASE_URL}/{variant_path}/info.json"
                try:
                    with urllib.request.urlopen(url, timeout=5) as response:
                        if response.status == 200:
                            return variant_path
                except:
                    continue
    except:
        pass
    
    # Try common subdirectories as fallback
    for variant in ["rev1", "rev2", "rev3", "v1", "v2", "default", "standard"]:
        variant_path = f"{keyboard_path}/{variant}"
        url = f"{BASE_URL}/{variant_path}/info.json"
        try:
            with urllib.request.urlopen(url, timeout=5) as response:
                if response.status == 200:
                    return variant_path
        except:
            continue
    
    return None


def fetch_keyboard_info(keyboard_path: str, display_name: str) -> Dict[str, Any] | None:
    """Fetch info.json for a keyboard."""
    # Find actual path to info.json
    actual_path = find_info_json_path(keyboard_path)
    if not actual_path:
        print(f"⚠️  No info.json found for {keyboard_path}")
        return None
    
    url = f"{BASE_URL}/{actual_path}/info.json"
    try:
        with urllib.request.urlopen(url, timeout=5) as response:
            data = json.loads(response.read())
            return {
                "path": actual_path,
                "display_name": display_name,
                "info": data
            }
    except (urllib.error.URLError, urllib.error.HTTPError, json.JSONDecodeError) as e:
        print(f"⚠️  Failed to fetch {keyboard_path}: {e}")
        return None


def main():
    """Generate popular keyboards bundle."""
    print(f"🔍 Fetching {len(POPULAR_KEYBOARDS)} popular keyboards...")
    
    keyboards = []
    for i, (keyboard_path, display_name) in enumerate(POPULAR_KEYBOARDS, 1):
        print(f"[{i}/{len(POPULAR_KEYBOARDS)}] Fetching {keyboard_path} ({display_name})...")
        result = fetch_keyboard_info(keyboard_path, display_name)
        if result:
            keyboards.append(result)
    
    output = {
        "version": "1.0",
        "keyboards": keyboards
    }
    
    with open(OUTPUT_FILE, "w") as f:
        json.dump(output, f, indent=2)
    
    print(f"\n✅ Generated {OUTPUT_FILE}")
    print(f"📦 Included {len(keyboards)} keyboards")
    print(f"📊 Success rate: {len(keyboards)}/{len(POPULAR_KEYBOARDS)} ({100*len(keyboards)/len(POPULAR_KEYBOARDS):.1f}%)")


if __name__ == "__main__":
    main()
