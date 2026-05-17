#!/usr/bin/env python3
"""Video 1: Tap vs Hold — horizontal layout: Key → Stopwatch → Result."""

from PIL import Image, ImageDraw, ImageFont
import random, os, shutil, math

W, H = 1800, 700
KEY = 148; DEPTH = 8; FPS = 24

bg = (237, 225, 205)
key_face = (245, 237, 222); key_pressed = (218, 208, 188); key_held = (228, 205, 172)
key_border = (165, 140, 105); key_side = (200, 185, 160); key_side_dark = (180, 163, 138)
text_color = (80, 62, 44); text_muted = (155, 138, 115)
green = (80, 140, 85); blue = (80, 118, 168); amber = (185, 135, 50)
watch_face_col = (250, 245, 236); watch_border_col = (165, 145, 115)
watch_hand_col = (160, 100, 50); watch_tick_col = (195, 178, 155)
divider_col = (205, 192, 170)

try:
    font_key = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 60)
    font_heading = ImageFont.truetype("/System/Library/Fonts/Supplemental/Georgia Bold.ttf", 44)
    font_sub = ImageFont.truetype("/System/Library/Fonts/Supplemental/Georgia.ttf", 30)
    font_hint = ImageFont.truetype("/System/Library/Fonts/Supplemental/Georgia.ttf", 32)
    font_status = ImageFont.truetype("/System/Library/Fonts/Supplemental/Georgia Bold.ttf", 34)
    font_result = ImageFont.truetype("/System/Library/Fonts/Supplemental/Georgia Bold.ttf", 72)
    font_result_sub = ImageFont.truetype("/System/Library/Fonts/Supplemental/Georgia.ttf", 30)
    font_cmd = ImageFont.truetype("/System/Library/Fonts/SFNSMono.ttf", 68)
except:
    font_key = ImageFont.load_default()
    font_heading = font_key; font_sub = font_key; font_hint = font_key
    font_status = font_key; font_result = font_key; font_result_sub = font_key; font_cmd = font_key

def make_bg():
    random.seed(42)
    img = Image.new("RGB", (W, H), bg)
    d = ImageDraw.Draw(img)
    for _ in range(16000):
        x, y = random.randint(0, W-1), random.randint(0, H-1)
        s = random.randint(-5, 5)
        d.point((x, y), fill=tuple(max(0, min(255, bg[i]+s)) for i in range(3)))
    return img

def ct(draw, x, y, text, font, color):
    bbox = draw.textbbox((0, 0), text, font=font)
    draw.text((x-(bbox[2]-bbox[0])//2, y), text, fill=color, font=font)

def draw_keycap(draw, cx, cy, label, state="normal", press_amount=0.0):
    x = cx - KEY//2; y = cy - KEY//2
    max_travel = 6; yo = int(press_amount * max_travel)
    if state == "held": face, brd = key_held, (150, 120, 75); yo = max(yo, 4)
    elif state == "pressed": face, brd = key_pressed, key_border; yo = max(yo, 4)
    else: face, brd = key_face, key_border
    ky = y + yo; dep = max(0, DEPTH - yo)
    if dep > 0:
        for dy in range(dep):
            draw.line([(x+4, ky+KEY-1+dy), (x+KEY-4, ky+KEY-1+dy)],
                      fill=tuple(max(0, key_side_dark[i]-dy*2) for i in range(3)))
        for dx in range(dep):
            draw.line([(x+KEY-1+dx, ky+4), (x+KEY-1+dx, ky+KEY-4)],
                      fill=tuple(max(0, key_side[i]-dx*3) for i in range(3)))
    draw.rounded_rectangle([x, ky, x+KEY-2, ky+KEY-2], radius=10, fill=face)
    draw.rounded_rectangle([x, ky, x+KEY-2, ky+KEY-2], radius=10, outline=brd, width=2)
    if yo < 2: draw.line([(x+8, ky+3), (x+KEY-10, ky+3)], fill=(250, 245, 236), width=2)
    bbox = draw.textbbox((0, 0), label, font=font_key)
    tw, th = bbox[2]-bbox[0], bbox[3]-bbox[1]
    lc = (55, 42, 28) if state != "normal" else text_color
    draw.text((x+(KEY-2-tw)//2, ky+(KEY-2-th)//2-2), label, fill=lc, font=font_key)

def draw_stopwatch(draw, cx, cy, r, progress, resolved=None):
    ring = watch_border_col
    if resolved == "letter": ring = green
    elif resolved == "modifier": ring = blue
    draw.ellipse([cx-r, cy-r, cx+r, cy+r], fill=watch_face_col, outline=ring, width=4)
    for i in range(12):
        a = math.radians(i*30-90)
        draw.line([(cx+(r-14)*math.cos(a), cy+(r-14)*math.sin(a)),
                   (cx+(r-6)*math.cos(a), cy+(r-6)*math.sin(a))], fill=watch_tick_col, width=2)
    if progress is not None:
        a = math.radians(progress*360-90); hl = r-22
        hc = watch_hand_col
        if resolved == "letter": hc = green
        elif resolved == "modifier": hc = blue
        draw.line([(cx, cy), (cx+hl*math.cos(a), cy+hl*math.sin(a))], fill=hc, width=4)
    draw.ellipse([cx-6, cy-6, cx+6, cy+6], fill=ring)
    draw.rounded_rectangle([cx-8, cy-r-16, cx+8, cy-r+2], radius=4, fill=ring)

# 3-column layout
col1_x = W * 0.22   # key
col2_x = W * 0.50   # stopwatch
col3_x = W * 0.78   # result
row_y = 340          # vertical center of content
heading_y = 50
sub_y = 100
watch_r = 70

background = make_bg()

def ease_out(t): return 1.0-(1.0-t)**2.5
def hold_f(img, s): return [img]*int(s*FPS)
def xfade(a, b, s):
    n = int(s*FPS)
    return [Image.blend(a, b, i/max(1,n-1)) for i in range(n)]

def frame(f_state="normal", f_pa=0.0, hint=None,
          watch_prog=None, watch_res=None, show_watch=False,
          status="", status_col=text_muted,
          result=None, result_font=None):
    img = background.copy()
    d = ImageDraw.Draw(img)
    # Persistent heading
    ct(d, W//2, heading_y, "Tap vs Hold", font_heading, text_color)
    ct(d, W//2, sub_y, "A quick press is a letter. A long press is a modifier.", font_sub, text_muted)
    d.line([(W//2-380, sub_y+42), (W//2+380, sub_y+42)], fill=divider_col, width=2)

    # Col 1: Key
    draw_keycap(d, int(col1_x), int(row_y), "F", state=f_state, press_amount=f_pa)
    if hint:
        ct(d, int(col1_x), int(row_y)+KEY//2+DEPTH+20, hint[0], font_hint, hint[1])

    # Col 2: Stopwatch
    if show_watch:
        draw_stopwatch(d, int(col2_x), int(row_y), watch_r, watch_prog, watch_res)
    if status:
        ct(d, int(col2_x), int(row_y)+watch_r+30, status, font_status, status_col)

    # Col 3: Result
    if result:
        t, s, sc = result
        rf = result_font or font_result
        ct(d, int(col3_x), int(row_y)-40, t, rf, text_color)
        ct(d, int(col3_x), int(row_y)+40, s, font_result_sub, sc)

    return img

all_frames = []
FADE = 0.3

rest = frame()
all_frames += hold_f(rest, 1.0)

# --- Quick tap → letter ---
n_press = int(0.2*FPS)
for i in range(n_press):
    t = ease_out(i/max(1,n_press-1))
    all_frames.append(frame(f_state="pressed" if t>0.5 else "normal", f_pa=t,
                            hint=("tap", blue), show_watch=True, watch_prog=0.0,
                            status="pressed", status_col=amber))

quick_n = int(0.7*FPS)
for i in range(quick_n):
    p = 0.12*(i/quick_n)
    all_frames.append(frame(f_state="pressed", f_pa=1.0, hint=("tap", blue),
                            show_watch=True, watch_prog=p,
                            status="quick tap...", status_col=text_muted))

n_rel = int(0.2*FPS)
for i in range(n_rel):
    t = 1.0-ease_out(i/max(1,n_rel-1))
    all_frames.append(frame(f_pa=t, show_watch=True, watch_prog=0.12, watch_res="letter",
                            status="released", status_col=green,
                            result=("f", "the letter", green)))

resolved_tap = frame(show_watch=True, watch_prog=0.12, watch_res="letter",
                     status="released", status_col=green,
                     result=("f", "the letter", green))
all_frames += hold_f(resolved_tap, 2.8)

# Transition
blank = background.copy()
d = ImageDraw.Draw(blank)
ct(d, W//2, heading_y, "Tap vs Hold", font_heading, text_color)
ct(d, W//2, sub_y, "A quick press is a letter. A long press is a modifier.", font_sub, text_muted)
d.line([(W//2-380, sub_y+42), (W//2+380, sub_y+42)], fill=divider_col, width=2)

all_frames += xfade(resolved_tap, blank, FADE)
all_frames += hold_f(blank, 0.5)

# --- Long hold → modifier ---
rest2 = frame()
all_frames += xfade(blank, rest2, 0.2)

for i in range(n_press):
    t = ease_out(i/max(1,n_press-1))
    all_frames.append(frame(f_state="held" if t>0.5 else "normal", f_pa=t,
                            hint=("hold", amber), show_watch=True, watch_prog=0.0,
                            status="pressed", status_col=amber))

hold_n = int(2.8*FPS)
for i in range(hold_n):
    p = i/hold_n
    all_frames.append(frame(f_state="held", f_pa=1.0, hint=("hold", amber),
                            show_watch=True, watch_prog=p,
                            status="holding...", status_col=amber))

resolved_hold = frame(f_state="held", f_pa=1.0, hint=("hold", amber),
                      show_watch=True, watch_prog=1.0, watch_res="modifier",
                      status="long press", status_col=blue,
                      result=("⌘", "Command", blue), result_font=font_cmd)
all_frames += hold_f(resolved_hold, 3.0)

# Loop
all_frames += xfade(resolved_hold, rest, FADE)

print(f"V1: {len(all_frames)} frames ({len(all_frames)/FPS:.1f}s)")
frame_dir = "/tmp/v1-frames"
if os.path.exists(frame_dir): shutil.rmtree(frame_dir)
os.makedirs(frame_dir)
for i, f in enumerate(all_frames): f.save(f"{frame_dir}/frame_{i:05d}.png")
print("Done")
