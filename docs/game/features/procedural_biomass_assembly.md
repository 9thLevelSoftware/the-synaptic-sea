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

### Out of scope for this contract task

- Meshy/provider calls, candidate generation, Blender authoring, or asset promotion.
- Runtime Godot assembly, five gait implementations, and scene integration.
- Procedural deformation or skeletal/IK animation.
- Real-time part swapping, part physics interaction, player-created threats, and damage visuals.
- Any mutation of `threat_visual_catalog.json`, exported assets, or wrapper scenes.

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

## Visual and review policy

Use a locked-isometric, low-poly, placeholder-first flow. Primitive fallbacks establish scale,
composition, and readability before any optional candidate asset is reviewed. No exported GLB may
carry a socket marker or helper node. Connectors are preauthored, non-deforming, visual-only parts;
they are not skinned at runtime to bridge arbitrary gaps.

The review matrix is five recipes × seeds `42` and `777` × `normal`, `emergency`, and `dark`
lighting: exactly 30 composite captures. All six 3D archetype pools remain covered during the
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

## Verification commands

```bash
PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 PYTHONPATH=. /opt/homebrew/bin/python3.11 -m pytest -q tests/test_biomass_catalog_validate.py
/opt/homebrew/bin/python3.11 tools/biomass_catalog_validate.py \
  --project-root . \
  --parts data/combat/biomass_part_catalog.json \
  --recipes data/combat/biomass_recipe_catalog.json
```

## Open questions

None for the canonical contract. Runtime implementation and visual promotion remain separate,
scoped tasks governed by ADR-0058 and this accepted contract.
