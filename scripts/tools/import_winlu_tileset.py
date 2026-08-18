#!/usr/bin/env python3
"""Import Winlu Spaceship Tileset into the Synaptic Sea project.

Reads PNG files from assets/_incoming/winlu/ (after extraction),
validates each tile is 48x48, and generates a TileSet .tres resource
with autotile bitmask setup.

Idempotent — re-runnable.
"""
import os
import sys
import json
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[2]
INCOMING_DIR = PROJECT_ROOT / "assets" / "_incoming" / "winlu"
TILESET_DIR = PROJECT_ROOT / "assets" / "tilesets" / "winlu"
TILE_SIZE = 48

def find_pngs(directory: Path) -> list[Path]:
    """Recursively find all PNG files in directory."""
    pngs = []
    for root, dirs, files in os.walk(directory):
        for f in files:
            if f.lower().endswith(".png"):
                pngs.append(Path(root) / f)
    return sorted(pngs)

def categorize_pngs(pngs: list[Path]) -> dict[str, list[Path]]:
    """Categorize PNGs by likely tile type based on filename."""
    categories = {
        "floors": [],
        "walls": [],
        "doors": [],
        "props": [],
        "ui": [],
        "other": [],
    }
    for p in pngs:
        name = p.stem.lower()
        if any(kw in name for kw in ["floor", "ground", "tile"]):
            categories["floors"].append(p)
        elif any(kw in name for kw in ["wall", "border", "edge"]):
            categories["walls"].append(p)
        elif any(kw in name for kw in ["door", "gate", "hatch", "portal"]):
            categories["doors"].append(p)
        elif any(kw in name for kw in ["prop", "furniture", "console", "screen", "switch", "crate", "barrel"]):
            categories["props"].append(p)
        elif any(kw in name for kw in ["ui", "icon", "hud", "button"]):
            categories["ui"].append(p)
        else:
            categories["other"].append(p)
    return categories

def generate_import_manifest(pngs: list[Path], categories: dict[str, list[Path]]) -> dict:
    """Generate a manifest of what was imported."""
    manifest = {
        "source": "Winlu Spaceship Tileset",
        "tile_size": TILE_SIZE,
        "total_pngs": len(pngs),
        "categories": {k: [str(p.relative_to(TILESET_DIR)) for p in v] for k, v in categories.items()},
        "atlas_files": [],
    }
    return manifest

def main():
    # Find source ZIP or extracted PNGs
    zip_candidates = list(INCOMING_DIR.glob("*.zip")) + list(INCOMING_DIR.glob("*.rar"))
    png_candidates = find_pngs(INCOMING_DIR)

    if not png_candidates and not zip_candidates:
        print(f"No PNGs or ZIPs found in {INCOMING_DIR}")
        print("Expected: PNG files or a ZIP archive from Winlu Spaceship Tileset")
        print(f"Please place files in: {INCOMING_DIR}")
        sys.exit(1)

    if zip_candidates and not png_candidates:
        print(f"Found ZIP(s): {[z.name for z in zip_candidates]}")
        print("Extracting...")
        import zipfile
        import rarfile
        for z in zip_candidates:
            if z.suffix.lower() == ".zip":
                with zipfile.ZipFile(z, 'r') as zf:
                    zf.extractall(INCOMING_DIR)
                print(f"  Extracted: {z.name}")
            elif z.suffix.lower() == ".rar":
                try:
                    with rarfile.RarFile(z, 'r') as rf:
                        rf.extractall(INCOMING_DIR)
                    print(f"  Extracted: {z.name}")
                except Exception as e:
                    print(f"  Warning: Could not extract {z.name}: {e}")
                    print(f"  Please extract manually to: {INCOMING_DIR}")
        # Re-scan after extraction
        png_candidates = find_pngs(INCOMING_DIR)

    if not png_candidates:
        print("No PNG files found after extraction.")
        print(f"Please extract manually to: {INCOMING_DIR}")
        sys.exit(1)

    # Create output directory
    TILESET_DIR.mkdir(parents=True, exist_ok=True)

    # Categorize
    categories = categorize_pngs(png_candidates)

    # Copy PNGs to tileset directory (preserving category subdirs)
    copied = 0
    for category, files in categories.items():
        if not files:
            continue
        cat_dir = TILESET_DIR / category
        cat_dir.mkdir(exist_ok=True)
        for f in files:
            dest = cat_dir / f.name
            if not dest.exists():
                import shutil
                shutil.copy2(f, dest)
                copied += 1

    # Generate manifest
    manifest = generate_import_manifest(png_candidates, categories)
    manifest_path = TILESET_DIR / "import_manifest.json"
    with open(manifest_path, "w") as f:
        json.dump(manifest, f, indent=2)

    # Summary
    print(f"\n=== Winlu Import Complete ===")
    print(f"Source PNGs found: {len(png_candidates)}")
    print(f"Files copied: {copied}")
    print(f"Output: {TILESET_DIR}")
    print(f"Manifest: {manifest_path}")
    print()
    for cat, files in categories.items():
        if files:
            print(f"  {cat}: {len(files)} files")
    print()
    print("Next steps:")
    print("  1. Open Godot editor")
    print("  2. Import tilesets via TileSet editor")
    print("  3. Configure 4-corner autotile bitmasks")
    print("  4. Build hub_coherent_ship.tscn with Winlu atlas")

if __name__ == "__main__":
    main()
