#!/usr/bin/env python3
"""
Final keyboard image slicer - isolates each keyboard with designer precision.

This script requires manual coordinate input for each keyboard.
The coordinates should be set by visually inspecting the image and identifying
the exact bounds of each keyboard (excluding labels and other keyboards).

Usage:
1. Run this script to see current status
2. Visually inspect the source image
3. Update KEYBOARD_COORDS with precise (left, top, right, bottom) coordinates
4. Run again to generate clean assets

The script will:
- Crop tightly around each keyboard
- Remove white space
- Save isolated PNG files
"""

from PIL import Image
import os

IMAGE_PATH = "/Users/malpern/.cursor/projects/Users-malpern-local-code-KeyPath/assets/Gemini_Generated_Image_dxfhgdxfhgdxfhgd-edc0e053-49e4-43e2-8c75-23330f8ee072.png"
OUTPUT_DIR = "/Users/malpern/local-code/KeyPath/Sources/KeyPathAppKit/Resources/KeyboardIllustrations"

# PRECISE COORDINATES FOR EACH KEYBOARD
# Format: (left, top, right, bottom) in pixels
# Extracted from image analysis - art_bbox converted to (x, y, x+w, y+h)
KEYBOARD_COORDS = {
    # Left column - Tier 1 keyboards
    "macbook-us": (48, 99, 443, 243),        # art_bbox: {x:48, y:99, w:395, h:144}
    "kinesis-360": (290, 99, 582, 292),     # art_bbox: {x:290, y:99, w:292, h:193}
    
    # Middle column - ANSI sizes  
    "ansi-40": (541, 122, 725, 185),        # art_bbox: {x:541, y:122, w:184, h:63}
    "ansi-60": (541, 219, 760, 294),        # art_bbox: {x:541, y:219, w:219, h:75}
    "ansi-65": (541, 337, 776, 412),        # art_bbox: {x:541, y:337, w:235, h:75}
    "ansi-75": (541, 454, 821, 543),        # art_bbox: {x:541, y:454, w:280, h:89}
    "ansi-80": (541, 591, 867, 680),        # art_bbox: {x:541, y:591, w:326, h:89}
    "ansi-100": (541, 728, 916, 832),       # art_bbox: {x:541, y:728, w:375, h:104} - clamped to image height
    
    # Right column - Custom configs
    "hhkb": (820, 122, 1077, 201),          # art_bbox: {x:820, y:122, w:257, h:79}
    "corne": (820, 240, 1077, 344),        # art_bbox: {x:820, y:240, w:257, h:104}
    "sofle": (820, 388, 1102, 509),        # art_bbox: {x:820, y:388, w:282, h:121}
    "ferris-sweep": (820, 550, 1077, 637), # art_bbox: {x:820, y:550, w:257, h:87}
    "cornix": (820, 688, 1110, 792),       # art_bbox: {x:820, y:688, w:290, h:104} - clamped to image height
}

def find_content_bounds(img_region):
    """
    Find tight bounding box around keyboard content.
    Removes white space and background.
    """
    # Convert to grayscale for analysis
    gray = img_region.convert('L')
    pixels = gray.load()
    width, height = gray.size
    
    # Threshold for content detection (adjust based on image)
    # Lower values = more sensitive (includes lighter grays)
    threshold = 240
    
    # Find bounding box of content
    min_x, min_y = width, height
    max_x, max_y = 0, 0
    
    found_content = False
    for y in range(height):
        for x in range(width):
            if pixels[x, y] < threshold:
                found_content = True
                min_x = min(min_x, x)
                min_y = min(min_y, y)
                max_x = max(max_x, x)
                max_y = max(max_y, y)
    
    if not found_content:
        # No content detected, return full region
        return (0, 0, width, height)
    
    # Add small padding for visual breathing room
    padding = 10
    min_x = max(0, min_x - padding)
    min_y = max(0, min_y - padding)
    max_x = min(width, max_x + padding)
    max_y = min(height, max_y + padding)
    
    return (min_x, min_y, max_x, max_y)

def isolate_keyboard(input_path, output_dir, layout_id, approximate_coords):
    """
    Isolate a keyboard using approximate coordinates, then tighten the crop.
    """
    img = Image.open(input_path)
    
    if approximate_coords is None:
        return None
    
    x1, y1, x2, y2 = approximate_coords
    
    # Validate and clamp to image bounds
    x1 = max(0, min(x1, img.width))
    y1 = max(0, min(y1, img.height))
    x2 = max(x1, min(x2, img.width))
    y2 = max(y1, min(y2, img.height))
    
    if x2 <= x1 or y2 <= y1:
        print(f"⚠️  Invalid coordinates for {layout_id}: {approximate_coords} (clamped to {x1},{y1},{x2},{y2})")
        # Still try to process with clamped coordinates
        if x2 > x1 and y2 > y1:
            pass  # Continue with clamped coordinates
        else:
            return None
    
    # Crop approximate region
    region = img.crop((x1, y1, x2, y2))
    
    # Find tight content bounds
    tight_bounds = find_content_bounds(region)
    left, top, right, bottom = tight_bounds
    
    # Crop to tight bounds
    keyboard = region.crop((left, top, right, bottom))
    
    # Save
    output_path = os.path.join(output_dir, f"{layout_id}.png")
    keyboard.save(output_path, "PNG", optimize=True)
    
    return keyboard

def main():
    if not os.path.exists(IMAGE_PATH):
        print(f"❌ Image not found: {IMAGE_PATH}")
        return
    
    img = Image.open(IMAGE_PATH)
    print(f"📐 Source image: {img.size[0]}x{img.size[1]} pixels\n")
    
    # Check if coordinates are set
    unset = [k for k, v in KEYBOARD_COORDS.items() if v is None]
    if unset:
        print(f"⚠️  {len(unset)} keyboards need coordinates:")
        for k in unset:
            print(f"   - {k}")
        print("\nTo set coordinates:")
        print("1. Open the image in Preview: open " + IMAGE_PATH)
        print("2. Enable Inspector: View > Show Inspector (⌘I)")
        print("3. For each keyboard:")
        print("   - Note top-left corner (x, y)")
        print("   - Note bottom-right corner (x, y)")
        print("   - Update KEYBOARD_COORDS in this script")
        print("\nExample:")
        print('   "macbook-us": (50, 30, 450, 200),')
        return
    
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    
    print("🎨 Isolating keyboards...\n")
    count = 0
    for layout_id, coords in KEYBOARD_COORDS.items():
        keyboard = isolate_keyboard(IMAGE_PATH, OUTPUT_DIR, layout_id, coords)
        if keyboard:
            print(f"✓ {layout_id:20s} -> {keyboard.size[0]}x{keyboard.size[1]} pixels")
            count += 1
    
    print(f"\n✅ Processed {count} keyboards")
    print(f"   Output directory: {OUTPUT_DIR}")

if __name__ == "__main__":
    main()
