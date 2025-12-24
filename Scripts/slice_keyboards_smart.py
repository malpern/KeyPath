#!/usr/bin/env python3
"""
Smart keyboard image slicer that isolates each keyboard with proper masking.

This script:
1. Analyzes the composite image to detect keyboard regions
2. Crops tightly around each keyboard (removes text and extra space)
3. Saves clean, isolated keyboard assets

The image is 2048x661 pixels. Based on the layout description:
- Left column: Tier 1 keyboards (MacBook US, Kinesis 360)
- Middle column: ANSI sizes (40%, 60%, 65%, 75%, 80%, 100%)
- Right column: Custom configs (HHKB, Corne, Sofle, Ferris Sweep, Cornix)
"""

from PIL import Image, ImageEnhance, ImageFilter
import os

# Image dimensions
IMAGE_WIDTH = 2048
IMAGE_HEIGHT = 661

# Estimated column widths (will be refined)
COL_WIDTH = IMAGE_WIDTH // 3  # ~682 pixels per column

# Keyboard layout order (as they appear in the image)
KEYBOARDS = [
    # Left column (Tier 1)
    ("macbook-us", 0, "MacBook US"),
    ("kinesis-360", 0, "Kinesis Advantage 360"),
    
    # Middle column (ANSI sizes) - approximate row positions
    ("ansi-40", 1, "40% ANSI"),
    ("ansi-60", 1, "60% ANSI"),
    ("ansi-65", 1, "65% ANSI"),
    ("ansi-75", 1, "75% ANSI"),
    ("ansi-80", 1, "80% ANSI"),
    ("ansi-100", 1, "100% ANSI"),
    
    # Right column (Custom configs)
    ("hhkb", 2, "HHKB"),
    ("corne", 2, "Corne"),
    ("sofle", 2, "Sofle"),
    ("ferris-sweep", 2, "Ferris Sweep"),
    ("cornix", 2, "Cornix"),
]

def detect_keyboard_in_region(img, col, row_index, total_in_col):
    """
    Detect keyboard bounds within a column region.
    Uses edge detection and content analysis.
    """
    # Calculate approximate region for this keyboard
    col_start = col * COL_WIDTH
    col_end = (col + 1) * COL_WIDTH
    
    # Estimate row height
    row_height = IMAGE_HEIGHT // max(6, total_in_col)  # At least 6 rows
    row_start = row_index * row_height
    row_end = (row_index + 1) * row_height
    
    # Crop region with some padding
    padding = 20
    x1 = max(0, col_start + padding)
    y1 = max(0, row_start + padding)
    x2 = min(IMAGE_WIDTH, col_end - padding)
    y2 = min(IMAGE_HEIGHT, row_end - padding)
    
    region = img.crop((x1, y1, x2, y2))
    
    # Convert to grayscale
    gray = region.convert('L')
    
    # Enhance contrast
    enhancer = ImageEnhance.Contrast(gray)
    gray = enhancer.enhance(1.5)
    
    # Find content bounds (non-white areas)
    pixels = gray.load()
    width, height = gray.size
    
    # Find bounding box of content
    min_x, min_y = width, height
    max_x, max_y = 0, 0
    
    threshold = 240  # Below this is considered content (not white background)
    
    for y in range(height):
        for x in range(width):
            if pixels[x, y] < threshold:
                min_x = min(min_x, x)
                min_y = min(min_y, y)
                max_x = max(max_x, x)
                max_y = max(max_y, y)
    
    if max_x < min_x or max_y < min_y:
        # No content found, return approximate bounds
        return (x1, y1, x2, y2)
    
    # Add small padding
    pad = 5
    min_x = max(0, min_x - pad)
    min_y = max(0, min_y - pad)
    max_x = min(width, max_x + pad)
    max_y = min(height, max_y + pad)
    
    # Convert back to full image coordinates
    return (x1 + min_x, y1 + min_y, x1 + max_x, y1 + max_y)

def isolate_keyboard(img, layout_id, bounds):
    """Crop and isolate a keyboard."""
    x1, y1, x2, y2 = bounds
    keyboard = img.crop((x1, y1, x2, y2))
    return keyboard

def main():
    input_path = "/Users/malpern/.cursor/projects/Users-malpern-local-code-KeyPath/assets/image-46a51a28-6b48-4eee-bd37-f72062d180f3.png"
    output_dir = "/Users/malpern/local-code/KeyPath/Sources/KeyPathAppKit/Resources/KeyboardIllustrations"
    
    if not os.path.exists(input_path):
        print(f"❌ Image not found: {input_path}")
        return
    
    img = Image.open(input_path)
    os.makedirs(output_dir, exist_ok=True)
    
    print("🎨 Isolating keyboards with smart detection...\n")
    
    # Group keyboards by column
    keyboards_by_col = {}
    for layout_id, col, name in KEYBOARDS:
        if col not in keyboards_by_col:
            keyboards_by_col[col] = []
        keyboards_by_col[col].append((layout_id, name))
    
    # Process each keyboard
    for layout_id, col, name in KEYBOARDS:
        # Find row index within column
        col_keyboards = keyboards_by_col[col]
        row_index = next(i for i, (lid, _) in enumerate(col_keyboards) if lid == layout_id)
        total_in_col = len(col_keyboards)
        
        # Detect bounds
        bounds = detect_keyboard_in_region(img, col, row_index, total_in_col)
        
        # Isolate keyboard
        keyboard = isolate_keyboard(img, layout_id, bounds)
        
        # Save
        output_path = os.path.join(output_dir, f"{layout_id}.png")
        keyboard.save(output_path, "PNG", optimize=True)
        
        print(f"✓ {layout_id:20s} -> {output_path}")
        print(f"  Bounds: {bounds}, Size: {keyboard.size[0]}x{keyboard.size[1]}")
    
    print(f"\n✅ Processed {len(KEYBOARDS)} keyboards")

if __name__ == "__main__":
    main()
