# Procedural Biomass Assembly — Canonical Feature Specification

> **ADR:** `docs/game/adr/0059-procedural-biomass-assembly.md`
> **Status:** Accepted contract; runtime assembly remains a follow-on implementation
> **Created:** 2026-09-02

## Summary

Procedural biomass threats are assembled from a strict repository-owned catalog of modular parts
rather than singular character meshes. A seeded recipe defines one explicit attachment graph. The
same graph validates, renders through Godot-owned wrappers, and persists without regeneration drift.

The contract is subordinate to ADR-0058: Meshy is candidate-only. Repository data and Godot
wrappers own sockets, connectors, collision, navigation, and runtime behavior. Meshy/Blender GLBs
are visual-only and contain no socket markers, marker empties, collision shapes, or helper nodes.

## Scope

### In scope for the canonical contract

- Strict part and recipe JSON schemas and catalogs.
- Eight exact `biomass_*` part IDs and five curated recipes.
- Six archetype pools: `biomatter_swarm`, `stalker`, `hull_tendril`, `puppet_corpse`, `mimic`,
  and `drone_swarm`.
- Stable, sorted diagnostics with duplicate-key and non-finite-number rejection.
- Repository-owned socket-space attachment validation, conservative node budgeting, and exact
  assembly-graph persistence shape.
- Placeholder-first, locked-isometric review planning for all 30 composite captures.

### Runtime restoration and validation seam (Tasks 7–9)

New records may select or generate a recipe. Restored biomass records never regenerate: the saved
recipe and nonzero seed are authoritative. Missing/invalid recipe or seed yields a stable diagnostic
and whole-threat fallback; malformed records are deterministically omitted/rejected; dead restored
records remain dead and create neither visual nor fallback. `ThreatManager.get_restore_diagnostics()`
returns a defensive sorted/deduplicated `PackedStringArray`. Fallback uses the existing plain
placeholder metadata `biomass_whole_threat_fallback=true` and
`biomass_fallback_reason=<stable diagnostic key>`.

`PlayableGeneratedShip.inject_biomass_validation_encounter(archetype_id: String, recipe_id: String,
seed: int, world_position: Vector3) -> Variant` is the public validation seam. It delegates to the
manager, uses valid loaded catalogs and exact recipe ID/seed, and returns the exact assembled/fallback
visual or `null`; production spawn semantics remain unchanged. `_build_run_snapshot(use_home_ship_summary=false)`
uses home-ship combat when away, while `_build_world_snapshot()` syncs active derelict combat once.
Load restores home and active combat once each, proven by distinct fingerprints. Legacy
`last_saved_snapshot` is assigned only after successful `save_load_service.save_world(ws)` and is not
authoritative over the saved `WorldSnapshot`.

### Out of scope for this contract task

- Meshy/provider calls, candidate generation, Blender authoring, or asset promotion.
- Runtime Godot assembly, five gait implementations, and scene integration.
- Procedural deformation or skeletal/IK animation.
- Real-time part swapping, part physics interaction, player-created threats, and damage visuals.
- Any mutation of `threat_visual_catalog.json`, exported assets, or wrapper scenes.

### Asset pipeline readiness boundary (Tasks 10–15)

The optional Meshy-to-Blender path remains candidate-only until a human-approved preview. Public
recipe resolution has a non-overridable external root: the exact `source/<asset_id>/<asset_id>_master.blend`
and `live-pilot/<asset_id>/<task_id>/` paths under `/Volumes/Untitled/SynapticSeaAssets/meshy/`.
Only tests may inject `RecipeRoots`. The five modes are `archive-raw`, `rehydrate-raw`, `preview`,
`approve-preview`, and `publish-cleaned`; archive works without a master, rehydrate uses neither
master nor Blender, and Blender modes require the exact regular master. Task 10 creates the
external archive; Task 14 order is rehydrate-raw → `meshy_blender_master` (create once) → preview
→ human inspection/approval → publish.

Preview atomically publishes the scratch GLB, five renders, and closed `biomass-part-preview.json`.
Approval is no-Blender/no-provider and immutably binds reviewer plus preview-manifest, render, GLB,
contract, catalog, generation, raw, archive, and master hashes. Publish reruns Blender privately,
compares the exact approved baseline, and only then writes task-local `cleaned.glb` and closed
`biomass-part-recipe.json`; an existing recipe permits only byte-identical idempotence. External
leaves are preflighted, mode `0600`, non-symlink regular files, and staged under the validated
external evidence directory as the atomic allowed root with rollback on injected failure.

## Canonical data contract

### Part catalog

`data/combat/biomass_part_catalog.json` has exactly `schema_version`, `document_kind`, `limits`,
and `parts`. The exact limits are:

```json
{"max_attachments":8,"max_depth":3,"max_triangles":30000,"max_nodes":160}
```

The exact eight IDs are:

1. `biomass_human_arm_v1` — `biomass_limb`, `human`, roles `locomotor`, `manipulator`, `puller`, budget 2500
2. `biomass_insect_leg_v1` — `biomass_limb`, `insectoid`, role `locomotor`, budget 2500
3. `biomass_cephalopod_tentacle_v1` — `biomass_limb`, `cephalopodic`, roles `locomotor`, `puller`, `slither`, budget 2500
4. `biomass_animal_skull_v1` — `biomass_head`, `animal`, roles `core`, `detail`, budget 3500
5. `biomass_humanoid_torso_v1` — `biomass_core`, `human`, role `core`, budget 5000
6. `biomass_gunk_connector_v1` — `biomass_connector`, `biomass`, role `connector`, budget 500
7. `biomass_claw_v1` — `biomass_appendage`, `alien`, roles `detail`, `manipulator`, budget 1500
8. `biomass_maw_v1` — `biomass_appendage`, `alien`, role `detail`, budget 1500

The only categories are `biomass_core`, `biomass_limb`, `biomass_head`, `biomass_connector`, and
`biomass_appendage`. The only roles are `core`, `locomotor`, `manipulator`, `detail`, `puller`,
`slither`, and `connector`. Every part has a repository `socket_root_0`; non-root socket names
match `^socket_(root|head|limb|appendage|jaw|distal)_[0-9]+$`. Coordinates use local `+Y` up
and `+Z` forward/outward. Child alignment is:

```text
parent_socket.global_transform * child_socket.transform.affine_inverse()
```

Collision shapes are exactly `box`, `capsule`, or `sphere`, and collision ownership stays in the
Godot wrapper. `wrapper_scene_path: ""` is a valid fallback authority. A non-empty wrapper path
must be an existing project-relative `res://` path. Fallback dimensions bound socket positions by
at most 0.05 m of tolerance.

### Recipe catalog and graph rules

`data/combat/biomass_recipe_catalog.json` has exactly `schema_version`, `document_kind`, `recipes`,
and `archetype_pools`. Recipe records have exactly `recipe_id`, `locomotion_hint`, `core`, and
`attachments`; attachment records have exactly `instance_id`, `part_id`, `parent_instance_id`,
`parent_socket`, `child_socket`, and `connector_part_id`.

The five recipes are `biped_puppet_v1`, `four_legged_scrambler_v1`, `tripod_hound_v1`,
`intestinal_dragger_v1`, and `tendril_knot_v1`. Records are parent-before-child. Every edge uses
`child_socket: "root_0"` (the catalog socket is `socket_root_0`) and
`connector_part_id: "biomass_gunk_connector_v1"`.

The strict graph limits are one core, at most 8 non-core attachments, depth 3, 30,000 triangles,
and 160 inclusive runtime nodes. Instance IDs are unique; each parent socket has one child; cycles,
forward references, unknown IDs, incompatible categories, missing child roots, and invalid role
requirements fail closed. A core may be a skull; a torso is not mandatory.

The runtime-node estimate is intentionally a deterministic conservative host-contract formula:
one assembler root plus two wrapper/visual nodes and one node per catalog socket or collision
descriptor for each part occurrence, including one connector occurrence per attachment. It does not
inspect future wrapper scene trees.

## Locomotion and runtime ownership

The only locomotion hints are:

| Hint | Contract requirement |
|---|---|
| `biped` | exactly two locomotor parts and a head |
| `quadruped` | exactly four locomotor parts and a head |
| `crawl` | at least one locomotor part |
| `drag` | at least one puller part |
| `slither` | at least one slither part |

These are rigid socket-space gait profiles, not skeleton or IK contracts. A per-manager `RefCounted`
assembler owns pure graph planning and is called by the threat manager; there is no
`BiomassAssemblerService` autoload. Godot wrapper scenes apply collision, navigation, connector,
and gameplay consequences. The complete recipe is serialized and loaded exactly, including every
instance, part, parent, socket, child root, connector, and locomotion hint.

### Runtime visual and gait boundary (Tasks 5–7)

Task 5 acceptance uses the final assembly smoke rather than intermediate preload-failure evidence.
Its fixture inventory includes the closed invalid-wrapper catalog, valid core/nested wrappers,
non-PackedScene and forbidden-physics wrappers, a node-overflow wrapper, and a predelete probe.
The factory validates before allocation; wrapper validation occurs before cache/retention; and every
off-tree rejection synchronously frees partial and unattached nodes. Recursive socket lookup is
unique and independent of child ordering, with ancestor transform composition. Complete core/child
transform and collision maps include connector occurrences. Loader-valid node and triangle overflow
fixtures must exceed 160 and exactly 30000 respectively before rejection, with exact diagnostics;
failure diagnostics are sorted, deduplicated, and byte-identical on repetition. The smoke proves
behavioral free/tree-removal evidence, not a copied RID validity bit.

When parts and attachment mounts are registered, `BiomassThreatVisual` stores immutable
assembly-rest `Transform3D` value copies. Part rests are immediate-parent-local `.transform` values:
visual-local for the core and mount-local for attachment children. Mount rests are visual-root-local
because mounts are direct visual children. The separate visual-root-local `part_to_visual` value is
collision/assembly bookkeeping and is never assigned to a mount-parented child's `.transform`.
These are dictionaries of data, not extra Nodes, so they do not alter assembly node, triangle, or
collision counts. The visual exposes
`part_rest_transform(instance_id: String) -> Variant` and
`attachment_rest_transform(instance_id: String) -> Variant`; known IDs return their `Transform3D`,
unknown IDs return `null`. Reset restores mounts directly from mount rests, then parts directly from
part rests, without capturing current animated transforms or double-applying attachment alignment.

Each visual owns exactly one private `RefCounted` gait controller. No manager/shared/autoload/Node
controller is permitted. The visual dynamically loads the controller script only after restoring
assembly rest and retains a fresh controller only when configuration succeeds. The controller
preloads and exact-script-compares the visual, part catalog, and recipe scripts. Invalid visual,
parts, recipe, catalog, recipe-document, core, or attachment dependencies fail closed with no
partial controller state; the visual remains at assembly rest and `step_gait` is a no-op.
Repeated configuration restores assembly rest, resets gait state, and replaces the controller.

Profile selection is role-driven: biped/quadruped/crawl drive `locomotor` attachments, drag drives
`puller` attachments, and slither drives `slither` attachments. Animation is rigid and socket-space,
rebuilt from immutable rest transforms; non-driven mounts remain at exact rest. v1 core bob/yaw is a
no-op. The core, visual/root transform, CharacterBody3D/world position, recipe, AI state, meshes,
and bones remain under their existing authorities and are unchanged by gait.

Task 7 calls `visual.configure_gait(parts, recipe, biomass_seed)` after `assembler.build(recipe,
parts)` succeeds and before scene-tree registration or any gait step. A false result frees the
assembled visual synchronously and selects the existing whole-threat primitive fallback; no
partially configured biomass visual enters `placeholder_nodes`.

Exact timing, phase assignment, angular bound, rest convergence, drift, and smoke-output mechanics
are specified in the implementation plan to keep this feature contract readable.

## Visual and review policy

Use a locked-isometric, low-poly, placeholder-first flow. Primitive fallbacks establish scale,
composition, and readability before any optional candidate asset is reviewed. No exported GLB may
carry a socket marker or helper node. Connectors are preauthored, non-deforming, visual-only parts;
they are not skinned at runtime to bridge arbitrary gaps. Their catalog collision descriptors are
materialized only as disabled `CollisionShape3D` nodes for uniform deterministic node accounting and
must never participate in gameplay collision or physics queries.

The review matrix is five recipes × seeds `42` and `777` × `normal`, `emergency`, and `dark`
lighting: exactly 30 composite captures. The runner has explicit `--visual-stage {placeholder,final}`
and fixed placeholder/final roots; Task 8 runs placeholder only, while Task 15 runs final. Captures
use production `scenes/main.tscn`, `IsoCameraRig`, `breach_field`, and `SliceAtmosphereApplier`, not
a standalone floor/camera/environment. Every case records exact recipe node/triangle oracles, caps
of 160 nodes and 24,000 triangles, finite 0.05–20 m AABB extents, collision counts and mask-1 ray
proof, plus frozen paired-camera readability values (RGB delta threshold 8/255, at least 64 changed
pixels and an 8×8 changed bounding box). All six 3D archetype pools remain covered during the
singular-threat migration. The migration from `threat_visual_catalog.json` is a separate reviewed
runtime task.

## Requirements and acceptance

- Part and recipe documents validate with no diagnostics through the exact CLI below.
- Repeated CLI runs emit byte-identical output and the marker
  `BIOMASS CATALOG VALIDATION PASS parts=8 recipes=5 archetypes=6`.
- Unknown/missing fields, duplicate keys, non-finite numbers, bad paths, malformed sockets/shapes,
  and malformed graphs are rejected with stable sorted diagnostics.
- All 30 review captures are required before visual promotion; Meshy candidate output never
  auto-promotes or mutates repository catalogs, wrappers, or imported assets.
- Closed in-tool validators define exact fields for source-raw, preview, preview-approval, and
  recipe records; low-poly status is exactly `low_poly_target` with `status` `met` or
  `review_required`, target/measured triangle counts, and hard maximum. Above hard maximum blocks.
- Task 12 persists exactly eight canonical plans at `assets/_staging/meshy/_plans/<asset_id>.json`
  and a mode-`0600` `biomass_reference_audit.json` with `status:"pass"`; each plan records both
  `request_plan_file_sha256` and `provider_payload_sha256`. The audit rejects undersized,
  transparent, duplicate, symlink, collage, or disconnected references before paid generation.

## Verification commands

```bash
PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 PYTHONPATH=. /opt/homebrew/bin/python3.11 -m pytest -q tests/test_biomass_catalog_validate.py
/opt/homebrew/bin/python3.11 tools/biomass_catalog_validate.py \
  --project-root . \
  --parts data/combat/biomass_part_catalog.json \
  --recipes data/combat/biomass_recipe_catalog.json
```

## Tasks 13–15 pilot execution contract

Task 13 is a paid, serial candidate stage owned exclusively by `tools/biomass_candidate_batch.py`.
Its read-only preflight authenticates the exact Task 12 plan/audit/pricing/reference hashes and
proves no prior journal or task directory exists; it recomputes the live plan immediately because
`meshy_stage.py generate` has no plan-SHA argument. All commands pin
`data/asset_generation/meshy_pricing_v1.json`. The stage is exactly eight journals × four unique
tasks (32 candidates), cost 5, approved/max 20 per asset, aggregate max 160 and actual <=160.
Unknown POST/SUBMITTING without an ID resumes then stops for reconciliation; known IDs/UNCERTAIN
resume; bound FAILED with a failure record and contiguous pending suffix continues then verifies.
Existing inventory never starts a new generate. Reconcile writes the canonical batch manifest.
Pillow renders deterministic 2x2 1024px contact sheets; tracked JSON binds four task IDs and all
input/output hashes, while PNGs remain ignored. All eight sheets are built before selection, and
each selection immediately archives raw evidence externally before commit.

Task 14 starts each selected asset with `rehydrate-raw`, never `archive-raw`, and uses a fail-fast
variable-pinned loop with fixed reviewer and pricing/catalog hashes. The Blender master is immutable
and create-once; an existing bound master is verified and never rerun. The order is rehydrate,
master, preview, human inspection, approve-preview, publish-cleaned. Fresh checkouts explicitly
restore fixed evidence permissions (directory 0700, 18 PNGs and review JSON 0600). Runtime review
transitions to `promotion_ready`; the candidate-review `verify` command is verify-only. The exact
commit inventory is eight selected records and eight fixed 18-PNG runtime leaves, with no binaries,
unselected tasks, contact sheets, or temporary files.

Task 15 is exclusively written by `tools/biomass_pilot_promote.py` (`plan`, `apply`, `verify`,
`rollback`, `finalize`). Plan preflights all eight packets against one pre-mutation catalog and a
protected prestate digest. Apply stages all GLBs, deterministic thin wrappers, catalog bytes and
import targets in a restrictive transaction journal; wrappers are Node3D + one imported GLB child
plus direct plain Node3D catalog sockets, with no collision/physics/animation. Publication accepts
only absent or byte-identical targets. Two Godot 4.7.1 imports must yield eight stable descriptors
and no `.godot/imported` staging. Every import/validation failure rolls back only newly created
hash-matching leaves and catalog bytes; interruption blocks until rollback or exact recovery.
Final review uses `--visual-stage final` at `artifacts/validation-previews/biomass-assembly-final`
and requires exactly 30 cases, caps, collision/LOS/readability, and visual approval. The executable
playable smoke proves eight wrappers, six archetypes, five gaits, kill/travel, and exact save/load
recipe/seed/graph/transform/collision fingerprints, printing the canonical pilot marker. Only
`finalize` may set this feature to Implemented; ADR-0059 remains Accepted.

## Open questions

None for the canonical contract. Runtime implementation and visual promotion remain separate,
scoped tasks governed by ADR-0058 and this accepted contract.
