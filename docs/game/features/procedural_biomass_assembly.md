# Procedural Biomass Assembly — Feature Specification

> **ADR:** 0059-procedural-biomass-assembly.md
> **Status:** Draft
> **Created:** 2026-09-02

## Summary

Replace singular threat character models with a modular body-part system. Enemies are assembled
at runtime from a library of limbs, heads, torsos, connectors, and appendages sourced from
multiple species (human, alien, insectoid, cephalopod). Assembly is procedural — the same part
library produces unlimited unique threat forms.

## Gameplay motivation

The Synaptic Sea's horror comes from biological contamination. Pre-modeled creatures are
predictable; a thing made of three human legs and a dog's head dragging itself via intestines is
not. Procedural assembly creates emergent horror that players cannot memorize or anticipate.

## Scope

### In scope

- Body-part asset contracts and Meshy generation for 8 pilot parts
- Blender socket authoring and validation for each part category
- `BiomassRecipe` resource format and JSON storage
- `BiomassAssemblerService` autoload for runtime assembly
- Locomotion hints (biped, quadruped, crawl, drag, slither) with IK
- `biomass_part_catalog.json` replacing `threat_visual_catalog.json` archetypes
- Locked-isometric runtime review for assembled threats at seeds 42/777
- Random recipe generation from available parts

### Out of scope

- Procedural animation blending (use predefined gaits per locomotion hint)
- Part degradation/damage visuals (future feature)
- Player-facing bestiary or part identification UI
- Networked assembly synchronization (single-player only)
- Audio design for assembled threats (future feature)

## Requirements

### REQ-BIO-001: Part contract schema

Each body part has an `ai_asset_contract` with category-specific fields:

```json
{
  "schema_version": "1.0.0",
  "document_kind": "ai_asset_contract",
  "asset_id": "human_arm_v1",
  "category": "biomass_limb",
  "species": "human",
  "gameplay_role": "locomotion_or_manipulation",
  "dimensions_m": [0.12, 0.65, 0.12],
  "pivot": "proximal_center",
  "forward_axis": "+Z",
  "required_states": ["default"],
  "collision_owner": "godot_assembler",
  "sockets": [
    {"id": "proximal_0", "category": "biomass_torso", "compatible": ["limb_anchor"]},
    {"id": "distal_0", "category": "biomass_appendage", "compatible": ["distal", "jaw"]}
  ],
  "budget": {"triangles": {"min": 800, "max": 2000}},
  "generation": {
    "provider": "meshy",
    "mode": "image_to_3d",
    "model_type": "smart-topology",
    "ai_model": "meshy-t2",
    "should_texture": false,
    "candidate_count": 4
  }
}
```

**Acceptance:** Contract loads, validates, and produces a deterministic prompt packet. Socket
definitions are required for all non-connector categories.

### REQ-BIO-002: Socket marker authoring

Every Blender master exposes sockets as empty `Node3D` markers in the GLB scene tree with
`extras` metadata containing `socket_id`, `category`, `compatible_categories`,
`orientation_hint`, and `max_parts`.

**Acceptance:** `meshy_blender_validate.py` rejects any part GLB that is missing required sockets
or has socket metadata that does not match the contract.

### REQ-BIO-003: BiomassRecipe resource

A `BiomassRecipe` resource defines one assembled threat: torso, head, limb IDs, appendage IDs,
connector style, and locomotion hint. Recipes are stored as JSON in `data/combat/biomass_recipes/`.

**Acceptance:** Recipe loads, references only parts that exist in the catalog, and the assembler
produces a valid `Node3D` tree from it.

### REQ-BIO-004: Runtime assembly

`BiomassAssemblerService.assemble(recipe)` instantiates parts, attaches them at socket positions,
fills gaps with connectors, and returns a `Node3D` with a `ThreatMovementController` configured
for the recipe's locomotion hint.

**Acceptance:** Assembled threat renders correctly in the `breach_field` at seeds 42/777. No
`ERROR:`, `WARNING:`, or `SCRIPT ERROR:` in Godot headless output. Composite collision shape is
generated from assembled parts.

### REQ-BIO-005: Random recipe generation

`BiomassAssemblerService.random_recipe(difficulty)` selects a torso, attaches 1–6 limbs from
available parts, adds 0–2 appendages, picks a head (optional for non-biped), and assigns a
locomotion hint compatible with the assembled limb count.

**Acceptance:** Generated recipe is valid, references only catalog parts, and the locomotion hint
matches the limb count (fallback to `crawl` when under-provisioned).

### REQ-BIO-006: Locomotion hints

| Hint | Min limbs | Max limbs | Head required | Behavior |
|---|---|---|---|---|
| `biped` | 2 | 2 | Yes | A* pathfollow, 2-leg IK |
| `quadruped` | 4 | 6 | Yes | A* pathfollow, 4-leg IK |
| `crawl` | 1 | 3 | No | Ground-hugging waypoint crawl |
| `drag` | 0 | 4 | No | Torso drags, limbs pull |
| `slither` | 0 | 0 | No | Sine-wave ground motion |

**Acceptance:** Each locomotion hint produces correct movement in the `breach_field`. Assemblies
with insufficient limbs for the requested hint fall back to `crawl`.

### REQ-BIO-007: Part catalog

`data/combat/biomass_part_catalog.json` indexes all promoted parts by category, species, socket
vocabulary, locomotion compatibility, and mesh path. Replaces the archetype entries in
`threat_visual_catalog.json`.

**Acceptance:** Catalog loads, all referenced mesh paths exist, and the assembler can query parts
by category and compatibility.

### REQ-BIO-008: Pilot part set

Eight parts are generated, validated, and promoted before the assembly system is considered
complete:

1. `human_arm_v1` (limb, human)
2. `insect_leg_v1` (limb, insectoid)
3. `tentacle_v1` (limb, cephalopod)
4. `animal_skull_v1` (head, canid)
5. `humanoid_torso_v1` (torso, human)
6. `biomass_gunk_v1` (connector)
7. `claw_v1` (appendage, insectoid)
8. `maw_v1` (appendage, alien)

**Acceptance:** All 8 parts pass the full Meshy pipeline (contract → generation → selection →
Blender master → validation → runtime review → promotion). Each part's GLB contains correct
socket markers.

### REQ-BIO-009: Runtime review

Assembled threats are reviewed in the `breach_field` at seeds 42 and 777 with normal, emergency,
and dark lighting (6 cases per assembly). At least 3 representative assemblies (biped, quadruped,
crawl) must pass before the system is considered promotion-ready.

**Acceptance:** 18 review images (6 cases × 3 assemblies) pass without unexpected Godot errors.

### REQ-BIO-010: No auto-promotion

Body parts follow the same promotion gate as all Meshy assets: candidate selection → Blender
cleanup → validation → runtime review → promotion proposal → separate human-approved promotion.
No part bypasses this chain.

**Acceptance:** No writes to `assets/imported`, `data/combat/biomass_part_catalog.json`, or
`scenes/wrappers` during generation or assembly testing.

## Non-goals

- Real-time part swapping during gameplay (assemblies are fixed at spawn time)
- Part-to-part physics interaction (connectors are visual only)
- Player crafting of custom threats
- Part degradation or damage states (future feature)

## Verification commands

```bash
# Contract validation
PYTHONPATH=. python3 tools/meshy_asset_contract.py validate data/asset_generation/contracts/biomass_*.json

# Part catalog validation
PYTHONPATH=. python3 tools/validate_biomass_catalog.py --project-root .

# Assembly smoke test
/opt/homebrew/bin/godot --headless --path . --script res://scripts/validation/biomass_assembly_smoke.gd

# Runtime review (after assembly)
PYTHONPATH=. python3 tools/meshy_runtime_review.py --project-root . \
  --contract data/asset_generation/contracts/<part_id>.json \
  --task-dir assets/_staging/meshy/<part_id>/<task_id> \
  --preview-dir artifacts/validation-previews/biomass/<part_id>
```

## Open questions

1. Should connectors be procedurally deformed (skinned mesh) to bridge arbitrary socket
   positions, or should we pre-author a fixed set of connector shapes for common gap sizes?
2. How many curated recipes should ship alongside the random generation system?
3. Should the assembler support recursive attachment (e.g., a tentacle that itself has a maw
   attached to its distal end)?
