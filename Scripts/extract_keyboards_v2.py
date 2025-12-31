#!/usr/bin/env python3
"""
Extract keyboard images from contact sheet with careful magic wand background removal.
Uses LOW tolerance to avoid eating into the keyboard images.
"""

from PIL import Image
import os
import math

# Target output size for all images
TARGET_WIDTH = 400
TARGET_HEIGHT = 140

def get_background_color(img):
    """Sample corners to get background color."""
    w, h = img.size
    corners = [
        img.getpixel((5, 5)),
        img.getpixel((w - 5, 5)),
        img.getpixel((5, h - 5)),
        img.getpixel((w - 5, h - 5)),
    ]
    # Average the corners
    r = sum(c[0] for c in corners) // 4
    g = sum(c[1] for c in corners) // 4
    b = sum(c[2] for c in corners) // 4
    return (r, g, b)

def color_distance(c1, c2):
    """Euclidean distance between two RGB colors."""
    return math.sqrt(sum((a - b) ** 2 for a, b in zip(c1, c2)))

def flood_fill_background(img, bg_color, tolerance=12):
    """
    Flood fill from edges to mark background pixels.
    Uses LOW tolerance (12) to be very conservative and not eat into keyboards.
    """
    w, h = img.size
    pixels = img.load()
    
    # Create alpha mask (255 = opaque, 0 = transparent)
    alpha = Image.new('L', (w, h), 255)
    alpha_pixels = alpha.load()
    
    # Track visited pixels
    visited = set()
    
    # Start from all edge pixels
    queue = []
    for x in range(w):
        queue.append((x, 0))
        queue.append((x, h - 1))
    for y in range(h):
        queue.append((0, y))
        queue.append((w - 1, y))
    
    # 8-connected flood fill
    directions = [(-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1)]
    
    while queue:
        x, y = queue.pop(0)
        
        if (x, y) in visited:
            continue
        if x < 0 or x >= w or y < 0 or y >= h:
            continue
            
        visited.add((x, y))
        
        pixel = pixels[x, y]
        if len(pixel) == 4:
            pixel = pixel[:3]
        
        dist = color_distance(pixel, bg_color)
        
        if dist <= tolerance:
            alpha_pixels[x, y] = 0  # Make transparent
            for dx, dy in directions:
                nx, ny = x + dx, y + dy
                if (nx, ny) not in visited:
                    queue.append((nx, ny))
    
    return alpha

def apply_alpha_mask(img, alpha):
    """Convert RGB image to RGBA with alpha mask."""
    if img.mode != 'RGB':
        img = img.convert('RGB')
    rgba = img.copy()
    rgba.putalpha(alpha)
    return rgba

def crop_to_content(img, padding=2):
    """Crop image to bounding box of non-transparent content."""
    bbox = img.getbbox()
    if bbox:
        left, top, right, bottom = bbox
        # Add padding
        left = max(0, left - padding)
        top = max(0, top - padding)
        right = min(img.size[0], right + padding)
        bottom = min(img.size[1], bottom + padding)
        return img.crop((left, top, right, bottom))
    return img

def fit_to_canvas(img, target_width, target_height, padding=6):
    """
    Scale image to fit within target dimensions while maintaining aspect ratio.
    Center on a transparent canvas.
    """
    # Calculate available space after padding
    avail_w = target_width - 2 * padding
    avail_h = target_height - 2 * padding
    
    # Get current size
    w, h = img.size
    
    # Calculate scale to fit
    scale_w = avail_w / w
    scale_h = avail_h / h
    scale = min(scale_w, scale_h)
    
    # Scale the image
    new_w = int(w * scale)
    new_h = int(h * scale)
    scaled = img.resize((new_w, new_h), Image.Resampling.LANCZOS)
    
    # Create transparent canvas
    canvas = Image.new('RGBA', (target_width, target_height), (0, 0, 0, 0))
    
    # Center the scaled image
    x = (target_width - new_w) // 2
    y = (target_height - new_h) // 2
    canvas.paste(scaled, (x, y), scaled)
    
    # Report fill ratio
    fill_w = new_w / target_width * 100
    fill_h = new_h / target_height * 100
    print(f"    Fill ratio: {fill_w:.1f}% width, {fill_h:.1f}% height")
    
    return canvas

def extract_keyboard(contact_sheet, row, col, rows, cols, margins, name, output_dir, tolerance=12):
    """Extract a single keyboard from the contact sheet."""
    w, h = contact_sheet.size
    cell_w = w // cols
    cell_h = h // rows
    
    # Calculate cell boundaries
    left = col * cell_w
    top = row * cell_h
    right = left + cell_w
    bottom = top + cell_h
    
    # Apply margins (top, right, bottom, left)
    m_top, m_right, m_bottom, m_left = margins
    left += m_left
    top += m_top
    right -= m_right
    bottom -= m_bottom
    
    print(f"  Extracting {name} from row {row}, col {col}")
    print(f"    Cell: ({left}, {top}) to ({right}, {bottom})")
    
    # Crop cell
    cell = contact_sheet.crop((left, top, right, bottom))
    
    # Get background color and flood fill
    bg_color = get_background_color(cell)
    print(f"    Background color: {bg_color}")
    
    alpha = flood_fill_background(cell, bg_color, tolerance=tolerance)
    rgba = apply_alpha_mask(cell, alpha)
    
    # Crop to content
    cropped = crop_to_content(rgba, padding=2)
    print(f"    Cropped size: {cropped.size}")
    
    # Fit to standard canvas
    final = fit_to_canvas(cropped, TARGET_WIDTH, TARGET_HEIGHT, padding=6)
    
    # Save
    output_path = os.path.join(output_dir, f"{name}.png")
    final.save(output_path)
    print(f"    Saved: {output_path}")
    
    return final

def main():
    input_path = "/Users/malpern/local-code/KeyPath/assets/keyboards/contact-sheet-new.png"
    output_dir = "/Users/malpern/local-code/KeyPath/Sources/KeyPathAppKit/Resources/KeyboardIllustrations"
    
    print(f"Loading contact sheet: {input_path}")
    img = Image.open(input_path)
    print(f"Size: {img.size}, Mode: {img.mode}")
    
    if img.mode != 'RGB':
        img = img.convert('RGB')
    
    # Grid is 5 rows x 3 columns
    rows, cols = 5, 3
    
    # Define which keyboards to extract with their margins
    # Format: (row, col): (name, (top, right, bottom, left margins))
    # We're only extracting the problematic ones: 60, 65, 75, 100
    keyboards = {
        # Row 0: 100% full-size
        (0, 0): ("ansi-100", (15, 15, 15, 15)),
        
        # Row 1: 75%, 65%
        (1, 0): ("ansi-75", (15, 15, 15, 15)),
        (1, 1): ("ansi-65", (15, 15, 15, 15)),
        
        # Row 3: 60%
        (3, 0): ("ansi-60", (15, 15, 15, 15)),
    }
    
    print(f"\nExtracting {len(keyboards)} keyboards...")
    
    for (row, col), (name, margins) in keyboards.items():
        extract_keyboard(img, row, col, rows, cols, margins, name, output_dir, tolerance=12)
    
    print("\n✅ Done!")

if __name__ == "__main__":
    main()
