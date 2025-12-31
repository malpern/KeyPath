#!/usr/bin/env python3
"""
Extract individual keyboard images from a contact sheet with transparent backgrounds.
Uses a "magic wand" style flood-fill algorithm to remove the background.
All images are sized to a uniform canvas for consistent display in the UI.
"""

from PIL import Image
import numpy as np
from collections import deque
import os

# Target canvas size for all keyboard images (width x height)
# This aspect ratio works well for the drawer preview boxes
TARGET_WIDTH = 400
TARGET_HEIGHT = 140


def get_background_color(img):
    """Sample the background color from the corners of the image."""
    pixels = img.load()
    width, height = img.size
    
    # Sample corners
    corners = [
        pixels[5, 5],
        pixels[width - 6, 5],
        pixels[5, height - 6],
        pixels[width - 6, height - 6]
    ]
    
    # Average the corner colors (assuming they're all background)
    r = sum(c[0] for c in corners) // 4
    g = sum(c[1] for c in corners) // 4
    b = sum(c[2] for c in corners) // 4
    
    return (r, g, b)


def color_distance(c1, c2):
    """Calculate Euclidean distance between two RGB colors."""
    return ((c1[0] - c2[0]) ** 2 + (c1[1] - c2[1]) ** 2 + (c1[2] - c2[2]) ** 2) ** 0.5


def flood_fill_background(img, bg_color, tolerance=25):
    """
    Flood fill from edges to mark background pixels as transparent.
    Uses 8-connected neighbors for more thorough filling.
    """
    width, height = img.size
    pixels = img.load()
    
    # Create alpha mask (255 = opaque, 0 = transparent)
    alpha = [[255 for _ in range(width)] for _ in range(height)]
    visited = [[False for _ in range(width)] for _ in range(height)]
    
    # Start flood fill from all edge pixels
    queue = deque()
    
    # Add all edge pixels to queue
    for x in range(width):
        queue.append((x, 0))
        queue.append((x, height - 1))
    for y in range(height):
        queue.append((0, y))
        queue.append((width - 1, y))
    
    # 8-connected neighbors
    neighbors = [(-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1)]
    
    while queue:
        x, y = queue.popleft()
        
        if x < 0 or x >= width or y < 0 or y >= height:
            continue
        if visited[y][x]:
            continue
            
        visited[y][x] = True
        pixel = pixels[x, y]
        
        # Check if this pixel is close to background color
        if color_distance(pixel[:3], bg_color) <= tolerance:
            alpha[y][x] = 0  # Make transparent
            
            # Add neighbors to queue
            for dx, dy in neighbors:
                nx, ny = x + dx, y + dy
                if 0 <= nx < width and 0 <= ny < height and not visited[ny][nx]:
                    queue.append((nx, ny))
    
    return alpha


def apply_alpha_mask(img, alpha):
    """Apply alpha mask to image, creating RGBA output."""
    width, height = img.size
    pixels = img.load()
    
    # Create new RGBA image
    result = Image.new('RGBA', (width, height))
    result_pixels = result.load()
    
    for y in range(height):
        for x in range(width):
            r, g, b = pixels[x, y][:3]
            a = alpha[y][x]
            result_pixels[x, y] = (r, g, b, a)
    
    return result


def crop_to_content(img, padding=2):
    """Crop image to non-transparent content with optional padding."""
    # Get bounding box of non-transparent pixels
    bbox = img.getbbox()
    if bbox is None:
        return img
    
    # Add padding
    left = max(0, bbox[0] - padding)
    top = max(0, bbox[1] - padding)
    right = min(img.width, bbox[2] + padding)
    bottom = min(img.height, bbox[3] + padding)
    
    return img.crop((left, top, right, bottom))


def fit_to_canvas(img, target_width, target_height, padding=8):
    """
    Fit an image onto a uniform canvas size, centered.
    The image is scaled to fit within the canvas minus padding.
    """
    # Calculate available space
    available_width = target_width - (padding * 2)
    available_height = target_height - (padding * 2)
    
    # Calculate scale to fit
    scale_w = available_width / img.width
    scale_h = available_height / img.height
    scale = min(scale_w, scale_h)
    
    # Resize image
    new_width = int(img.width * scale)
    new_height = int(img.height * scale)
    resized = img.resize((new_width, new_height), Image.Resampling.LANCZOS)
    
    # Create transparent canvas
    canvas = Image.new('RGBA', (target_width, target_height), (0, 0, 0, 0))
    
    # Center the image on the canvas
    x = (target_width - new_width) // 2
    y = (target_height - new_height) // 2
    
    canvas.paste(resized, (x, y), resized)
    
    return canvas


def extract_keyboard_with_transparency(img, bg_color, tolerance=25):
    """Extract a keyboard image with transparent background."""
    # Flood fill to find background
    alpha = flood_fill_background(img, bg_color, tolerance)
    
    # Apply alpha mask
    result = apply_alpha_mask(img, alpha)
    
    # Crop to content
    result = crop_to_content(result)
    
    return result


def process_contact_sheet(input_path, output_dir, rows=5, cols=3, tolerance=25):
    """
    Process a contact sheet and extract individual keyboards with transparency.
    All images are resized to a uniform canvas size.
    """
    print(f"Loading contact sheet: {input_path}")
    img = Image.open(input_path).convert('RGB')
    width, height = img.size
    print(f"Image size: {width}x{height}")
    
    # Get background color
    bg_color = get_background_color(img)
    print(f"Detected background color: RGB{bg_color}")
    
    # Calculate cell dimensions
    cell_width = width // cols
    cell_height = height // rows
    print(f"Cell size: {cell_width}x{cell_height}")
    print(f"Target canvas size: {TARGET_WIDTH}x{TARGET_HEIGHT}")
    
    os.makedirs(output_dir, exist_ok=True)
    
    # Keyboard names mapping (row, col) -> (name, margins)
    # margins = (top, right, bottom, left) extra cropping to remove artifacts
    # Based on the contact sheet layout:
    # Row 0: Full-size, Kinesis-360, TKL (80%)
    # Row 1: 75%, HHKB, 65%
    # Row 2: 65% alt, 60%, 75% alt
    # Row 3: 40%, Corne split, Corne alt
    # Row 4: Sofle, Ferris Sweep, Cornix
    keyboard_config = {
        (0, 0): ("ansi-100", (15, 15, 10, 15)),      # Full-size
        (0, 1): ("kinesis-360", (10, 10, 10, 10)),   # Kinesis Advantage 360
        (0, 2): ("ansi-80", (15, 15, 10, 15)),       # TKL 80%
        (1, 0): ("ansi-75", (20, 15, 10, 15)),       # 75% - extra top margin
        (1, 1): ("hhkb", (15, 15, 10, 15)),          # HHKB-style
        (1, 2): ("ansi-65", (15, 15, 10, 15)),       # 65%
        (2, 0): ("ansi-65-alt", (15, 15, 10, 15)),   # 65% alternative (skip)
        (2, 1): ("ansi-60", (15, 15, 10, 15)),       # 60%
        (2, 2): ("ansi-75-alt", (15, 15, 10, 15)),   # 75% alternative (skip)
        (3, 0): ("ansi-40", (15, 15, 10, 15)),       # 40%
        (3, 1): ("corne", (15, 15, 10, 15)),         # Corne split
        (3, 2): ("corne-alt", (15, 15, 10, 15)),     # Corne alternative (skip)
        (4, 0): ("sofle", (15, 15, 15, 15)),         # Sofle
        (4, 1): ("ferris-sweep", (15, 15, 15, 15)),  # Ferris Sweep
        (4, 2): ("cornix", (15, 15, 15, 15)),        # Cornix
    }
    
    # Skip duplicates
    skip_names = {"ansi-65-alt", "ansi-75-alt", "corne-alt"}
    
    extracted = []
    for row in range(rows):
        for col in range(cols):
            config = keyboard_config.get((row, col))
            if config is None:
                continue
            
            name, margins = config
            if name in skip_names:
                continue
            
            top_margin, right_margin, bottom_margin, left_margin = margins
            
            # Calculate cell boundaries with margins
            x1 = col * cell_width + left_margin
            y1 = row * cell_height + top_margin
            x2 = (col + 1) * cell_width - right_margin
            y2 = (row + 1) * cell_height - bottom_margin
            
            print(f"Extracting {name} from ({x1},{y1}) to ({x2},{y2})...")
            
            # Crop cell with margins
            cell = img.crop((x1, y1, x2, y2))
            
            # Extract with transparency
            result = extract_keyboard_with_transparency(cell, bg_color, tolerance)
            
            # Fit to uniform canvas
            result = fit_to_canvas(result, TARGET_WIDTH, TARGET_HEIGHT)
            
            # Save
            output_path = os.path.join(output_dir, f"{name}.png")
            result.save(output_path, 'PNG')
            print(f"  Saved: {output_path} ({result.width}x{result.height})")
            extracted.append(name)
    
    return extracted


def process_single_keyboard(input_path, output_path, tolerance=25):
    """
    Process a single keyboard image with transparent background.
    The image is resized to the uniform canvas size.
    """
    print(f"Loading single keyboard: {input_path}")
    img = Image.open(input_path).convert('RGB')
    width, height = img.size
    print(f"Image size: {width}x{height}")
    
    # Get background color
    bg_color = get_background_color(img)
    print(f"Detected background color: RGB{bg_color}")
    
    # Extract with transparency
    result = extract_keyboard_with_transparency(img, bg_color, tolerance)
    
    # Fit to uniform canvas
    result = fit_to_canvas(result, TARGET_WIDTH, TARGET_HEIGHT)
    
    # Save
    result.save(output_path, 'PNG')
    print(f"Saved: {output_path} ({result.width}x{result.height})")
    
    return output_path


def main():
    base_dir = "/Users/malpern/local-code/KeyPath"
    assets_dir = os.path.join(base_dir, "assets/keyboards")
    output_dir = os.path.join(base_dir, "Sources/KeyPathAppKit/Resources/KeyboardIllustrations")
    
    # Process contact sheet
    contact_sheet = os.path.join(assets_dir, "contact-sheet.png")
    if os.path.exists(contact_sheet):
        print("\n" + "="*60)
        print("Processing contact sheet...")
        print("="*60)
        extracted = process_contact_sheet(contact_sheet, output_dir, rows=5, cols=3, tolerance=30)
        print(f"\nExtracted {len(extracted)} keyboards from contact sheet")
    
    # Process MacBook JIS separately
    macbook_jis = os.path.join(assets_dir, "macbook-jis-source.png")
    if os.path.exists(macbook_jis):
        print("\n" + "="*60)
        print("Processing MacBook JIS keyboard...")
        print("="*60)
        output_path = os.path.join(output_dir, "macbook-jis.png")
        process_single_keyboard(macbook_jis, output_path, tolerance=30)
    
    # Resize macbook-us to match
    macbook_us_path = os.path.join(output_dir, "macbook-us.png")
    if os.path.exists(macbook_us_path):
        print("\n" + "="*60)
        print("Resizing MacBook US keyboard...")
        print("="*60)
        img = Image.open(macbook_us_path)
        if img.mode != 'RGBA':
            img = img.convert('RGBA')
        if img.width != TARGET_WIDTH or img.height != TARGET_HEIGHT:
            result = fit_to_canvas(img, TARGET_WIDTH, TARGET_HEIGHT)
            result.save(macbook_us_path, 'PNG')
            print(f"Resized macbook-us.png to {TARGET_WIDTH}x{TARGET_HEIGHT}")
        else:
            print("macbook-us.png already correct size")
    
    print("\n" + "="*60)
    print("Extraction complete!")
    print(f"All images sized to {TARGET_WIDTH}x{TARGET_HEIGHT} for consistent display")
    print("="*60)


if __name__ == "__main__":
    main()
