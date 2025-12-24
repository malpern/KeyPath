#!/usr/bin/env python3
"""
Precise keyboard image slicer with manual coordinate refinement.

This script uses a combination of:
1. Image analysis to detect keyboard regions
2. Manual coordinate refinement for precision
3. Tight cropping to isolate each keyboard

The image is 2048x661 pixels with keyboards arranged in a grid.
"""

from PIL import Image, ImageEnhance
import os

IMAGE_WIDTH = 2048
IMAGE_HEIGHT = 661

# Manual keyboard coordinates: (left, top, right, bottom)
# These should be set by visually inspecting the image
# Format: layout_id: (x1, y1, x2, y2)
KEYBOARD_COORDS = {
    # Left column - Tier 1
    "macbook-us": None,      # Needs manual setting
    "kinesis-360": None,     # Needs manual setting
    
    # Middle column - ANSI sizes
    "ansi-40": None,
    "ansi-60": None,
    "ansi-65": None,
    "ansi-75": None,
    "ansi-80": None,
    "ansi-100": None,
    
    # Right column - Custom configs
    "hhkb": None,
    "corne": None,
    "sofle": None,
    "ferris-sweep": None,
    "cornix": None,
}

def find_tight_bounds(img_region):
    """
    Find tight bounding box around keyboard content.
    Removes white space and text areas.
    """
    # Convert to grayscale
    gray = img_region.convert('L')
    pixels = gray.load()
    width, height = gray.size
    
    # Find content bounds (non-white areas)
    # Use a threshold to distinguish keyboard from white background
    threshold = 230  # Adjust based on image contrast
    
    min_x, min_y = width, height
    max_x, max_y = 0, 0
    
    # Scan for content
    for y in range(height):
        for x in range(width):
            if pixels[x, y] < threshold:
                min_x = min(min_x, x)
                min_y = min(min_y, y)
                max_x = max(max_x, x)
                max_y = max(max_y, y)
    
    if max_x < min_x or max_y < min_y:
        # No content found, return full region
        return (0, 0, width, height)
    
    # Add small padding for visual breathing room
    padding = 8
    min_x = max(0, min_x - padding)
    min_y = max(0, min_y - padding)
    max_x = min(width, max_x + padding)
    max_y = min(height, max_y + padding)
    
    return (min_x, min_y, max_x, max_y)

def create_coordinate_helper(input_path, output_path):
    """
    Create a helper image with grid overlay to assist in coordinate identification.
    """
    img = Image.open(input_path)
    width, height = img.size
    
    # Create overlay with grid
    overlay = img.copy()
    from PIL import ImageDraw
    draw = ImageDraw.Draw(overlay)
    
    # Draw grid lines
    cols = 3
    rows = 6
    col_width = width / cols
    row_height = height / rows
    
    # Vertical lines
    for i in range(cols + 1):
        x = int(i * col_width)
        draw.line([(x, 0), (x, height)], fill=(255, 0, 0), width=2)
    
    # Horizontal lines
    for i in range(rows + 1):
        y = int(i * row_height)
        draw.line([(0, y), (width, y)], fill=(255, 0, 0), width=2)
    
    # Add coordinate labels at corners
    for col in range(cols):
        for row in range(rows):
            x = int(col * col_width)
            y = int(row * row_height)
            label = f"({x},{y})"
            draw.text((x + 5, y + 5), label, fill=(255, 0, 0))
    
    overlay.save(output_path)
    print(f"📐 Grid helper saved to: {output_path}")
    print("   Use this to identify precise coordinates for each keyboard")

def isolate_keyboard(input_path, output_dir, layout_id, coords):
    """Isolate a keyboard using precise coordinates."""
    img = Image.open(input_path)
    
    if coords is None:
        print(f"⚠️  Skipping {layout_id} (no coordinates)")
        return
    
    x1, y1, x2, y2 = coords
    
    # Validate bounds
    x1 = max(0, min(x1, img.width))
    y1 = max(0, min(y1, img.height))
    x2 = max(x1, min(x2, img.width))
    y2 = max(y1, min(y2, img.height))
    
    # Crop approximate region
    region = img.crop((x1, y1, x2, y2))
    
    # Find tight bounds
    tight = find_tight_bounds(region)
    left, top, right, bottom = tight
    
    # Crop to tight bounds
    keyboard = region.crop((left, top, right, bottom))
    
    # Save
    output_path = os.path.join(output_dir, f"{layout_id}.png")
    keyboard.save(output_path, "PNG", optimize=True)
    
    print(f"✓ {layout_id:20s} -> {keyboard.size[0]}x{keyboard.size[1]}")

def main():
    input_path = "/Users/malpern/.cursor/projects/Users-malpern-local-code-KeyPath/assets/image-46a51a28-6b48-4eee-bd37-f72062d180f3.png"
    output_dir = "/Users/malpern/local-code/KeyPath/Sources/KeyPathAppKit/Resources/KeyboardIllustrations"
    
    if not os.path.exists(input_path):
        print(f"❌ Image not found: {input_path}")
        return
    
    # Create grid helper
    helper_path = "/tmp/keyboard_grid_helper.png"
    create_coordinate_helper(input_path, helper_path)
    
    # Check if coordinates are set
    if all(c is None for c in KEYBOARD_COORDS.values()):
        print("\n⚠️  No keyboard coordinates set!")
        print("\nTo set coordinates:")
        print("1. Open the grid helper image: open /tmp/keyboard_grid_helper.png")
        print("2. For each keyboard, identify:")
        print("   - Top-left corner (x, y)")
        print("   - Bottom-right corner (x, y)")
        print("3. Update KEYBOARD_COORDS in this script")
        print("\nExample:")
        print('   "macbook-us": (50, 30, 450, 200),')
        return
    
    os.makedirs(output_dir, exist_ok=True)
    
    print("\n🎨 Isolating keyboards...\n")
    count = 0
    for layout_id, coords in KEYBOARD_COORDS.items():
        if coords is not None:
            isolate_keyboard(input_path, output_dir, layout_id, coords)
            count += 1
    
    print(f"\n✅ Processed {count} keyboards")

if __name__ == "__main__":
    main()
