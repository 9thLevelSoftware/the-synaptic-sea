#!/usr/bin/env python3
"""Make generated tile textures friendlier to modular tiling.

The default operation is deliberately offline and deterministic.  It mirrors
matching pixels from the opposite edge of a tile and blends the pair together
with a linear falloff across an eight-pixel border.  This avoids requiring
ComfyUI or a GPU while making the first/last rows and columns agree better when
tiles are placed next to one another.

Usage::

    python3 tools/inpaint_tile_edges.py \
        --input-dir assets/tiles/synaptic_sea/ \
        --output-dir assets/tiles/synaptic_sea/

    python3 tools/inpaint_tile_edges.py \
        --input-dir assets/tiles/synaptic_sea/ \
        --output-dir /tmp/seamless_test/ \
        --test-grid

Each source image produces ``{stem}_edge_mask.png`` and
``{stem}_seamless.png``.  Generated mask/seamless/grid files are ignored on a
subsequent run, which makes using the same input and output directory safe.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Any, Iterable, Sequence

try:
    from PIL import Image as _PILImage
except ModuleNotFoundError:  # pragma: no cover - depends on the host install
    _PILImage = None

Image: Any = _PILImage


BORDER_PIXELS = 8
_GENERATED_SUFFIXES = ("_edge_mask", "_seamless", "_test_grid")


def _source_pngs(input_dir: Path) -> list[Path]:
    """Return source PNGs in a stable order, excluding our generated files."""

    paths = []
    for path in input_dir.iterdir():
        if not path.is_file() or path.suffix.lower() != ".png":
            continue
        if path.stem.lower().endswith(_GENERATED_SUFFIXES):
            continue
        paths.append(path)
    return sorted(paths, key=lambda path: path.name.lower())


def _effective_border(width: int, height: int) -> int:
    """Use eight pixels where possible, shrinking for tiny test images."""

    return max(1, min(BORDER_PIXELS, width // 2 or 1, height // 2 or 1))


def make_edge_mask(size: tuple[int, int], border: int = BORDER_PIXELS):
    """Return an L image with a white border and a black interior."""

    if Image is None:  # pragma: no cover - guarded by main
        raise RuntimeError("Pillow is required to create an edge mask")

    width, height = size
    mask = Image.new("L", size, 0)
    pixels = [0] * (width * height)
    for y in range(height):
        edge_row = y < border or y >= height - border
        for x in range(width):
            if edge_row or x < border or x >= width - border:
                pixels[y * width + x] = 255
    mask.putdata(pixels)
    return mask


def _mix(first: Sequence[int], second: Sequence[int], amount: float) -> tuple[int, ...]:
    """Linearly interpolate two pixels and round to integer channel values."""

    return tuple(
        max(0, min(255, int(round(a + (b - a) * amount))))
        for a, b in zip(first, second)
    )


def _blend_opposite_edges(
    pixels: list[tuple[int, ...]],
    width: int,
    height: int,
    border: int,
) -> None:
    """Blend opposite edge pairs toward one another in-place.

    For each distance ``d`` from an edge, the top row and the vertically
    mirrored bottom row are moved toward the same midpoint.  The same operation
    is then applied to the left/right columns.  At distance zero the edge is
    changed most strongly; the blend falls linearly to a small amount at the
    inner edge of the border.
    """

    def strength(distance: int) -> float:
        # Keep a visible transition on the inner border row while making the
        # actual outermost edge the strongest correction.
        return (border - distance) / border

    for distance in range(border):
        amount = strength(distance)
        top_y = distance
        bottom_y = height - 1 - distance
        for x in range(width):
            top_index = top_y * width + x
            bottom_index = bottom_y * width + x
            target = _mix(pixels[top_index], pixels[bottom_index], 0.5)
            pixels[top_index] = _mix(pixels[top_index], target, amount)
            pixels[bottom_index] = _mix(pixels[bottom_index], target, amount)

    for distance in range(border):
        amount = strength(distance)
        left_x = distance
        right_x = width - 1 - distance
        for y in range(height):
            left_index = y * width + left_x
            right_index = y * width + right_x
            target = _mix(pixels[left_index], pixels[right_index], 0.5)
            pixels[left_index] = _mix(pixels[left_index], target, amount)
            pixels[right_index] = _mix(pixels[right_index], target, amount)


def make_seamless(image):
    """Return a copy with edge-mirrored RGB/RGBA pixels.

    Pillow modes other than RGB/RGBA are converted to RGBA so the operation is
    predictable for palette, grayscale, or indexed PNGs.  RGB/RGBA modes are
    retained so callers do not unexpectedly change ordinary tile assets.
    """

    if Image is None:  # pragma: no cover - guarded by main
        raise RuntimeError("Pillow is required to process tile images")

    if image.mode not in {"RGB", "RGBA"}:
        image = image.convert("RGBA")
    else:
        image = image.copy()

    width, height = image.size
    border = _effective_border(width, height)
    pixels = list(image.getdata())
    _blend_opposite_edges(pixels, width, height, border)
    image.putdata(pixels)
    return image, border


def _floor_candidate(paths: Iterable[Path]) -> Path | None:
    """Select a non-corridor floor source first for the tiling preview."""

    candidates = [path for path in paths if "floor" in path.stem.lower()]
    if not candidates:
        return None
    non_corridor = [path for path in candidates if "corridor" not in path.stem.lower()]
    return sorted(non_corridor or candidates, key=lambda path: path.name.lower())[0]


def _save_test_grid(image, output_dir: Path, source_path: Path):
    """Save a 3x3 repetition of the processed floor image."""

    width, height = image.size
    grid = Image.new(image.mode, (width * 3, height * 3))
    for row in range(3):
        for column in range(3):
            grid.paste(image, (column * width, row * height))
    output_path = output_dir / f"{source_path.stem}_test_grid.png"
    grid.save(output_path)
    return output_path


def process_image(source_path: Path, output_dir: Path):
    """Create the edge mask and seamless output for one source PNG."""

    if Image is None:  # pragma: no cover - guarded by main
        raise RuntimeError("Pillow is required to process tile images")

    with Image.open(source_path) as source:
        image, border = make_seamless(source)
        mask = make_edge_mask(source.size, border=border)

    mask_path = output_dir / f"{source_path.stem}_edge_mask.png"
    output_path = output_dir / f"{source_path.stem}_seamless.png"
    mask.save(mask_path)
    image.save(output_path)
    return output_path, mask_path, image, border


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-dir", required=True, help="directory containing source PNG tiles")
    parser.add_argument("--output-dir", required=True, help="directory for masks and seamless PNGs")
    parser.add_argument(
        "--test-grid",
        action="store_true",
        help="also save a 3x3 tiling preview of the first floor tile found",
    )
    args = parser.parse_args(argv)

    if Image is None:
        print(
            "ERROR: Pillow is not installed. Install it with 'python3 -m pip install Pillow' "
            "before processing tile PNGs.",
            file=sys.stderr,
        )
        return 2

    input_dir = Path(args.input_dir).expanduser()
    output_dir = Path(args.output_dir).expanduser()
    if not input_dir.is_dir():
        print(f"ERROR: input directory does not exist: {input_dir}", file=sys.stderr)
        return 2
    output_dir.mkdir(parents=True, exist_ok=True)

    sources = _source_pngs(input_dir)
    if not sources:
        print(f"No source PNGs found in {input_dir}")
        return 0

    successes = 0
    failures = 0
    floor_image = None
    floor_source = _floor_candidate(sources) if args.test_grid else None

    for source_path in sources:
        try:
            output_path, mask_path, image, border = process_image(source_path, output_dir)
        except (OSError, ValueError, RuntimeError) as exc:
            failures += 1
            print(f"FAIL {source_path.name}: {exc}", file=sys.stderr)
            continue

        successes += 1
        print(
            f"OK {source_path.name}: {output_path.name} "
            f"(mask={mask_path.name}, border={border}px)"
        )
        if floor_source == source_path:
            floor_image = image

    if floor_image is not None and floor_source is not None:
        try:
            grid_path = _save_test_grid(floor_image, output_dir, floor_source)
        except OSError as exc:
            failures += 1
            print(f"FAIL test grid for {floor_source.name}: {exc}", file=sys.stderr)
        else:
            print(f"OK test grid: {grid_path}")
    elif args.test_grid:
        print("No floor tile found; skipped --test-grid preview")

    print(f"\nSummary: {successes} processed, {failures} failures")
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
