#!/usr/bin/env python3
"""Home row layout diagram: keycaps with modifier labels below."""

from PIL import Image, ImageDraw, ImageFont
import random

W, H = 1800, 580
KEY = 180
GAP = 12
DEPTH = 10

bg = (237, 225, 205)
key_face = (245, 237, 222)
key_border = (165, 140, 105)
key_side = (200, 185, 160)
key_side_dark = (180, 163, 138)
text_color = (80, 62, 44)
text_muted = (155, 138, 115)
blue = (80, 118, 168)
divider_col = (205, 192, 170)

try:
    font_letter = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 76)
    font_mod_name = ImageFont.truetype("/System/Library/Fonts/Supplemental/Georgia.ttf", 26)
    font_mod_symbol = ImageFont.truetype("/System/Library/Fonts/SFNSMono.ttf", 97)
    font_hand = ImageFont.truetype("/System/Library/Fonts/Supplemental/Georgia.ttf", 32)
except:
    font_letter = ImageFont.load_default()
    font_mod = font_letter
    font_hand = font_letter


def make_bg():
    random.seed(55)
    img = Image.new("RGB", (W, H), bg)
    d = ImageDraw.Draw(img)
    for _ in range(12000):
        x, y = random.randint(0, W-1), random.randint(0, H-1)
        s = random.randint(-5, 5)
        d.point((x, y), fill=tuple(max(0, min(255, bg[i]+s)) for i in range(3)))
    return img


def ct(draw, x, y, text, font, color):
    bbox = draw.textbbox((0, 0), text, font=font)
    draw.text((x - (bbox[2]-bbox[0])//2, y), text, fill=color, font=font)


def draw_keycap(draw, x, y, letter):
    # Side walls
    for dy in range(DEPTH):
        draw.line([(x+4, y+KEY-1+dy), (x+KEY-4, y+KEY-1+dy)],
                  fill=tuple(max(0, key_side_dark[i]-dy*2) for i in range(3)))
    for dx in range(DEPTH):
        draw.line([(x+KEY-1+dx, y+4), (x+KEY-1+dx, y+KEY-4)],
                  fill=tuple(max(0, key_side[i]-dx*3) for i in range(3)))

    # Face
    draw.rounded_rectangle([x, y, x+KEY-2, y+KEY-2], radius=12, fill=key_face)
    draw.rounded_rectangle([x, y, x+KEY-2, y+KEY-2], radius=12, outline=key_border, width=2)

    # Top highlight
    draw.line([(x+10, y+3), (x+KEY-12, y+3)], fill=(250, 245, 236), width=2)

    # Letter centered
    bbox = draw.textbbox((0, 0), letter, font=font_letter)
    tw, th = bbox[2]-bbox[0], bbox[3]-bbox[1]
    draw.text((x+(KEY-2-tw)//2, y+(KEY-2-th)//2-4), letter, fill=text_color, font=font_letter)


keys_left = [
    ("A", "Shift", "⇧"),
    ("S", "Control", "⌃"),
    ("D", "Option", "⌥"),
    ("F", "Command", "⌘"),
]
keys_right = [
    ("J", "Command", "⌘"),
    ("K", "Option", "⌥"),
    ("L", "Control", "⌃"),
    (";", "Shift", "⇧"),
]

split_gap = 100
total_w = 4*(KEY+GAP)-GAP + split_gap + 4*(KEY+GAP)-GAP
mid = W // 2
start_x = mid - total_w // 2
right_start = start_x + 4*(KEY+GAP)-GAP + split_gap
# Vertically center: keys + depth + gap + mod labels (~100px)
content_h = KEY + DEPTH + 170
ky = (H - content_h) // 2

img = make_bg()
draw = ImageDraw.Draw(img)

# Hand labels
left_center = start_x + (4*(KEY+GAP)-GAP) // 2
right_center = right_start + (4*(KEY+GAP)-GAP) // 2
ct(draw, left_center, ky - 50, "left hand", font_hand, text_muted)
ct(draw, right_center, ky - 50, "right hand", font_hand, text_muted)

def draw_mod_label(draw, cx, y, symbol, name):
    """Draw large symbol first, name below in same color."""
    ct(draw, cx, y, symbol, font_mod_symbol, blue)
    ct(draw, cx, y + 100, name, font_mod_name, blue)

# Draw keys and modifier labels
for i, (letter, mod, sym) in enumerate(keys_left):
    kx = start_x + i * (KEY + GAP)
    draw_keycap(draw, kx, ky, letter)
    draw_mod_label(draw, kx + KEY//2, ky + KEY + DEPTH + 20, sym, mod)

for i, (letter, mod, sym) in enumerate(keys_right):
    kx = right_start + i * (KEY + GAP)
    draw_keycap(draw, kx, ky, letter)
    draw_mod_label(draw, kx + KEY//2, ky + KEY + DEPTH + 20, sym, mod)

# Remove standalone legend — the modifier labels speak for themselves

img.save("/tmp/diagram-home-row-layout.png", "PNG", quality=95)
print(f"Saved {W}x{H}")
