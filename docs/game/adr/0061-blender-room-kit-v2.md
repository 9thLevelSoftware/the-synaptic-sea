# ADR-0061: Procgen-safe Blender room kit v2

Shared art measurements: `data/art/structural_visual_dimensions.v1.json`. This art-only policy does not replace source-attestation or runtime collision/navigation authority.

Status: Accepted for implementation; assets remain staged and runtime promotion remains closed.

## Supersession notice

The shared modular-fit policy and runbook in [`docs/game/features/modular_structural_fit.md`](../features/modular_structural_fit.md) is canonical for structural visual dimensions. It supersedes the older room-kit plan's zero-depth visual paragraph and blanket bevel rule. This ADR retains the room-kit roster, source-recovery scope, placement ownership, and review obligations, but no longer treats legacy local bounds as visual geometry authority. The mirrored feature document carries the same notice.

## Context

The room kit needs readable salvage-industrial structural visuals without changing procgen placement, sockets, wrapper collision, navigation, or source provenance. Research supports predetermined thickness, reserved joining space, a shared walking datum, and target-renderer assembly tests; it does not prove that existing staged assets pass. The local ledger is `artifacts/room_kit_v2/research/2026-09-08_154121-modular-fit/research-brief.txt` and cites the Level Design Book, Godot GridMap/Camera3D/StandardMaterial3D/Decal documentation, Epic's FBX pipeline guidance, Bethesda modular-level guidance, Frozenbyte trim-sheet guidance, and Vuk Banovic's modular-kit workflow.

Root-code authority remains `scripts/procgen/walkability_contract.gd`, the structural compiler/placement consumers, per-module placement contracts, `.tres` companions, and Godot wrappers. The visual policy is art-only and must not migrate source attestation or become a second physics authority.

## Decision

Retain the existing source → staged GLB → sidecar/derived-index → factory/binder → generated-ship pipeline. Structural sources remain editable recovered `.blend` files with source records and locked contract-derived helpers. Exported visual collections are validated from fresh temporary GLBs before staged replacement. Every requested variant must pass before any variant is published to staging. Runtime promotion checks source-authority HOLD before backup/copy and remains closed while the A/B source-authority decision is unresolved.

Adopt the shared visual policy:

- 4 m lattice; floor top `Y=0`; floor underside `Y=-0.25`.
- Positive walkable relief `0`; recesses at most `0.02` m outside protected walking guards.
- Wall/top height `3.2` m.
- The complete edge visual envelope is `0.20` m deep, normal `[-0.10,+0.10]`. There is no additional outward decoration allowance: recess detail or use materials inside that same envelope.
- `terminal_mating_band_m` = `0.20` m along the edge tangent at each terminal. Preserve its full `3.2` m height and `0.20` m depth, including planar end faces and continuous band surfaces. No bevel, trim, greeble or damage may consume it.
- Doorway clear opening `1.2 × 2.2` m with no raised threshold.
- The pillar `footprint_cells` is `[1,1]` on the `4.0` m lattice, with centered X/Z contacts and Y contacts at `0` and `3.2`. The policy reserves that cell footprint; it does not prescribe a separate cosmetic body width or a filled-cell cube.
- Preserve helper mapping `[x, y, z] → [x, z, y]`; physical Blender geometry uses glTF axes `[x, z, -y]`.
- Use flat/color textures, normals, and trim sheets for small detail; use actual geometry only for readable large features and silhouette changes. For Godot Compatibility, prefer baked materials or tightly bound non-colliding overlays with deliberate depth sorting; do not rely on Decal rendering or blanket offsets.

Seven profiles are automatically supported by this policy: `floor_1x1`, `floor_2x1`, `corridor_floor_1x1`, `corridor_floor_1x2`, `wall_straight_1x1`, `doorway_frame_open_1x1`, and `pillar_support_1x1`. Every other module ID requires a reviewed profile and fails closed as `hold`; it is not automatically a bad-geometry failure. `ramp_up_1x2` remains HOLD because its endpoint transform is not authorized.

## Gate boundary

The implemented per-module path may validate policy data, transformed triangles, floor datum/underside, recess/relief, interface coverage, doorway triangle intersection, pillar contacts/envelope, and imported helper/transform leakage. The source/helper validator remains separate from the visual-fit gate.

The new core preflight does **not** automatically implement whole-assembly acceptance. Full review still requires four rotations; straight floor/wall joins; door corners; inner/outer corners; T-junctions; a mixed-length 2×2 floor patch; a closed room-to-corridor loopback; a mixed-length vertical stack with deliberate gap/overlap negatives; clay and material evidence from the actual production camera; variant interface parity; and separate visual-floor, collision, navigation, and doorway-clearance evidence. A geometric PASS is not promotion approval.

The implemented visual-fit command is:

```bash
blender --background --factory-startup --python-exit-code 1 \
  --python tools/validate_structural_visual_fit.py -- \
  --project-root ROOT --module ID --glb PATH --report PATH
```

The checked-in exporter validates every temporary GLB before `os.replace`, and the promoter checks source-authority HOLD before backup/copy; these implementation facts do not constitute asset approval.

## Consequences

Accessor-only bounds and numeric contract checks cannot approve artwork. Widening/scaling the visual shell is allowed when it preserves the existing helper and placement contract; editing helpers, wrapper physics, nav, sockets, or placement JSON is not. Existing baseline defects remain HOLD; this ADR does not claim old baselines all pass. A/B source authority and ramp decisions remain HOLD. This documentation update authored no assets and approved no assets for promotion.
