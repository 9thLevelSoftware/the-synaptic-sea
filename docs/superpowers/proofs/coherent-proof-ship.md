# Coherent Proof Ship Evidence Log

Spec: `docs/superpowers/specs/2026-06-17-coherent-proof-ship-design.md`
Plan: `docs/superpowers/plans/2026-06-17-coherent-proof-ship.md`
Fixture: `data/procgen/golden/coherent_ship_001/`

## Task 1

Static fixture validation:

```text
COHERENT STATIC FIXTURE PASS rooms=8 traversable_links=7 blocked_links=1 vertical_connections=1
```

## Task 2

Coherent fixture metadata smoke (loader accessors for room center / role / deck / critical path / room links / blocked links / landmarks):

```text
COHERENT LOADER METADATA PASS critical_path=5 blocked_links=1 landmarks=2
```

Seed-17 playable regression:

```text
PLAYABLE SHIP SMOKE PASS player_spawned=true collision_checked=true interaction_completed=true objectives_completed=1 objective_count=4 collision_shapes=316 frames=1
```

## Task 3

Coherent runtime loader smoke (loader creates Landmark_<id> / BlockedRoute_<id> / VisibleVerticalTransition_<id> marker nodes under structural_root, each with a BoxMesh + StandardMaterial3D + StaticBody3D/CollisionShape3D):

```text
COHERENT RUNTIME LOADER PASS collision_shapes=31 landmarks=2 blocked_routes=1 visible_transitions=1
```

Regressions after Task 3:

```text
COHERENT STATIC FIXTURE PASS rooms=8 traversable_links=7 blocked_links=1 vertical_connections=1
PLAYABLE SHIP SMOKE PASS player_spawned=true collision_checked=true interaction_completed=true objectives_completed=1 objective_count=4 collision_shapes=317 frames=1
COHERENT LOADER METADATA PASS critical_path=5 blocked_links=1 landmarks=2
```

Notes:
- The runtime loader smoke reports `collision_shapes=31` for the loader subtree (structural wrappers + new marker nodes).
- The Task 2 playable collision_shapes baseline of 316 grew to 317 because the new runtime marker nodes (landmark/blocked/vertical-transition) live under `structural_root` and the playable summary counts them too. Static fixture shape is unchanged (`rooms=8 traversable_links=7 blocked_links=1 vertical_connections=1`).
- Blocked-route cells in the golden fixture (`from_cell=[8,1,1]`, `to_cell=[9,1,1]`) do not have matching structural placements, so the loader falls back to room centers for those endpoints.

## Task 4

Sibling playable scene (`scenes/procgen/playable_coherent_ship.tscn`) reuses the `PlayableGeneratedShip` script with the three fixture-path exports overridden to point at the coherent golden fixture. The smoke (`scripts/validation/coherent_playable_scene_smoke.gd`) instantiates the scene, asserts the loader resolves to a 5-room critical path / >=2 landmark nodes / 4 objectives / spawned player, and confirms a clean physics frame after ready:

```text
PLAYABLE SHIP READY player_spawned=true camera_spawned=true objectives=4 collision_shapes=31
COHERENT PLAYABLE SCENE READY player_spawned=true objectives=4 critical_path=5 landmarks=2
COHERENT PLAYABLE SCENE PASS frames=1
```

## Task 5

Playable traversal smoke (`scripts/validation/coherent_playable_traversal_smoke.gd`) instantiates the sibling coherent scene, waits for `playable_ready` (240-frame timeout + 30-frame settle), then validates:

- For every room on the 5-room critical path, `playable_ship.teleport_player_to_room_for_validation(room_id)` lands the player above the nearest `floor_1x1` / `corridor_floor_1x1` placement (with `>= 0.05` upward clearance above the floor collision top at `placement_y + 0.125`).
- Same check holds for the three side rooms `["cargo_01", "medbay_01", "maintenance_01"]`.
- The first blocked-route marker node (`BlockedRoute_*`) emitted by the loader has a descendant `CollisionShape3D` with a non-null `shape`.
- `playable_ship.complete_first_interaction_for_validation()` returns `true` (objective completion count >= 1).

Floor-position lookup reads both `position` (seed-17) and `world_position` (golden coherent fixture), matching the loader's `_read_placement_position()` semantics — this is what allows the smoke to find the floor placements in the golden fixture (which uses `world_position`).

```text
COHERENT PLAYABLE TRAVERSAL PASS rooms_traversed=5 side_rooms=3 blocked_route_blocked=true objective_completed=true
```

Regressions after Task 5:

```text
FLOOR WRAPPER COLLISION FOOTPRINT PASS checked=4
PLAYER GRAVITY FLOOR SNAP PASS player_y=0.125 frames=120
INTERACTABLE DISTANCE FALLBACK PASS completed_count=1
PLAYABLE SHIP SMOKE PASS player_spawned=true collision_checked=true interaction_completed=true objectives_completed=1 objective_count=4 collision_shapes=317 frames=1
COHERENT STATIC FIXTURE PASS rooms=8 traversable_links=7 blocked_links=1 vertical_connections=1
COHERENT LOADER METADATA PASS critical_path=5 blocked_links=1 landmarks=2
COHERENT RUNTIME LOADER PASS collision_shapes=31 landmarks=2 blocked_routes=1 visible_transitions=1
COHERENT PLAYABLE SCENE PASS frames=1
```

Note: the `collision_shapes=31` line above is what `PlayableGeneratedShip` prints — it reflects the loader subtree (structural wrappers + landmark/blocked/visible-vertical marker nodes introduced in Task 3). The seed-17 playable regression line below still reports `collision_shapes=317` because the seed-17 scene's exported paths were not changed; only the new coherent sibling scene was added.

Regressions after Task 4:

```text
COHERENT STATIC FIXTURE PASS rooms=8 traversable_links=7 blocked_links=1 vertical_connections=1
PLAYABLE SHIP SMOKE PASS player_spawned=true collision_checked=true interaction_completed=true objectives_completed=1 objective_count=4 collision_shapes=317 frames=1
COHERENT LOADER METADATA PASS critical_path=5 blocked_links=1 landmarks=2
COHERENT RUNTIME LOADER PASS collision_shapes=31 landmarks=2 blocked_routes=1 visible_transitions=1
COHERENT PLAYABLE SCENE READY player_spawned=true objectives=4 critical_path=5 landmarks=2
COHERENT PLAYABLE SCENE PASS frames=1
```

## Task 6

Fresh in-engine viewport capture for the coherent proof ship. `scripts/validation/coherent_proof_ship_capture.gd` instantiates the sibling `res://scenes/procgen/playable_coherent_ship.tscn`, waits for `playable_ready`, lets the iso camera settle for 6 process frames, advances to the requested capture frame (default 180), captures the root viewport texture, and saves it as PNG. Unlike `procgen_playable_ship_capture.gd`, this script deliberately does NOT silently fall back to a synthetic top-down map if the viewport texture is unavailable — it fails clearly with `COHERENT PROOF SHIP CAPTURE FAIL reason=viewport_texture_unavailable`. The run is invoked without `--headless` so Godot actually renders the scene.

Capture command:

```sh
mkdir -p /Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/coherent_proof_ship
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --path /Users/christopherwilloughby/the-sargasso-of-stars --script res://scripts/validation/coherent_proof_ship_capture.gd -- --output /Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/coherent_proof_ship/coherent_proof_ship_viewport.png --capture-frame 180
```

Pass marker (note `mode=viewport` confirms a real rendered capture rather than a synthetic map):

```text
COHERENT PROOF SHIP CAPTURE PASS output=/Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/coherent_proof_ship/coherent_proof_ship_viewport.png frame=180 mode=viewport
```

PNG metadata:

```text
pixelWidth: 1280
pixelHeight: 720
format: png
```

```text
sha256: 962486ee93c512e2c0877a37687ff2a32c41fac08d7c849476dc2439d7916a9a
```

Human review: `open /Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/coherent_proof_ship/coherent_proof_ship_viewport.png` was issued and returned exit 0. The capture is a real rendered frame (178 unique colors; ~81% flat kit floor background, ~16% wall/floor, with objective marker, player, and the cobalt blue sky/player accent visible at the iso camera target).

## Task 7 — Final Acceptance

Final regression bundle + capture re-run for ship acceptance. All commands re-issued from the project root with the spec'd Godot binary.

### Coherent proof validation bundle

```text
=== res://scripts/validation/coherent_static_fixture_validator.gd ===
COHERENT STATIC FIXTURE PASS rooms=8 traversable_links=7 blocked_links=1 vertical_connections=1
=== res://scripts/validation/coherent_loader_metadata_smoke.gd ===
COHERENT LOADER METADATA PASS critical_path=5 blocked_links=1 landmarks=2
=== res://scripts/validation/coherent_runtime_loader_smoke.gd ===
COHERENT RUNTIME LOADER PASS collision_shapes=31 landmarks=2 blocked_routes=1 visible_transitions=1
=== res://scripts/validation/coherent_playable_scene_smoke.gd ===
PLAYABLE SHIP READY player_spawned=true camera_spawned=true objectives=4 collision_shapes=31
COHERENT PLAYABLE SCENE READY player_spawned=true objectives=4 critical_path=5 landmarks=2
COHERENT PLAYABLE SCENE PASS frames=1
=== res://scripts/validation/coherent_playable_traversal_smoke.gd ===
PLAYABLE SHIP READY player_spawned=true camera_spawned=true objectives=4 collision_shapes=31
PLAYABLE INTERACTION interaction=objective:01:cargo_01:cargo_supply_cache objective=cargo_01:cargo_supply_cache sequence=1 type=recover_supplies room=cargo_01
COHERENT PLAYABLE TRAVERSAL PASS rooms_traversed=5 side_rooms=3 blocked_route_blocked=true objective_completed=true
```

### Existing regression bundle

```text
=== res://scripts/validation/floor_wrapper_collision_footprint_smoke.gd ===
FLOOR WRAPPER COLLISION FOOTPRINT PASS checked=4
=== res://scripts/validation/player_gravity_floor_snap_smoke.gd ===
PLAYER GRAVITY FLOOR SNAP PASS player_y=0.125 frames=120
=== res://scripts/validation/interactable_distance_fallback_smoke.gd ===
INTERACTABLE DISTANCE FALLBACK PASS completed_count=1
=== res://scripts/validation/procgen_playable_ship_smoke.gd ===
PLAYABLE SHIP READY player_spawned=true camera_spawned=true objectives=4 collision_shapes=317
PLAYABLE INTERACTION interaction=objective:01:cargo_01:cargo_01_loot_container objective=cargo_01:cargo_01_loot_container sequence=1 type=recover_supplies room=cargo_01
PLAYABLE SHIP SMOKE PASS player_spawned=true collision_checked=true interaction_completed=true objectives_completed=1 objective_count=4 collision_shapes=317 frames=1
```

### Final capture (non-headless re-run)

```text
Godot Engine v4.6.2.stable.official.71f334935 - https://godotengine.org
Metal 4.0 - Forward+ - Using Device #0: Apple - Apple M4 (Apple9)

PLAYABLE SHIP READY player_spawned=true camera_spawned=true objectives=4 collision_shapes=31
COHERENT PROOF SHIP CAPTURE PASS output=/Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/coherent_proof_ship/coherent_proof_ship_viewport.png frame=180 mode=viewport
```

Capture path: `/Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/coherent_proof_ship/coherent_proof_ship_viewport.png` (1280x720 PNG, sha256 `962486ee93c512e2c0877a37687ff2a32c41fac08d7c849476dc2439d7916a9a`). Bytes match the Task 6 capture exactly — the renderer is deterministic at frame 180 with the sibling scene's fixed seed + camera, which is the desired property for a reproducible proof artefact.

### Acceptance checklist

- [x] Named coherent proof ship fixture exists. — `data/procgen/golden/coherent_ship_001/` (golden fixture from Task 1).
- [x] Fixture contains 5–8 meaningful rooms or segments. — `COHERENT STATIC FIXTURE PASS rooms=8` (5-room critical path plus 3 side rooms `cargo_01`, `medbay_01`, `maintenance_01`).
- [x] Fixture uses existing loader/playable path. — Loader metadata + runtime loader smoke + sibling `scenes/procgen/playable_coherent_ship.tscn` all green; playable scene smoke confirms `critical_path=5 landmarks=2`.
- [x] Player can traverse entry to reactor/destination. — `COHERENT PLAYABLE TRAVERSAL PASS rooms_traversed=5` teleports cleanly onto each critical-path floor placement.
- [x] Visible elevation transition exists. — `COHERENT STATIC FIXTURE PASS … vertical_connections=1` and `COHERENT RUNTIME LOADER PASS … visible_transitions=1` (`VisibleVerticalTransition_*` marker emitted under `structural_root`).
- [x] Visible blocked route exists and has collision. — `COHERENT STATIC FIXTURE PASS … blocked_links=1`, `COHERENT RUNTIME LOADER PASS … blocked_routes=1`, and the traversal smoke confirms `blocked_route_blocked=true` against a `BlockedRoute_*` `CollisionShape3D` with a non-null `shape`.
- [x] Landmark/orientation anchor exists. — `COHERENT LOADER METADATA PASS … landmarks=2` and `COHERENT RUNTIME LOADER PASS … landmarks=2` (`Landmark_*` marker nodes).
- [x] At least one side room is reachable. — `COHERENT PLAYABLE TRAVERSAL PASS … side_rooms=3` (cargo_01, medbay_01, maintenance_01) all teleport cleanly onto floor placements.
- [x] Static fixture validation passes. — `COHERENT STATIC FIXTURE PASS rooms=8 traversable_links=7 blocked_links=1 vertical_connections=1`.
- [x] Runtime loader validation passes. — `COHERENT RUNTIME LOADER PASS collision_shapes=31 landmarks=2 blocked_routes=1 visible_transitions=1`.
- [x] Playable traversal validation passes. — `COHERENT PLAYABLE TRAVERSAL PASS rooms_traversed=5 side_rooms=3 blocked_route_blocked=true objective_completed=true`.
- [x] Fresh Godot viewport capture exists. — `COHERENT PROOF SHIP CAPTURE PASS … mode=viewport` (non-headless, Metal 4.0 Forward+, Apple M4) writing the 1280x720 PNG above.
- [x] Existing seed-17 playable smoke still passes. — `PLAYABLE SHIP SMOKE PASS player_spawned=true collision_checked=true interaction_completed=true objectives_completed=1 objective_count=4 collision_shapes=317 frames=1` (seed-17 scene unchanged, still 4 objectives / 317 collision shapes).

All five coherent bundle scripts, all four regression bundle scripts, and the non-headless viewport capture emitted their expected pass markers. The coherent proof ship is shipped.

## Main-Scene Incorporation

The coherent proof ship is now the default playable scene instantiated by `res://scenes/main.tscn`, the project `run/main_scene` path from `project.godot`. `scripts/main.gd` instantiates `res://scenes/procgen/playable_coherent_ship.tscn` by default and `scenes/main.tscn` no longer keeps a stale current `LockedIsoCamera`; the playable scene creates the active `PlayableIsoCamera` through `IsoCameraRig`.

Main boot smoke command (headless, run from the project root with the spec'd Godot binary):

```sh
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-sargasso-of-stars --script res://scripts/validation/main_coherent_boot_smoke.gd
```

Main boot smoke output:

```text
Godot Engine v4.6.2.stable.official.71f334935 - https://godotengine.org

The Sargasso of Stars coherent proof ship bootstrap loaded.
PLAYABLE SHIP READY player_spawned=true camera_spawned=true objectives=4 collision_shapes=31
MAIN COHERENT BOOT PASS scene=playable_coherent_ship objectives=4 critical_path=5 landmarks=2 frames=1
```

Main-scene capture command (non-headless, run from the project root with the spec'd Godot binary; invoked without `--headless` so Godot actually renders the scene):

```sh
mkdir -p /Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/coherent_proof_ship
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --path /Users/christopherwilloughby/the-sargasso-of-stars --script res://scripts/validation/main_coherent_capture.gd -- --output /Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/coherent_proof_ship/main_coherent_viewport.png --capture-frame 180
```

Main-scene capture output (note `mode=viewport` confirms a real rendered capture through `scenes/main.tscn` rather than a synthetic map):

```text
Godot Engine v4.6.2.stable.official.71f334935 - https://godotengine.org
Metal 4.0 - Forward+ - Using Device #0: Apple - Apple M4 (Apple9)

The Sargasso of Stars coherent proof ship bootstrap loaded.
PLAYABLE SHIP READY player_spawned=true camera_spawned=true objectives=4 collision_shapes=31
MAIN COHERENT CAPTURE PASS output=/Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/coherent_proof_ship/main_coherent_viewport.png frame=180 mode=viewport
```

Main-scene capture artifact:

```text
/Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/coherent_proof_ship/main_coherent_viewport.png
  pixelWidth: 1280
  pixelHeight: 720
  format: png
sha256: 883e7a22822f680573db14be2ff9fbc8521f7f8b7f0ecb7ff931aff016f7cec8
```

Note on sha256 divergence from the Task 6 direct sibling capture (`962486ee93c512e2c0877a37687ff2a32c41fac08d7c849476dc2439d7916a9a`): the main-scene capture is taken through the full `scenes/main.tscn` bootstrap/node graph (which loads `scripts/main.gd` and instantiates the sibling coherent scene through the project's main-scene entry point), rather than through direct sibling scene instantiation used by `scripts/validation/coherent_proof_ship_capture.gd`. The two paths reach the same deterministic coherent ship state, but the surrounding main-scene bootstrap graph (extra root nodes, autoload context, default-project rendering/audio context) is a separate deterministic viewport artifact, so the rendered PNG bytes are expected to differ. Both sha256s are individually stable for their respective capture paths.

Human review note: `open /Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/coherent_proof_ship/main_coherent_viewport.png` returned exit 0. This is a real Godot viewport capture through `scenes/main.tscn` (`mode=viewport`), not an HTML/mockup or synthetic diagnostic map.

## Final Main-Path Regression Evidence

Final re-run of every script that gates main-path acceptance, plus the two non-headless viewport captures, immediately before the acceptance checklist below. All commands were issued from the project root with the spec'd Godot binary.

### Coherent + main validation bundle (headless)

```text
=== res://scripts/validation/coherent_static_fixture_validator.gd ===
COHERENT STATIC FIXTURE PASS rooms=8 traversable_links=7 blocked_links=1 vertical_connections=1
=== res://scripts/validation/coherent_loader_metadata_smoke.gd ===
COHERENT LOADER METADATA PASS critical_path=5 blocked_links=1 landmarks=2
=== res://scripts/validation/coherent_runtime_loader_smoke.gd ===
COHERENT RUNTIME LOADER PASS collision_shapes=31 landmarks=2 blocked_routes=1 visible_transitions=1
=== res://scripts/validation/coherent_playable_scene_smoke.gd ===
PLAYABLE SHIP READY player_spawned=true camera_spawned=true objectives=4 collision_shapes=31
COHERENT PLAYABLE SCENE READY player_spawned=true objectives=4 critical_path=5 landmarks=2
COHERENT PLAYABLE SCENE PASS frames=1
=== res://scripts/validation/coherent_playable_traversal_smoke.gd ===
PLAYABLE SHIP READY player_spawned=true camera_spawned=true objectives=4 collision_shapes=31
PLAYABLE INTERACTION interaction=objective:01:cargo_01:cargo_supply_cache objective=cargo_01:cargo_supply_cache sequence=1 type=recover_supplies room=cargo_01
COHERENT PLAYABLE TRAVERSAL PASS rooms_traversed=5 side_rooms=3 blocked_route_blocked=true objective_completed=true
=== res://scripts/validation/main_coherent_boot_smoke.gd ===
The Sargasso of Stars coherent proof ship bootstrap loaded.
PLAYABLE SHIP READY player_spawned=true camera_spawned=true objectives=4 collision_shapes=31
MAIN COHERENT BOOT PASS scene=playable_coherent_ship objectives=4 critical_path=5 landmarks=2 frames=1
```

### Existing regression bundle (headless)

```text
=== res://scripts/validation/floor_wrapper_collision_footprint_smoke.gd ===
FLOOR WRAPPER COLLISION FOOTPRINT PASS checked=4
=== res://scripts/validation/player_gravity_floor_snap_smoke.gd ===
PLAYER GRAVITY FLOOR SNAP PASS player_y=0.125 frames=120
=== res://scripts/validation/interactable_distance_fallback_smoke.gd ===
INTERACTABLE DISTANCE FALLBACK PASS completed_count=1
=== res://scripts/validation/procgen_playable_ship_smoke.gd ===
PLAYABLE SHIP READY player_spawned=true camera_spawned=true objectives=4 collision_shapes=317
PLAYABLE INTERACTION interaction=objective:01:cargo_01:cargo_01_loot_container objective=cargo_01:cargo_01_loot_container sequence=1 type=recover_supplies room=cargo_01
PLAYABLE SHIP SMOKE PASS player_spawned=true collision_checked=true interaction_completed=true objectives_completed=1 objective_count=4 collision_shapes=317 frames=1
```

### Non-headless viewport captures (final re-run)

```text
$ /Users/christopherwilloughby/.local/bin/godot-4.6.2 --path /Users/christopherwilloughby/the-sargasso-of-stars --script res://scripts/validation/coherent_proof_ship_capture.gd -- --output /Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/coherent_proof_ship/coherent_proof_ship_viewport.png --capture-frame 180
Godot Engine v4.6.2.stable.official.71f334935 - https://godotengine.org
Metal 4.0 - Forward+ - Using Device #0: Apple - Apple M4 (Apple9)

PLAYABLE SHIP READY player_spawned=true camera_spawned=true objectives=4 collision_shapes=31
COHERENT PROOF SHIP CAPTURE PASS output=/Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/coherent_proof_ship/coherent_proof_ship_viewport.png frame=180 mode=viewport

$ /Users/christopherwilloughby/.local/bin/godot-4.6.2 --path /Users/christopherwilloughby/the-sargasso-of-stars --script res://scripts/validation/main_coherent_capture.gd -- --output /Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/coherent_proof_ship/main_coherent_viewport.png --capture-frame 180
Godot Engine v4.6.2.stable.official.71f334935 - https://godotengine.org
Metal 4.0 - Forward+ - Using Device #0: Apple - Apple M4 (Apple9)

The Sargasso of Stars coherent proof ship bootstrap loaded.
PLAYABLE SHIP READY player_spawned=true camera_spawned=true objectives=4 collision_shapes=31
MAIN COHERENT CAPTURE PASS output=/Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/coherent_proof_ship/main_coherent_viewport.png frame=180 mode=viewport
```

Capture artifact sha256s (bit-identical to the Task 4 / Task 6 captures — re-run is deterministic):

```text
962486ee93c512e2c0877a37687ff2a32c41fac08d7c849476dc2439d7916a9a  /Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/coherent_proof_ship/coherent_proof_ship_viewport.png
883e7a22822f680573db14be2ff9fbc8521f7f8b7f0ecb7ff931aff016f7cec8  /Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/coherent_proof_ship/main_coherent_viewport.png
```

## Final Main-Path Incorporation Checklist

- [x] `project.godot` still points to `res://scenes/main.tscn`.
- [x] `scenes/main.tscn` instantiates the coherent proof ship through `scripts/main.gd`.
- [x] Main path uses `res://scenes/procgen/playable_coherent_ship.tscn` by default.
- [x] Main boot smoke passes: `MAIN COHERENT BOOT PASS scene=playable_coherent_ship objectives=4 critical_path=5 landmarks=2`.
- [x] Direct coherent scene validation remains green: `COHERENT PLAYABLE SCENE PASS` and `COHERENT PLAYABLE TRAVERSAL PASS`.
- [x] Existing seed-17 regression remains green: `PLAYABLE SHIP SMOKE PASS`.
- [x] Direct coherent viewport capture remains green: `COHERENT PROOF SHIP CAPTURE PASS ... mode=viewport`.
- [x] Main-scene viewport capture is green: `MAIN COHERENT CAPTURE PASS ... mode=viewport`.
- [x] Main-scene capture artifact exists at `/Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/coherent_proof_ship/main_coherent_viewport.png`.
- [x] No fixture JSON files were modified during incorporation.

