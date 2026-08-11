#!/usr/bin/env python3
"""Prepare the Synaptic Sea SDXL LoRA image/caption dataset."""

from __future__ import annotations

import argparse
import hashlib
import shutil
import sys
from pathlib import Path
from typing import Iterable, Sequence


PROJECT_ROOT = Path(__file__).resolve().parents[1]
RAW_DIR = PROJECT_ROOT / "data/training/lora_synaptic_sea/raw"
TILE_RENDER_DIR = Path("/tmp/tile_renders")
ASSET_TILE_DIR = PROJECT_ROOT / "assets/tiles/synaptic_sea"
EXTRA_SOURCES = (
    Path("/tmp/synaptic_sea_derelict_00001_.png"),
    Path("/tmp/synaptic_sea_controlnet_depth_00001_.png"),
    Path("/tmp/synaptic_floor_canny_00001_.png"),
    Path("/tmp/synaptic_wall_canny_00001_.png"),
    Path("/tmp/tile_test/synaptic_tile_floor_1x1_00002_.png"),
)
IMAGE_SUFFIXES = {".jpeg", ".jpg", ".png", ".webp"}
TARGET_SIZE = (1024, 1024)
CAPTION = (
    "synaptic_sea salvage-industrial derelict, weathered dark metal panels, "
    "visible rivets, rust patina, dim amber and cool blue-green accent lighting, "
    "functional military aesthetic, utilitarian, worn, ventilation grates, "
    "exposed pipes, emergency lighting strips"
)


def discover_sources(project_root: Path = PROJECT_ROOT) -> list[Path]:
    """Return available seed images in stable order, without filtering duplicates."""

    tile_render_dir = TILE_RENDER_DIR
    asset_tile_dir = project_root / "assets/tiles/synaptic_sea"
    sources: list[Path] = []

    if tile_render_dir.is_dir():
        sources.extend(sorted(tile_render_dir.glob("*_beauty.png")))
    else:
        print(f"Warning: missing Blender render directory: {tile_render_dir}", file=sys.stderr)

    for source in EXTRA_SOURCES:
        if source.is_file():
            sources.append(source)
        else:
            print(f"Warning: missing optional generated tile: {source}", file=sys.stderr)

    if asset_tile_dir.is_dir():
        sources.extend(
            sorted(
                path
                for path in asset_tile_dir.iterdir()
                if path.is_file() and path.suffix.lower() in IMAGE_SUFFIXES
            )
        )
    else:
        print(f"Warning: missing project tile directory: {asset_tile_dir}", file=sys.stderr)

    return sources


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _unique_name(source: Path, used_names: set[str]) -> str:
    """Return a collision-safe output name while keeping the original basename."""

    name = source.name
    if name not in used_names:
        return name

    candidate = f"{source.parent.name}__{name}"
    if candidate not in used_names:
        return candidate

    stem = source.stem
    suffix = source.suffix
    index = 2
    while f"{stem}__{index}{suffix}" in used_names:
        index += 1
    return f"{stem}__{index}{suffix}"


def _copy_image(source: Path, destination: Path, pillow_image) -> None:
    """Copy an image, resizing it to the SDXL training resolution when possible."""

    if pillow_image is None:
        shutil.copy2(source, destination)
        return

    try:
        with pillow_image.open(source) as image:
            if image.size == TARGET_SIZE:
                shutil.copy2(source, destination)
                return

            resampling = getattr(pillow_image, "Resampling", pillow_image).LANCZOS
            resized = image.resize(TARGET_SIZE, resampling)
            if destination.suffix.lower() in {".jpg", ".jpeg"} and resized.mode in {"RGBA", "LA", "P"}:
                resized = resized.convert("RGB")
            resized.save(destination)
    except (OSError, ValueError) as exc:
        print(
            f"Warning: could not resize {source} ({exc}); copying unchanged",
            file=sys.stderr,
        )
        shutil.copy2(source, destination)


def prepare_dataset(
    raw_dir: Path,
    sources: Iterable[Path],
    *,
    resize: bool = True,
) -> int:
    """Copy source images and captions into ``raw_dir`` and return the image count."""

    raw_dir.mkdir(parents=True, exist_ok=True)
    try:
        from PIL import Image
    except ImportError:
        Image = None
        if resize:
            print("Warning: Pillow is unavailable; images will not be resized", file=sys.stderr)

    seen_hashes: dict[str, Path] = {}
    used_names: set[str] = set()
    prepared = 0

    for source in sources:
        source = Path(source)
        if not source.is_file():
            print(f"Warning: skipping missing source: {source}", file=sys.stderr)
            continue
        if source.suffix.lower() not in IMAGE_SUFFIXES:
            print(f"Warning: skipping non-image source: {source}", file=sys.stderr)
            continue

        digest = _sha256(source)
        if digest in seen_hashes:
            print(f"Skipping duplicate image: {source} (same bytes as {seen_hashes[digest]})")
            continue

        output_name = _unique_name(source, used_names)
        destination = raw_dir / output_name
        if resize:
            _copy_image(source, destination, Image)
        else:
            shutil.copy2(source, destination)
        destination.with_suffix(".txt").write_text(CAPTION + "\n", encoding="utf-8")

        seen_hashes[digest] = destination
        used_names.add(output_name)
        prepared += 1
        print(f"Prepared {destination}")

    return prepared


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--raw-dir",
        type=Path,
        default=RAW_DIR,
        help=f"dataset output directory (default: {RAW_DIR})",
    )
    parser.add_argument(
        "--no-resize",
        action="store_true",
        help="copy source images without resizing",
    )
    args = parser.parse_args(argv)

    sources = discover_sources(PROJECT_ROOT)
    prepared = prepare_dataset(args.raw_dir, sources, resize=not args.no_resize)
    print(f"Prepared {prepared} images ready for LoRA training in {args.raw_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
