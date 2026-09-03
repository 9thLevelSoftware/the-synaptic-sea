# ADR-0059: Procedural Biomass Assembly — Modular Body-Part Threats

## Status

Proposed

## Context

The original threat art direction defined singular character models for each archetype: a Stalker
is one humanoid biped, a Hull Tendril is one segmented chain, a Biomatter Swarm is one cluster of
organisms. Each archetype would get its own Meshy-generated candidate, Blender master, and Godot
wrapper.

During the first Stalker candidate review (2026-09-02), the team identified that pre-modeled
creatures are less unsettling than emergent, unpredictable forms. The Synaptic Sea's horror is
rooted in biological contamination — biomass that recombines, adapts, and violates expectations.
A library of modular body parts that assemble into randomized threats better serves this theme
than any single creature design.

The existing project already has:
- A `ModularSocketCatalog` and socket-compatible join system (ADR-0056) used for structural kits.
- A `threat_visual_catalog.json` with per-archetype primitive placeholders and mesh paths.
- A governed Meshy-to-Blender asset pipeline that generates, validates, and stages individual
  assets with contract-defined sockets and budgets (ADR-0058).
- A `breach_field` production environment at seeds 42/777 for locked-isometric runtime review.

Without a decision, the likely outcome is either:
1. Committing to singular creature models that undermine the game's horror identity, or
2. An ad-hoc body-part system with inconsistent sockets, no assembly contract, and no provenance
   tracking.

## Decision

Replace singular threat character models with a **procedural biomass assembly** system built from
a library of modular body parts. Each part is a governed Meshy candidate with a Blender master,
standardized socket points, and a contract-defined attachment vocabulary. Godot owns the assembly,
locomotion, and gameplay behavior.

### Part categories

| Category | Examples | Socket role |
|---|---|---|
| `biomass_limb` | Human arm, insect leg, tentacle, cephalopod arm | Provides locomotion or manipulation; exposes `proximal` (root) and `distal` (tip) sockets |
| `biomass_head` | Human skull, animal skull, alien head, eyeless mass | Visual identity anchor; exposes `neck` (root) socket; optional `jaw` socket for maw attachment |
| `biomass_torso` | Humanoid torso, quadruped mass, amorphous blob | Central mass; exposes 2–6 `limb_anchor` sockets and 1 `head_anchor` socket |
| `biomass_connector` | Biomass gunk, tendon bundle, membrane, ichor strand | Fills gaps between parts; attaches to any two `proximal`/`distal` pair; purely visual |
| `biomass_appendage` | Claw, pincer, maw, stinger, eye stalk | Attaches to `distal` or `jaw` sockets; defines attack or interaction behavior |

### Socket contract

Every body-part Blender master exposes sockets as empty `Node3D` markers in the GLB scene tree.
Socket naming follows a deterministic convention:

```
socket_<category>_<index>
```

Examples: `socket_limb_anchor_0`, `socket_head_anchor_0`, `socket_proximal_0`,
`socket_distal_0`, `socket_jaw_0`.

Each socket carries metadata in the GLB `extras`:
```json
{
  "socket_id": "limb_anchor_0",
  "category": "biomass_limb",
  "compatible_categories": ["biomass_limb", "biomass_connector"],
  "orientation_hint": "outward",
  "max_parts": 1
}
```

The Godot assembler reads socket metadata at load time and performs compatible-category matching.
Connectors are wildcard attachments that fill any gap between two non-connector parts.

### Assembly contract

An assembled threat is defined by a lightweight `BiomassRecipe` resource:

```gdscript
class_name BiomassRecipe
extends Resource

@export var torso_id: StringName       # e.g. &"humanoid_torso_v1"
@export var head_id: StringName        # e.g. &"animal_skull_v1"
@export var limb_ids: Array[StringName]  # e.g. [&"human_arm_v1", &"insect_leg_v1", &"insect_leg_v1"]
@export var appendage_ids: Array[StringName]  # e.g. [&"claw_v1"]
@export var connector_style: StringName  # e.g. &"biomass_gunk"
@export var locomotion_hint: StringName  # &"biped", &"quadruped", &"crawl", &"drag", &"slither"
```

The assembler:
1. Instantiates the torso as root.
2. Attaches head to `head_anchor`.
3. Attaches limbs to `limb_anchor` sockets (fills from index 0).
4. Attaches appendages to `distal` sockets on limbs.
5. Fills visible gaps with connectors.
6. Applies the locomotion hint to the `ThreatMovementController`.

Recipes are stored in `data/combat/biomass_recipes/` as JSON. The game can load a curated set or
generate random recipes at runtime from the available part catalog.

### Locomotion hints

| Hint | Behavior | Typical assembly |
|---|---|---|
| `biped` | Standard A* pathfollow with 2-leg IK | 2 legs + torso + head |
| `quadruped` | A* pathfollow with 4-leg IK | 4 legs + torso + head |
| `crawl` | Ground-hugging waypoint crawl, irregular gait | 1–3 limbs + torso, no head required |
| `drag` | Torso drags along ground, limbs pull | Mass torso + tendrils/intestines |
| `slither` | Sine-wave ground motion | Tentacles/appendages only, no rigid torso |

The locomotion hint is a suggestion; the assembler validates that the assembled shape has enough
limbs to support it and falls back to `crawl` when under-provisioned.

### Meshy pipeline integration

Body parts follow the same governed pipeline as any other asset:
- Contract → Meshy candidate generation → human selection → Blender master → validation →
  runtime review → promotion.
- Each part is a separate contract with its own staging directory.
- Socket markers are authored in Blender and validated by `meshy_blender_validate.py`.
- The `threat_visual_catalog.json` archetypes are replaced by a `biomass_part_catalog.json`
  that indexes all promoted parts by category, socket vocabulary, and locomotion compatibility.

### What this replaces

The following contracts are **retired** and replaced by the biomass part system:
- `stalker_v1` → replaced by `biomass_limb` + `biomass_head` + `biomass_torso` parts
- `hull_tendril_kit_v1` → replaced by `biomass_limb` (tentacle) + `biomass_connector` parts
- `biomatter_swarm_kit_v1` → replaced by `biomass_appendage` + `biomass_connector` parts

The `loot_container_derelict_v1` and `crafting_station_derelict_v1` contracts are **unchanged**.

### Pilot part set (8 parts)

To prove the assembly pipeline before scaling:

| # | Part ID | Category | Source species | Budget (tris) | Meshy mode |
|---|---|---|---|---|---|
| 1 | `human_arm_v1` | limb | Human | 800–2000 | image_to_3d |
| 2 | `insect_leg_v1` | limb | Insectoid | 600–1500 | image_to_3d |
| 3 | `tentacle_v1` | limb | Cephalopod | 500–1200 | image_to_3d |
| 4 | `animal_skull_v1` | head | Animal (canid) | 800–2000 | image_to_3d |
| 5 | `humanoid_torso_v1` | torso | Human | 1500–3000 | image_to_3d |
| 6 | `biomass_gunk_v1` | connector | N/A | 300–800 | image_to_3d |
| 7 | `claw_v1` | appendage | Insectoid | 400–1000 | image_to_3d |
| 8 | `maw_v1` | appendage | Alien | 600–1500 | image_to_3d |

Total pilot credits: 8 parts × 4 candidates × 5 credits = **160 credits** (image_to_3d,
smart-topology, untextured).

### Godot runtime architecture

New autoload: `BiomassAssemblerService`

```
BiomassAssemblerService
  ├── load_part_catalog() -> reads biomass_part_catalog.json
  ├── assemble(recipe: BiomassRecipe) -> Node3D
  │     ├── instantiate torso
  │     ├── attach head to head_anchor
  │     ├── attach limbs to limb_anchor sockets
  │     ├── attach appendages to distal sockets
  │     ├── fill gaps with connectors
  │     └── apply locomotion hint
  ├── random_recipe(difficulty: int) -> BiomassRecipe
  └── get_available_parts(category: StringName) -> Array[StringName]
```

The assembled `Node3D` is parented under the threat spawner. Each part retains its own
`MeshInstance3D` and collision shape. The `ThreatMovementController` reads the locomotion hint
and applies the appropriate gait.

### Collision and gameplay ownership

Per ADR-0058: collision, navigation, sockets, integrity, and gameplay bindings remain owned by
Godot wrappers and repository data. Body-part GLBs carry visual geometry and socket markers only.
The assembler creates a composite collision shape from the assembled parts at runtime.

## Consequences

- **Positive:** Unlimited visual variety from a finite part library. Horror improves through
  unpredictability. Each part is a small, manageable Meshy generation (low credit cost). The
  existing governed pipeline requires no structural changes.
- **Negative:** More Blender masters to maintain (8+ parts vs 3 creatures). Assembly adds runtime
  complexity. Locomotion IK needs tuning per assembly shape. Some assembled forms will look
  absurd rather than scary — the recipe system needs curation alongside random generation.
- **Neutral:** The `threat_visual_catalog.json` archetypes are replaced, not extended. The
  existing primitive placeholders remain as fallbacks for un-assembled threats.

## References

- ADR-0056: ModularSocketCatalog missing-kit fallback
- ADR-0058: Meshy candidates, Blender authority
- `data/combat/threat_visual_catalog.json`
- `docs/game/features/ai_candidate_asset_pipeline.md`
