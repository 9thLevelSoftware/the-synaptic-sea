# Main Playable Slice v2 — Readable Ship, Real Props Design

Date: 2026-06-18
Project: The Synapse Sea
Godot project: `/Users/christopherwilloughby/the-synapse-sea-of-stars`
Godot version target: `4.6.2.stable.official.71f334935`
Workspace state: no git repository; use the no-git record ledger instead of commits.

## Purpose

Move the project out of proof-artifact churn by making the actual Godot main scene read like a crude but real playable derelict ship. The v1 slice proved that the main path can boot, move the player, show a HUD, complete four objectives, honor a blocked route and vertical transition, and capture viewport frames. It still looks like a validation harness: grey slabs, colored debug blocks, and in-world text labels.

The v2 readability slice should make the existing playable route understandable in-engine. A player should be able to launch the main scene, identify where they spawned, understand the route/spine, recognize objective objects, notice the blocked path, find the ramp/vertical transition, and understand the reactor/destination without relying on giant in-world text.

## Approved Direction

Use the combined direction selected during brainstorming:

1. **Navigation-first** — make the route readable before adding broader gameplay systems.
2. **Marker-to-prop conversion** — replace debug labels and colored blocks with simple semantic in-engine props.

This milestone is not another HTML/mockup/proof-image deliverable. Proof artifacts are allowed only as evidence after the actual playable scene has been improved.

## Current Baseline

The current main playable slice already has:

- main scene path: `res://scenes/main.tscn`
- coherent proof ship path: `res://scenes/procgen/playable_coherent_ship.tscn`
- runtime coordinator: `scripts/procgen/playable_generated_ship.gd`
- loader: `scripts/procgen/generated_ship_loader.gd`
- interaction component: `scripts/interaction/interactable.gd`
- HUD tracker: `scripts/ui/objective_tracker.gd`
- validation scripts for HUD, completion, affordances, input loop, traversal, procgen seed regression, and viewport capture
- proof log: `docs/superpowers/proofs/main-playable-slice-v1.md`

Recent verified markers included:

```text
MAIN PLAYABLE SLICE HUD PASS canvas_layer=true width=520 current_sequence=1
MAIN PLAYABLE SLICE COMPLETE PASS completed=4 current_sequence=5 run_complete=true
MAIN PLAYABLE SLICE AFFORDANCE PASS objectives=4 blocked=1 vertical=1 landmarks=2
MAIN PLAYABLE INPUT LOOP PASS moved=true camera_followed=true interaction_input_path=true current_sequence=2
MAIN PLAYABLE SLICE CAPTURE SEQUENCE PASS frames=6 mode=viewport output_dir=/Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/main_playable_slice_v1
```

The current limitation is visual readability, not basic playability.

## Design Goals

1. Make the actual main scene feel like a playable ship slice rather than a validation image.
2. Replace in-world debug text labels with semantic props and compact markers.
3. Make the critical route, blocker, ramp, objectives, and destination visible from the locked-isometric camera.
4. Preserve the existing objective sequence and interaction contract.
5. Keep loader, playable coordinator, interaction, HUD, and visual-prop responsibilities separated.
6. Add automated checks that semantic props exist and debug label clutter is not present in normal capture mode.
7. Produce a fresh viewport capture or short sequence only as evidence, after the in-engine scene is improved.

## Non-Goals

This slice does not implement combat, inventory, save/load, resource drain, enemies, final art, broad procgen generation changes, asset-pack ingestion, or more objectives. It also does not make a production-quality art pass. The goal is readable in-engine structure and props for the existing playable loop.

## Component Design

### Semantic Prop Wrappers

Create a small semantic set of simple in-engine props. These may be primitive meshes or lightweight wrapper scenes, but they must be named and placed as gameplay-readable objects rather than arbitrary debug geometry.

Initial prop set:

- `ObjectiveSupplyCache`
- `ObjectiveBreakerPanel`
- `ObjectiveMedTerminal`
- `ObjectiveReactorConsole`
- `BlockedBiomatter`
- `RampCue`
- `EntryBeacon`
- `DestinationReactorCore`

Each prop should have:

- a stable root node
- display geometry under a visual child or equivalent local grouping
- simple scale and local origin policy
- optional simple collision or interaction boundary only when needed
- a semantic name discoverable by validation scripts

The first implementation can use Godot primitives, color, emissive material, rings, panels, cylinders, boxes, and silhouettes. It should not wait on marketplace or generated art assets.

### PlayableGeneratedShip Visual Affordance Layer

`PlayableGeneratedShip` should remain the place where loaded ship markers become player-facing runtime affordances. Its normal mode should instantiate semantic props at objective, blocker, vertical-transition, entry, and destination marker positions.

The existing `Label3D` affordance path may remain as an optional debug mode, but normal gameplay and normal viewport capture should not show large in-world text labels. Text belongs primarily in the HUD.

### Route Readability Layer

Add lightweight readability elements to the coherent proof ship route:

- clearer floor or edge treatment for the critical path
- visible portal or doorway cues at route transitions
- blocker object placed directly at the blocked route
- ramp cue placed at the vertical transition
- destination/reactor silhouette visible enough to signal the endpoint
- entry beacon or spawn cue so the player understands where they began

The route does not need final walls everywhere. It needs enough in-engine geometry and hierarchy that a player can visually parse entry, route, branch/blocker, ramp, and destination.

### HUD Responsibility

The HUD remains the textual objective/progress source. It should show the current objective and progress, but it should not compensate for unreadable world geometry. In-world semantic props should carry the visual identity of objectives and route features.

## Data Flow

Current flow:

```text
layout/gameplay_slice data -> GeneratedShipLoader -> PlayableGeneratedShip -> labels/HUD/interactables
```

v2 flow:

```text
layout/gameplay_slice data
  -> GeneratedShipLoader marker positions
  -> PlayableGeneratedShip visual affordance layer
  -> semantic props + interactables + HUD
```

`GeneratedShipLoader` continues to expose ship structure and marker positions. It should not own player input, HUD, camera, or visual gameplay prop behavior.

`PlayableGeneratedShip` maps loaded marker data into runtime player-facing props:

- `recover_supplies` -> `ObjectiveSupplyCache`
- `restore_systems` -> `ObjectiveBreakerPanel`
- `download_logs` -> `ObjectiveMedTerminal`
- `stabilize_reactor` -> `ObjectiveReactorConsole`
- blocked route marker -> `BlockedBiomatter`
- vertical transition marker -> `RampCue`
- landmark/start/destination markers -> `EntryBeacon` and `DestinationReactorCore` where appropriate

The underlying interaction chain remains unchanged:

```text
Player.request_interact()
  -> interact_requested signal
  -> PlayableGeneratedShip._on_player_interact_requested
  -> Interactable.try_interact(player_body)
  -> completed signal
  -> objective sequence advances
```

## Normal Mode Versus Debug Mode

Normal gameplay/capture mode:

- semantic props are visible
- HUD text is visible
- giant `Label3D` world labels are hidden or not created
- compact icons/markers are allowed if they do not clutter the scene

Debug/validation mode:

- labels may be enabled for targeted tests
- validation scripts may inspect semantic node names and marker counts
- capture scripts must explicitly avoid showing every debug label at once

## Validation Design

Existing smokes must remain green:

- main playable slice HUD smoke
- completion smoke
- affordance count smoke
- input loop smoke
- main coherent boot smoke
- coherent traversal smoke
- procgen playable seed regression
- viewport capture sequence

Add or update readability validation to prove:

- all four objective semantic props exist
- blocker, ramp cue, entry beacon, and destination/reactor marker exist
- objective props are near their corresponding interactable positions
- normal capture mode does not show all debug labels at once
- normal capture mode exposes semantic prop nodes, not just text labels
- prop nodes have stable semantic names that validation can query

The validation should fail if the scene regresses to giant overlapping `Label3D` text as the primary visual evidence.

## Visual Proof Standard

Proof artifacts are secondary evidence, not the product. When generated, they must be real Godot viewport captures from the main playable path.

A successful proof bundle should include:

- one current contact sheet or short viewport sequence showing spawn, objective, blocker, ramp, and completion
- metadata and hashes for reproducibility
- explicit human/vision inspection of the pixels before claiming visual success
- a plain statement of remaining visual limitations

Do not accept file size, non-empty pixels, `open` exit status, or hashes alone as visual proof.

## Acceptance Criteria

The milestone is accepted when:

1. Launching the main scene shows the improved playable slice, not a separate proof scene.
2. The first objective is represented by a recognizable in-world object, not only text.
3. All four objective types have distinct semantic prop representations.
4. The blocked route is visibly blocked by an obstruction prop.
5. The ramp or vertical transition is visibly cued.
6. The entry/spawn and destination/reactor are visually identifiable.
7. The existing objective chain remains completable.
8. Existing v1 smokes and regressions pass.
9. New readability validation confirms semantic props and absence of normal-mode label clutter.
10. A fresh viewport artifact is visually inspected and judged readable enough for prototype v2, with limitations stated honestly.

## No-Git Recording

This workspace is not inside a git repository. The implementation plan should use the established fallback ledger pattern and append changed-file records to:

```text
/tmp/synapse_sea_main_playable_slice_v2_readability_no_git_changes.log
```

The design document itself should be recorded with:

```text
NO_GIT Main Playable Slice v2 Readability design changed: docs/superpowers/specs/2026-06-18-main-playable-slice-v2-readability-design.md
```

## Implementation Planning Boundary

Do not implement from this design directly. After user review and approval, invoke the writing-plans workflow to create a task-by-task implementation plan with verification commands and no-git recording steps.
