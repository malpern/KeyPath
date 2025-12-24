#!/usr/bin/env python3
"""
Slice the keyboard illustration image into individual keyboard assets.
Based on the image description, the layout is:
- Tier 1 (left): MacBook US, Kinesis Advantage 360
- Tier 2 ANSI SIZES (left column): 40%, 60%, 65%, 75%, 80%, 100%
- Tier 2 CUSTOM CONFIGS (right column): HHKB, Corne, Sofle, Ferris Sweep, Cornix
"""

from PIL import Image
import os

# Keyboard layout mapping: (row, col) -> (layout_id, display_name)
KEYBOARDS = [
    # Tier 1 (left side, top to bottom)
    (0, 0, "macbook-us", "MacBook US"),
    (1, 0, "kinesis-360", "Kinesis Advantage 360"),
    
    # Tier 2 ANSI SIZES (left column, top to bottom)
    (0, 1, "ansi-40", "40% ANSI"),
    (1, 1, "ansi-60", "60% ANSI"),
    (2, 1, "ansi-65", "65% ANSI"),
    (3, 1, "ansi-75", "75% ANSI"),
    (4, 1, "ansi-80", "80% TKL ANSI"),
    (5, 1, "ansi-100", "100% ANSI"),
    
    # Tier 2 CUSTOM CONFIGS (right column, top to bottom)
    (0, 2, "hhkb", "HHKB"),
    (1, 2, "corne", "Corne"),
    (2, 2, "sofle", "Sofle"),
    (3, 2, "ferris-sweep", "Ferris Sweep"),
    (4, 2, "cornix", "Cornix"),
]

def slice_keyboard_images(input_path: str, output_dir: str):
    """Slice the source image into individual keyboard illustrations."""
    img = Image.open(input_path)
    width, height = img.size
    
    # Estimate grid layout: 3 columns, 6 rows
    # Based on description: Tier 1 (2 rows), ANSI (6 rows), Custom (5 rows)
    cols = 3
    rows = 6
    
    col_width = width / cols
    row_height = height / rows
    
    os.makedirs(output_dir, exist_ok=True)
    
    for row, col, layout_id, display_name in KEYBOARDS:
        # Calculate crop box (with some padding)
        left = int(col * col_width)
        top = int(row * row_height)
        right = int((col + 1) * col_width)
        bottom = int((row + 1) * row_height)
        
        # Crop the image
        cropped = img.crop((left, top, right, bottom))
        
        # Save as PNG
        output_path = os.path.join(output_dir, f"{layout_id}.png")
        cropped.save(output_path, "PNG")
        print(f"Saved {display_name} -> {output_path} ({cropped.size[0]}x{cropped.size[1]})")

if __name__ == "__main__":
    input_path = "/Users/malpern/.cursor/projects/Users-malpern-local-code-KeyPath/assets/Gemini_Generated_Image_4jx6qo4jx6qo4jx6-d10192bd-9a9d-4807-a450-77fb78054aed.png"
    output_dir = "/Users/malpern/local-code/KeyPath/Sources/KeyPathAppKit/Resources/KeyboardIllustrations"
    
    slice_keyboard_images(input_path, output_dir)
    print(f"\nExtracted {len(KEYBOARDS)} keyboard illustrations to {output_dir}")
