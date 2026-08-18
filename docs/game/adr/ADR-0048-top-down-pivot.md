# ADR-0048: Top-Down Pivot — Supersedes ADR-0010/0017

**Date:** 2026-08-18
**Status:** Accepted
**Deciders:** Christopher Willoughby, architect (MiMo-v2.5-pro)

## Context

The Synaptic Sea was originally designed as a locked-isometric 3D space-horror survival sim. After completing all 18 simulation loops (PRs #50–#60), the project entered content/polish phase. Market research revealed:

1. **Asset availability gap**: Top-down sci-fi horror tilesets are far more available, affordable, and cohesive than isometric options. The Winlu Spaceship Tileset ($17.50) alone covers full ship interiors — iso options required heavy custom art.
2. **Failed 3D art pipeline**: Meshy image-to-3D → Blender pipeline produced concepts that were explicitly rejected as "terrible" for final game art.
3. **Budget efficiency**: $20.50 covers environment + enemies for top-down. Custom 3D outsourcing would have been 10×–30× more.
4. **Simulation is projection-agnostic**: All 18 closed loops in `scripts/systems/**.gd` operate on abstract state with no `Vector3` math in loop bodies.

## Decision

**Pivot from locked-iso 3D to orthogonal top-down 2D for the production art path.**

### What changes
- New `scenes/topdown/` tree with TileMap-based world (48px tiles)
- New presentation scripts: `TopDownCameraRig`, `TopDownPlayerController`, `TopDownThreatManager`
- New validation harness: `top_down_readability_harness.tscn`
- Winlu Spaceship Tileset as authoritative environment art

### What does NOT change
- All 18 simulation loops in `scripts/systems/**.gd`
- Save/load system (`scripts/systems/save_*.gd`)
- Audio manager + event router (`scripts/audio/**.gd`)
- Schema files (`data/schemas/**`, `data/procgen/**`)
- Inventory + smoke pipeline (`scripts/validation/**.gd`)
- Vertical slice contract (`docs/game/features/vertical_slice_v1.md`)

### What becomes frozen (smoke-only)
- `scenes/validation/locked_iso_readability_harness.tscn` — kept as 3D proof harness
- `scripts/camera/iso_camera_rig.gd` — frozen, loaded only by 3D harness
- `scenes/wrappers/structural/**` — frozen for content-audit diffs
- `assets/imported/**` (GLB files) — no new 3D assets ordered

## Consequences

- **Positive**: 10× cheaper asset pipeline, faster iteration, broader asset marketplace
- **Positive**: Simulation code untouched — zero regression risk
- **Negative**: Existing 3D vertical slice work becomes non-production (sunk cost)
- **Negative**: Coordinate system mismatch — old saves won't import (acceptable in pre-alpha)

## Supersedes

- ADR-0010 (locked-isometric decision)
- ADR-0017 (GLB wrapper pipeline)
