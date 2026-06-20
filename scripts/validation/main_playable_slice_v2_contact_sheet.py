#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

FRAMES = [
    ("01 Spawn / entry", "01_spawn_airlock.png"),
    ("02 Objective prop", "02_objective_01_prompt.png"),
    ("03 Next route", "03_objective_01_complete.png"),
    ("04 Blocker prop", "04_blocked_route.png"),
    ("05 Ramp cue", "05_vertical_transition.png"),
    ("06 Destination complete", "06_slice_complete.png"),
]


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: main_playable_slice_v2_contact_sheet.py <artifact_dir>", file=sys.stderr)
        return 2
    artifact_dir = Path(sys.argv[1]).expanduser().resolve()
    if not artifact_dir.exists():
        print(f"artifact_dir does not exist: {artifact_dir}", file=sys.stderr)
        return 1
    thumb_w, thumb_h = 640, 360
    label_h = 34
    pad = 16
    cols = 2
    rows = 3
    sheet_w = cols * thumb_w + (cols + 1) * pad
    sheet_h = rows * (thumb_h + label_h) + (rows + 1) * pad
    sheet = Image.new("RGB", (sheet_w, sheet_h), (28, 28, 28))
    draw = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 22)
    except Exception:
        font = ImageFont.load_default()
    for idx, (label, filename) in enumerate(FRAMES):
        frame_path = artifact_dir / filename
        if not frame_path.exists():
            print(f"missing frame: {frame_path}", file=sys.stderr)
            return 1
        img = Image.open(frame_path).convert("RGB")
        if img.size != (1280, 720):
            print(f"unexpected frame size: {frame_path} {img.size}", file=sys.stderr)
            return 1
        img = img.resize((thumb_w, thumb_h), Image.Resampling.LANCZOS)
        col = idx % cols
        row = idx // cols
        x = pad + col * (thumb_w + pad)
        y = pad + row * (thumb_h + label_h + pad)
        draw.text((x, y), label, fill=(245, 245, 245), font=font)
        sheet.paste(img, (x, y + label_h))
    out = artifact_dir / "main_playable_slice_v2_readability_contact_sheet.png"
    sheet.save(out)
    print(f"CONTACT_SHEET {out}")
    for _, filename in FRAMES:
        frame_path = artifact_dir / filename
        print(f"{filename} sha256={sha256(frame_path)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
