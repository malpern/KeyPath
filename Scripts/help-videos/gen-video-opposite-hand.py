#!/usr/bin/env python3
"""Video 2: Opposite-Hand — horizontal: Left keys → Stopwatch → Right keys/Result."""

from PIL import Image, ImageDraw, ImageFont
import random, os, shutil, math

W, H = 1800, 700
KEY = 130; GAP = 8; DEPTH = 7; FPS = 24

bg = (237, 225, 205)
key_face = (245, 237, 222); key_pressed = (218, 208, 188); key_held = (228, 205, 172)
key_border = (165, 140, 105); key_side = (200, 185, 160); key_side_dark = (180, 163, 138)
text_color = (80, 62, 44); text_muted = (155, 138, 115)
green = (80, 140, 85); blue = (80, 118, 168); amber = (185, 135, 50)
watch_face_col = (250, 245, 236); watch_border_col = (165, 145, 115)
watch_hand_col = (160, 100, 50); watch_tick_col = (195, 178, 155)
divider_col = (205, 192, 170)
flash_col = (170, 205, 240)

try:
    font_key = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 52)
    font_heading = ImageFont.truetype("/System/Library/Fonts/Supplemental/Georgia Bold.ttf", 44)
    font_sub = ImageFont.truetype("/System/Library/Fonts/Supplemental/Georgia.ttf", 28)
    font_hint = ImageFont.truetype("/System/Library/Fonts/Supplemental/Georgia.ttf", 30)
    font_status = ImageFont.truetype("/System/Library/Fonts/Supplemental/Georgia Bold.ttf", 32)
    font_result = ImageFont.truetype("/System/Library/Fonts/Supplemental/Georgia Bold.ttf", 64)
    font_result_sub = ImageFont.truetype("/System/Library/Fonts/Supplemental/Georgia.ttf", 28)
    font_cmd = ImageFont.truetype("/System/Library/Fonts/SFNSMono.ttf", 60)
    font_hand = ImageFont.truetype("/System/Library/Fonts/Supplemental/Georgia.ttf", 26)
except:
    font_key = ImageFont.load_default()
    font_heading = font_key; font_sub = font_key; font_hint = font_key
    font_status = font_key; font_result = font_key; font_result_sub = font_key
    font_cmd = font_key; font_hand = font_key

def make_bg():
    random.seed(77)
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
    max_travel = 5; yo = int(press_amount * max_travel)
    if state == "held": face, brd = key_held, (150, 120, 75); yo = max(yo, 3)
    elif state == "pressed": face, brd = key_pressed, key_border; yo = max(yo, 3)
    else: face, brd = key_face, key_border
    ky = y + yo; dep = max(0, DEPTH - yo)
    if dep > 0:
        for dy in range(dep):
            draw.line([(x+4, ky+KEY-1+dy), (x+KEY-4, ky+KEY-1+dy)],
                      fill=tuple(max(0, key_side_dark[i]-dy*2) for i in range(3)))
        for dx in range(dep):
            draw.line([(x+KEY-1+dx, ky+4), (x+KEY-1+dx, ky+KEY-4)],
                      fill=tuple(max(0, key_side[i]-dx*3) for i in range(3)))
    draw.rounded_rectangle([x, ky, x+KEY-2, ky+KEY-2], radius=9, fill=face)
    draw.rounded_rectangle([x, ky, x+KEY-2, ky+KEY-2], radius=9, outline=brd, width=2)
    if yo < 2: draw.line([(x+7, ky+3), (x+KEY-9, ky+3)], fill=(250, 245, 236), width=2)
    bbox = draw.textbbox((0, 0), label, font=font_key)
    tw, th = bbox[2]-bbox[0], bbox[3]-bbox[1]
    lc = (55, 42, 28) if state != "normal" else text_color
    draw.text((x+(KEY-2-tw)//2, ky+(KEY-2-th)//2-2), label, fill=lc, font=font_key)

def draw_stopwatch(draw, cx, cy, r, progress, resolved=None, flash=False):
    ring = watch_border_col
    if resolved == "modifier": ring = blue
    elif resolved == "letter": ring = green
    fc = flash_col if flash else watch_face_col
    draw.ellipse([cx-r, cy-r, cx+r, cy+r], fill=fc, outline=ring, width=5 if flash else 4)
    for i in range(12):
        a = math.radians(i*30-90)
        draw.line([(cx+(r-14)*math.cos(a), cy+(r-14)*math.sin(a)),
                   (cx+(r-6)*math.cos(a), cy+(r-6)*math.sin(a))], fill=watch_tick_col, width=2)
    if progress is not None:
        a = math.radians(progress*360-90); hl = r-22
        hc = watch_hand_col
        if resolved == "modifier": hc = blue
        elif resolved == "letter": hc = green
        draw.line([(cx, cy), (cx+hl*math.cos(a), cy+hl*math.sin(a))], fill=hc, width=4)
    draw.ellipse([cx-6, cy-6, cx+6, cy+6], fill=ring)
    draw.rounded_rectangle([cx-8, cy-r-16, cx+8, cy-r+2], radius=4, fill=ring)

# 3-column layout
col1_x = W * 0.20
col2_x = W * 0.50
col3_x = W * 0.80
row_y = 340
heading_y = 50
sub_y = 100
watch_r = 65

left_keys = ["D", "F"]
right_keys = ["J", "K"]

background = make_bg()

def ease_out(t): return 1.0-(1.0-t)**2.5
def hold_f(img, s): return [img]*int(s*FPS)
def xfade(a, b, s):
    n = int(s*FPS)
    return [Image.blend(a, b, i/max(1,n-1)) for i in range(n)]

def frame(left_st=None, right_st=None, pa=None, hints=None,
          watch_prog=None, watch_res=None, show_watch=False, watch_flash=False,
          status="", status_col=text_muted,
          result=None, result_font=None):
    img = background.copy()
    d = ImageDraw.Draw(img)
    ls = left_st or {}; rs = right_st or {}; p = pa or {}

    ct(d, W//2, heading_y, "Opposite-Hand Activation", font_heading, text_color)
    ct(d, W//2, sub_y, "The other hand resolves the decision instantly.", font_sub, text_muted)
    d.line([(W//2-380, sub_y+38), (W//2+380, sub_y+38)], fill=divider_col, width=2)

    # Col 1: Left hand keys
    ct(d, int(col1_x), int(row_y)-KEY-10, "left hand", font_hand, text_muted)
    for i, k in enumerate(left_keys):
        ky_offset = (i - 0.5) * (KEY + GAP)
        draw_keycap(d, int(col1_x) + int(ky_offset), int(row_y),
                    k, state=ls.get(k, "normal"), press_amount=p.get(k, 0.0))
        if hints:
            for kn, lt, col in hints:
                if kn == k:
                    ct(d, int(col1_x) + int(ky_offset), int(row_y)+KEY//2+DEPTH+14,
                       lt, font_hint, col)

    # Col 2: Stopwatch
    if show_watch:
        draw_stopwatch(d, int(col2_x), int(row_y), watch_r, watch_prog, watch_res, watch_flash)
    if status:
        ct(d, int(col2_x), int(row_y)+watch_r+28, status, font_status, status_col)

    # Col 3: Right hand keys OR result
    if result:
        t, s, sc = result
        rf = result_font or font_result
        ct(d, int(col3_x), int(row_y)-36, t, rf, text_color)
        ct(d, int(col3_x), int(row_y)+36, s, font_result_sub, sc)
    else:
        ct(d, int(col3_x), int(row_y)-KEY-10, "right hand", font_hand, text_muted)
        for i, k in enumerate(right_keys):
            ky_offset = (i - 0.5) * (KEY + GAP)
            draw_keycap(d, int(col3_x) + int(ky_offset), int(row_y),
                        k, state=rs.get(k, "normal"), press_amount=p.get(k, 0.0))
            if hints:
                for kn, lt, col in hints:
                    if kn == k:
                        ct(d, int(col3_x) + int(ky_offset), int(row_y)+KEY//2+DEPTH+14,
                           lt, font_hint, col)

    return img

def press_anim(key_name, left_st, right_st, hints, s=0.2, **kw):
    n = int(s*FPS); frames = []
    for i in range(n):
        t = ease_out(i/max(1,n-1))
        st = "pressed" if t>0.5 else "normal"
        ls, rs = dict(left_st), dict(right_st)
        if key_name in left_keys: ls[key_name] = st
        else: rs[key_name] = st
        frames.append(frame(ls, rs, pa={key_name: t}, hints=hints, **kw))
    return frames

all_frames = []
FADE = 0.3

rest = frame()
all_frames += hold_f(rest, 1.0)

# --- Scenario 1: Other hand (J) → modifier ---
n_press = int(0.25*FPS)
for i in range(n_press):
    t = ease_out(i/max(1,n_press-1))
    all_frames.append(frame({"F": "held" if t>0.5 else "normal"}, {}, pa={"F": t},
                            hints=[("F", "hold", amber)],
                            show_watch=True, watch_prog=0.0,
                            status="F held", status_col=amber))

tick_dur = 1.8; interrupt_at = 0.35
tick_n = int(tick_dur * interrupt_at * FPS)
for i in range(tick_n):
    p = interrupt_at * (i/max(1, tick_n-1))
    all_frames.append(frame({"F": "held"}, {}, pa={"F": 1.0},
                            hints=[("F", "hold", amber)],
                            show_watch=True, watch_prog=p,
                            status="waiting...", status_col=amber))

all_frames += press_anim("J", {"F": "held"}, {},
                         [("F", "hold", amber), ("J", "tap", blue)],
                         s=0.15,
                         show_watch=True, watch_prog=interrupt_at,
                         status="waiting...", status_col=amber)

flash_n = int(0.5*FPS)
for i in range(flash_n):
    flashing = i < 6
    all_frames.append(frame({"F": "held"}, {"J": "pressed"},
                            pa={"F": 1.0, "J": 1.0},
                            hints=[("F", "hold", amber), ("J", "tap", blue)],
                            show_watch=True, watch_prog=interrupt_at,
                            watch_res="modifier", watch_flash=flashing,
                            status="resolved!", status_col=blue))

resolved = frame({"F": "held"}, {"J": "pressed"},
                 pa={"F": 1.0, "J": 1.0},
                 hints=[("F", "hold", amber), ("J", "tap", blue)],
                 show_watch=True, watch_prog=interrupt_at, watch_res="modifier",
                 status="other hand — instant", status_col=blue)
all_frames += hold_f(resolved, 0.6)

result_mod = frame(show_watch=True, watch_prog=interrupt_at, watch_res="modifier",
                   status="other hand — instant", status_col=blue,
                   result=("⌘J", "Command + J", blue), result_font=font_cmd)
all_frames += xfade(resolved, result_mod, FADE)
all_frames += hold_f(result_mod, 2.8)

# Transition
blank_h = background.copy()
d = ImageDraw.Draw(blank_h)
ct(d, W//2, heading_y, "Opposite-Hand Activation", font_heading, text_color)
ct(d, W//2, sub_y, "The other hand resolves the decision instantly.", font_sub, text_muted)
d.line([(W//2-380, sub_y+38), (W//2+380, sub_y+38)], fill=divider_col, width=2)

all_frames += xfade(result_mod, blank_h, FADE)
all_frames += hold_f(blank_h, 0.5)

# --- Scenario 2: Same hand (D) → letter ---
rest2 = frame()
all_frames += xfade(blank_h, rest2, 0.2)

for i in range(n_press):
    t = ease_out(i/max(1,n_press-1))
    all_frames.append(frame({"F": "held" if t>0.5 else "normal"}, {}, pa={"F": t},
                            hints=[("F", "hold", amber)],
                            show_watch=True, watch_prog=0.0,
                            status="F held", status_col=amber))

tick_n2 = int(tick_dur * 0.25 * FPS)
for i in range(tick_n2):
    p = 0.25 * (i/max(1, tick_n2-1))
    all_frames.append(frame({"F": "held"}, {}, pa={"F": 1.0},
                            hints=[("F", "hold", amber)],
                            show_watch=True, watch_prog=p,
                            status="waiting...", status_col=amber))

all_frames += press_anim("D", {"F": "held"}, {},
                         [("D", "tap", blue), ("F", "tap", blue)],
                         s=0.15,
                         show_watch=True, watch_prog=0.25,
                         status="waiting...", status_col=amber)

for i in range(flash_n):
    flashing = i < 6
    all_frames.append(frame({"D": "pressed", "F": "pressed"}, {},
                            pa={"D": 1.0, "F": 1.0},
                            hints=[("D", "tap", blue), ("F", "tap", blue)],
                            show_watch=True, watch_prog=0.25,
                            watch_res="letter", watch_flash=flashing,
                            status="resolved!", status_col=green))

resolved_l = frame({"D": "pressed", "F": "pressed"}, {},
                   pa={"D": 1.0, "F": 1.0},
                   hints=[("D", "tap", blue), ("F", "tap", blue)],
                   show_watch=True, watch_prog=0.25, watch_res="letter",
                   status="same hand — letters", status_col=green)
all_frames += hold_f(resolved_l, 0.6)

result_l = frame(show_watch=True, watch_prog=0.25, watch_res="letter",
                 status="same hand — letters", status_col=green,
                 result=("fd", "just the letters", green))
all_frames += xfade(resolved_l, result_l, FADE)
all_frames += hold_f(result_l, 2.8)

# Loop
all_frames += xfade(result_l, rest, FADE)

print(f"V2: {len(all_frames)} frames ({len(all_frames)/FPS:.1f}s)")
frame_dir = "/tmp/v2-frames"
if os.path.exists(frame_dir): shutil.rmtree(frame_dir)
os.makedirs(frame_dir)
for i, f in enumerate(all_frames): f.save(f"{frame_dir}/frame_{i:05d}.png")
print("Done")
