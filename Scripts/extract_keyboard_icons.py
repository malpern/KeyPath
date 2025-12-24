#!/usr/bin/env python3
"""
Extract individual keyboard icons from a grid image.
Each keyboard is cropped tightly, resized to uniform dimensions, and saved as PNG.

The image contains keyboards in a grid layout. This script:
1. Detects/crops each keyboard tightly (removes boxes/backgrounds)
2. Resizes all to the same dimensions
3. Saves with standardized names matching layout IDs
"""

from PIL import Image, ImageEnhance
import os

IMAGE_PATH = "/Users/malpern/.cursor/projects/Users-malpern-local-code-KeyPath/assets/Gemini_Generated_Image_gndsoagndsoagnds-5ec340c1-b2af-456e-b811-df6d7fbf46d4.png"
OUTPUT_DIR = "/Users/malpern/local-code/KeyPath/Sources/KeyPathAppKit/Resources/KeyboardIllustrations"

# Mapping: Display name -> layout ID
KEYBOARD_NAMES = {
    "MacBook US keyboard": "macbook-us",
    "Kinesis Advantage 360": "kinesis-360",
    "40% ANSI keyboard (41 keys)": "ansi-40",
    "60% ANSI keyboard (62 keys)": "ansi-60",
    "65% ANSI keyboard (68 keys)": "ansi-65",
    "75% ANSI keyboard (84 keys)": "ansi-75",
    "80% TKL ANSI keyboard (87 keys)": "ansi-80",
    "100% ANSI keyboard (104 keys)": "ansi-100",  # May not be in image
    "HHKB layout keyboard": "hhkb",
    "Corne split keyboard": "corne",
    "Sofle split keyboard": "sofle",
    "Ferris Sweep split keyboard": "ferris-sweep",
    "Cornix split keyboard": "cornix",
}

# Grid layout: 4 rows x 3 columns based on image description
# Order: top-to-bottom, left-to-right
KEYBOARD_ORDER = [
    # Row 1
    "MacBook US keyboard",
    "Kinesis Advantage 360",
    "40% ANSI keyboard (41 keys)",
    # Row 2
    "60% ANSI keyboard (62 keys)",
    "65% ANSI keyboard (68 keys)",
    "75% ANSI keyboard (84 keys)",
    # Row 3
    "80% TKL ANSI keyboard (87 keys)",
    "Corne split keyboard",  # First split keyboard
    "Sofle split keyboard",   # Second split keyboard
    # Row 4
    "Ferris Sweep split keyboard",  # Third split keyboard
    "Cornix split keyboard",        # Fourth split keyboard
    "HHKB layout keyboard",         # Likely the 12th keyboard
]

# Standard output size (will use largest keyboard as reference, or this if specified)
STANDARD_WIDTH = 400
STANDARD_HEIGHT = 300

def find_content_bounds(img_region):
    """
    Find tight bounding box around keyboard content.
    Removes white space, boxes, and backgrounds.
    """
    # Convert to grayscale for analysis
    gray = img_region.convert('L')
    pixels = gray.load()
    width, height = gray.size
    
    # Threshold for content detection
    # Lower values = more sensitive (includes lighter grays)
    threshold = 250  # Very high threshold to detect any non-white content
    
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

def extract_keyboard(img, row, col, total_rows, total_cols):
    """
    Extract a keyboard from the grid using row/col position.
    """
    width, height = img.size
    
    # Calculate grid cell dimensions
    col_width = width / total_cols
    row_height = height / total_rows
    
    # Calculate approximate region
    x1 = int(col * col_width)
    y1 = int(row * row_height)
    x2 = int((col + 1) * col_width)
    y2 = int((row + 1) * row_height)
    
    # Crop region
    region = img.crop((x1, y1, x2, y2))
    
    # Find tight content bounds
    tight_bounds = find_content_bounds(region)
    left, top, right, bottom = tight_bounds
    
    # Crop to tight bounds
    keyboard = region.crop((left, top, right, bottom))
    
    return keyboard

def resize_to_standard(keyboard_img, target_width, target_height):
    """
    Resize keyboard image to standard dimensions while preserving aspect ratio.
    Pads with transparency if needed.
    """
    # Calculate scaling to fit within target dimensions
    scale_w = target_width / keyboard_img.width
    scale_h = target_height / keyboard_img.height
    scale = min(scale_w, scale_h)  # Use smaller scale to fit within bounds
    
    # Resize maintaining aspect ratio
    new_width = int(keyboard_img.width * scale)
    new_height = int(keyboard_img.height * scale)
    resized = keyboard_img.resize((new_width, new_height), Image.Resampling.LANCZOS)
    
    # Create new image with transparency
    if keyboard_img.mode == 'RGBA':
        result = Image.new('RGBA', (target_width, target_height), (0, 0, 0, 0))
    else:
        result = Image.new('RGBA', (target_width, target_height), (0, 0, 0, 0))
        resized = resized.convert('RGBA')
    
    # Center the resized image
    x_offset = (target_width - new_width) // 2
    y_offset = (target_height - new_height) // 2
    result.paste(resized, (x_offset, y_offset), resized if resized.mode == 'RGBA' else None)
    
    return result

def main():
    if not os.path.exists(IMAGE_PATH):
        print(f"❌ Image not found: {IMAGE_PATH}")
        return
    
    img = Image.open(IMAGE_PATH)
    print(f"📐 Source image: {img.size[0]}x{img.size[1]} pixels\n")
    
    # Convert to RGBA if needed for transparency support
    if img.mode != 'RGBA':
        img = img.convert('RGBA')
    
    # Grid dimensions: 4 rows x 3 columns
    total_rows = 4
    total_cols = 3
    
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    
    print("🎨 Extracting keyboard icons...\n")
    
    # Track dimensions to determine standard size
    extracted_keyboards = []
    
    # Extract each keyboard
    for idx, display_name in enumerate(KEYBOARD_ORDER):
        row = idx // total_cols
        col = idx % total_cols
        
        keyboard = extract_keyboard(img, row, col, total_rows, total_cols)
        extracted_keyboards.append((display_name, keyboard))
        print(f"✓ Extracted {display_name}: {keyboard.size[0]}x{keyboard.size[1]} pixels")
    
    # Find maximum dimensions for standard size
    max_width = max(k.width for _, k in extracted_keyboards)
    max_height = max(k.height for _, k in extracted_keyboards)
    
    # Use a standard size that accommodates all keyboards
    # Add some padding for visual breathing room
    standard_width = max(STANDARD_WIDTH, max_width + 40)
    standard_height = max(STANDARD_HEIGHT, max_height + 40)
    
    print(f"\n📏 Standard size: {standard_width}x{standard_height} pixels\n")
    
    # Resize and save each keyboard
    for display_name, keyboard in extracted_keyboards:
        layout_id = KEYBOARD_NAMES.get(display_name)
        if not layout_id:
            print(f"⚠️  No layout ID for '{display_name}', skipping")
            continue
        
        # Resize to standard dimensions
        standardized = resize_to_standard(keyboard, standard_width, standard_height)
        
        # Save
        output_path = os.path.join(OUTPUT_DIR, f"{layout_id}.png")
        standardized.save(output_path, "PNG", optimize=True)
        print(f"✓ Saved {layout_id:20s} -> {standardized.size[0]}x{standardized.size[1]} pixels")
    
    print(f"\n✅ Processed {len(extracted_keyboards)} keyboards")
    print(f"   Output directory: {OUTPUT_DIR}")

if __name__ == "__main__":
    main()
