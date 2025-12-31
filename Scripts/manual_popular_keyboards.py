#!/usr/bin/env python3
"""
Manually curate a list of popular keyboards with known-working info.json paths.

This script manually fetches keyboards we know work, avoiding rate limits
by being selective and using known paths.
"""

import json
import urllib.request
import time
from typing import List, Dict, Any

BASE_URL = "https://raw.githubusercontent.com/qmk/qmk_firmware/master/keyboards"
OUTPUT_FILE = "Sources/KeyPathAppKit/Resources/popular-keyboards.json"

# Manually curated list: (path, display_name)
# These are keyboards we know exist and are popular
CURATED_KEYBOARDS = [
    # Already confirmed working
    ("crkbd", "Corne (crkbd)"),
    ("sofle", "Sofle"),
    ("helix", "Helix"),
    ("planck", "Planck"),
    ("preonic", "Preonic"),
    ("ergodox_ez", "Ergodox EZ"),
    ("atreus", "Atreus"),
    ("kinesis", "Kinesis"),
    ("lets_split", "Let's Split"),
    ("redox/rev1", "Redox"),
    ("0_sixty", "0_sixty"),
    ("3w6", "3w6"),
    ("8pack", "8-Pack"),
    
    # Popular splits (checking known paths)
    ("lily58/rev1", "Lily58"),
    ("lily58/rev2", "Lily58 Rev2"),
    ("lily58/lite_rev3", "Lily58 Lite Rev3"),
    ("kyria/rev1", "Kyria Rev1"),
    ("kyria/rev3", "Kyria Rev3"),
    ("iris/rev2", "Iris Rev2"),
    ("iris/rev4", "Iris Rev4"),
    ("dactyl_manuform/4x5", "Dactyl Manuform 4x5"),
    ("dactyl_manuform/5x6", "Dactyl Manuform 5x6"),
    ("dactyl_manuform/6x6", "Dactyl Manuform 6x6"),
    ("atreus62", "Atreus62"),
    ("atreus64", "Atreus64"),
    
    # Popular ortho
    ("nyquist/rev1", "Nyquist Rev1"),
    ("nyquist/rev2", "Nyquist Rev2"),
    ("viterbi/rev1", "Viterbi Rev1"),
    ("viterbi/rev2", "Viterbi Rev2"),
    ("xd75", "XD75"),
    ("id75", "ID75"),
    ("ortho60", "Ortho60"),
    ("ortho48", "Ortho48"),
    
    # Popular 40%
    ("minivan/rev1", "Minivan Rev1"),
    ("ut47/rev2", "UT47 Rev2"),
    
    # Popular 60%
    ("dz60", "DZ60"),
    ("dz60/rev3_60", "DZ60 Rev3"),
    ("gh60", "GH60"),
    ("tada68", "TADA68"),
    ("kbd60", "KBD60"),
    
    # Popular 65%
    ("kbd67/rev2", "KBD67 Rev2"),
    ("dz65", "DZ65"),
    
    # Popular 75%
    ("kbd75/rev1", "KBD75 Rev1"),
    ("kbd75/rev2", "KBD75 Rev2"),
    ("xd84", "XD84"),
    ("id80", "ID80"),
    
    # Popular TKL
    ("kbd8x/mkii", "KBD8X MKII"),
    
    # ZSA keyboards
    ("zsa/moonlander", "Moonlander"),
    ("zsa/ergodox", "Ergodox"),
    
    # Keyboardio
    ("keyboardio/atreus", "Keyboardio Atreus"),
    ("keyboardio/model01", "Keyboardio Model 01"),
    
    # Keebio
    ("keebio/iris", "Keebio Iris"),
    ("keebio/nyquist", "Keebio Nyquist"),
    ("keebio/viterbi", "Keebio Viterbi"),
    ("keebio/quefrency", "Keebio Quefrency"),
    ("keebio/fourier", "Keebio Fourier"),
    ("keebio/bfo9000", "Keebio BFO9000"),
    
    # OLKB
    ("olkb/planck", "OLKB Planck"),
    ("olkb/preonic", "OLKB Preonic"),
    
    # KBDFans
    ("kbdfans/kbd67", "KBDFans KBD67"),
    ("kbdfans/kbd75", "KBDFans KBD75"),
    ("kbdfans/kbd8x", "KBDFans KBD8X"),
    
    # More popular splits
    ("splitkb/kyria", "SplitKB Kyria"),
    ("splitkb/aurora", "SplitKB Aurora"),
    
    # BoardSource
    ("boardsource/3x4", "BoardSource 3x4"),
    ("boardsource/4x12", "BoardSource 4x12"),
    ("boardsource/5x12", "BoardSource 5x12"),
    
    # Fingerpunch
    ("fingerpunch/ffkb", "Fingerpunch FFKB"),
    ("fingerpunch/bgkeeb", "Fingerpunch BGKeeb"),
    
    # More ergo
    ("dactyl", "Dactyl"),
    ("dactyl_promicro", "Dactyl Promicro"),
]


def fetch_keyboard(keyboard_path: str, display_name: str) -> Dict[str, Any] | None:
    """Fetch info.json for a keyboard."""
    url = f"{BASE_URL}/{keyboard_path}/info.json"
    try:
        with urllib.request.urlopen(url, timeout=5) as response:
            if response.status == 200:
                data = json.loads(response.read())
                return {
                    "path": keyboard_path,
                    "display_name": display_name,
                    "info": data
                }
    except Exception as e:
        return None
    return None


def main():
    """Generate popular keyboards bundle."""
    print(f"🔍 Fetching {len(CURATED_KEYBOARDS)} curated keyboards...")
    
    keyboards = []
    for i, (keyboard_path, display_name) in enumerate(CURATED_KEYBOARDS, 1):
        print(f"[{i}/{len(CURATED_KEYBOARDS)}] {keyboard_path}...", end=" ")
        result = fetch_keyboard(keyboard_path, display_name)
        if result:
            keyboards.append(result)
            print("✅")
        else:
            print("❌")
        
        # Small delay to avoid rate limits
        if i % 10 == 0:
            time.sleep(1)
    
    output = {
        "version": "1.0",
        "keyboards": keyboards
    }
    
    with open(OUTPUT_FILE, "w") as f:
        json.dump(output, f, indent=2)
    
    print(f"\n✅ Generated {OUTPUT_FILE}")
    print(f"📦 Included {len(keyboards)} keyboards")
    print(f"📊 Success rate: {len(keyboards)}/{len(CURATED_KEYBOARDS)} ({100*len(keyboards)/len(CURATED_KEYBOARDS):.1f}%)")


if __name__ == "__main__":
    main()
