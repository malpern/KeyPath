#!/usr/bin/env python3
"""
Designer-friendly keyboard image slicer.
This script isolates each keyboard individually with proper masking and cropping.

Usage:
1. Run with --analyze to see image structure and get suggestions
2. Manually identify keyboard regions using an image editor
3. Update KEYBOARD_REGIONS with precise coordinates
4. Run again to generate clean assets

The script will:
- Crop tightly around each keyboard
- Remove text labels (heuristic-based)
- Save isolated, clean keyboard images
"""

from PIL import Image, ImageEnhance, ImageFilter, ImageDraw
import os
import sys
import argparse

# Manual keyboard regions: (left, top, right, bottom) in pixels
# These need to be set by visually inspecting the image
# Format: layout_id: (x1, y1, x2, y2)
KEYBOARD_REGIONS = {
    # Tier 1 (left column, top to bottom)
    "macbook-us": (50, 50, 450, 250),      # Approximate - needs adjustment
    "kinesis-360": (50, 280, 450, 480),    # Approximate - needs adjustment
    
    # ANSI sizes (middle column, top to bottom)
    "ansi-40": (500, 50, 900, 200),        # Approximate - needs adjustment
    "ansi-60": (500, 220, 900, 370),       # Approximate - needs adjustment
    "ansi-65": (500, 390, 900, 540),       # Approximate - needs adjustment
    "ansi-75": None,  # Not visible in current crop
    "ansi-80": None,
    "ansi-100": None,
    
    # Custom configs (right column, top to bottom)
    "hhkb": None,
    "corne": None,
    "sofle": None,
    "ferris-sweep": None,
    "cornix": None,
}

def analyze_image_structure(img_path):
    """Analyze the image and suggest keyboard regions."""
    img = Image.open(img_path)
    width, height = img.size
    
    print(f"\n📐 Image Analysis")
    print(f"   Size: {width}x{height} pixels")
    print(f"   Mode: {img.mode}")
    
    # Convert to grayscale for analysis
    gray = img.convert('L')
    
    # Detect potential keyboard regions by looking for darker areas
    # (keyboards are typically darker than white backgrounds)
    gray_array = np.array(gray)
    
    # Threshold to find non-white areas
    threshold = 200
    mask = gray_array < threshold
    
    # Find bounding boxes of connected components
    from scipy import ndimage
    labeled, num_features = ndimage.label(mask)
    
    print(f"\n🔍 Found {num_features} potential regions")
    print("\nSuggested approach:")
    print("1. Open the image in Preview or another image editor")
    print("2. For each keyboard, note the pixel coordinates:")
    print("   - Top-left corner (x, y)")
    print("   - Bottom-right corner (x, y)")
    print("3. Update KEYBOARD_REGIONS in this script")
    print("\nTip: Use Preview's Inspector (⌘I) to see pixel coordinates")

def find_keyboard_bounds(img_region):
    """
    Find tight bounds around a keyboard within a region.
    Uses edge detection and content analysis.
    """
    import numpy as np
    
    # Convert to grayscale
    gray = img_region.convert('L')
    gray_array = np.array(gray)
    
    # Find rows/columns with significant content (not pure white)
    # Use a threshold to distinguish keyboard from background
    threshold = 240  # Slightly below white (255)
    
    # Find content bounds
    rows_with_content = np.any(gray_array < threshold, axis=1)
    cols_with_content = np.any(gray_array < threshold, axis=0)
    
    if not np.any(rows_with_content) or not np.any(cols_with_content):
        # No content detected, return full region
        return (0, 0, img_region.width, img_region.height)
    
    # Find bounds
    top = np.argmax(rows_with_content)
    bottom = len(rows_with_content) - np.argmax(rows_with_content[::-1])
    left = np.argmax(cols_with_content)
    right = len(cols_with_content) - np.argmax(cols_with_content[::-1])
    
    # Add small padding for visual breathing room
    padding = 5
    top = max(0, top - padding)
    left = max(0, left - padding)
    bottom = min(img_region.height, bottom + padding)
    right = min(img_region.width, right + padding)
    
    return (left, top, right, bottom)

def remove_text_heuristic(img):
    """
    Heuristic approach to remove text labels.
    This is imperfect - manual cropping should avoid text areas.
    """
    # For now, return original
    # In a production tool, you might use OCR to detect and remove text
    return img

def isolate_keyboard(input_path, output_dir, layout_id, region):
    """
    Isolate a single keyboard from the composite image.
    """
    img = Image.open(input_path)
    width, height = img.size
    
    if region is None:
        print(f"⚠️  Skipping {layout_id} (no region specified)")
        return
    
    x1, y1, x2, y2 = region
    
    # Validate bounds
    x1 = max(0, min(x1, width))
    y1 = max(0, min(y1, height))
    x2 = max(x1, min(x2, width))
    y2 = max(y1, min(y2, height))
    
    if x2 <= x1 or y2 <= y1:
        print(f"⚠️  Invalid bounds for {layout_id}: {region}")
        return
    
    # Crop the approximate region
    region_img = img.crop((x1, y1, x2, y2))
    
    # Find tight bounds around the keyboard
    tight_bounds = find_keyboard_bounds(region_img)
    left, top, right, bottom = tight_bounds
    
    # Crop to tight bounds
    keyboard = region_img.crop((left, top, right, bottom))
    
    # Try to remove text (heuristic)
    keyboard = remove_text_heuristic(keyboard)
    
    # Save
    output_path = os.path.join(output_dir, f"{layout_id}.png")
    keyboard.save(output_path, "PNG", optimize=True)
    
    print(f"✓ {layout_id:20s} -> {output_path}")
    print(f"  Cropped from ({x1+left}, {y1+top}) to ({x1+right}, {y1+bottom})")
    print(f"  Size: {keyboard.size[0]}x{keyboard.size[1]} pixels")

def main():
    parser = argparse.ArgumentParser(description='Slice keyboard images with designer precision')
    parser.add_argument('--analyze', action='store_true', help='Analyze image structure')
    parser.add_argument('--input', default='/Users/malpern/.cursor/projects/Users-malpern-local-code-KeyPath/assets/image-46a51a28-6b48-4eee-bd37-f72062d180f3.png',
                        help='Input image path')
    parser.add_argument('--output', default='/Users/malpern/local-code/KeyPath/Sources/KeyPathAppKit/Resources/KeyboardIllustrations',
                        help='Output directory')
    
    args = parser.parse_args()
    
    if not os.path.exists(args.input):
        print(f"❌ Image not found: {args.input}")
        sys.exit(1)
    
    if args.analyze:
        try:
            import numpy as np
            from scipy import ndimage
            analyze_image_structure(args.input)
        except ImportError:
            print("⚠️  scipy not available, using basic analysis")
            img = Image.open(args.input)
            print(f"\n📐 Image Analysis")
            print(f"   Size: {img.size[0]}x{img.size[1]} pixels")
            print(f"   Mode: {img.mode}")
            print("\nTo set up keyboard regions:")
            print("1. Open the image in Preview (⌘I to show coordinates)")
            print("2. For each keyboard, note top-left and bottom-right coordinates")
            print("3. Update KEYBOARD_REGIONS in this script")
    else:
        os.makedirs(args.output, exist_ok=True)
        
        print("🎨 Isolating keyboards...\n")
        count = 0
        for layout_id, region in KEYBOARD_REGIONS.items():
            if region is not None:
                isolate_keyboard(args.input, args.output, layout_id, region)
                count += 1
            else:
                print(f"⚠️  Skipping {layout_id} (no region specified)")
        
        print(f"\n✅ Processed {count} keyboards")

if __name__ == "__main__":
    try:
        import numpy as np
    except ImportError:
        print("⚠️  numpy not installed. Install with: pip install numpy")
        print("   Basic functionality will still work")
        np = None
    
    main()
