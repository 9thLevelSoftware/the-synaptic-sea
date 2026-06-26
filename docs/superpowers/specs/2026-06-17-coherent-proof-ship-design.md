# Coherent Proof Ship Design

Date: 2026-06-17
Project: The Synaptic Sea
Godot project: `/Users/christopherwilloughby/the-synaptic-sea-of-stars`
Godot version: `4.6.2.stable.official.71f334935`

## Purpose

Build one curated 5–8 room derelict ship proof that establishes spatial coherence before expanding gameplay systems. The current playable generated ship can launch and pass smoke validation, but the next priority is making the ship read as a connected place instead of isolated rooms or box clusters.

The player should understand where they entered, how spaces connect, where elevation changes happen, what route is blocked, and where the destination lies. This slice is the canonical human-readable target that future procedural generation should learn to reproduce.

## Current Baseline

The project already has a deterministic playable generated-ship prototype:

- Main scene: `res://scenes/main.tscn`
- Playable scene: `res://scenes/procgen/playable_generated_ship.tscn`
- Loader: `res://scripts/procgen/generated_ship_loader.gd`
- Player controller: `res://scripts/player/player_controller.gd`
- Camera rig: `res://scripts/camera/iso_camera_rig.gd`
- Interaction component: `res://scripts/interaction/interactable.gd`
- Objective tracker: `res://scripts/ui/objective_tracker.gd`

Fresh validation before this design included:

```text
FLOOR WRAPPER COLLISION FOOTPRINT PASS checked=4
PLAYER GRAVITY FLOOR SNAP PASS player_y=0.125 frames=120
INTERACTABLE DISTANCE FALLBACK PASS completed_count=1
PLAYABLE SHIP SMOKE PASS player_spawned=true collision_checked=true interaction_completed=true objectives_completed=1 objective_count=4 collision_shapes=316 frames=1
```

This proves the prototype can launch, spawn a player, settle onto floors, and complete at least one interaction. It does not prove the ship is spatially coherent or readable.

## Approved Approach

Use a curated data-driven proof ship.

The layout should be intentionally designed by hand, then encoded as fixture data consumed by the existing Godot loader path. It should not be a hand-only Godot diorama, and it should not require a broad random-generator rewrite before there is a readable target.

Rejected alternatives:

1. Hand-authored Godot scene first
   - Fastest visible result, but risks becoming a one-off scene outside the real pipeline.
2. Generator-first rules rewrite
   - Strong long-term direction, but too abstract before the project has a clear human-readable target.

The approved path is a hybrid: design one coherent ship deliberately, encode it as a named golden fixture, validate it in-engine, and later use it as the standard for generator improvements.

## Design Goals

1. Provide one canonical in-engine derelict ship that reads as a connected place.
2. Keep the proof ship within 5–8 meaningful rooms or segments.
3. Preserve the existing loader/playable-scene architecture.
4. Demonstrate a readable entry, route, branch structure, blocked route, elevation transition, landmark, and destination.
5. Prove the player can walk the designed route in Godot.
6. Produce a fresh Godot viewport capture as visual proof.
7. Add validation that fails if the ship is technically traversable but spatially incoherent.

## Non-Goals

This slice does not implement combat, inventory, oxygen, repair mechanics, save/load, final art, broad content variety, random seed statistics, or a full procedural generation rewrite. It also does not need production-quality ship dressing. Its job is spatial coherence.

## Spatial Target

The proof ship should feel like a small derelict with a clear route and side spaces.

Recommended room and segment set:

1. Airlock / breach entry
   - Player origin and orientation anchor.
   - Establishes where the player entered.
2. Decompression corridor
   - Narrow transition from entry into the body of the ship.
3. Visible ramp or ladder transition
   - A clear physical and visual deck/elevation change.
   - Must not exist only as navigation metadata.
4. Central spine
   - Main route axis.
   - Includes a landmark visible from multiple positions.
5. Cargo bay
   - A side room with open volume and cover-like silhouettes.
   - Can host one objective marker.
6. Med nook or crew nook
   - Small identity room that proves side-room variety.
   - Can be merged into another room if the fixture needs to stay at seven rooms.
7. Maintenance room
   - Secondary side room with machinery or repair identity.
   - Can host a second objective marker.
8. Control / overlook and reactor destination
   - The destination may be a reactor room with a nearby control overlook, or control may be its own small room if the layout remains readable.

The preferred structure is a central spine with branches rather than a pure linear corridor. The player should be able to see or foreshadow the reactor/destination before reaching it.

## Spatial Requirements

Hard requirements:

- The ship has 5–8 meaningful rooms or segments.
- There is at least one non-straight turn or branch.
- There is at least one visible deck or elevation transition.
- There is at least one visible blocked route.
- There is at least one landmark visible from the central spine.
- The reactor or destination is visible or foreshadowed before arrival.
- The player can traverse from entry to destination without debug-only teleporting.
- The blocked route is visible but not accidentally traversable.

Acceptance feel:

The player should be able to say: “I entered here, transitioned decks there, followed the spine, saw the reactor, found side rooms, and understood why one path was blocked.”

## Data Model

Create a named golden fixture rather than mutating the current seed-17 smoke fixture in place.

Recommended fixture naming:

- `data/procgen/golden/coherent_ship_001/layout.json`
- `data/procgen/golden/coherent_ship_001/gameplay_slice.json`

The fixture should continue to reference the existing `ship_structural_v0` kit unless a missing wrapper blocks the proof.

The data may add minimal explicit metadata for concepts that the current fixture only implies poorly:

- room ids and roles
- deck/elevation level per room or placement
- door or portal links between rooms
- blocked links or blocked doorways
- vertical transition links
- landmark markers
- start marker
- destination marker
- objective markers

The design should not introduce a broad new ship DSL in this slice. Add the smallest fields needed to make the proof ship unambiguous and validatable.

## Component Boundaries

### Fixture data

Defines what the proof ship is:

- rooms
- cells or placement positions
- deck heights
- doors and portals
- blocked routes
- vertical transitions
- landmarks
- objective markers
- start and destination markers

### GeneratedShipLoader

Turns fixture data into runtime structure:

- loads layout, gameplay slice, and kit catalog
- instantiates wrapper scenes
- creates visible doors, blocked routes, and vertical transition placements
- exposes spawn, destination, objective, landmark, and route marker queries
- reports exact load failures

The loader must not own player movement, camera behavior, prompt behavior, or objective progression.

### PlayableGeneratedShip

Wires gameplay components onto the loaded ship:

- spawns player at the airlock or breach entry
- attaches locked-isometric camera
- initializes objective tracker
- creates interactable prompts from fixture objective markers
- reports playability state to validation scripts

### Validation scripts

Prove the fixture is coherent before it is accepted:

- static topology checks
- runtime loader checks
- playable traversal checks
- visual capture generation

## Error Handling

The proof ship path should fail loudly and specifically.

Required failures:

- Missing golden fixture file reports the exact path.
- Invalid JSON reports the exact path and parse failure.
- Duplicate room id fails static validation.
- Door or portal target references a missing room fails static validation.
- Start room or destination room is missing fails static validation.
- Destination is unreachable from airlock through declared traversable links fails static validation.
- Blocked links are included in traversable route graph fails validation.
- Declared vertical transition has metadata but no visible or physical runtime representation fails runtime validation.
- Player start and destination are on mismatched decks without a declared transition fails validation.
- Blocked route is physically traversable fails playable validation.
- Player can technically reach the destination but the capture is unreadable or box-like fails design review.

## Testing and Verification Gates

### 1. Static fixture validation

Validates fixture data without launching the full playable scene.

Required checks:

- Fixture JSON files parse.
- Room ids are unique.
- Required roles or segments are present: entry, spine, vertical transition, destination.
- Doors and portals reference valid rooms.
- Blocked links are represented separately from traversable links.
- Airlock can reach all required rooms through traversable links.
- Reactor or destination can be reached from airlock.

### 2. Runtime loader validation

Validates that Godot can instantiate the fixture.

Required checks:

- Loader can load the named golden fixture.
- All referenced wrapper scenes exist.
- Floor collision footprint sanity still passes.
- Collision shape count is nonzero.
- Visible landmark node exists.
- Visible blocked route node exists.
- Vertical transition has a physical or visible runtime representation.

### 3. Playable validation

Validates player-facing traversal.

Required checks:

- Player spawns at airlock or breach entry.
- Player can move from entry to central spine.
- Player can traverse the declared vertical transition.
- Player can reach at least one side room off the spine.
- Player can reach the reactor or destination.
- Blocked route is not traversable by player movement.
- At least one objective or destination interaction can complete.

### 4. Visual proof

A fresh Godot viewport capture must be generated for the coherent proof ship.

The capture should show enough of the ship to verify spatial readability. Preferably it includes:

- player marker
- central spine
- at least one side branch
- a landmark
- vertical transition or reactor destination
- visible blocked route, if framing allows

The capture is not judged as final art. It is judged as proof that the in-engine structure reads as a connected place.

## Acceptance Criteria

The slice is accepted when:

1. A named coherent proof ship fixture exists.
2. The fixture contains 5–8 meaningful rooms or segments.
3. It uses the existing Godot loader and playable scene path.
4. The player can walk from airlock or breach entry to reactor or destination.
5. A visible deck/elevation transition exists and is traversable.
6. A visible blocked route exists and is not traversable.
7. A landmark or strong orientation anchor is visible from the central spine.
8. At least one side room is reachable off the main route.
9. Static fixture validation passes.
10. Runtime loader validation passes.
11. Playable traversal validation passes.
12. A fresh Godot viewport capture is produced.
13. Existing core playable smokes either continue to pass or are intentionally superseded by equivalent golden-fixture smokes.

## Deferred Work

After this proof is accepted, next candidates are:

1. Teach the random generator to produce layouts that resemble the golden proof ship.
2. Add stronger room dressing and mood for the proof ship.
3. Add gameplay systems such as repair, oxygen, inventory, combat, or encounter pacing.
4. Add multi-seed playability statistics.
5. Expand objective variety.
6. Turn vertical traversal into final gameplay rather than proof-level traversal.

## Repository Note

At design-writing time, `/Users/christopherwilloughby/the-synaptic-sea-of-stars` and `/Users/christopherwilloughby/off-the-rails-ai-infra` did not contain a `.git` repository from the shell. The design document can be written to disk, but a normal `git add` / `git commit` cannot succeed until the workspace is placed under git or a repository target is chosen.
