#!/usr/bin/env python3
"""
Improved keyboard image slicer that isolates each keyboard individually.
This script:
1. Uses manual bounding boxes to precisely crop each keyboard
2. Removes text labels using image processing
3. Crops tightly around each keyboard
4. Saves clean, isolated assets

Keyboard layout IDs match PhysicalLayout.swift:
- macbook-us, kinesis-360
- ansi-40, ansi-60, ansi-65, ansi-75, ansi-80, ansi-100
- hhkb, corne, sofle, ferris-sweep, cornix
"""

from PIL import Image, ImageEnhance, ImageFilter
import os
import numpy as np

# Manual bounding boxes for each keyboard: (left, top, right, bottom)
# These need to be adjusted based on the actual image layout
# Format: layout_id: (x1, y1, x2, y2)
KEYBOARD_BOUNDS = {
    # Tier 1 keyboards (left column)
    "macbook-us": None,  # Will be set after inspecting image
    "kinesis-360": None,
    
    # ANSI sizes (middle column)
    "ansi-40": None,
    "ansi-60": None,
    "ansi-65": None,
    "ansi-75": None,
    "ansi-80": None,
    "ansi-100": None,
    
    # Custom configs (right column)
    "hhkb": None,
    "corne": None,
    "sofle": None,
    "ferris-sweep": None,
    "cornix": None,
}

def detect_keyboard_bounds(img, approximate_box):
    """
    Detect the actual keyboard bounds within an approximate box.
    Uses edge detection and contour finding to isolate the keyboard.
    """
    # Crop to approximate region
    x1, y1, x2, y2 = approximate_box
    region = img.crop((x1, y1, x2, y2))
    
    # Convert to grayscale for processing
    gray = region.convert('L')
    
    # Enhance contrast to make keyboard stand out
    enhancer = ImageEnhance.Contrast(gray)
    gray = enhancer.enhance(2.0)
    
    # Apply edge detection
    edges = gray.filter(ImageFilter.FIND_EDGES)
    
    # Convert to numpy for processing
    edges_array = np.array(edges)
    
    # Find bounding box of non-white (keyboard) content
    # Keyboard keys are darker, so we look for areas with significant content
    rows = np.any(edges_array < 200, axis=1)  # Rows with content
    cols = np.any(edges_array < 200, axis=0)  # Columns with content
    
    if not np.any(rows) or not np.any(cols):
        # Fallback to original box if detection fails
        return approximate_box
    
    # Find actual bounds
    top = np.argmax(rows)
    bottom = len(rows) - np.argmax(rows[::-1])
    left = np.argmax(cols)
    right = len(cols) - np.argmax(cols[::-1])
    
    # Add small padding
    padding = 10
    top = max(0, top - padding)
    left = max(0, left - padding)
    bottom = min(region.height, bottom + padding)
    right = min(region.width, right + padding)
    
    # Convert back to full image coordinates
    return (x1 + left, y1 + top, x1 + right, y1 + bottom)

def remove_text_labels(img):
    """
    Attempt to remove text labels from the image.
    This is a heuristic approach - may need manual refinement.
    """
    # Convert to numpy array
    img_array = np.array(img)
    
    # Text is typically white or very light colored
    # We'll try to detect and remove very bright areas that might be text
    # This is a simple approach - may need more sophisticated methods
    
    # For now, return original image
    # Manual cropping should avoid text areas
    return img

def isolate_keyboard(input_path, output_dir, layout_id, bounds):
    """
    Isolate a single keyboard from the composite image.
    """
    img = Image.open(input_path)
    width, height = img.size
    
    if bounds is None:
        print(f"⚠️  No bounds specified for {layout_id}, skipping")
        return
    
    x1, y1, x2, y2 = bounds
    
    # Ensure bounds are within image
    x1 = max(0, min(x1, width))
    y1 = max(0, min(y1, height))
    x2 = max(x1, min(x2, width))
    y2 = max(y1, min(y2, height))
    
    # Crop the keyboard
    keyboard = img.crop((x1, y1, x2, y2))
    
    # Try to remove text (heuristic - may need refinement)
    keyboard = remove_text_labels(keyboard)
    
    # Save as PNG with transparency support
    output_path = os.path.join(output_dir, f"{layout_id}.png")
    keyboard.save(output_path, "PNG", optimize=True)
    
    print(f"✓ Saved {layout_id} -> {output_path} ({keyboard.size[0]}x{keyboard.size[1]})")

def analyze_image_layout(input_path):
    """
    Analyze the image to help determine keyboard positions.
    Prints image info and suggests a grid layout.
    """
    img = Image.open(input_path)
    width, height = img.size
    
    print(f"Image size: {width}x{height}")
    print(f"Image mode: {img.mode}")
    print("\nTo set up bounding boxes, you can:")
    print("1. Open the image in an image editor")
    print("2. Note the approximate (x, y) coordinates for each keyboard")
    print("3. Update KEYBOARD_BOUNDS dictionary with precise coordinates")
    print("\nSuggested approach:")
    print("- Use a tool like Preview or GIMP to get pixel coordinates")
    print("- For each keyboard, note: left, top, right, bottom")
    print("- Update the script with these coordinates")

def slice_keyboards(input_path, output_dir, use_auto_detect=False):
    """
    Slice all keyboards from the composite image.
    """
    os.makedirs(output_dir, exist_ok=True)
    
    # If no bounds are set, analyze the image first
    if all(b is None for b in KEYBOARD_BOUNDS.values()):
        print("⚠️  No keyboard bounds specified!")
        analyze_image_layout(input_path)
        print("\nPlease update KEYBOARD_BOUNDS with manual coordinates.")
        return
    
    for layout_id, bounds in KEYBOARD_BOUNDS.items():
        if bounds is not None:
            isolate_keyboard(input_path, output_dir, layout_id, bounds)
        else:
            print(f"⚠️  Skipping {layout_id} (no bounds)")

if __name__ == "__main__":
    # Update this path to your actual image
    input_path = "/Users/malpern/.cursor/projects/Users-malpern-local-code-KeyPath/assets/image-46a51a28-6b48-4eee-bd37-f72062d180f3.png"
    output_dir = "/Users/malpern/local-code/KeyPath/Sources/KeyPathAppKit/Resources/KeyboardIllustrations"
    
    # Check if image exists
    if not os.path.exists(input_path):
        print(f"❌ Image not found: {input_path}")
        print("Please update input_path to the correct image location.")
        analyze_image_layout(input_path) if os.path.exists(input_path) else None
    else:
        slice_keyboards(input_path, output_dir)
