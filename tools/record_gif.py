#!/usr/bin/env python3
# Runs `sq squad.nut`, parses each tick, renders colored frames -> assets/squad.gif
import re, subprocess, os
from PIL import Image, ImageDraw, ImageFont

REPO = "/Users/harvardsummer/npc"
OUT  = os.path.join(REPO, "assets", "squad.gif")

BG      = (13, 17, 23)
DOT     = (48, 54, 61)
TITLE   = (88, 166, 255)
TEXTC   = (201, 209, 217)
COLORS  = {"P": (248, 81, 73), "1": (88, 166, 255), "2": (63, 185, 80), "3": (210, 153, 34), "x": (139, 148, 158)}

FONT = "/System/Library/Fonts/Menlo.ttc"
big  = ImageFont.truetype(FONT, 24)
mid  = ImageFont.truetype(FONT, 18)
cellf = ImageFont.truetype(FONT, 24)

CELL_W, CELL_H = 17, 22
MARGIN = 28
GRID_W = 20

# --- parse the demo output into frames ---
out = subprocess.run(["sq", "squad.nut"], cwd=REPO, capture_output=True, text=True).stdout.splitlines()
status_re = re.compile(r"\[t=\s*([\d.]+)\].*Guard-1 (\w+).*?susp=(\d+)%.*Guard-2 (\w+).*?susp=(\d+)%")
grid_re   = re.compile(r"^[.P123x]+$")

frames, cur = [], None
for line in out:
    m = status_re.search(line)
    if m:
        if cur: frames.append(cur)
        cur = {"t": m.group(1), "g1": (m.group(2), int(m.group(3))),
               "g2": (m.group(4), int(m.group(5))), "grid": [], "events": []}
        continue
    if cur is None: continue
    s = line.strip()
    if grid_re.match(s) and len(s) == GRID_W:
        cur["grid"].append(s)
    elif "spotted" in line:
        cur["events"].append("Guard-1 spots the target and radios it in!")
    elif "responds" in line:
        cur["events"].append("Guard-2 responds -> moving to investigate")
if cur: frames.append(cur)

# carry the most recent event forward as a caption
caption = "Guards patrolling"
for f in frames:
    if f["events"]:
        caption = "Guard-1 spots the target and radios it in" if "spots" in f["events"][-1] else "Guard-2 responds and moves to investigate"
    f["caption"] = caption

W = 560
GRID_X = (W - GRID_W * CELL_W) // 2
H = MARGIN + 40 + len(frames[0]["grid"]) * CELL_H + 20 + 60 + MARGIN

def chip(d, x, y, label, state, susp, color):
    d.text((x, y), label, font=mid, fill=color)
    d.text((x + 100, y), f"{state.lower():<7}", font=mid, fill=TEXTC)
    d.text((x + 190, y), f"{susp:3d}%", font=mid, fill=TEXTC)
    bx, by, bw = x + 250, y + 6, 110
    d.rectangle([bx, by, bx + bw, by + 10], outline=DOT)
    if susp: d.rectangle([bx, by, bx + int(bw * susp / 100), by + 10], fill=color)

def render(f):
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    d.text((MARGIN, MARGIN - 6), "npc-fsm", font=big, fill=TITLE)
    d.text((MARGIN + 116, MARGIN), "squad alert propagation", font=mid, fill=TEXTC)
    gy = MARGIN + 40
    for r, row in enumerate(f["grid"]):
        for c, ch in enumerate(row):
            col = COLORS.get(ch, DOT)
            d.text((GRID_X + c * CELL_W, gy + r * CELL_H), ch, font=cellf, fill=col)
    cy = gy + len(f["grid"]) * CELL_H + 12
    hot = ("spot" in f["caption"] or "respond" in f["caption"])
    d.text((MARGIN, cy), f["caption"], font=mid, fill=(240, 200, 90) if hot else TEXTC)
    chip(d, MARGIN, cy + 30, "Guard-1", *f["g1"], COLORS["1"])
    chip(d, MARGIN, cy + 52, "Guard-2", *f["g2"], COLORS["2"])
    return img

imgs = [render(f) for f in frames]
# hold longer on frames where an event fires, and a long hold at the end
durs = [420 if f["events"] else 240 for f in frames]
durs[-1] = 1800
os.makedirs(os.path.dirname(OUT), exist_ok=True)
imgs[0].save(OUT, save_all=True, append_images=imgs[1:], duration=durs, loop=0, optimize=True, disposal=2)
print(f"wrote {OUT}  ({len(imgs)} frames, {os.path.getsize(OUT)//1024} KB)")
