# Playable Generated Ship Prototype Design

Date: 2026-06-17
Project: The Synaptic Sea
Godot project: `/Users/christopherwilloughby/the-synaptic-sea-of-stars`
Procgen infra project: `/Users/christopherwilloughby/off-the-rails-ai-infra`

## Purpose

Move the project from a validated generated-ship/debug-runner prototype to the first genuinely playable generated-ship slice. The player should spawn inside a generated derelict ship, move through generated walkable spaces, interact with at least one generated objective or portal target, and preserve the existing deterministic procgen validation evidence.

This design targets the next accepted claim boundary from `docs/game/ship_structural_v0_resume_playbook.md`: playable prototype, not final gameplay or production art.

## Current Baseline

The structural/procgen foundation is real and currently green enough to build on:

- Canonical Godot project root: `/Users/christopherwilloughby/the-synaptic-sea-of-stars`
- Godot version verified: `4.6.2.stable.official.71f334935`
- Seed-17 runtime fixture currently loads:
  - `data/procgen/smoke/seed_000017/layout.json`
  - `data/procgen/smoke/seed_000017/gameplay_slice.json`
  - `data/kits/ship_structural_v0.json`
- Current fixture metrics:
  - 8 rooms
  - 316 structural wrapper placements
  - 135 floor-like placements
  - 135 unique floor-like positions
  - 0 duplicate floor-like positions
  - 4 ordered gameplay objectives
  - 1 vertical navigation link
- Current fresh verification evidence:
  - Focused test set: `25 passed in 109.38s`
  - Runtime demo smoke: `RUNTIME GAMEPLAY DEMO PASS objectives=4 interactions=4 frames=4320 final_distance=0.766`
  - Explicit gameplay smoke: `GAMEPLAY SMOKE PASS objectives=4 interactions=4 frames=4317 final_distance=0.766`
  - Walkthrough smoke: `WALKTHROUGH PASS frames=734 reached=true distance=0.787`

The current runtime is still not a player-facing game loop. It uses a debug runner and objective volumes to prove generated navigation and objective ordering. The next step is to add player-controlled traversal and interaction while preserving the validation harnesses.

## Design Goals

1. A human can launch the main scene and control a visible placeholder player inside the generated ship.
2. The player can move through generated walkable spaces using a locked-isometric camera.
3. Structural collision blocks at least walls or closed blockers in a simple sanity check.
4. The player can complete at least one generated objective through interact input.
5. The existing seed-17 four-objective debug route remains green.
6. The implementation keeps loader, player, camera, interaction, UI, and validation responsibilities separated.
7. The new validation distinguishes debug-runner route proof from player-facing playability proof.

## Non-Goals

This pass does not implement combat, inventory, economy, save/load, encounter pacing, production art, hub-ship state management, arbitrary room shapes, solver rewrites, final lighting, or full game progression. It also does not claim broad random-seed gameplay readiness.

## Recommended Approach

Build a playable generated-ship gate around the existing `ship_structural_v0` runtime path.

Rejected alternatives:

1. Gameplay/content expansion first.
   - This would add more objectives and roles, but without a player-controlled loop it only enriches the debug runner.
2. Visual readability/art first.
   - This would make the prototype more appealing, but it risks hiding the still-unproven player traversal and interaction gate.
3. More structural topology first.
   - The structural foundation is already the strongest layer. More topology work should be driven by failures in the playable gate, not by default.

## Runtime Architecture

```text
main.tscn
  Main
    PlayableGeneratedShipScene
      GeneratedShipLoader
        StructuralRoot
        ObjectiveRoot
        NavigationRegion3D
        NavigationLink3D...
      PlayerController
      IsoCameraRig
      ObjectiveTracker
      InteractionRoot
        Interactable...
```

### GeneratedShipLoader

`GeneratedShipLoader` remains the source of truth for turning `layout.json`, `ship_structural_v0.json`, and `gameplay_slice.json` into runtime nodes.

Responsibilities:

- Load and validate fixture data.
- Resolve module ids to wrapper scenes.
- Instantiate structural wrappers.
- Build or expose navigation/collision affordances.
- Expose start room, goal room, objective specs, objective world positions, and portal or doorway placements.
- Emit explicit load success/failure signals.

It should not own player movement, camera behavior, input, or objective UI.

### PlayableGeneratedShipScene

This scene coordinates the playable slice.

Responsibilities:

- Load the deterministic seed-17 fixture for the first playable gate.
- Spawn the player at the generated start room.
- Attach the locked-isometric camera rig to the player.
- Initialize objective UI from `gameplay_slice.json`.
- Convert generated objective/portal metadata into interactable runtime nodes.
- Report playability status to validation scripts.

For the first pass, this should wrap the existing generated ship demo rather than destructively renaming it. The existing debug demo and validation scripts should remain usable until the new playable path is proven.

### PlayerController

A new `CharacterBody3D` placeholder player.

Responsibilities:

- WASD movement in locked-isometric space.
- Collision-driven movement across generated floors.
- Interact action dispatch, defaulting to `E`.
- Visible placeholder mesh or capsule.

This component should not parse procgen data and should not know about objective ordering beyond receiving interactable signals.

### IsoCameraRig

A separate locked-isometric camera rig.

Responsibilities:

- Follow the player.
- Use a fixed orthographic/isometric angle.
- Keep seed-17 traversal readable.

Camera tuning should stay separate from movement and loader code.

### Interactable

A small reusable component for player-facing interactions.

Responsibilities:

- Store `interaction_id`.
- Optionally store `objective_id` when tied to objective completion.
- Store prompt text.
- Detect player-in-range state.
- Complete when the player presses interact while eligible.
- Emit completion signals.

For this pass, interaction can be simple: press `E` while inside range. The green debug objective volumes may remain as validation helpers or visual prompt markers, but they should not be the whole gameplay abstraction.

### ObjectiveTracker

The existing tracker should be lightly upgraded.

Responsibilities:

- Read ordered objectives from `gameplay_slice.json` through the playable scene.
- Display current objective and completed objectives.
- Update from real player interaction events.
- Report final completion state.

## Data Flow

1. Load deterministic generated fixture:
   - `layout.json`
   - `ship_structural_v0.json`
   - `gameplay_slice.json`
2. `GeneratedShipLoader` creates runtime structural wrappers, objective metadata, and navigation affordances.
3. `PlayableGeneratedShipScene` spawns the player at the generated start room.
4. `IsoCameraRig` follows the player.
5. `ObjectiveTracker` displays ordered objectives.
6. `Interactable` nodes are created for generated objective targets and at least one door or portal target.
7. The player moves, reaches an interaction target, presses interact, and advances objective state.
8. Validation scripts verify both existing debug-runner completion and new player-facing playability behavior.

The playable scene starts with deterministic seed 17. Random seed coverage should be added only after this fixture passes the playable gate.

## Error Handling

The playable path should fail loudly and specifically.

- Missing data file: fail startup with the exact path.
- Missing wrapper scene: fail with module id and expected `res://` path.
- Missing start room: fail with `start_room` id.
- Missing goal room: fail with `goal_room` id.
- Missing objective: fail with objective id and sequence.
- Objective sequence mismatch: fail, because route order must stay deterministic.
- Missing objective approach cell: fail with objective id and room id.
- Objective target is generated but unreachable: validation fail.
- Structural blockers lack collision in sanity check: validation fail.
- Debug runner pass alone: not accepted as playable pass.

## Testing and Verification Gates

Minimum gates before claiming the playable generated-ship prototype works:

1. Existing focused tests still pass.
2. Existing runtime demo smoke still passes with `RUNTIME GAMEPLAY DEMO PASS objectives=4 interactions=4`.
3. Existing explicit gameplay smoke still passes with `GAMEPLAY SMOKE PASS objectives=4 interactions=4`.
4. New playable smoke passes and reports:
   - `PLAYABLE SHIP SMOKE PASS`
   - `player_spawned=true`
   - `collision_checked=true`
   - `interaction_completed=true`
   - `objectives_completed>=1`
5. A fresh Godot capture PNG exists for the playable scene. This proves the scene renders; it does not prove final visual quality.
6. Manual launch from the main scene allows a human to move the placeholder player and complete at least one generated interaction.

Recommended verification commands will be finalized in the implementation plan, but should include headless Godot smoke commands and pytest wrappers from `/Users/christopherwilloughby/off-the-rails-ai-infra`.

## File Scope

Likely Godot project additions:

- `scenes/procgen/playable_generated_ship.tscn`
- `scripts/procgen/playable_generated_ship.gd`
- `scripts/player/player_controller.gd`
- `scripts/camera/iso_camera_rig.gd`
- `scripts/interaction/interactable.gd`
- `scripts/validation/procgen_playable_ship_smoke.gd`

Likely Godot project modifications:

- `scripts/main.gd`
- `scripts/procgen/generated_ship_loader.gd`
- `scripts/ui/objective_tracker.gd`
- Possibly `scenes/procgen/generated_ship_demo.tscn` only if wrapping is insufficient.

Likely infra project additions:

- A pytest wrapper for the new playable smoke under `/Users/christopherwilloughby/off-the-rails-ai-infra/tests/`.

Likely validation and cleanup checks:

- Verify structural wrapper collision is meaningful enough for the sanity gate.
- Fix only collision defects that block the playable gate.
- Do not start broad art or topology changes inside this pass.

## Acceptance Criteria

The spec is implemented when:

1. The main scene can load the playable generated ship scene.
2. A visible placeholder player spawns at the generated start room.
3. The player can be moved by human input through generated walkable spaces.
4. A locked-isometric camera follows the player.
5. At least one generated objective or portal target can be completed by player interact input.
6. Objective UI updates from player-facing interaction events.
7. Structural collision sanity validation passes for blockers required by the playable path.
8. Existing debug-runner route validation still passes for the four seed-17 objectives.
9. New playable smoke validation passes independently of debug-runner success.
10. A fresh capture artifact is produced from the playable scene.

## Deferred Work

After this gate passes, strong next candidates are:

1. Hub ship and biomatter-web top-level loop.
2. Expanded generated objective/content variety.
3. Room identity and visual readability pass.
4. Production interaction UX and prompts.
5. Inventory, oxygen, repair, combat, and encounter pacing.
6. Broader random-seed playability statistics.

## Repository Note

At spec-writing time, `/Users/christopherwilloughby/the-synaptic-sea-of-stars` and `/Users/christopherwilloughby/off-the-rails-ai-infra` did not contain a `.git` repository from the shell. The design document can be written to disk, but a normal `git add` / `git commit` cannot succeed until the workspace is placed under git or the user chooses a repository target.
