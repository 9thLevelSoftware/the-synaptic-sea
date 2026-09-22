"""Package real captured PNGs without altering their scene pixels."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import html
import json

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "artifacts/room_kit_v2"
OUT = BASE / "review"
OUT.mkdir(exist_ok=True)
FONT = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 24)
SMALL = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 18)
IDS = ["fabrication_station_derelict_v1", "coolant_pump_skid_derelict_v1", "suit_service_stand_derelict_v1"]
VIEWS = ["front", "back", "left", "right", "top", "underside"]

for mode in ("normal", "clay"):
    sheet = Image.new("RGB", (2160, 1010), "#18212a")
    draw = ImageDraw.Draw(sheet)
    draw.text((20, 16), f"Actual Blender pilot renders — {mode} — staged, not approved/promoted", fill="white", font=FONT)
    for row, aid in enumerate(IDS):
        top = 60 + row * 312
        draw.text((12, top), aid, fill="white", font=SMALL)
        for col, view in enumerate(VIEWS):
            source = BASE / "pilot-props" / aid / "renders" / f"{view}_{mode}.png"
            image = Image.open(source).convert("RGB")
            image.thumbnail((356, 252))
            x = col * 360
            sheet.paste(image, (x + (360-image.width)//2, top+30))
            draw.text((x+12, top+284), view, fill="#b6c7d7", font=SMALL)
    sheet.save(OUT / f"pilot-{mode}-contact-sheet.png")

comparison = Image.new("RGB", (3200, 990), "#18212a")
draw = ImageDraw.Draw(comparison)
for index, (kind, label) in enumerate((("baseline", "BEFORE: existing assets"), ("candidate", "AFTER: 3 staged props, unchanged existing shell"))):
    image = Image.open(BASE / "pilot-room/final" / kind / "pilot-room-iso.png").convert("RGB")
    assert image.size == (1600,900)
    comparison.paste(image,(1600*index,70))
    draw.text((1600*index+20,16),label,fill="white",font=FONT)
draw.text((20,966), "Actual Godot diagnostic scene. Not procedural/boarded proof. No runtime promotion.", fill="#c2cbd4", font=SMALL)
comparison.save(OUT / "before-after.png")

blocks=[]
for kind in ("baseline","candidate"):
    images=[]
    for name in ("pilot-room-iso","pilot-room-top","pilot-station-detail","pilot-room-iso-720"):
        path=BASE / "pilot-room/final" / kind / f"{name}.png"
        images.append(f'<figure><a href="{path.as_uri()}"><img src="{path.as_uri()}"></a><figcaption>{html.escape(name)} — actual Godot viewport</figcaption></figure>')
    blocks.append(f'<h2>{kind.title()}</h2><section>{"".join(images)}</section>')
for mode in ("normal","clay"):
    path=OUT/f"pilot-{mode}-contact-sheet.png"
    blocks.append(f'<h2>Blender six-view {mode}</h2><a href="{path.as_uri()}"><img src="{path.as_uri()}"></a>')
(OUT / "index.html").write_text('''<!doctype html><meta charset="utf-8"><title>Room kit v2 pilot evidence</title>
<style>body{background:#18212a;color:#edf3fa;font:16px system-ui;margin:2em auto;max-width:1500px}img{width:100%}section{display:grid;grid-template-columns:1fr 1fr;gap:1em}figure{margin:0}a{color:#8cddff}p{max-width:90ch}</style>
<h1>Room kit v2 — implemented pilot, structural gate HOLD</h1>
<p>Three real editable Blender masters and strict staged GLBs: improved fabrication station, new coolant pump skid, and new suit service stand. The shell is the existing unchanged structural kit. No runtime promotion, no full-pilot approval, and no claim of procedural consumer coverage.</p>
<p>Source/socket mismatch and variant-binding failures block structural authoring and bulk expansion. Use full-size image links to inspect pixel detail; captures use orthographic 1600×900 and 1280×720 viewports.</p>
''' + ''.join(blocks),encoding="utf-8")
print(json.dumps({"gallery":str(OUT/"index.html"),"comparison":str(OUT/"before-after.png"),"contact_sheets":[str(OUT/f"pilot-{mode}-contact-sheet.png") for mode in ("normal","clay")]},indent=2))
