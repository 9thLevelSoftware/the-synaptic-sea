# Focused-Nine Airlock/Control Room Preview Design

## Purpose

Create a readable room-level review artifact for the focused-nine staged asset batch. The existing comparison capture is an asset-validation tableau; this preview proves that the proposed visual kit reads as one coherent locked-isometric space.

This is **not a promotion**. It must use only staged focused-nine GLBs and staged prop sidecars, and it must not modify live runtime imports, wrappers, manifests, generated bindings, or the canonical structural source root.

## Chosen approach

Use a disposable Godot review harness that composes staged GLBs in an isolated overlay/project view. This preserves the strongest value of a Godot proof—real import and scene rendering—without implying that staged visuals are active runtime content.

Rejected alternatives:

- Blender-only render: visually useful, but it would not prove Godot import/render behavior.
- Editing a live wrapper or procgen scene: more representative, but it would violate the no-promotion review boundary.

## Room composition

The room is a compact 3x3-cell airlock/control room at the established 4.0 m structural grid step.

- **Floor:** nine connected instances of staged `floor_1x1` form the 3x3 interior.
- **Entry:** staged `doorway_frame_open_1x1` on the south center. A staged `ramp_up_1x2` feeds the threshold without breaking the interior grid.
- **Airlock:** staged `pressure_door_1x1` is centered on the north wall in its intact role by default. The staged package remains the source of the wrapper/role metadata; damaged and breached are not displayed in the primary room image.
- **Walls:** staged `wall_straight_1x1` instances enclose the rear and side perimeter while preserving an open front/roof cutaway for locked-isometric readability.
- **Supports/ceiling:** staged `pillar_support_1x1` anchors the two rear corners. Staged `ceiling_cap_1x1` covers the rear portion, leaving a deliberate camera cutaway rather than closing the room into an unreadable box.
- **Props:** staged `fire_suppression_station` sits beside the entry; staged `hull_breach_seal_point` sits on a side wall as an emergency-repair focal point.

## Presentation

The harness uses the already proven locked-isometric camera orientation and produces one deterministic 1600x900 PNG.

Lighting and readability rules:

- dark navy environment rather than a pure-black void;
- directional key lighting with shadows;
- restrained cyan control/reactor accents from the staged assets;
- floor footprint, doorway, pressure door, and both props must be visible in the primary frame;
- no baseline asset lineup in this preview. Its single purpose is staged-room readability.

## Boundaries and failure behavior

1. Staged GLBs/sidecars are loaded from `assets/_staging/focused_nine` only.
2. The harness must reject a missing or symlinked staged dependency before capture.
3. It must assert the staged pressure-door package and both staged props validate before rendering.
4. Capture output is atomically published only after a successful non-headless Godot run with no `ERROR:`, `WARNING:`, or `SCRIPT ERROR:` diagnostics.
5. The normal runtime no-diff snapshot must cover imported assets, generated bindings, kit data, and live structural wrappers before and after the run.
6. Failures preserve the pre-existing preview artifact and report an exact causal blocker.

## Acceptance criteria

- A new isolated review scene and capture path exist; no live runtime scene is edited.
- The real Godot run exits 0 and emits an explicit room-preview pass marker.
- A valid non-empty 1600x900 PNG shows the complete 3x3 room composition described above.
- Staged pressure-door wrapper and both staged prop sidecars validate before capture.
- Existing focused-nine tests remain green, and dedicated scene/capture tests cover staged-only loading, composition placement, diagnostics rejection, and runtime no-diff.
- The committed proof records source staging paths, capture path, dimensions, validation results, and an explicit `no runtime promotion` statement.

## Non-goals

- Promoting any staged GLB or sidecar.
- Changing `assets/imported`, live wrappers, generated visual bindings, or kit manifests.
- Full procedural room generation, gameplay interaction, navigation, collision redesign, or final environment art direction.
- Treating this visual review as promotion approval.
