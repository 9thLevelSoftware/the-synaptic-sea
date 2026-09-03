# ADR-0059: Procedural Biomass Assembly — Canonical Part and Recipe Contracts

## Status

Accepted

## Date

2026-09-02

## Context

The Synaptic Sea's contaminated-biological horror is better served by recombinable body parts than
by six singular threat meshes. The assembly system must therefore be a data contract first: the
same catalog must produce the same graph, validation result, and persisted recipe on every host.

This decision is subordinate to ADR-0058. Meshy remains candidate-only and no provider call or
asset mutation is part of this contract task. Repository data and Godot wrappers are authoritative
for sockets, connectors, collision, and runtime behavior. Exported Meshy/Blender GLBs are visual-only
and contain no socket markers, marker empties, collision shapes, or helper nodes.

## Decision

Adopt a strict, repository-owned procedural biomass assembly contract with two canonical JSON
catalogs:

- `data/combat/biomass_part_catalog.json`, validated by
  `data/combat/schemas/biomass_part_catalog_v1.schema.json`;
- `data/combat/biomass_recipe_catalog.json`, validated by
  `data/combat/schemas/biomass_recipe_catalog_v1.schema.json`.

The host-side validator is the authority for cross-record graph rules:

```text
/opt/homebrew/bin/python3.11 tools/biomass_catalog_validate.py \
  --project-root . \
  --parts data/combat/biomass_part_catalog.json \
  --recipes data/combat/biomass_recipe_catalog.json
```

It rejects duplicate JSON keys, unknown or missing fields, non-finite numbers, invalid paths,
invalid socket/shape/fallback data, and invalid assembly graphs. Diagnostics are stable and sorted.

### Canonical part vocabulary

The only categories are `biomass_core`, `biomass_limb`, `biomass_head`,
`biomass_connector`, and `biomass_appendage`. The only locomotion hints are `biped`, `quadruped`,
`crawl`, `drag`, and `slither`. The only assembly roles are `core`, `locomotor`, `manipulator`,
`detail`, `puller`, `slither`, and `connector`.

The eight canonical part IDs are:

| Part ID | Category | Species tags | Assembly roles | Triangle budget |
|---|---|---|---|---:|
| `biomass_human_arm_v1` | `biomass_limb` | `human` | `locomotor`, `manipulator`, `puller` | 2500 |
| `biomass_insect_leg_v1` | `biomass_limb` | `insectoid` | `locomotor` | 2500 |
| `biomass_cephalopod_tentacle_v1` | `biomass_limb` | `cephalopodic` | `locomotor`, `puller`, `slither` | 2500 |
| `biomass_animal_skull_v1` | `biomass_head` | `animal` | `core`, `detail` | 3500 |
| `biomass_humanoid_torso_v1` | `biomass_core` | `human` | `core` | 5000 |
| `biomass_gunk_connector_v1` | `biomass_connector` | `biomass` | `connector` | 500 |
| `biomass_claw_v1` | `biomass_appendage` | `alien` | `detail`, `manipulator` | 1500 |
| `biomass_maw_v1` | `biomass_appendage` | `alien` | `detail` | 1500 |

Every part has a repository-owned `socket_root_0`. Socket names match
`^socket_(root|head|limb|appendage|jaw|distal)_[0-9]+$`; root sockets accept no categories and
non-root sockets declare non-empty accepted category lists. Socket coordinates are local meters,
with local `+Y` up and `+Z` forward/outward. A child is aligned in socket space as:

```text
parent_socket.global_transform * child_socket.transform.affine_inverse()
```

An empty `wrapper_scene_path` is a valid fallback authority. A non-empty path must be a
project-relative existing `res://` path. Collision descriptors are exactly `box`, `capsule`, or
`sphere`; collision ownership remains in the Godot wrapper. The fallback primitive is visual-only.

### Attachment graph

A recipe has exactly one core record and zero or more ordered attachment records. A core is not
required to be a torso: `biomass_animal_skull_v1` is a valid core because it has the `core` role.
The graph rules are:

- one core; at most 8 non-core attachments;
- maximum graph depth 3;
- at most 30,000 triangles and 160 inclusive runtime nodes;
- parent-before-child ordering, unique instance IDs, one child per parent socket, and no cycles;
- every child uses socket reference `root_0` (the catalog socket is `socket_root_0`) and every edge uses the canonical
  `biomass_gunk_connector_v1` connector;
- connectors are non-deforming, preauthored visual parts. They do not own gameplay collision or
  physics and are not procedurally skinned to bridge arbitrary gaps. Their required catalog
  collision descriptors are instantiated only as disabled `CollisionShape3D` nodes so deterministic
  node accounting still includes every descriptor; connector shapes must never register a hit.

The validator's deterministic conservative runtime-node estimate is derived only from the recipe
and catalog: one assembler-root node plus two wrapper/visual nodes and one node per authored socket
or collision descriptor for every part occurrence, including one connector occurrence per edge.
It deliberately does not claim to inspect future wrapper scene trees.

### Curated recipes, random generation, and persistence

The catalog contains exactly five parent-before-child recipes:
`biped_puppet_v1`, `four_legged_scrambler_v1`, `tripod_hound_v1`, `intestinal_dragger_v1`, and
`tendril_knot_v1`. Six existing 3D archetypes map to deterministic pools:
`biomatter_swarm`, `stalker`, `hull_tendril`, `puppet_corpse`, `mimic`, and `drone_swarm`.

Random recipes are seeded and deterministic. They draw only from the canonical catalog, pass the
same graph and locomotion checks as curated recipes, and serialize the complete recipe: recipe ID,
locomotion hint, core instance/part, every attachment instance/part, parent and child sockets, and
connector part ID. Save/load restores that exact graph rather than regenerating a replacement.

### Runtime ownership and movement

The assembler is a per-manager `RefCounted` service/model, not an autoload and not a scene-tree
god-object. It consumes the repository catalogs and creates wrapper-owned runtime nodes under the
calling threat manager. It does not mutate the catalogs or exported assets.

Locomotion uses five rigid socket-space gait profiles (`biped`, `quadruped`, `crawl`, `drag`, and
`slither`). These are authored rigid-part gaits, not skeleton or IK contracts. Runtime wrappers own
collision, navigation, connectors, and gameplay bindings.

### Runtime visual and gait boundary

Task 5 records immutable assembly-rest `Transform3D` value copies as each part and attachment mount
is registered. A part rest is the part node's immediate-parent-local `.transform`: visual-local for
the directly parented core and mount-local for an attachment child. A mount rest is visual-root-local
because every attachment mount is a direct visual child. The separate `part_to_visual` composition
remains collision/assembly bookkeeping and must never be assigned to a mount-parented child's
`.transform`. The copies are data, not scene nodes, and therefore do not change part, triangle,
collision, or runtime-node accounting. `BiomassThreatVisual` exposes
`part_rest_transform(instance_id: String) -> Variant` and
`attachment_rest_transform(instance_id: String) -> Variant`; each returns the corresponding
`Transform3D` for a known ID and `null` for an unknown ID. Reset restores mount values directly,
then part values directly, and never captures a current animated pose.

Each `BiomassThreatVisual` owns exactly one private `RefCounted` `BiomassGaitController`. There is
no manager-owned, shared, autoload, or scene-tree gait controller. The controller preloads the exact
visual, part-catalog, and recipe scripts and compares object scripts exactly. The visual dynamically
loads the controller script, restores all parts and mounts from the assembly-rest dictionaries, and
retains a fresh controller only after `configure` succeeds. Configuration is fail-closed; an
invalid dependency or incomplete assembly leaves no controller and leaves the visual at assembly
rest. Reconfiguration replaces rather than shares or stacks controllers.

Gait roles are derived from the validated attachment part roles: `biped`, `quadruped`, and `crawl`
drive `locomotor` edges, `drag` drives `puller` edges, and `slither` drives `slither` edges. Driven
mounts are animated rigidly in socket space from their saved rest transforms; non-driven mounts stay
at exact rest. The core part, `BiomassThreatVisual`/`CharacterBody3D` root transform, recipe, AI
state, meshes, bones, and world position remain authoritative elsewhere and unchanged by v1 gait;
core bob and yaw are explicitly no-ops.

Task 7 must call `visual.configure_gait(parts, recipe, biomass_seed)` after a successful assembly
build and before scene-tree registration or any gait step. A false result synchronously frees the
assembled visual and uses the existing whole-threat primitive fallback; no partially configured
biomass visual may enter `placeholder_nodes`.

The exact timing, phase, bounded-motion, rest, drift, and smoke assertions are governed by the
implementation plan rather than duplicated here.

### Visual pipeline and review

The locked-isometric, low-poly, placeholder-first flow is:

```text
repository contract -> primitive placeholder review -> Meshy candidate (optional)
  -> Blender visual cleanup -> staged visual review -> separate human-approved promotion
```

No exported asset carries socket markers or helper nodes. Composite readability and low-poly
cohesion are reviewed in all 30 planned captures: five recipes × seeds `42` and `777` × `normal`,
`emergency`, and `dark` lighting. The six archetype pools remain data-compatible during the
singular-threat migration; replacing `threat_visual_catalog.json` is a later, separately reviewed
runtime migration, not an implicit side effect of this catalog task.

### Biomass asset-pipeline contract (Tasks 10–15)

The asset path boundary is non-overridable: public recipe resolution accepts only
`/Volumes/Untitled/SynapticSeaAssets/meshy/source/<asset_id>/<asset_id>_master.blend` and
`/Volumes/Untitled/SynapticSeaAssets/meshy/live-pilot/<asset_id>/<task_id>/`; a private injected
`RecipeRoots` seam is test-only. Modes are exactly `archive-raw`, `rehydrate-raw`, `preview`,
`approve-preview`, and `publish-cleaned`. Archive works before a master exists; rehydrate requires
neither master nor Blender; the other three require an exact regular external master.

Preview produces five renders, `cleaned.preview.glb`, and a closed preview manifest. Human approval
is a separate no-Blender/no-provider operation producing an immutable approval manifest that binds
reviewer, preview-manifest SHA, every render and preview-GLB hash, and contract/catalog/generation/
raw/archive/master hashes. Publish privately reruns Blender and must match that baseline before
writing task-local `cleaned.glb` and the closed recipe manifest; an existing recipe is accepted only
on an exact byte-identical idempotent rerun. All coupled external leaves are preflighted and staged
under the validated evidence directory as the atomic-write root, mode `0600`, with rollback on
injected failure. The generic Blender report remains `meshy_blender_validation` with
`master_provenance: null`.

## Consequences

- The catalog and recipes are machine-checkable, deterministic, and suitable for exact save/load.
- A skull can be a core, so the data model no longer encodes a mandatory torso assumption.
- Repository data and Godot wrappers retain all gameplay authority; visual exports stay safe and
  replaceable.
- Connector readability is predictable because connectors are preauthored and non-deforming.
- Runtime assembly, five gait implementations, persistence wiring, and the 30-capture review remain
  follow-on work; this task does not call Meshy, Blender, or Godot asset mutation paths.
- Task 10–12 pipeline records use closed in-tool validators; Task 11 uses the existing
  `asset_provenance` envelope and adds no fields to the generic Blender schema. Task 12 persists
  exactly eight plans under `assets/_staging/meshy/_plans/<asset_id>.json` plus a mode-`0600`
  reference audit manifest before Task 13 paid generation.

## References

- ADR-0056: Modular socket catalog and missing-kit fallback
- ADR-0058: Meshy candidates, Blender authority, and Godot runtime authority
- `data/combat/schemas/biomass_part_catalog_v1.schema.json`
- `data/combat/schemas/biomass_recipe_catalog_v1.schema.json`
- `tools/biomass_catalog_validate.py`
- `docs/game/features/procedural_biomass_assembly.md`
