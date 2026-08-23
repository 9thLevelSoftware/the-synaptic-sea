# Salvage-Industrial Golden Room Design

## Goal

Turn the staged focused-nine airlock/control room into the visual reference for the structural kit: a readable, connected, salvage-industrial interior that looks intentional at the locked-isometric gameplay distance. The room is the asset-quality gate, not a procgen milestone and not a runtime promotion.

## Scope

Polish the existing focused-nine staged assets first:

- Structural: `floor_1x1`, `wall_straight_1x1`, `doorway_frame_open_1x1`, `pillar_support_1x1`, `ramp_up_1x2`, `ceiling_cap_1x1`.
- Door: `pressure_door_1x1` intact, damaged, and breached variants.
- Props: `hull_breach_seal_point`, `fire_suppression_station`.

All authoring remains deterministic Blender source generation under the parallel focused structural source root and staged-only GLB publication. Existing live assets, runtime wrappers, manifests, and procgen mappings remain unchanged until a separate explicit promotion decision.

## Visual Language

### Base construction

- Dark painted alloy is the base material, broken into deliberately sized panels rather than a featureless surface.
- Each structural module carries a clear primary silhouette plus one secondary mechanical layer: a recessed service channel, seam, rib, bracket, access panel, or conduit route.
- Edges are selectively beveled or inset where they catch the isometric key light. The goal is readable form, not dense micro-detail.

### Salvage history

- Wear is localized and causal: welded reinforcement plate near a breach, a replaced access panel near a service run, scrape/heat discoloration near a door threshold, and repair clamps on a pillar or wall.
- No uniform noise, random decal scattering, or identical damage patterns across every instance.
- The intact pressure door is maintained but used; damaged and breached variants show increasingly specific structural failure while preserving the same connector/silhouette contract.

### Lighting and signal color

- The room remains predominantly cool dark alloy.
- Cyan is reserved for live status/system cues; amber marks warnings, access points, and repair/maintenance zones; red appears only for faults/emergencies.
- Emissives frame decisions and circulation rather than becoming decorative wallpaper.

## Asset-Level Requirements

| Asset family | Golden-room role | Required refinement |
|---|---|---|
| Floors and ramp | navigation/readability | connected panel flow, recessed service tracks, directional threshold detail, controlled anti-slip/rib treatment |
| Straight wall and pillar | room silhouette | wall panel hierarchy, one exposed conduit/service run, sparse repair brackets; pillar gets structural ribs and cable/utility anchor points |
| Ceiling | environmental density | recessed overhead service tray, vent/grille rhythm, a restrained practical/emissive recess; it must read as a ceiling from the cutaway camera |
| Doorway and pressure door | transitions/state | substantial frames, threshold cues, mechanical rails/seals, state-specific damage that remains legible at the standard camera |
| Breach seal and fire station | functional landmarks | believable mounting plates, hose/cable/handle silhouette, cyan/amber/red status differentiation, placement flush to their supporting structure |

## Material Contract

Retain canonical material identity and provenance. Reuse the established structural palette where appropriate; any new canonical material must be explicitly added to the controlled library/provenance contract before use. Do not silently create Blender `.001` material variants.

Texture work is optional in this first pass. Geometry, material value/roughness contrast, and emissive behavior must already communicate the design without relying on high-frequency textures.

## Quality Bar

At the 1600x900 locked-isometric room capture:

1. The room reads as one connected industrial environment, not tiled samples.
2. A player can distinguish traversable floor, wall boundary, threshold, ceiling, pressure door, repair/hazard location, and two functional props in under five seconds.
3. Structural repetition is masked by orientation, panel hierarchy, and purposeful localized variation—not random per-instance geometry.
4. Every focused asset remains valid under source, staged evidence, wrapper/prop, material provenance, and no-runtime-diff gates.
5. The improved room renders with no unexpected Godot diagnostics and passes the staged-only preview runner.

## Non-Goals

- No runtime promotion or rewrite of procgen placement.
- No broad texture library, character art, enemies, gameplay redesign, or final lighting system.
- No unbounded new asset catalog before the golden room passes review.

## Review Sequence

1. Produce deterministic candidate source/staged assets for the existing focused-nine set.
2. Run all source/material/evidence contracts before updating the room preview.
3. Render the staged-only golden room and inspect it visually against the baseline capture.
4. Accept, revise, or reject individual asset families based on the quality bar.
5. Derive the next structural expansion batch—corners, T-junctions, end caps, corridor/door variants—from the accepted language.

## Canonical Structural Compiler and Capture Policy (Task9)

`StructuralEdgePlan` is the sole boundary authority. `StructuralEdgeCompiler` may
compile its records and `StructuralPlanValidator` may reject an invalid plan, but
no resolver, placer, loader, capture harness, or visual asset may derive a second
wall/door boundary, pose, or placement identity. The canonical inventory is the
sorted tuple of `placement_id`, `edge_key`, `kind`, `state`, `module_id`, pose,
and `room_ids` emitted by the validated structural plan.

The legacy `wall_door_resolver` is an adapter for legacy debug/serializer callers;
it is not a competing production authority. `structural_placer` is a legacy
debug-only room visualizer and must never be used by `ShipGenerator` or a capture
path to create production geometry. Any new boundary behavior belongs in the
compiler/plan contract first, with resolver and placer output treated as
diagnostic compatibility views only.

Runtime capture and staged capture have separate policies. Runtime capture uses
the live wrapper catalog and proves that instantiated wrapper metadata is backed
one-for-one by the canonical plan. Staged capture runs the disposable overlay
runner, which mounts staged GLBs/materials at canonical import/wrapper paths
without promoting them into the runtime tree. The Task9 parity smoke compares
only the structural inventory across those paths: GLB, material, and scene-path
differences are permitted visual differences, while any structural plan drift
fails the gate. A staged capture is evidence, not a runtime promotion decision.
