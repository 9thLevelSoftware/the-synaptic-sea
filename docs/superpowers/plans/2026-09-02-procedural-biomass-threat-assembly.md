# Procedural Biomass Threat Assembly Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace singular 3D threat meshes with deterministic, save-stable threats assembled from reusable low-poly human, alien, insectoid, cephalopodic, and biomass parts, presented through the production locked-isometric camera, then produce and promote an eight-part Meshy/Blender pilot through the existing governed asset pipeline.

**Architecture:** Represent each threat as a validated directed attachment graph rooted at one core part. A per-`ThreatManager` assembler instantiates Godot wrappers or deterministic primitive fallbacks, aligns child root sockets to parent attachment sockets from the repository-owned biomass catalog, adds pre-authored connector meshes and Godot-owned physics-body collision shapes, and drives rigid-part socket-space gait motion without changing gameplay AI/pathfinding authority. Meshy remains a candidate generator, Blender authors visual-only canonical masters and non-exported socket-fit guides, Godot wrappers/repository data own runtime sockets and behavior, and promotion remains a review-only proposal followed by an explicit manual commit.

**Tech Stack:** Godot 4.7.1/GDScript, Blender 5.2 LTS Python/`bpy`, Python 3.11, pytest, strict JSON, existing Meshy stage/review/runtime-review tools, git worktrees.

## Global Constraints

- Requirements: REQ-BIO-001 through REQ-BIO-010, REQ-AIAP-001 through REQ-AIAP-010, ADR-0058, ADR-0059, and Task 0’s ADR-0060 production-path reversal.
- Execute this plan in an isolated git worktree created with `using-git-worktrees`; the current main worktree contains hundreds of unrelated modified/untracked entries that must not be staged, cleaned, or reverted.
- Production direction confirmed by Christopher on 2026-09-02: locked-isometric 3D remains the production presentation. Task 0 creates and accepts ADR-0060 explicitly superseding ADR-0048’s 2D-production/no-new-GLB clauses before Task 1 or any implementation code begins.
- Production gameplay-authority changes are limited to `scripts/systems/threat_manager.gd`, shared `scripts/systems/threat_ai_state.gd`, and the existing lifecycle/LOS owner `scripts/procgen/playable_generated_ship.gd`; supporting catalog, recipe, wrapper, governance, validation, schema, tooling, documentation, and evidence files listed below are also in scope. `scripts/threats/topdown_threat_manager.gd` and 2D scenes receive no feature behavior changes, only regression coverage for shared-state compatibility.
- Preserve the existing locked orthographic/isometric gameplay camera contract. Do not introduce a free camera, perspective-camera dependency, or camera-specific geometry that fails from the current gameplay view.
- Working art direction is stylized low-poly 3D. Prioritize readable silhouette, separated masses, attachment-zone clearance, and gait readability over micro-detail. Existing per-part and 30,000-triangle assembly values are hard ceilings, not targets; do not add geometry merely to consume them.
- Geometry-selection generation remains untextured. Each promoted part uses no more than two material slots and must read under neutral, emergency, and dark lighting before texture/detail work is considered.
- ADR-0058 remains authoritative: runtime sockets/connectors, collision, navigation, integrity, and gameplay bindings live in Godot wrappers and repository data. Blender socket objects are preview-only guides excluded from exported GLBs; `meshy_blender_validate.py` must continue rejecting exported `socket`/`marker` helper nodes.
- Do not add an autoload or scene-tree assembler node. `BiomassAssembler` extends `RefCounted`; each `ThreatManager` owns one non-tree field and injects catalog/recipe paths for tests. `_clear_runtime_nodes()` may free assembled visual children but must never invalidate the assembler.
- The attachment graph requires one `core` instance, at most 8 non-core attachments, at most depth 3, unique instance IDs, parent-before-child ordering, one child per parent socket, and no cycles.
- Recipe persistence stores the full validated recipe document plus its seed; regenerating from a mutable catalog is not sufficient for save/load fidelity.
- Socket convention: local `+Y` is up, local `+Z` is forward/outward, attachable part geometry begins at `socket_root_0`, and child alignment is `parent_socket.global_transform * child_socket.transform.affine_inverse()`.
- Supported part categories are exactly `biomass_core`, `biomass_limb`, `biomass_head`, `biomass_connector`, and `biomass_appendage`.
- Supported locomotion hints are exactly `biped`, `quadruped`, `crawl`, `drag`, and `slither`.
- Gait v1 uses bounded rigid-part socket-space aiming; it does not add skeletal rigs, runtime mesh deformation, procedural animation blending, or Meshy rigging.
- Connectors are pre-authored collar/gunk parts instanced at each occupied attachment socket. Procedural connector deformation is out of scope for v1.
- Recursive attachments are supported only through the validated graph depth limit of 3; the pilot proves a limb with a distal claw/maw but not unbounded recursion.
- All six current 3D archetypes (`biomatter_swarm`, `stalker`, `hull_tendril`, `puppet_corpse`, `mimic`, `drone_swarm`) receive biomass recipe pools; the primitive renderer remains only a fail-safe for invalid or missing assembly data.
- The runtime must pass all catalog, generator, assembly, gait, persistence, and visual-review gates using deterministic primitive parts before any paid Meshy generation.
- Pilot part IDs are exactly `biomass_human_arm_v1`, `biomass_insect_leg_v1`, `biomass_cephalopod_tentacle_v1`, `biomass_animal_skull_v1`, `biomass_humanoid_torso_v1`, `biomass_gunk_connector_v1`, `biomass_claw_v1`, and `biomass_maw_v1`.
- Pilot generation uses `image_to_3d`, Smart Topology `meshy-t2`, `should_texture: false`, 4 candidates per part, and an aggregate approved maximum of 160 credits.
- Per-part triangle maxima are: core 5,000; limb 2,500; head 3,500; connector 500; appendage 1,500. An assembled threat must stay at or below 30,000 triangles and 160 inclusive runtime nodes.
- `runtime_node_count()` counts every live `Node` in the assembled visual subtree, including the `CharacterBody3D` root, part/wrapper roots, imported visual nodes, all repository-authored socket nodes, attachment mounts, connector roots/visuals/sockets, and every `CollisionShape3D`; `RefCounted` catalogs, recipes, assembler, and gait controller are excluded. The conservative eight-attachment promoted-wrapper bound is 144 nodes (1 body + 8 mounts + up to 86 core/attachment nodes + 32 connector nodes + 17 collision nodes), leaving 16 nodes of hard-cap headroom.
- Every generated part has `collision_owner: "godot_wrapper"`; generated/imported GLBs contain no gameplay collision bodies.
- Meshy writes only under `assets/_staging/meshy/<asset_id>/`; canonical Blender masters/evidence remain under `/Volumes/Untitled/SynapticSeaAssets/meshy/`.
- Candidate generation, Blender cleanup, validation, runtime review, and promotion packets must never directly mutate `assets/imported`, `scenes/wrappers`, `data/combat`, or runtime indices.
- A human-visible contact sheet and runtime review are mandatory before selection and before final promotion. No auto-promotion path is introduced.
- Existing staged Stalker candidates remain immutable historical evidence and are not promoted.
- The obsolete singular-threat contract files and every historical staging/evidence file remain byte-identical at their current paths. Retirement is recorded in `data/asset_generation/contract_lifecycle_v1.json`; new planning rejects retired IDs while historical hash-bound verification remains readable.
- Every task follows RED → GREEN → focused regression → commit. Do not mix asset-generation side effects into code/schema commits.

## File Structure

### Governance and host tooling

- Create `docs/game/adr/0060-restore-3d-production-path.md` — explicitly supersede ADR-0048’s top-down-only and no-new-GLB clauses while preserving the 2D path as a legacy/alternate presentation.
- Modify `docs/game/adr/README.md` — index ADR-0060.
- Modify `docs/game/adr/0059-procedural-biomass-assembly.md` — replace the flat torso/head/limb recipe and autoload decision with the explicit attachment graph, per-manager assembler, repository-owned sockets, and locked-isometric low-poly presentation constraints.
- Modify `docs/game/features/procedural_biomass_assembly.md` — lock v1 limits, locked-isometric low-poly readability rules, pilot IDs, curated recipes, promotion gates, and resolved design questions.
- Modify `docs/game/05_requirements.md` — align REQ-BIO wording with graph persistence, socket-space gait, catalog authority, and no-autoload runtime ownership.
- Modify `docs/game/06_validation_plan.md` — register host and Godot gates with exact pass markers only after they exist.
- Modify `docs/game/07_risk_register.md` — record 3D pipeline cost/cohesion, composite-creature readability, and migration risks.
- Create `data/combat/schemas/biomass_part_catalog_v1.schema.json` — repository/Godot socket authority for part catalog documents.
- Create `data/combat/schemas/biomass_recipe_catalog_v1.schema.json` — checked-in structural contract for curated recipe catalogs.
- Create `tools/biomass_catalog_validate.py` — strict host validator shared by tests and CI/manual gates.
- Create `tests/test_biomass_catalog_validate.py` — malformed catalog/recipe, graph, compatibility, limit, and determinism tests.
- Modify `tools/meshy_asset_contract.py` and its existing schema tests — add biomass category cross-field policy without adding socket transforms to the AI contract.
- Create eight `data/asset_generation/contracts/biomass_*_v1.json` pilot contracts using the existing closed contract shape.
- Create `data/asset_generation/schemas/contract_lifecycle_v1.schema.json` and `data/asset_generation/contract_lifecycle_v1.json` — retire singular-threat IDs without moving or editing their contracts.
- Modify `tools/meshy_stage.py` — reject new plans/generation for lifecycle-retired IDs while preserving historical verification.
- Create `scripts/systems/biomass_wrapper_validator.gd` — validate repository-owned socket nodes/transforms on wrapper/placeholder instances.
- Create `tools/meshy_biomass_part_recipe.py` — host-safe Blender authoring recipe for visual-only masters, non-exported socket-fit guides, previews, and scratch GLBs.
- Create `tests/test_meshy_biomass_part_recipe.py`; retain the existing `meshy_blender_validate.py` socket/marker rejection and add a regression proving biomass exports contain no helper nodes.
- Modify `tools/meshy_promotion_packet.py` and `tests/test_meshy_promotion_packet.py` — add a review-only `biomass-part` proposal.

### Runtime domain and visuals

- Create `data/combat/biomass_part_catalog.json` — part capabilities, wrapper paths, fallback profiles, socket contracts, collision descriptors, and budgets.
- Create `data/combat/biomass_recipe_catalog.json` — five curated recipes plus archetype pools.
- Modify `data/combat/threat_visual_catalog.json` — route every 3D threat archetype to biomass mode while retaining primitive fail-safe fields; curated pool IDs remain solely in `biomass_recipe_catalog.json`.
- Create `scripts/systems/biomass_part_catalog.gd` — strict runtime part catalog loader/query API.
- Create `scripts/systems/biomass_recipe.gd` — immutable validated graph model and canonical serialization.
- Create `scripts/systems/biomass_recipe_library.gd` — curated recipe/pool loader.
- Create `scripts/systems/biomass_recipe_generator.gd` — deterministic seeded recipe generator.
- Create `scripts/tools/biomass_placeholder_factory.gd` — primitive part/sockets used until wrappers are promoted and as fail-safe evidence.
- Create `scripts/threats/biomass_threat_visual.gd` — assembled visual root, instance/socket lookup, connector and collision ownership.
- Create `scripts/threats/biomass_assembler.gd` — graph instantiation, socket alignment, limits, and fail-closed diagnostics.
- Create `scripts/threats/biomass_gait_controller.gd` — five bounded socket-space gait profiles.
- Modify `scripts/systems/threat_ai_state.gd` — persist `biomass_recipe` and `biomass_seed`.
- Modify `scripts/systems/threat_manager.gd` — own catalogs/assembler, choose recipes, instantiate assembled visuals, and preserve primitive fallback.

### Validation and evidence

- Create `scripts/validation/biomass_catalog_smoke.gd` — runtime catalog and recipe validation.
- Create `scripts/validation/biomass_recipe_generator_smoke.gd` — deterministic 100-seed generator matrix.
- Create `scripts/validation/biomass_assembly_smoke.gd` — graph alignment, connector, collision, limits, and gait tests.
- Create `scripts/validation/biomass_threat_manager_smoke.gd` — all-archetype spawn and exact manager summary reconstruction.
- Create `scripts/validation/biomass_revisit_persistence_smoke.gd` — `PlayableGeneratedShip` save/revisit regeneration with exact assembly equality.
- Create `scripts/validation/biomass_visual_review.gd` — one deterministic capture case for a requested recipe/seed/lighting tuple.
- Create `data/asset_generation/schemas/biomass_composite_review_v1.schema.json`, `tools/biomass_composite_review.py`, and `tests/test_biomass_composite_review.py` — separate 30-capture composite review; do not overload the existing one-GLB Meshy runtime-review schema.
- Create `docs/superpowers/proofs/procedural-biomass-pilot.md` — final fresh commands, hashes, runtime markers, contact sheets, and promotion evidence.

---

### Task 0: Accept the locked-isometric 3D production-path ADR

**Files:**
- Create: `docs/game/adr/0060-restore-3d-production-path.md`
- Modify: `docs/game/adr/README.md`

**Interfaces:**
- Consumes: Christopher’s 2026-09-02 confirmation that production remains locked-isometric 3D with a stylized low-poly bias.
- Produces: accepted architectural authority for Tasks 1-15; no implementation task may begin without it.

- [ ] **Step 1: Write the decision record before any implementation work**

Create ADR-0060 with `Status: Accepted`, `Decision owner: Christopher`, `Confirmation date: 2026-09-02`, and `Supersedes in part: ADR-0048`. Identify the exact ADR-0048 clauses superseded: top-down 2D as the sole production path, the locked-isometric freeze, and the prohibition on new production GLBs. Preserve the 2D path as legacy/alternate rather than deleting it. Declare ADR-0058 and ADR-0059 the governing 3D asset/runtime authority, lock the existing orthographic/isometric gameplay camera, and record the stylized low-poly working direction with silhouette/readability prioritized over micro-detail.

- [ ] **Step 2: Index and verify acceptance evidence separately from the commit**

Add ADR-0060 to `docs/game/adr/README.md`. Verify the file itself—not commit metadata—contains all four acceptance fields and names ADR-0048, ADR-0058, and ADR-0059:

```bash
/opt/homebrew/bin/python3.11 -c 'from pathlib import Path; p=Path("docs/game/adr/0060-restore-3d-production-path.md"); s=p.read_text(); required=["Status: Accepted","Decision owner: Christopher","Confirmation date: 2026-09-02","Supersedes in part: ADR-0048","ADR-0058","ADR-0059"]; missing=[x for x in required if x not in s]; assert not missing, missing; print("ADR-0060 ACCEPTANCE PASS")'
```

Expected marker: `ADR-0060 ACCEPTANCE PASS`.

- [ ] **Step 3: Commit the accepted decision gate**

```bash
git add docs/game/adr/0060-restore-3d-production-path.md docs/game/adr/README.md
git commit -m "docs: accept locked-isometric 3d production path"
```

Stop if the acceptance verification fails. Task 1 begins only after this commit exists and the ADR remains `Accepted`.

---

### Task 1: Canonical part and recipe data contracts

**Files:**
- Create: `data/combat/schemas/biomass_part_catalog_v1.schema.json`
- Create: `data/combat/schemas/biomass_recipe_catalog_v1.schema.json`
- Create: `data/combat/biomass_part_catalog.json`
- Create: `data/combat/biomass_recipe_catalog.json`
- Create: `tools/biomass_catalog_validate.py`
- Create: `tests/test_biomass_catalog_validate.py`
- Modify: `docs/game/adr/0059-procedural-biomass-assembly.md`
- Modify: `docs/game/features/procedural_biomass_assembly.md`
- Modify: `docs/game/05_requirements.md`
- Modify: `docs/game/07_risk_register.md`

**Interfaces:**
- Consumes: strict JSON bytes and repository-relative resource paths.
- Produces:
  - `validate_part_catalog(document: object, project_root: Path) -> list[str]`
  - `validate_recipe_catalog(document: object, part_catalog: Mapping[str, Any]) -> list[str]`
  - `validate_recipe(recipe: object, part_catalog: Mapping[str, Any]) -> list[str]`
  - `canonical_recipe_bytes(recipe: Mapping[str, Any]) -> bytes`
  - CLI: `python tools/biomass_catalog_validate.py --project-root . --parts data/combat/biomass_part_catalog.json --recipes data/combat/biomass_recipe_catalog.json`

- [ ] **Step 1: Write RED tests for exact fields and graph safety**

```python
from copy import deepcopy
from pathlib import Path

from tools import biomass_catalog_validate as validator

ROOT = Path(__file__).resolve().parents[1]


def valid_recipe() -> dict:
    return {
        "recipe_id": "biped_puppet_v1",
        "locomotion_hint": "biped",
        "core": {"instance_id": "core", "part_id": "biomass_humanoid_torso_v1"},
        "attachments": [
            {
                "instance_id": "leg_left",
                "part_id": "biomass_human_arm_v1",
                "parent_instance_id": "core",
                "parent_socket": "socket_limb_0",
                "child_socket": "socket_root_0",
                "connector_part_id": "biomass_gunk_connector_v1",
            },
            {
                "instance_id": "leg_right",
                "part_id": "biomass_human_arm_v1",
                "parent_instance_id": "core",
                "parent_socket": "socket_limb_1",
                "child_socket": "socket_root_0",
                "connector_part_id": "biomass_gunk_connector_v1",
            },
        ],
    }


def test_recipe_rejects_duplicate_socket_use_and_forward_reference(part_catalog: dict) -> None:
    recipe = valid_recipe()
    recipe["attachments"][1]["parent_socket"] = "socket_limb_0"
    errors = validator.validate_recipe(recipe, part_catalog)
    assert "parent socket core/socket_limb_0 is occupied more than once" in errors
    recipe = valid_recipe()
    recipe["attachments"][0]["parent_instance_id"] = "leg_right"
    errors = validator.validate_recipe(recipe, part_catalog)
    assert "attachment parent must appear before child: leg_left" in errors


def test_recipe_rejects_depth_over_three_and_incompatible_category(part_catalog: dict) -> None:
    recipe = valid_recipe()
    recipe["attachments"].extend([
        {"instance_id": "a", "part_id": "biomass_cephalopod_tentacle_v1", "parent_instance_id": "leg_left", "parent_socket": "socket_distal_0", "child_socket": "socket_root_0", "connector_part_id": "biomass_gunk_connector_v1"},
        {"instance_id": "b", "part_id": "biomass_cephalopod_tentacle_v1", "parent_instance_id": "a", "parent_socket": "socket_distal_0", "child_socket": "socket_root_0", "connector_part_id": "biomass_gunk_connector_v1"},
        {"instance_id": "c", "part_id": "biomass_cephalopod_tentacle_v1", "parent_instance_id": "b", "parent_socket": "socket_distal_0", "child_socket": "socket_root_0", "connector_part_id": "biomass_gunk_connector_v1"},
    ])
    errors = validator.validate_recipe(recipe, part_catalog)
    assert "attachment depth exceeds 3: c" in errors
```

- [ ] **Step 2: Run RED tests**

Run:

`PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 PYTHONPATH=. /opt/homebrew/bin/python3.11 -m pytest -q tests/test_biomass_catalog_validate.py`

Expected: FAIL because the validator and catalogs do not exist.

- [ ] **Step 3: Define the exact part catalog shape**

Use this top-level contract and no additional fields:

```json
{
  "schema_version": "1.0.0",
  "document_kind": "biomass_part_catalog",
  "limits": {"max_attachments": 8, "max_depth": 3, "max_triangles": 30000, "max_nodes": 160},
  "parts": {
    "biomass_human_arm_v1": {
      "category": "biomass_limb",
      "species_tags": ["human"],
      "assembly_roles": ["locomotor", "manipulator", "puller"],
      "wrapper_scene_path": "",
      "triangle_budget": 2500,
      "sockets": [
        {"name": "socket_root_0", "kind": "root", "accepts_categories": [], "position_m": [0.0, 0.0, 0.0], "rotation_deg": [0.0, 0.0, 0.0]},
        {"name": "socket_distal_0", "kind": "distal", "accepts_categories": ["biomass_appendage", "biomass_limb"], "position_m": [0.0, 0.0, 1.0], "rotation_deg": [0.0, 0.0, 0.0]}
      ],
      "collision_shapes": [
        {"shape": "capsule", "position_m": [0.0, 0.0, 0.45], "rotation_deg": [90.0, 0.0, 0.0], "radius_m": 0.12, "height_m": 0.9}
      ],
      "fallback": {"primitive": "capsule", "dimensions_m": [0.24, 0.24, 1.0], "albedo": "#8b5252"}
    }
  }
}
```

Every one of the eight pilot entries uses the same exact field set. Empty `wrapper_scene_path` means the deterministic fallback factory is authoritative until manual promotion. Socket names match `^socket_(root|head|limb|appendage|jaw|distal)_[0-9]+$`; only `root` sockets have an empty `accepts_categories` list.

The catalog values are not left to worker discretion. Use this compact notation: `S(name, kind, accepts, position_m, rotation_deg)`, `Capsule(position_m, rotation_deg, radius_m, height_m)`, `Box(position_m, rotation_deg, dimensions_m)`, `Sphere(position_m, radius_m)`, and `F(primitive, dimensions_m, albedo)`. Every omitted `wrapper_scene_path` below is exactly `""`.

- `biomass_human_arm_v1`: category `biomass_limb`; species `['human']`; roles `['locomotor','manipulator','puller']`; triangle budget `2500`; sockets `S('socket_root_0','root',[],[0,0,0],[0,0,0])`, `S('socket_distal_0','distal',['biomass_appendage','biomass_limb'],[0,0,1.0],[0,0,0])`; collision `Capsule([0,0,0.45],[90,0,0],0.12,0.90)`; fallback `F('capsule',[0.24,0.24,1.0],'#8b5252')`.
- `biomass_insect_leg_v1`: category `biomass_limb`; species `['insectoid']`; roles `['locomotor']`; triangle budget `2500`; sockets `S('socket_root_0','root',[],[0,0,0],[0,0,0])`, `S('socket_distal_0','distal',['biomass_appendage','biomass_limb'],[0,0,0.90],[0,0,0])`; collision `Capsule([0,0,0.42],[90,0,0],0.10,0.84)`; fallback `F('capsule',[0.22,0.22,0.90],'#6f7046')`.
- `biomass_cephalopod_tentacle_v1`: category `biomass_limb`; species `['cephalopodic']`; roles `['locomotor','puller','slither']`; triangle budget `2500`; sockets `S('socket_root_0','root',[],[0,0,0],[0,0,0])`, `S('socket_distal_0','distal',['biomass_appendage','biomass_limb'],[0,0,1.20],[0,0,0])`; collision `Capsule([0,0,0.55],[90,0,0],0.11,1.10)`; fallback `F('capsule',[0.24,0.24,1.20],'#765070')`.
- `biomass_animal_skull_v1`: category `biomass_head`; species `['animal']`; roles `['core','detail']`; triangle budget `3500`; sockets `S('socket_root_0','root',[],[0,0,0],[0,0,0])`, `S('socket_appendage_0','appendage',['biomass_limb','biomass_appendage'],[-0.20,0.05,0.20],[0,-65,0])`, `S('socket_appendage_1','appendage',['biomass_limb','biomass_appendage'],[0.20,0.05,0.20],[0,65,0])`, `S('socket_appendage_2','appendage',['biomass_limb','biomass_appendage'],[-0.18,-0.10,0.35],[25,-40,0])`, `S('socket_appendage_3','appendage',['biomass_limb','biomass_appendage'],[0.18,-0.10,0.35],[25,40,0])`, `S('socket_jaw_0','jaw',['biomass_appendage'],[0,-0.18,0.50],[15,0,0])`; collision `Box([0,0,0.30],[0,0,0],[0.45,0.40,0.60])`; fallback `F('box',[0.45,0.40,0.60],'#8a806b')`.
- `biomass_humanoid_torso_v1`: category `biomass_core`; species `['human']`; roles `['core']`; triangle budget `5000`; sockets `S('socket_root_0','root',[],[0,0,0],[0,0,0])`, `S('socket_head_0','head',['biomass_head','biomass_appendage'],[0,0.45,0.05],[-90,0,0])`, `S('socket_limb_0','limb',['biomass_limb'],[-0.34,0.28,0],[0,-90,0])`, `S('socket_limb_1','limb',['biomass_limb'],[0.34,0.28,0],[0,90,0])`, `S('socket_limb_2','limb',['biomass_limb'],[-0.34,-0.05,0],[0,-90,0])`, `S('socket_limb_3','limb',['biomass_limb'],[0.34,-0.05,0],[0,90,0])`, `S('socket_limb_4','limb',['biomass_limb'],[-0.20,-0.45,0],[90,0,0])`, `S('socket_limb_5','limb',['biomass_limb'],[0.20,-0.45,0],[90,0,0])`, `S('socket_appendage_0','appendage',['biomass_head','biomass_appendage'],[0,0.15,-0.20],[0,180,0])`, `S('socket_appendage_1','appendage',['biomass_head','biomass_appendage'],[-0.22,0.15,-0.18],[0,-135,0])`, `S('socket_appendage_2','appendage',['biomass_head','biomass_appendage'],[0.22,0.15,-0.18],[0,135,0])`; collision `Box([0,0,0],[0,0,0],[0.65,0.90,0.40])`; fallback `F('box',[0.65,0.90,0.40],'#80585d')`.
- `biomass_gunk_connector_v1`: category `biomass_connector`; species `['biomass']`; roles `['connector']`; triangle budget `500`; sockets `S('socket_root_0','root',[],[0,0,0],[0,0,0])`; collision `Sphere([0,0,0.10],0.18)`; fallback `F('sphere',[0.35,0.35,0.25],'#704b63')`.
- `biomass_claw_v1`: category `biomass_appendage`; species `['alien']`; roles `['detail','manipulator']`; triangle budget `1500`; sockets `S('socket_root_0','root',[],[0,0,0],[0,0,0])`; collision `Box([0,0,0.10],[0,0,0],[0.35,0.20,0.20])`; fallback `F('box',[0.35,0.20,0.20],'#6d6148')`.
- `biomass_maw_v1`: category `biomass_appendage`; species `['alien']`; roles `['detail']`; triangle budget `1500`; sockets `S('socket_root_0','root',[],[0,0,0],[0,0,0])`; collision `Box([0,0,0.175],[0,0,0],[0.40,0.30,0.35])`; fallback `F('box',[0.40,0.30,0.35],'#8c4851')`.

`assembly_roles` accepts exactly `core`, `locomotor`, `manipulator`, `detail`, `puller`, `slither`, and `connector`. Tests assert the exact eight IDs/entries above, role counts (`core=2`, `locomotor=3`, `puller=2`, `slither=1`, `detail=3`, `connector=1`), unique socket names, every curated recipe socket reference, and every position/rotation/collision/fallback value. Socket-position bounds remain `abs(position_m[i]) <= dimensions_m[i] + 0.05` for each axis.

- [ ] **Step 4: Define five curated recipes and all six archetype pools**

The recipe catalog uses the exact attachment records below. Define the connector token once in code while authoring, but write the expanded string `biomass_gunk_connector_v1` into every JSON edge:

```json
{
  "schema_version": "1.0.0",
  "document_kind": "biomass_recipe_catalog",
  "recipes": {
    "biped_puppet_v1": {
      "recipe_id": "biped_puppet_v1",
      "locomotion_hint": "biped",
      "core": {"instance_id": "core", "part_id": "biomass_humanoid_torso_v1"},
      "attachments": [
        {"instance_id": "leg_left", "part_id": "biomass_human_arm_v1", "parent_instance_id": "core", "parent_socket": "socket_limb_0", "child_socket": "socket_root_0", "connector_part_id": "biomass_gunk_connector_v1"},
        {"instance_id": "leg_right", "part_id": "biomass_human_arm_v1", "parent_instance_id": "core", "parent_socket": "socket_limb_1", "child_socket": "socket_root_0", "connector_part_id": "biomass_gunk_connector_v1"},
        {"instance_id": "head", "part_id": "biomass_animal_skull_v1", "parent_instance_id": "core", "parent_socket": "socket_head_0", "child_socket": "socket_root_0", "connector_part_id": "biomass_gunk_connector_v1"},
        {"instance_id": "left_claw", "part_id": "biomass_claw_v1", "parent_instance_id": "leg_left", "parent_socket": "socket_distal_0", "child_socket": "socket_root_0", "connector_part_id": "biomass_gunk_connector_v1"}
      ]
    },
    "four_legged_scrambler_v1": {
      "recipe_id": "four_legged_scrambler_v1",
      "locomotion_hint": "quadruped",
      "core": {"instance_id": "core", "part_id": "biomass_humanoid_torso_v1"},
      "attachments": [
        {"instance_id": "leg_0", "part_id": "biomass_insect_leg_v1", "parent_instance_id": "core", "parent_socket": "socket_limb_0", "child_socket": "socket_root_0", "connector_part_id": "biomass_gunk_connector_v1"},
        {"instance_id": "leg_1", "part_id": "biomass_insect_leg_v1", "parent_instance_id": "core", "parent_socket": "socket_limb_1", "child_socket": "socket_root_0", "connector_part_id": "biomass_gunk_connector_v1"},
        {"instance_id": "leg_2", "part_id": "biomass_insect_leg_v1", "parent_instance_id": "core", "parent_socket": "socket_limb_2", "child_socket": "socket_root_0", "connector_part_id": "biomass_gunk_connector_v1"},
        {"instance_id": "leg_3", "part_id": "biomass_insect_leg_v1", "parent_instance_id": "core", "parent_socket": "socket_limb_3", "child_socket": "socket_root_0", "connector_part_id": "biomass_gunk_connector_v1"},
        {"instance_id": "head", "part_id": "biomass_animal_skull_v1", "parent_instance_id": "core", "parent_socket": "socket_head_0", "child_socket": "socket_root_0", "connector_part_id": "biomass_gunk_connector_v1"},
        {"instance_id": "maw", "part_id": "biomass_maw_v1", "parent_instance_id": "head", "parent_socket": "socket_jaw_0", "child_socket": "socket_root_0", "connector_part_id": "biomass_gunk_connector_v1"}
      ]
    },
    "tripod_hound_v1": {
      "recipe_id": "tripod_hound_v1",
      "locomotion_hint": "crawl",
      "core": {"instance_id": "core", "part_id": "biomass_animal_skull_v1"},
      "attachments": [
        {"instance_id": "leg_0", "part_id": "biomass_insect_leg_v1", "parent_instance_id": "core", "parent_socket": "socket_appendage_0", "child_socket": "socket_root_0", "connector_part_id": "biomass_gunk_connector_v1"},
        {"instance_id": "leg_1", "part_id": "biomass_insect_leg_v1", "parent_instance_id": "core", "parent_socket": "socket_appendage_1", "child_socket": "socket_root_0", "connector_part_id": "biomass_gunk_connector_v1"},
        {"instance_id": "leg_2", "part_id": "biomass_insect_leg_v1", "parent_instance_id": "core", "parent_socket": "socket_appendage_2", "child_socket": "socket_root_0", "connector_part_id": "biomass_gunk_connector_v1"},
        {"instance_id": "maw", "part_id": "biomass_maw_v1", "parent_instance_id": "core", "parent_socket": "socket_jaw_0", "child_socket": "socket_root_0", "connector_part_id": "biomass_gunk_connector_v1"},
        {"instance_id": "claw", "part_id": "biomass_claw_v1", "parent_instance_id": "leg_0", "parent_socket": "socket_distal_0", "child_socket": "socket_root_0", "connector_part_id": "biomass_gunk_connector_v1"}
      ]
    },
    "intestinal_dragger_v1": {
      "recipe_id": "intestinal_dragger_v1",
      "locomotion_hint": "drag",
      "core": {"instance_id": "core", "part_id": "biomass_animal_skull_v1"},
      "attachments": [
        {"instance_id": "puller", "part_id": "biomass_cephalopod_tentacle_v1", "parent_instance_id": "core", "parent_socket": "socket_appendage_0", "child_socket": "socket_root_0", "connector_part_id": "biomass_gunk_connector_v1"},
        {"instance_id": "arm", "part_id": "biomass_human_arm_v1", "parent_instance_id": "core", "parent_socket": "socket_appendage_1", "child_socket": "socket_root_0", "connector_part_id": "biomass_gunk_connector_v1"},
        {"instance_id": "maw", "part_id": "biomass_maw_v1", "parent_instance_id": "core", "parent_socket": "socket_jaw_0", "child_socket": "socket_root_0", "connector_part_id": "biomass_gunk_connector_v1"}
      ]
    },
    "tendril_knot_v1": {
      "recipe_id": "tendril_knot_v1",
      "locomotion_hint": "slither",
      "core": {"instance_id": "core", "part_id": "biomass_humanoid_torso_v1"},
      "attachments": [
        {"instance_id": "tendril_0", "part_id": "biomass_cephalopod_tentacle_v1", "parent_instance_id": "core", "parent_socket": "socket_limb_0", "child_socket": "socket_root_0", "connector_part_id": "biomass_gunk_connector_v1"},
        {"instance_id": "tendril_1", "part_id": "biomass_cephalopod_tentacle_v1", "parent_instance_id": "core", "parent_socket": "socket_limb_1", "child_socket": "socket_root_0", "connector_part_id": "biomass_gunk_connector_v1"},
        {"instance_id": "maw", "part_id": "biomass_maw_v1", "parent_instance_id": "tendril_0", "parent_socket": "socket_distal_0", "child_socket": "socket_root_0", "connector_part_id": "biomass_gunk_connector_v1"},
        {"instance_id": "claw", "part_id": "biomass_claw_v1", "parent_instance_id": "tendril_1", "parent_socket": "socket_distal_0", "child_socket": "socket_root_0", "connector_part_id": "biomass_gunk_connector_v1"}
      ]
    }
  },
  "archetype_pools": {
    "biomatter_swarm": ["tripod_hound_v1", "intestinal_dragger_v1"],
    "stalker": ["biped_puppet_v1", "four_legged_scrambler_v1"],
    "hull_tendril": ["tendril_knot_v1", "intestinal_dragger_v1"],
    "puppet_corpse": ["biped_puppet_v1", "tripod_hound_v1"],
    "mimic": ["four_legged_scrambler_v1", "tripod_hound_v1"],
    "drone_swarm": ["tendril_knot_v1", "tripod_hound_v1"]
  }
}
```

The torso and skull socket contracts must accept every child category used above. The depth-2 claw on `tripod_hound_v1` and depth-2 maw/claw on `tendril_knot_v1` are the bounded recursive-attachment proof.

- [ ] **Step 5: Implement strict host validation**

```python
PART_CATEGORIES = frozenset({"biomass_core", "biomass_limb", "biomass_head", "biomass_connector", "biomass_appendage"})
ASSEMBLY_ROLES = frozenset({"core", "locomotor", "manipulator", "detail", "puller", "slither", "connector"})
LOCOMOTION_HINTS = frozenset({"biped", "quadruped", "crawl", "drag", "slither"})
PART_FIELDS = frozenset({"category", "species_tags", "assembly_roles", "wrapper_scene_path", "triangle_budget", "sockets", "collision_shapes", "fallback"})
RECIPE_FIELDS = frozenset({"recipe_id", "locomotion_hint", "core", "attachments"})
ATTACHMENT_FIELDS = frozenset({"instance_id", "part_id", "parent_instance_id", "parent_socket", "child_socket", "connector_part_id"})
MAX_ATTACHMENTS = 8
MAX_DEPTH = 3
MAX_TRIANGLES = 30_000
MAX_NODES = 160


def canonical_recipe_bytes(recipe: Mapping[str, Any]) -> bytes:
    return (json.dumps(recipe, sort_keys=True, separators=(",", ":"), allow_nan=False) + "\n").encode("utf-8")
```

Validation rejects unknown/missing fields, duplicate JSON keys, non-finite numbers, absolute or non-`res://` wrapper paths, missing wrapper files when the path is non-empty, unknown part IDs, unknown/duplicate assembly roles, a recipe core whose catalog entry lacks role `core`, connector parts lacking role `connector`, connector IDs outside `biomass_connector`, incompatible socket/category pairs, missing child root sockets, duplicate instance IDs, duplicate parent/socket occupancy, forward references, cycles, depth/attachment/node/triangle limits, unsupported locomotion hints, and locomotion recipes lacking their required role counts. Return stable sorted diagnostics.

- [ ] **Step 6: Run GREEN and determinism tests**

Run:

`PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 PYTHONPATH=. /opt/homebrew/bin/python3.11 -m pytest -q tests/test_biomass_catalog_validate.py`

Run the CLI twice and compare hashes:

```bash
/opt/homebrew/bin/python3.11 tools/biomass_catalog_validate.py --project-root . --parts data/combat/biomass_part_catalog.json --recipes data/combat/biomass_recipe_catalog.json > /tmp/biomass-validate-a.txt
/opt/homebrew/bin/python3.11 tools/biomass_catalog_validate.py --project-root . --parts data/combat/biomass_part_catalog.json --recipes data/combat/biomass_recipe_catalog.json > /tmp/biomass-validate-b.txt
cmp /tmp/biomass-validate-a.txt /tmp/biomass-validate-b.txt
```

Expected marker: `BIOMASS CATALOG VALIDATION PASS parts=8 recipes=5 archetypes=6`.

- [ ] **Step 7: Reconcile the feature documents with accepted ADR-0060**

Treat Task 0’s accepted ADR-0060 as immutable input. Record these resolved decisions in ADR-0059/spec/requirements: explicit attachment graph; `core` rather than mandatory torso; repository/Godot-owned sockets; exported GLBs are visual-only; pre-authored non-deforming connectors; graph depth 3; five curated recipes; deterministic random recipes; full recipe persistence; per-manager non-tree assembler; rigid-part socket-space gait rather than skeletal IK; all six 3D archetypes use biomass pools; production presentation remains locked-isometric; low-poly silhouettes and attachment readability take precedence over micro-detail; placeholder-first proof before paid generation. After those conflicts are reconciled, set ADR-0059 to `Accepted`; do not leave it `Proposed`, because Tasks 2-15 consume it as architecture authority. Restore the currently missing requirements as `REQ-BIO-006: Five locomotion gait profiles` and `REQ-BIO-007: Exact assembly save/load persistence`, update REQ-BIO-003 verification to the real `biomass_catalog_validate.py` CLI, and update REQ-BIO-009 from three assemblies to all five locomotion hints and 30 composite captures. Add the corresponding 3D pipeline, low-poly cohesion, and migration risks to `07_risk_register.md`.

- [ ] **Step 8: Commit Task 1**

```bash
git add data/combat/schemas data/combat/biomass_part_catalog.json data/combat/biomass_recipe_catalog.json tools/biomass_catalog_validate.py tests/test_biomass_catalog_validate.py docs/game/adr/0059-procedural-biomass-assembly.md docs/game/features/procedural_biomass_assembly.md docs/game/05_requirements.md docs/game/07_risk_register.md
git commit -m "feat: define procedural biomass assembly contracts"
```

---

### Task 2: Existing-schema biomass contracts, staged-artifact limits, and lifecycle retirement

**Files:**
- Modify: `tools/meshy_asset_contract.py`
- Modify: `tests/test_meshy_asset_contract.py`
- Modify: `tests/test_meshy_stage.py`
- Modify: `tools/meshy_stage.py`
- Create: eight `data/asset_generation/contracts/biomass_*_v1.json` files
- Create: `data/asset_generation/schemas/contract_lifecycle_v1.schema.json`
- Create: `data/asset_generation/contract_lifecycle_v1.json`
- Preserve unchanged and in place: `data/asset_generation/contracts/stalker_v1.json`, `hull_tendril_kit_v1.json`, and `biomatter_swarm_kit_v1.json`

**Interfaces:**
- Consumes: Task 1 part IDs/categories and repository-owned socket catalog.
- Produces: eight visual-generation contracts using the current closed `ai_asset_contract_v1` shape, plus a separate lifecycle document used only to prevent new work on retired IDs.
- Commits the already-proven paid-stage bounds `_GLB_MAX_BYTES = 128 * 1024 * 1024` and `_DOWNLOAD_TOTAL_MAX_BYTES = 256 * 1024 * 1024` into `tools/meshy_stage.py`; do not rely on the current main worktree’s uncommitted copy.
- Does not duplicate socket transforms, assembly roles, or runtime attachment graphs into AI contracts or GLBs.

- [ ] **Step 1: Write RED tests for biomass cross-field policy**

```python
def test_biomass_contract_requires_visual_only_wrapper_policy() -> None:
    contract = valid_contract()
    contract.update({
        "asset_id": "biomass_human_arm_v1",
        "category": "biomass_limb",
        "pivot": "attachment",
        "collision_owner": "godot_wrapper",
        "state_derivation": "single_state",
        "required_states": ["default"],
    })
    contract["animation"] = {"kind": "static_mesh", "meshy_rigging_allowed": False, "rigging_target": "none"}
    contract["generation"]["should_texture"] = False
    assert meshy_asset_contract.validate_contract(contract) == []


def test_biomass_contract_rejects_meshing_runtime_authority() -> None:
    contract = valid_biomass_contract()
    contract["collision_owner"] = "blender_master"
    assert "biomass assets require collision_owner=godot_wrapper" in meshy_asset_contract.validate_contract(contract)
```

Also test that every biomass category rejects Meshy rigging, non-static animation, alternate states, `should_texture: true`, and an invalid pivot. Do not add an `assembly` top-level field to the closed schema.

- [ ] **Step 2: Run RED tests**

`PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 PYTHONPATH=. /opt/homebrew/bin/python3.11 -m pytest -q tests/test_meshy_asset_contract.py -k biomass`

Expected: FAIL because biomass cross-field policy is absent.

- [ ] **Step 3: Implement category-specific policy without socket duplication**

```python
BIOMASS_CATEGORIES = frozenset({
    "biomass_core", "biomass_limb", "biomass_head",
    "biomass_connector", "biomass_appendage",
})
```

Require `collision_owner == "godot_wrapper"`, `animation.kind == "static_mesh"`, `animation.meshy_rigging_allowed is false`, `animation.rigging_target == "none"`, `state_derivation == "single_state"`, `required_states == ["default"]`, and `generation.should_texture is false`. Require `pivot == "attachment"` for the seven non-`biomass_core` contracts and exactly `pivot == "scene_origin"` for `biomass_humanoid_torso_v1`; all eight use `forward_axis == "+Z"`. Keep the JSON schema closed and validate the real full contract shape; do not invent `species`, `sockets`, `godot_assembler`, or `proximal_center` fields/values.

- [ ] **Step 4: Create the eight contracts**

Use these fixed envelopes and budgets:

| asset_id | category | dimensions_m | low-poly target / hard max triangles | art-facing clearance brief |
|---|---|---:|---:|---|
| biomass_human_arm_v1 | biomass_limb | [0.28, 0.28, 1.00] | 1400 / 2500 | clear proximal root and distal end |
| biomass_insect_leg_v1 | biomass_limb | [0.35, 0.30, 0.90] | 1400 / 2500 | clear proximal root and distal end |
| biomass_cephalopod_tentacle_v1 | biomass_limb | [0.32, 0.32, 1.20] | 1600 / 2500 | clear proximal root and distal end |
| biomass_animal_skull_v1 | biomass_head | [0.45, 0.40, 0.60] | 2200 / 3500 | clear neck root, jaw, and four side/rear attachment regions |
| biomass_humanoid_torso_v1 | biomass_core | [0.65, 0.90, 0.40] | 3200 / 5000 | clear head, six limb, and three rear attachment regions |
| biomass_gunk_connector_v1 | biomass_connector | [0.35, 0.35, 0.25] | 300 / 500 | radial collar with neutral local origin |
| biomass_claw_v1 | biomass_appendage | [0.35, 0.20, 0.20] | 900 / 1500 | clear proximal root |
| biomass_maw_v1 | biomass_appendage | [0.40, 0.30, 0.35] | 1000 / 1500 | clear proximal root |

Every contract uses `image_to_3d`, Smart Topology `meshy-t2`, the listed low-poly target as integer `generation.target_polycount`, and the listed hard maximum as the exact object `budget.triangles = {"min": 1, "max": <hard-max>, "scope": "whole_asset"}`; biomass contracts never use the integer shorthand. Also require four candidates, one project-owned `three_quarter` reference, `budget.material_slots: 2`, `budget.texture_resolution: 2048`, and `generation.should_texture: false`. The `visual_brief` requests cohesive stylized low-poly form, broad readable planes/masses, and no photoreal micro-detail; it describes only visual form and clearance regions. Authoritative socket IDs/transforms stay exclusively in `data/combat/biomass_part_catalog.json`. The host validator and Blender gate enforce `budget.triangles.max` independently of the preferred `generation.target_polycount`.

- [ ] **Step 5: Write RED lifecycle and historical-size artifact tests**

Tests must prove:

1. `stalker_v1`, `hull_tendril_kit_v1`, and `biomatter_swarm_kit_v1` stay at their original paths and remain byte-identical to the tracked `origin/main` blobs at Task 2's base. Record and assert these canonical identities: `stalker_v1.json` = SHA-256 `fb31123b77453a42372715468d97a579b6f6a2433198d3ff0f00758c8cb3f9ff`, 1,633 bytes; `hull_tendril_kit_v1.json` = SHA-256 `d5139bbbffaa0a5e2f6628efd9f62f91060fcfa9d2b2ac58d430e0d8116533f0`, 1,755 bytes; `biomatter_swarm_kit_v1.json` = SHA-256 `b50b1694a563a8521994bdcbc1b9f0e7b41d00f4df28278282607d82399da6be`, 1,782 bytes. Do not derive historical identity from uncommitted or transient working-tree copies.
2. `meshy_stage.py plan/generate` rejects those IDs with `contract lifecycle is retired`.
3. Historical staging manifests, candidate reviews, Blender reports, runtime reports, and promotion packets can still resolve and hash-verify the original contract path.
4. Active loot-container, crafting-station, and biomass IDs still plan normally.
5. The lifecycle parser rejects duplicate IDs, unknown states, path traversal, and malformed/unknown fields.
6. A portable valid GLB fixture is exactly `94_588_220` bytes—the measured size of historical `stalker_v1/01a063a4-6158-7363-8f43-f6773a041de4/raw.glb`, above 64 MiB and below 128 MiB. Construct it in a pytest temp directory from a minimal aligned JSON chunk plus a padded BIN chunk; never depend on the ignored local Stalker file at test runtime.
7. Name the regression `test_historical_94588220_byte_glb_survives_generate_and_verify`. A normal four-candidate fake-client `generate_batch()` stores that fixture for exactly one candidate and small valid GLBs for the three companions, preserving the production `candidate_count` range of 3–6. `load_generation_record()` then re-reads, validates, hashes, and accepts the large fixture through the real `_verify_generation_adjacent_artifacts()` path. Assert every fake GLB download received a 128 MiB ceiling, `_DOWNLOAD_TOTAL_MAX_BYTES` is 256 MiB, and a GLB larger than 128 MiB is rejected. No network or provider credits are used.

- [ ] **Step 6: Implement committed artifact limits and additive lifecycle enforcement**

First set exactly `_GLB_MAX_BYTES = 128 * 1024 * 1024` and `_DOWNLOAD_TOTAL_MAX_BYTES = 256 * 1024 * 1024` in `tools/meshy_stage.py`. Keep `_THUMBNAIL_MAX_BYTES = 16 * 1024 * 1024`; apply the GLB ceiling consistently to download, recovery, and read-only verification. Then create `contract_lifecycle_v1.json` with `document_kind`, `schema_version`, and entries containing `asset_id`, `state`, `reason`, `effective_date`, `contract_path`, and `contract_sha256`. The three retired entry keys and their on-disk contract `asset_id` values are exactly `stalker_v1`, `hull_tendril_kit_v1`, and `biomatter_swarm_kit_v1`; do not substitute runtime archetype IDs (`stalker`, `hull_tendril`, `biomatter_swarm`) or rename historical files. States are `active`, `retired`, or `experimental`; omitted IDs default to active for backward compatibility. Consult lifecycle only at the start of new `plan`, `generate`, and `continue` work. Read-only validation of existing evidence must not reject retired IDs.

- [ ] **Step 7: Run all contract and lifecycle gates**

```bash
PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 PYTHONPATH=. /opt/homebrew/bin/python3.11 -m pytest -q tests/test_meshy_asset_contract.py tests/test_meshy_stage.py
/opt/homebrew/bin/python3.11 tools/meshy_asset_contract.py validate data/asset_generation/contracts/biomass_*_v1.json
```

Expected: 8 valid biomass contracts; existing non-retired contracts remain valid; retired files retain their original hashes and paths; the exact 94,588,220-byte GLB passes generation plus read-only verification under the committed 128/256 MiB limits, while an over-128 MiB GLB fails closed.

- [ ] **Step 8: Commit Task 2**

```bash
git add tools/meshy_asset_contract.py tools/meshy_stage.py tests/test_meshy_asset_contract.py tests/test_meshy_stage.py data/asset_generation/schemas/contract_lifecycle_v1.schema.json data/asset_generation/contract_lifecycle_v1.json data/asset_generation/contracts/biomass_*_v1.json
git commit -m "feat: add governed biomass contracts and lifecycle"
```

---

### Task 3: Runtime part catalog and immutable recipe model

**Files:**
- Create: `scripts/systems/biomass_part_catalog.gd`
- Create: `scripts/systems/biomass_recipe.gd`
- Create: `scripts/systems/biomass_recipe_library.gd`
- Create: `scripts/validation/biomass_catalog_smoke.gd`

**Interfaces:**
- Consumes: Task 1 JSON documents.
- Produces:
  - `BiomassPartCatalog.load_path(path: String) -> bool`
  - `BiomassPartCatalog.get_part(part_id: String) -> Dictionary`
  - `BiomassPartCatalog.find_by_role(role: String) -> PackedStringArray`
  - `BiomassPartCatalog.socket(part_id: String, socket_name: String) -> Dictionary`
  - class-scope factory `BiomassRecipe.from_dict(document, catalog)`, declared `static func from_dict(document: Dictionary, catalog: BiomassPartCatalog) -> BiomassRecipe`
  - `BiomassRecipe.is_valid() -> bool`
  - `BiomassRecipe.diagnostics() -> PackedStringArray`
  - `BiomassRecipe.to_dict() -> Dictionary`
  - `BiomassRecipeLibrary.load_path(path: String, parts: BiomassPartCatalog) -> bool`
  - `BiomassRecipeLibrary.get_recipe(recipe_id: String) -> BiomassRecipe`
  - `BiomassRecipeLibrary.recipe_ids() -> PackedStringArray`
  - `BiomassRecipeLibrary.pool_for(archetype_id: String) -> PackedStringArray`

- [ ] **Step 1: Write the RED runtime smoke**

```gdscript
extends SceneTree

const PartCatalogScript := preload("res://scripts/systems/biomass_part_catalog.gd")
const RecipeLibraryScript := preload("res://scripts/systems/biomass_recipe_library.gd")

func _initialize() -> void:
    var parts = PartCatalogScript.new()
    assert(parts.load_path("res://data/combat/biomass_part_catalog.json"))
    assert(parts.get_part("biomass_human_arm_v1").category == "biomass_limb")
    assert(parts.find_by_role("locomotor").size() == 3)
    var recipes = RecipeLibraryScript.new()
    assert(recipes.load_path("res://data/combat/biomass_recipe_catalog.json", parts))
    for recipe_id in recipes.recipe_ids():
        var recipe = recipes.get_recipe(recipe_id)
        assert(recipe.is_valid(), "invalid recipe %s: %s" % [recipe_id, recipe.diagnostics()])
        assert(recipe.to_dict() == recipes.get_recipe(recipe_id).to_dict())
    print("BIOMASS CATALOG SMOKE PASS parts=8 recipes=5 archetypes=6")
    quit(0)
```

- [ ] **Step 2: Run RED smoke**

`/opt/homebrew/bin/godot --headless --path . --script res://scripts/validation/biomass_catalog_smoke.gd`

Expected: parse/load failure because the scripts do not exist.

- [ ] **Step 3: Implement defensive loaders**

Use `FileAccess.get_file_as_string`, `JSON.parse_string`, exact top-level field checks, deep copies at API boundaries, sorted IDs, and fail-closed empty results. Do not retain caller-owned dictionaries.

```gdscript
extends RefCounted
class_name BiomassPartCatalog

var _document: Dictionary = {}
var _parts: Dictionary = {}
var _errors: PackedStringArray = PackedStringArray()

func get_part(part_id: String) -> Dictionary:
    var value: Variant = _parts.get(part_id, {})
    return (value as Dictionary).duplicate(true) if value is Dictionary else {}

func find_by_role(role: String) -> PackedStringArray:
    var result := PackedStringArray()
    var ids: Array = _parts.keys()
    ids.sort()
    for part_id in ids:
        var entry: Dictionary = _parts[part_id]
        if role in entry.get("assembly_roles", []):
            result.append(str(part_id))
    return result
```

- [ ] **Step 4: Implement graph validation and canonical serialization**

`BiomassRecipe.from_dict` is declared `static func from_dict(document: Dictionary, catalog: BiomassPartCatalog) -> BiomassRecipe` and validates in one forward pass. Because the static factory lives on the same script and must compile under `godot --headless --script`, instantiate the return object with `load("res://scripts/systems/biomass_recipe.gd").new()` rather than self-referencing the `class_name`; external callers use a preloaded script constant and call `RecipeScript.from_dict(...)`. Seed `seen_instances` with `core.instance_id`; before adding each attachment require its parent in `seen_instances`, then compute depth from its parent. Store only a defensive copy after zero diagnostics. `to_dict` returns a fresh deep copy. `canonical_json` uses `JSON.stringify(to_dict(), "", true)` only for runtime comparisons; host canonical bytes remain authoritative for hashes.

- [ ] **Step 5: Run GREEN smoke and headless parse gate**

```bash
/opt/homebrew/bin/godot --headless --path . --script res://scripts/validation/biomass_catalog_smoke.gd
/opt/homebrew/bin/godot --headless --path . --editor --quit-after 2
```

Expected marker: `BIOMASS CATALOG SMOKE PASS parts=8 recipes=5 archetypes=6`; no new parser errors.

- [ ] **Step 6: Commit Task 3**

```bash
git add scripts/systems/biomass_part_catalog.gd scripts/systems/biomass_recipe.gd scripts/systems/biomass_recipe_library.gd scripts/validation/biomass_catalog_smoke.gd
git commit -m "feat: load biomass parts and attachment recipes"
```

---

### Task 4: Deterministic procedural recipe generator

**Files:**
- Create: `scripts/systems/biomass_recipe_generator.gd`
- Create: `scripts/validation/biomass_recipe_generator_smoke.gd`

**Interfaces:**
- Consumes: `BiomassPartCatalog` and the static `BiomassRecipe.from_dict` factory from Task 3.
- Produces: class-scope `BiomassRecipeGenerator.generate(parts, seed_value, locomotion_hint, max_attachments)`, declared `static func generate(parts: Variant, seed_value: int, locomotion_hint: String, max_attachments: int = 6) -> Variant`. The returned Variant is always a non-null `BiomassRecipe` instance; cross-file `class_name` annotations are deliberately avoided because Godot headless `--script` cannot resolve them reliably.

- [ ] **Step 1: Write RED determinism and diversity smoke**

```gdscript
extends SceneTree

const PartsScript := preload("res://scripts/systems/biomass_part_catalog.gd")
const GeneratorScript := preload("res://scripts/systems/biomass_recipe_generator.gd")

func _initialize() -> void:
    var parts = PartsScript.new()
    assert(parts.load_path("res://data/combat/biomass_part_catalog.json"))
    var distinct: Dictionary = {}
    var hints := ["biped", "quadruped", "crawl", "drag", "slither"]
    for seed_value in range(1, 101):
        var hint: String = hints[(seed_value - 1) % hints.size()]
        var a = GeneratorScript.generate(parts, seed_value, hint, 6)
        var b = GeneratorScript.generate(parts, seed_value, hint, 6)
        assert(a.is_valid())
        assert(a.to_dict() == b.to_dict())
        assert(a.to_dict().attachments.size() <= 6)
        distinct[JSON.stringify(a.to_dict(), "", true)] = true
    assert(distinct.size() >= 20)
    print("BIOMASS GENERATOR PASS seeds=100 distinct=%d hints=5" % distinct.size())
    quit(0)
```

- [ ] **Step 2: Run RED smoke**

`/opt/homebrew/bin/godot --headless --path . --script res://scripts/validation/biomass_recipe_generator_smoke.gd`

Expected: preload failure.

- [ ] **Step 3: Implement stable plan selection**

```gdscript
extends RefCounted
class_name BiomassRecipeGenerator

const PLAN_COUNTS := {
    "biped": {"locomotor": 2, "detail": 1},
    "quadruped": {"locomotor": 4, "detail": 1},
    "crawl": {"locomotor": 3, "detail": 2},
    "drag": {"puller": 1, "detail": 3},
    "slither": {"slither": 2, "detail": 2},
}

static func _pick(sorted_ids: PackedStringArray, rng: RandomNumberGenerator) -> String:
    if sorted_ids.is_empty():
        return ""
    return sorted_ids[rng.randi_range(0, sorted_ids.size() - 1)]
```

Declare both class-scope APIs explicitly: `static func generate(parts: Variant, seed_value: int, locomotion_hint: String, max_attachments: int = 6) -> Variant` and the shown `static func _pick(...)`. Validate that `parts` is an Object whose script is the preloaded `biomass_part_catalog.gd`; otherwise return `RecipeScript.from_dict({}, parts)` so wrong-type input fails closed as a non-null invalid recipe. `generate` initializes a local `RandomNumberGenerator` with `seed_value if seed_value != 0 else 1`. Sort all catalog IDs and socket names before every random choice. Choose exactly one compatible part carrying role `core`; both canonical core candidates are eligible, and a skull core is valid without a torso. `PLAN_COUNTS` is normative and gives the exact non-core occurrence count for every listed role. A multi-role core does not satisfy any of those counts, and one distal detail attachment consumes one `detail` quota rather than adding another. Reserve compatible core sockets, satisfy locomotion-role quotas first, add the exact head/appendage detail quota, and prefer one compatible detail on a previously emitted limb's `distal_0` when available. Recipe socket references use short names such as `appendage_0` and `distal_0`, never catalog names prefixed with `socket_`. Every edge uses child socket `root_0` and connector `biomass_gunk_connector_v1`. Reusing a part ID for multiple instance IDs is allowed, but instance IDs and `(parent_instance_id, parent_socket)` occupancy remain unique. Emit parent-before-child records and validate the final dictionary through a preloaded recipe script constant's static `from_dict`.

Reject rather than clamp invalid capacity. `max_attachments` must be positive, must not exceed the loaded catalog's `limits.max_attachments` of 8, and must be large enough for the selected hint's exact quota (`biped=3`, `quadruped=5`, `crawl=5`, `drag=4`, `slither=4`). Unsupported hints, wrong-type/unloaded/failed catalogs, role-starved catalogs, exhausted compatible sockets, and any triangle/node/depth overflow return a non-null invalid `BiomassRecipe` with stable sorted nonempty diagnostics; never silently omit a required occurrence.

Expand the smoke before implementation. Use explicit `_need(...)` failure handling and `quit(1)`, not raw assertions. Across all five hints, assert exact non-core role counts, exact recipe fields, stable nonempty `recipe_id`, echoed hint, known part IDs, `child_socket == "root_0"`, canonical connector IDs, unique instance IDs, unique occupied parent sockets, parent-before-child order, exact quota-bounded edge counts, and catalog triangle/node/depth limits. Verify empty diagnostics and defensive `to_dict()` copies for valid recipes. Exercise seeds `0`, `1`, `42`, `777`, `-1`, and `2147483647`; prove seed 0 is byte-identical to seed 1, interleaved calls do not consume global RNG state, and serialized documents are byte-identical on repeat. Exercise limits `0, 1, 2, 3, 4, 5, 6, 8, 9` using the exact validity threshold per hint. Repeat unsupported-hint, wrong-type (`{}`, `null`, and an unrelated RefCounted), unloaded-catalog, failed-load, and role-starved failures twice and assert identical sorted deduplicated diagnostics and `{}` from `to_dict()`. Measure diversity from normalized structural signatures that omit recipe/instance identifiers; require at least 20 global signatures and at least 2 per hint across seeds 1 through 100 so seed-derived IDs cannot fake diversity.

- [ ] **Step 4: Run GREEN and repeatability gates**

Run the smoke twice and compare complete output:

```bash
/opt/homebrew/bin/godot --headless --path . --script res://scripts/validation/biomass_recipe_generator_smoke.gd > /tmp/biomass-generator-a.txt
/opt/homebrew/bin/godot --headless --path . --script res://scripts/validation/biomass_recipe_generator_smoke.gd > /tmp/biomass-generator-b.txt
cmp /tmp/biomass-generator-a.txt /tmp/biomass-generator-b.txt
```

- [ ] **Step 5: Commit Task 4**

```bash
git add scripts/systems/biomass_recipe_generator.gd scripts/validation/biomass_recipe_generator_smoke.gd
git commit -m "feat: generate deterministic biomass recipes"
```

---

### Task 5: Primitive part factory and socket graph assembler

**Files:**
- Create: `scripts/tools/biomass_placeholder_factory.gd`
- Create: `scripts/threats/biomass_threat_visual.gd`
- Create: `scripts/threats/biomass_assembler.gd`
- Create: `scripts/validation/biomass_assembly_smoke.gd`

**Interfaces:**
- Consumes: validated `BiomassRecipe` and `BiomassPartCatalog`.
- Produces:
  - class-scope `BiomassPlaceholderFactory.build(part_id, entry)`, declared `static func build(part_id: String, entry: Dictionary) -> Node3D`
  - `BiomassThreatVisual.part(instance_id: String) -> Node3D`
  - `BiomassThreatVisual.socket(instance_id: String, socket_name: String) -> Node3D`
  - `BiomassThreatVisual.attachment_mount(instance_id: String) -> Node3D`
  - `BiomassThreatVisual.recipe_document() -> Dictionary`
  - `BiomassThreatVisual.runtime_node_count() -> int`
  - `BiomassThreatVisual.triangle_budget() -> int`
  - `BiomassAssembler.build(recipe: BiomassRecipe, parts: BiomassPartCatalog) -> BiomassThreatVisual`
  - `BiomassAssembler.last_diagnostics() -> PackedStringArray`

- [ ] **Step 1: Write RED alignment and limit tests**

The smoke adds the built visual to `get_root()` before inspecting global transforms, then awaits both `process_frame` and `physics_frame` so the `CharacterBody3D` and its shapes are registered. It loads `tripod_hound_v1`, builds it, and asserts every instance exists; for each attachment it checks:

```gdscript
var parent_socket: Node3D = visual.socket(edge.parent_instance_id, edge.parent_socket)
var child_socket: Node3D = visual.socket(edge.instance_id, edge.child_socket)
assert(parent_socket.global_position.distance_to(child_socket.global_position) <= 0.001)
assert(parent_socket.global_basis.z.dot(child_socket.global_basis.z) >= 0.999)
assert(visual is CharacterBody3D)
assert(visual.collision_layer == 1)
assert(visual.get_children().any(func(child: Node) -> bool: return child is CollisionShape3D))
assert(visual.runtime_node_count() <= 160)
assert(visual.triangle_budget() <= 30000)
```

Also pass a recipe with 9 attachments and assert `build` returns `null` with `attachment count exceeds 8`.

- [ ] **Step 2: Run RED smoke**

`/opt/homebrew/bin/godot --headless --path . --script res://scripts/validation/biomass_assembly_smoke.gd`

Expected: preload failure.

- [ ] **Step 3: Implement deterministic primitive parts**

Declare the factory entry point as `static func build(part_id: String, entry: Dictionary) -> Node3D`; it owns no instance state and is called through the preloaded `BiomassPlaceholderFactoryScript`. The factory creates one `Node3D` root, one primitive `MeshInstance3D` from the catalog fallback shape/dimensions/color, and one `Node3D` for each socket using the repository-authoritative transforms in `biomass_part_catalog.json`. It sets metadata `biomass_part_id`, `biomass_category`, and `biomass_placeholder = true`. It creates no collision nodes.

- [ ] **Step 4: Implement wrapper-or-fallback instantiation**

```gdscript
func _instantiate_part(part_id: String, entry: Dictionary) -> Node3D:
    var path: String = str(entry.get("wrapper_scene_path", ""))
    if not path.is_empty() and ResourceLoader.exists(path, "PackedScene"):
        var packed: PackedScene = load(path)
        var instance: Node = packed.instantiate()
        if instance is Node3D:
            return instance
        instance.queue_free()
    return BiomassPlaceholderFactoryScript.build(part_id, entry)
```

Require every configured socket node before accepting the instance. A missing wrapper/socket fails that build and lets `ThreatManager` use its whole-threat primitive fallback; do not silently use a partly assembled creature.

- [ ] **Step 5: Implement attachment alignment and connectors**

Instantiate the core first. For each edge in order: instantiate child; find parent/child socket nodes; add a `Node3D` mount under the visual root; set mount global transform to parent socket global transform; parent child under mount; set child transform to `child_socket.transform.affine_inverse()`; then instantiate the connector part at the same mount with its root socket inverse. Record each part and mount by instance ID.

- [ ] **Step 6: Build Godot-owned target collision volumes**

`BiomassThreatVisual` extends `CharacterBody3D`, because the existing LOS owner is `PlayableGeneratedShip.update_threat_engaged_los()` (`scripts/procgen/playable_generated_ship.gd`), whose ray query uses `collide_with_bodies = true` and `collide_with_areas = false`. Create one `CollisionShape3D` child per catalog descriptor, transformed by the owning part’s assembled transform. Support only `box`, `capsule`, and `sphere`; unknown shapes fail the build. Set the visual root’s `collision_layer = 1` and `collision_mask = 1`. Movement remains model-authoritative: `ThreatManager` copies `ThreatAIState.world_position` into the body transform rather than calling physics-driven motion. Task 7 explicitly sets the production LOS query’s `collision_mask = 1`. Add no imported collision bodies or `Area3D`-only target substitute. The smoke adds the visual to the tree, awaits `process_frame` and `physics_frame`, proves a mask-1 ray hits the assembled body, then queues removal, awaits another process and physics frame, and only then asserts the body/collision RID is gone.

- [ ] **Step 7: Run GREEN smoke**

`/opt/homebrew/bin/godot --headless --path . --script res://scripts/validation/biomass_assembly_smoke.gd`

Expected marker: `BIOMASS ASSEMBLY PASS recipes=5 aligned=true collisions=true max_nodes<=160 max_triangles<=30000`.

- [ ] **Step 8: Commit Task 5**

```bash
git add scripts/tools/biomass_placeholder_factory.gd scripts/threats/biomass_threat_visual.gd scripts/threats/biomass_assembler.gd scripts/validation/biomass_assembly_smoke.gd
git commit -m "feat: assemble socketed biomass threat graphs"
```

---

### Task 6: Five socket-space gait profiles

**Files:**
- Create: `scripts/threats/biomass_gait_controller.gd`
- Modify: `scripts/threats/biomass_threat_visual.gd`
- Modify: `scripts/validation/biomass_assembly_smoke.gd`

**Interfaces:**
- Consumes: attachment mounts and part roles from Tasks 3 and 5.
- Produces:
  - `BiomassGaitController.configure(visual: BiomassThreatVisual, parts: BiomassPartCatalog, recipe: BiomassRecipe, seed_value: int) -> bool`
  - `BiomassGaitController.step(delta: float, velocity: Vector3, ai_state: String) -> void`
  - `BiomassThreatVisual.step_gait(delta: float, velocity: Vector3, ai_state: String) -> void`

- [ ] **Step 1: Extend RED smoke across five gaits**

For each curated recipe, capture every mount basis, call `step_gait(0.1, Vector3(1, 0, 0), "hunt")` ten times, and assert: all basis components are finite; at least one locomotor/slither mount changed; rotations remain within 35 degrees from rest; `idle`, `stun`, and `dead` converge to rest; same recipe/seed/delta sequence yields the same transforms.

- [ ] **Step 2: Run RED gait slice**

`/opt/homebrew/bin/godot --headless --path . --script res://scripts/validation/biomass_assembly_smoke.gd`

Expected: gait assertions fail.

- [ ] **Step 3: Implement bounded gait profiles**

Use fixed frequencies and phase sets:

```gdscript
const GAIT := {
    "biped": {"frequency": 1.8, "swing_deg": 24.0, "phases": [0.0, PI]},
    "quadruped": {"frequency": 2.2, "swing_deg": 20.0, "phases": [0.0, PI, PI, 0.0]},
    "crawl": {"frequency": 2.6, "swing_deg": 28.0, "phases": [0.0, 2.094, 4.189]},
    "drag": {"frequency": 1.4, "swing_deg": 18.0, "phases": [0.0]},
    "slither": {"frequency": 1.7, "swing_deg": 30.0, "phases": [0.0, 1.571, 3.142, 4.712]},
}
```

Copy rest transforms at configure time. Apply sinusoidal rotation around the mount-local X/Y axes, using sorted instance IDs and seed-derived phase offset. Scale amplitude by horizontal speed, clamp to 35 degrees, and return to rest with `lerp` when velocity is near zero or state is `idle`, `stun`, or `dead`. The core may receive at most `0.08 m` body bob and `6 degrees` yaw. Do not modify meshes, bones, recipes, AI state, or world positions.

- [ ] **Step 4: Run GREEN and no-drift checks**

Run the assembly smoke twice; both complete outputs and final sampled transforms must match.

- [ ] **Step 5: Commit Task 6**

```bash
git add scripts/threats/biomass_gait_controller.gd scripts/threats/biomass_threat_visual.gd scripts/validation/biomass_assembly_smoke.gd
git commit -m "feat: animate biomass threats with socket-space gaits"
```

---

### Task 7: ThreatManager integration and exact save/load reconstruction

**Files:**
- Modify: `data/combat/threat_visual_catalog.json`
- Modify: `scripts/systems/threat_ai_state.gd`
- Modify: `scripts/systems/threat_manager.gd`
- Modify: `scripts/procgen/playable_generated_ship.gd`
- Create: `scripts/validation/biomass_threat_manager_smoke.gd`
- Create: `scripts/validation/biomass_revisit_persistence_smoke.gd`
- Create: `data/combat/fixtures/biomass_invalid_recipe_catalog.json` — deliberately incompatible attachment used only to prove whole-threat fallback.

**Interfaces:**
- Consumes: assembler, catalog, library, generator, and gait APIs.
- Produces:
  - `ThreatAIState.biomass_recipe: Dictionary`
  - `ThreatAIState.biomass_seed: int`
  - `ThreatAIState.set_biomass_recipe(recipe: Dictionary, seed: int) -> void`
  - Existing `ThreatAIState.configure(config: Dictionary = {}) -> void` retains full combat/AI configuration semantics and additionally restores the two biomass fields.
  - `ThreatManager.configure_biomass_sources(part_catalog_path: String, recipe_catalog_path: String) -> bool` — may be called only before the manager enters the scene tree; production uses default `res://data/combat/biomass_part_catalog.json` and `res://data/combat/biomass_recipe_catalog.json`.
  - `ThreatManager._spawn_threat_visual(threat, index: int, anchor: Vector3) -> void`
  - `ThreatManager._update_placeholder(threat, player_position: Vector3, delta: float) -> void` — extends the existing private helper solely to forward gait delta.
  - Compatibility wrapper `ThreatManager._spawn_placeholder(threat, index: int, anchor: Vector3) -> void` delegates to `_spawn_threat_visual`.

- [ ] **Step 1: Write RED all-archetype and persistence smoke**

```gdscript
var manager = ThreatManagerScript.new()
get_root().add_child(manager)
await process_frame
manager.inject_validation_encounter(["biomatter_swarm", "stalker", "hull_tendril", "puppet_corpse", "mimic", "drone_swarm"], Vector3.ZERO)
await process_frame
await physics_frame
assert(manager.threats.size() == 6)
for threat in manager.threats:
    assert(not threat.biomass_recipe.is_empty())
    assert(threat.biomass_seed != 0)
    assert(manager.placeholder_nodes[threat.instance_id] is BiomassThreatVisual)
var before: Dictionary = manager.get_summary()
var restored = ThreatManagerScript.new()
get_root().add_child(restored)
await process_frame
assert(restored.apply_summary(before))
await process_frame
await physics_frame
assert(restored.get_summary()["threats"] == before["threats"])
for threat in restored.threats:
    assert(restored.placeholder_nodes[threat.instance_id].recipe_document() == threat.biomass_recipe)
```

After the valid six-archetype path, assert none of its visuals has `biomass_whole_threat_fallback = true`. Then create the invalid manager in this exact order:

```gdscript
var invalid_manager = ThreatManagerScript.new()
assert(invalid_manager.configure_biomass_sources(
    "res://data/combat/biomass_part_catalog.json",
    "res://data/combat/fixtures/biomass_invalid_recipe_catalog.json",
))
get_root().add_child(invalid_manager)
await process_frame
invalid_manager.inject_validation_encounter(["stalker"], Vector3.ZERO)
await process_frame
await physics_frame
```

The invalid fixture has the same closed top-level shape as the production recipe catalog but one curated edge is deliberately socket-incompatible. Assert assembly fails closed and exactly one whole-threat primitive visual is created with `biomass_whole_threat_fallback = true`. Assert a second `configure_biomass_sources()` call after `add_child` returns `false` and does not reload or mutate sources. Await `process_frame` and `physics_frame` after each spawn/rebuild and after each `queue_free()`-based removal before asserting scene-tree or collision disappearance. The valid-path and fallback-case counters remain separate.

Also construct a standalone `ThreatAIState` through the existing top-down-shaped `configure(config)` path, snapshot every pre-biomass summary field, call `set_biomass_recipe()`, round-trip its full summary through a fresh `ThreatAIState.configure(summary)`, and assert every old field is unchanged while the new recipe and seed survive exactly.

- [ ] **Step 2: Run RED smoke**

`/opt/homebrew/bin/godot --headless --path . --script res://scripts/validation/biomass_threat_manager_smoke.gd`

Expected: missing biomass state fields.

- [ ] **Step 3: Add save-stable visual fields to ThreatAIState**

```gdscript
var biomass_recipe: Dictionary = {}
var biomass_seed: int = 0
```

Add `set_biomass_recipe(recipe: Dictionary, seed: int)` to deep-copy the recipe and store the nonzero seed. Extend—not replace—the existing `configure(config)` implementation so it reads `biomass_recipe`/`biomass_seed` alongside the complete combat/AI configuration it already handles. `get_summary()` returns a deep copy and `apply_summary()` continues to delegate through full-config `configure()`. Add a regression that configures a normal threat, applies biomass data, round-trips the summary, and proves all pre-existing combat/AI fields remain equal. Do not change top-down combat behavior.

- [ ] **Step 4: Route every 3D archetype through biomass pools**

Each `threat_visual_catalog.json` entry retains `primitive`, `scale`, `albedo`, and adds exactly:

```json
{
  "visual_mode": "biomass",
  "generated_recipe_weight": 0.35,
  "allowed_locomotion_hints": ["biped", "crawl"]
}
```

`BiomassRecipeLibrary.pool_for(archetype_id)` is the sole curated-pool authority from Task 1; do not duplicate recipe IDs into the visual catalog. Use exact allowed-hint arrays: `biomatter_swarm=["crawl","drag"]`, `stalker=["biped","quadruped"]`, `hull_tendril=["slither","drag"]`, `puppet_corpse=["biped","crawl"]`, `mimic=["quadruped","crawl"]`, and `drone_swarm=["slither","crawl"]`; `generated_recipe_weight` is `0.35` for all six. The visual entry only opts the archetype into biomass, bounds generated selection, and restricts generated locomotion hints. In `_ready()`, load the live visual catalog once through `ThreatPlaceholderRenderer.load_catalog()` and retain the `archetypes` dictionary for routing. Unknown/missing/invalid visual settings or any catalog/recipe/assembly failure use the existing primitive fallback.

- [ ] **Step 5: Own assembler state inside ThreatManager**

`scripts/threats/biomass_assembler.gd` extends `RefCounted`, not `Node`; it owns no scene-tree children. Add constants `DEFAULT_BIOMASS_PART_CATALOG_PATH` and `DEFAULT_BIOMASS_RECIPE_CATALOG_PATH`, matching mutable path fields initialized to those defaults. Implement `configure_biomass_sources(part_catalog_path, recipe_catalog_path)` to reject empty/non-`res://` paths and return `false` whenever `is_inside_tree()` is true; on success it only stores the two paths. In `_ready()`, load `BiomassPartCatalog.load_path(stored_part_path)` first, then `BiomassRecipeLibrary.load_path(stored_recipe_path, parts)`, then load `ThreatPlaceholderRenderer.load_catalog()` and retain its `archetypes` dictionary, then create one non-tree assembler field. A load failure leaves biomass unavailable and routes later spawns to whole-threat fallback; never reload implicitly after `_ready()`. Derive a nonzero seed from `instance_id`, cell, and archetype. For curated selection use only `BiomassRecipeLibrary.pool_for(archetype_id)`; use the visual entry only for `visual_mode`, `generated_recipe_weight`, and `allowed_locomotion_hints`. If a restored threat already has a recipe, validate and use it unchanged. Otherwise use the seed to select curated versus generated and then store the entire recipe document before building. Keep `placeholder_nodes` as the compatibility dictionary used by existing tests and callers. Add regressions proving production defaults load, pre-tree fixture injection loads exactly once, post-tree injection fails without mutation, every visual archetype’s allowed hints are nonempty and known, `configure_for_layout()` can run twice, and `apply_summary()` after `_ready()` rebuilds visuals while `_clear_runtime_nodes()` preserves the same valid non-tree assembler/catalog objects.

- [ ] **Step 6: Feed movement into gait without changing path authority**

In `PlayableGeneratedShip.update_threat_engaged_los()`, retain `collide_with_areas = false` and `collide_with_bodies = true`, and explicitly set `query.collision_mask = 1` before `intersect_ray()`. In `_update_placeholder`, compute velocity from the node’s prior position and authoritative `threat.world_position`, set world position exactly as before, then call `step_gait(delta, velocity, threat.state)` when the node is a `BiomassThreatVisual`. Pass `delta` from `tick_threats`; do not create a second movement loop.

- [ ] **Step 7: Prove ship-cell revisit persistence, not only manager round-trip**

`biomass_revisit_persistence_smoke.gd` follows the proven `world_save_anywhere_smoke.gd` bootstrap: preload and instantiate `res://scenes/main.tscn`; add it to the root; wait until `PlayableGeneratedShip.loader.has_loaded_ship()`; repair the travel-critical systems; select one in-range marker ID; and call `travel_to_marker_id(marker_id)`. Capture the live `threat_manager.get_summary()`, each assembled visual’s canonical recipe, transforms, node count, and AABB. Call `travel_home()`—which invokes `_sync_current_ship_combat_summary()`—and assert `visited_ships[marker_id].combat_summary` contains the exact threat recipe/seed documents. Call `travel_to_marker_id(marker_id)` again, await process/physics frames, and compare the rebuilt manager/visual fingerprints within `0.001`.

Then call `save_world_for_validation()`, require `get_last_saved_snapshot()` to be non-null, mutate/free the active threat visuals, and call `load_world_for_validation()` through the same bootstrapped coordinator. Assert `get_current_ship().marker_id`, `get_current_ship().combat_summary`, the restored `ThreatManager` summary, and every visual fingerprint match the pre-save values. Use only these real world/travel seams; ship-level dictionary round-trip authority remains `ShipInstance.get_summary()`/`apply_summary()` and the real world-save path.

- [ ] **Step 8: Run GREEN and adjacent threat regressions**

```bash
/opt/homebrew/bin/godot --headless --path . --script res://scripts/validation/biomass_threat_manager_smoke.gd
/opt/homebrew/bin/godot --headless --path . --script res://scripts/validation/biomass_revisit_persistence_smoke.gd
/opt/homebrew/bin/godot --headless --path . --script res://scripts/validation/threat_path_follow_smoke.gd
/opt/homebrew/bin/godot --headless --path . --script res://scripts/validation/threat_los_perception_smoke.gd
/opt/homebrew/bin/godot --headless --path . --script res://scripts/validation/threat_kill_removal_smoke.gd
/opt/homebrew/bin/godot --headless --path . --script res://scripts/validation/topdown_threat_smoke.gd
/opt/homebrew/bin/godot --headless --path . --script res://scripts/validation/topdown_vertical_slice_smoke.gd
```

Expected markers:

- `BIOMASS THREAT MANAGER PASS archetypes=6 persisted=true exact_rebuild=true fallback_supported=true fallback_used_valid=0`
- `BIOMASS REVISIT PERSISTENCE PASS marker_revisit=true world_save_load=true`
- Both existing top-down smoke markers remain PASS, and the direct `ThreatAIState` regression proves all pre-existing summary fields survive biomass set/apply without behavior drift.

- [ ] **Step 9: Commit Task 7**

```bash
git add data/combat/threat_visual_catalog.json data/combat/fixtures/biomass_invalid_recipe_catalog.json scripts/systems/threat_ai_state.gd scripts/systems/threat_manager.gd scripts/procgen/playable_generated_ship.gd scripts/validation/biomass_threat_manager_smoke.gd scripts/validation/biomass_revisit_persistence_smoke.gd
git commit -m "feat: spawn persistent assembled biomass threats"
```

---

### Task 8: Placeholder-first composite runtime review

**Files:**
- Create: `scripts/validation/biomass_visual_review.gd`
- Create: `data/asset_generation/schemas/biomass_composite_review_v1.schema.json`
- Create: `tools/biomass_composite_review.py`
- Create: `tests/test_biomass_composite_review.py`
- Modify: `docs/game/06_validation_plan.md`
- Create: `docs/superpowers/proofs/procedural-biomass-pilot.md`

**Interfaces:**
- Consumes: complete placeholder runtime from Tasks 1-7.
- Produces: one canonical committed `biomass_composite_review_v1` evidence manifest plus exactly 30 committed PNGs under `artifacts/validation-previews/biomass-assembly-placeholder`: five locomotion recipes × seeds `42`/`777` × lighting cases `neutral`/`emergency`/`dark`. This stable path is outside the ignored `assets/_staging/meshy/**` tree; fail the task if `git check-ignore` reports the selected evidence root as ignored.
- Remains separate from `meshy_runtime_review_v1`, which binds one GLB and must not be overloaded with multi-part assembly evidence.

- [ ] **Step 1: Write RED host-runner tests**

Test a fake Godot executable and synthetic PNGs. Require an exact 30-case matrix, stable sorted case IDs, command/exit/stdout/stderr capture per case, project-relative output paths, PNG SHA-256/size/dimensions, catalog/recipe hashes, commit, Godot version, maximum nodes/triangles, deterministic recipe documents, and canonical JSON bytes. Reject missing/duplicate/extra/stale images, path escapes, symlinks, non-PNG content, a nonzero child exit, missing pass marker, unknown fields, and a report whose bound input hashes no longer match.

- [ ] **Step 2: Implement one-case Godot renderer and strict Python orchestrator**

`biomass_visual_review.gd` accepts `--recipe-id`, `--seed`, `--lighting`, and `--output`. It builds a neutral floor, fixed locked-isometric camera, the requested creature, and the named lighting rig; advances its gait for exactly 120 frames at `1/60 s`; records node/triangle budgets and AABB; saves only the requested PNG; and prints `BIOMASS COMPOSITE CASE PASS` with the canonical recipe hash.

`biomass_composite_review.py` owns the 30-case matrix, launches Godot once per case, verifies every result, and writes a deterministic JSON report. It supports `plan` (no subprocess), `run`, and `verify`; `verify` performs no rendering and re-hashes every input/output.

- [ ] **Step 3: Run the prerequisite smokes and 30-case placeholder review**

```bash
if git check-ignore --no-index artifacts/validation-previews/biomass-assembly-placeholder/review.json >/dev/null 2>&1; then echo "stable biomass evidence path is ignored" >&2; exit 1; fi
PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 PYTHONPATH=. /opt/homebrew/bin/python3.11 -m pytest -q tests/test_biomass_composite_review.py
/opt/homebrew/bin/godot --headless --path . --script res://scripts/validation/biomass_catalog_smoke.gd
/opt/homebrew/bin/godot --headless --path . --script res://scripts/validation/biomass_recipe_generator_smoke.gd
/opt/homebrew/bin/godot --headless --path . --script res://scripts/validation/biomass_assembly_smoke.gd
/opt/homebrew/bin/godot --headless --path . --script res://scripts/validation/biomass_threat_manager_smoke.gd
/opt/homebrew/bin/godot --headless --path . --script res://scripts/validation/biomass_revisit_persistence_smoke.gd
/opt/homebrew/bin/python3.11 tools/biomass_composite_review.py run --project-root . --godot /opt/homebrew/bin/godot --output-root artifacts/validation-previews/biomass-assembly-placeholder --report artifacts/validation-previews/biomass-assembly-placeholder/review.json
/opt/homebrew/bin/python3.11 tools/biomass_composite_review.py verify --project-root . --report artifacts/validation-previews/biomass-assembly-placeholder/review.json
```

Expected final marker: `BIOMASS COMPOSITE REVIEW PASS gaits=5 seeds=2 lighting=3 captures=30 placeholder=true`.

- [ ] **Step 4: Inspect all 30 PNGs and reject incoherent assemblies**

Reject the proof if any socket gap is visible, any part is inside-out, collisions are grossly displaced, silhouettes collapse at gameplay camera distance, the dark/emergency cases lose readable massing, or a gait causes self-intersection beyond the pre-authored connector collar. Fix the owning runtime task, rerun all commands, and record fresh hashes. A green schema report is not visual approval.

- [ ] **Step 5: Register only fresh validation truth**

After the runner and marker exist, add the exact commands/markers to `docs/game/06_validation_plan.md`. Start the proof document with commit, Godot version, catalog/recipe hashes, report hash, all 30 image hashes, measured maximum nodes/triangles, and a statement that all visuals are deterministic primitive fallbacks and no paid generation occurred.

- [ ] **Step 6: Commit Task 8**

```bash
git add scripts/validation/biomass_visual_review.gd data/asset_generation/schemas/biomass_composite_review_v1.schema.json tools/biomass_composite_review.py tests/test_biomass_composite_review.py docs/game/06_validation_plan.md docs/superpowers/proofs/procedural-biomass-pilot.md artifacts/validation-previews/biomass-assembly-placeholder
git commit -m "test: prove placeholder biomass composite runtime"
```

---

### Task 9: Godot/repository socket authority and export-boundary regression

**Files:**
- Create: `scripts/systems/biomass_wrapper_validator.gd`
- Create: `scripts/validation/biomass_wrapper_authority_smoke.gd`
- Modify: `tests/test_meshy_blender_tools.py`
- Do not weaken: `tools/meshy_blender_validate.py`

**Interfaces:**
- Consumes: one instantiated part wrapper/placeholder and its authoritative `biomass_part_catalog.json` entry.
- Produces:
  - `BiomassWrapperValidator.validate_part(instance: Node3D, entry: Dictionary) -> PackedStringArray`
  - `BiomassWrapperValidator.validate_assembly(visual: BiomassThreatVisual, recipe: BiomassRecipe, parts: BiomassPartCatalog) -> PackedStringArray`
- Enforces the ADR-0058 boundary: socket names/transforms are Godot/repository metadata; exported GLBs contain visual meshes/materials only.

- [ ] **Step 1: Write RED wrapper-authority smoke**

Build each of the eight placeholders and assert every catalog socket exists exactly once as `Node3D`, has the exact catalog-local transform within `0.001 m`/`0.1°`, carries no mesh/collision/physics child, and has no undeclared `socket_*` sibling. Then create invalid synthetic instances proving stable rejection of missing/extra/duplicate sockets, wrong node type, non-finite or scaled bases, transform drift, path duplication, and mismatched `biomass_part_id` metadata. Validate all five assembled recipes through `validate_assembly`.

- [ ] **Step 2: Pin the GLB visual-only boundary in host regression tests**

Add synthetic GLB fixtures containing meshless leaf helpers named `socket_root_0`, `socket_limb_0`, `marker_root`, and extras such as `{"biomass_socket": true}`. Assert the existing Blender validator rejects every fixture. Also assert a biomass visual-only GLB with no helper nodes remains valid. These are regression tests for the existing rule at `meshy_blender_validate.py:748-768`; do not turn exported helpers into an allowed special case.

- [ ] **Step 3: Implement strict Godot wrapper validation**

Normalize expected transforms from catalog `position_m`/`rotation_deg`; reject non-finite values and scales outside `1 ± 1e-4`; require exact socket-node inventory; compare transforms in the part root’s local space; and return stable sorted diagnostics. The assembler calls `validate_part` before accepting any real wrapper. Failure rejects the whole assembly and routes through the existing whole-threat primitive fail-safe; never mix an invalid wrapper with valid parts silently.

- [ ] **Step 4: Run focused and full regressions**

```bash
/opt/homebrew/bin/godot --headless --path . --script res://scripts/validation/biomass_wrapper_authority_smoke.gd
PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 PYTHONPATH=. /opt/homebrew/bin/python3.11 -m pytest -q tests/test_meshy_blender_tools.py
/opt/homebrew/bin/godot --headless --path . --script res://scripts/validation/biomass_assembly_smoke.gd
```

Expected marker: `BIOMASS WRAPPER AUTHORITY PASS parts=8 recipes=5 glb_helpers=forbidden`.

- [ ] **Step 5: Commit Task 9**

```bash
git add scripts/systems/biomass_wrapper_validator.gd scripts/validation/biomass_wrapper_authority_smoke.gd tests/test_meshy_blender_tools.py
git commit -m "feat: enforce Godot-owned biomass sockets"
```

---

### Task 10: Generic canonical Blender recipe for biomass parts

**Files:**
- Create: `tools/meshy_biomass_part_recipe.py`
- Create: `tests/test_meshy_biomass_part_recipe.py`

**Interfaces:**
- Consumes: selected governed task, immutable AI contract, exact matching entry/hash from `data/combat/biomass_part_catalog.json`, and—only for Blender modes—the canonical external master from `meshy_blender_master.py`.
- Canonical external paths are fixed as `/Volumes/Untitled/SynapticSeaAssets/meshy/source/<asset_id>/<asset_id>_master.blend` and `/Volumes/Untitled/SynapticSeaAssets/meshy/live-pilot/<asset_id>/<selected_task_id>/`; no other evidence root is accepted.
- Produces:
  - `RecipePaths`
  - `resolve_recipe_paths(project_root: Path, contract_path: Path, catalog_path: Path, expected_part_catalog_sha256: str, task_dir: Path, evidence_dir: Path) -> tuple[AssetContract, Mapping[str, Any], RecipePaths]`
  - `build_socket_guides(catalog_entry: Mapping[str, Any]) -> tuple[SocketGuide, ...]`
  - `run_blender_recipe(paths: RecipePaths, contract: AssetContract, catalog_entry: Mapping[str, Any], mode: str) -> dict[str, Any]`
  - One CLI with required `--project-root`, `--contract`, `--part-catalog`, `--expected-part-catalog-sha256`, `--task-dir`, `--evidence-dir`, and `--mode {archive-raw,rehydrate-raw,preview,publish-cleaned}` options.

- [ ] **Step 1: Write RED host safety and socket-spec tests**

Verify host import never loads `bpy`; paths stay under the exact selected task, exact asset-specific master leaf, and exact `/Volumes/Untitled/SynapticSeaAssets/meshy/live-pilot/<asset_id>/<selected_task_id>/` evidence leaf; runtime/import/catalog/wrapper paths are rejected as write targets; guide specs are derived from the exact catalog entry/hash; duplicate sockets and non-regular/symlink masters or evidence inputs fail closed. Add RED tests for two non-Blender recovery modes: `archive-raw` accepts only task-local `raw.glb` whose hash/size match bound `generation.json`, atomically writes `source.raw.glb` plus canonical `source-raw-manifest.json`, and treats a byte-identical preexisting archive as idempotent; `rehydrate-raw` accepts only that exact regular external archive/manifest, creates a missing task-local `raw.glb` atomically, read-back verifies the generation hash/size, and rejects a differing or symlink destination without overwrite. Neither recovery mode invokes Blender, Meshy, or a paid endpoint. Implement and test one exact normalization helper in `meshy_biomass_part_recipe.py`:

```python
def triangle_limits(contract: AssetContract) -> tuple[int, int]:
    document = contract.document
    target = document["generation"]["target_polycount"]
    budget = document["budget"]["triangles"]
    hard_max = budget if isinstance(budget, int) and not isinstance(budget, bool) else budget["max"]
    if not isinstance(target, int) or isinstance(target, bool) or not isinstance(hard_max, int) or isinstance(hard_max, bool):
        raise BiomassRecipeError("triangle target/hard maximum must be integers")
    if target < 1 or hard_max < target:
        raise BiomassRecipeError("triangle target must be within hard maximum")
    return target, hard_max
```

Biomass contracts use the object form, so their hard cap is specifically `budget.triangles.max`; integer support remains only for existing generic contracts. Add threshold tests: `triangles <= target` reports `target_met=true`; `target < triangles <= hard_max` remains reviewable but emits a structured low-poly-target warning and `target_met=false`; `triangles > hard_max` is a hard failure.

- [ ] **Step 2: Run RED tests**

`PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 PYTHONPATH=. /opt/homebrew/bin/python3.11 -m pytest -q tests/test_meshy_biomass_part_recipe.py`

- [ ] **Step 3: Implement host-safe path and command layer**

Use `/opt/homebrew/bin/blender`, `/Volumes/Untitled/SynapticSeaAssets/meshy/source/<asset_id>/<asset_id>_master.blend`, and exactly `/Volumes/Untitled/SynapticSeaAssets/meshy/live-pilot/<asset_id>/<selected_task_id>/`. Require selected review state, SUCCEEDED generation, matching raw hash, immutable contract snapshot, exact part-catalog hash, regular-file roots, and bounded process-group timeout. Implement all four modes behind the single required `--mode` option: `archive-raw` and `rehydrate-raw` perform only the bounded, atomic copy/verification behavior from Step 1; `preview` writes external `cleaned.preview.glb`; `publish-cleaned` writes only task-local `cleaned.glb` after explicit visual approval. Both Blender modes first require task-local `raw.glb` and the external `source.raw.glb` archive to match the same bound generation hash, so a clean-worker recovery never silently changes the selected source.

- [ ] **Step 4: Implement deterministic Blender authoring**

Inside Blender only: preserve hidden immutable `SOURCE_RAW`; duplicate selected geometry into `CANONICAL_PART`; normalize dimensions and pivot per contract; apply transforms; remove skins/animations; and perform bounded cleanup/decimation toward the contract’s low-poly target while preserving the approved locked-isometric silhouette and every catalog attachment-clearance region. Fail if the hard triangle maximum cannot be met without changing the design. Retain at most two material slots, create UV0, and create preview-only axis guides from the catalog entry in a separate `SOCKET_GUIDES` collection. Export only selected `CANONICAL_PART` mesh objects. Exclude `SOCKET_GUIDES`, empties, markers, axes, cameras, lights, and collision objects from the GLB. Socket guides are fit-review aids, never runtime authority or exported metadata.

- [ ] **Step 5: Render fixed evidence**

Render `front.png`, `side.png`, `three_quarter.png`, `socket_overlay.png`, and `contact_sheet.png`. `socket_overlay.png` renders the non-exported guide collection against the cleaned visual mesh. `preview` writes canonical `biomass-part-preview.json`; `publish-cleaned` writes canonical `biomass-part-recipe.json` to the same exact external evidence leaf. The publish manifest binds contract, part-catalog, generation, raw archive, input/published master, and cleaned-output hashes; dimensions; target/hard-max/measured triangles; materials; UV status; guide inventory/transforms; `socket_guides_exported: false`; `source_raw_preserved: true`; and `runtime_promoted: false`. Re-hash every named regular file after publication. Task 11 treats `biomass-part-recipe.json` as the sole master-to-cleaned provenance record; the generic Blender validation report remains independent and must keep `master_provenance: null`.

- [ ] **Step 6: Add a bounded Blender integration probe**

Create a synthetic cube task/master under pytest temp paths, invoke Blender once, parse the scratch GLB through `meshy_blender_validate`, and assert the visual-only export passes while containing no node whose name/extras identify a socket or marker. Separately verify the preview manifest binds the catalog guide inventory/hash. Skip only when `/opt/homebrew/bin/blender` is absent; do not skip on authoring/validation failures.

- [ ] **Step 7: Run GREEN tests**

```bash
PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 PYTHONPATH=. /opt/homebrew/bin/python3.11 -m pytest -q tests/test_meshy_biomass_part_recipe.py
PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 PYTHONPATH=. /opt/homebrew/bin/python3.11 -m pytest -q tests/test_meshy_blender_tools.py tests/test_meshy_candidate_review.py
```

- [ ] **Step 8: Commit Task 10**

```bash
git add tools/meshy_biomass_part_recipe.py tests/test_meshy_biomass_part_recipe.py
git commit -m "feat: author visual-only biomass part masters"
```

---

### Task 11: Review-only biomass part promotion packets

**Files:**
- Modify: `tools/meshy_promotion_packet.py`
- Modify: `tests/test_meshy_promotion_packet.py`

**Interfaces:**
- Consumes: `promotion_ready` task with hash-bound visual-only Blender validation, canonical external `source-raw-manifest.json` and `biomass-part-recipe.json`, per-part runtime review, and the exact repository-authoritative part-catalog entry/hash. `blender-validation.json.master_provenance` must be `null`; master provenance comes only from the separately verified recipe manifest.
- Produces: CLI subcommand `biomass-part --project-root PATH --contract PATH --task-dir PATH --evidence-dir PATH --part-catalog PATH --expected-part-catalog-sha256 HEX` and immutable leaves `biomass_part_catalog.patch.json`, `biomass_wrapper.proposal.json`, and `asset-provenance.json` under the task directory.

- [ ] **Step 1: Write RED proposal tests**

Assert a valid proposal names only:

```json
{
  "asset_id": "biomass_human_arm_v1",
  "import_target": "res://assets/imported/threats/biomass/biomass_human_arm_v1.glb",
  "wrapper_target": "res://scenes/wrappers/biomass/biomass_human_arm_v1.tscn",
  "catalog_target": "res://data/combat/biomass_part_catalog.json",
  "catalog_entry": {}
}
```

Assert it rejects non-biomass categories, wrong asset IDs/paths, a non-canonical evidence directory, changed catalog hashes, a proposal socket inventory/transform that differs from the catalog entry, any GLB socket/marker/helper node, collision objects in GLB, non-null `blender-validation.json.master_provenance`, unsigned/mismatched reports, secret fields, signed URLs, symlink leaves, and any attempted runtime write. Require cross-file equality for asset/task/contract/catalog/raw/master/cleaned hashes among `generation.json`, `source-raw-manifest.json`, `biomass-part-recipe.json`, `blender-validation.json`, `runtime-review.json`, and the actual regular files; only `biomass-part-recipe.json` may establish the master path/hash. Add CLI tests proving `prop --help` and `threat --help` retain their live arguments/behavior, `biomass-part --help` lists exactly the six required options, and missing/unknown biomass options exit through argparse without writes.

- [ ] **Step 2: Run RED tests**

`PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 PYTHONPATH=. /opt/homebrew/bin/python3.11 -m pytest -q tests/test_meshy_promotion_packet.py -k biomass`

- [ ] **Step 3: Implement `biomass-part` proposal**

Reuse `_verified_task`, provenance validation, canonical JSON, atomic governed writes, and security scanning. Add `biomass-part` beside the live `prop` and `threat` subparsers in `meshy_promotion_packet._build_parser()`; do not repurpose either existing mode. The parser requires the six options pinned in the interface and rejects unknown or missing arguments. Require `--evidence-dir` to equal `/Volumes/Untitled/SynapticSeaAssets/meshy/live-pilot/<asset_id>/<selected_task_id>` and verify the two Task 10 manifests and all cross-file hashes from Step 1 before producing a packet. Add a `main()` branch that calls the biomass proposal writer and prints `MESHY BIOMASS PART PROMOTION PROPOSAL PASS asset=<asset_id>`. Category must be in the five biomass categories. The catalog patch may change only `wrapper_scene_path` for the matching existing catalog entry; category, roles, sockets, collisions, fallback, budgets, and all other catalog fields remain unchanged. Contract/catalog/GLB/report hashes plus the recipe-manifest path/hash and its bound master path/hash live only in `biomass_wrapper.proposal.json`, `asset-provenance.json`, and the proof document—not in the closed part catalog. The generic Blender report must retain `master_provenance: null`; do not copy recipe provenance into it. The wrapper proposal imports the visual-only GLB and authors its plain `Node3D` socket nodes from the bound catalog entry; collision descriptors remain catalog data consumed by `BiomassAssembler`, so the wrapper proposal contains no `CollisionObject3D`. It never infers transforms from GLB nodes or Blender data.

- [ ] **Step 4: Verify no-promotion behavior**

Snapshot protected runtime paths before and after proposal creation and assert byte-identical state. CLI help must describe proposals as review-only and make no claim of promotion.

- [ ] **Step 5: Run full promotion regression**

`PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 PYTHONPATH=. /opt/homebrew/bin/python3.11 -m pytest -q tests/test_meshy_promotion_packet.py tests/test_meshy_governance.py tests/test_meshy_candidate_review.py`

- [ ] **Step 6: Commit Task 11**

```bash
git add tools/meshy_promotion_packet.py tests/test_meshy_promotion_packet.py
git commit -m "feat: propose governed biomass part promotion"
```

---

### Task 12: Pilot reference art and no-cost dry run

**Files:**
- Create: `assets/_staging/meshy/<each-pilot-id>/_references/three_quarter.png`
- Modify: `.gitignore` — add only `!assets/_staging/meshy/*/_references/*.png` after the broad Meshy PNG ignore.
- Modify: `docs/superpowers/proofs/procedural-biomass-pilot.md`
- No runtime/catalog/wrapper mutations.

**Interfaces:**
- Consumes: eight active contracts and working runtime proof.
- Produces: eight project-owned reference images and eight deterministic request plans.

- [ ] **Step 1: Generate one reference image per contract**

Use a neutral orthographic three-quarter view matched to the production locked-isometric reading angle, flat gray background, no floor contact shadow, no text, no gore photorealism, and no disconnected geometry. Depict cohesive stylized low-poly masses with broad planes and a silhouette that remains legible when reduced to gameplay size. Each image must show the asset alone, with geometry extending from the catalog root side toward local `+Z` and enough clean volume for repository-defined attachment zones.

- [ ] **Step 2: Validate image files and contract binding**

Require PNG, decoded dimensions at least 1024×1024, alpha/opaque consistency, byte size under 16 MiB, project-owned rights, and a SHA-256 recorded in the proof. Reject collage files. Add this exact `.gitignore` exception immediately after `assets/_staging/meshy/**/*.png`:

```gitignore
!assets/_staging/meshy/*/_references/*.png
```

After creating each file, run `git check-ignore assets/_staging/meshy/<asset_id>/_references/three_quarter.png`; the required exit code is `1` (not ignored). Then run `git add --dry-run` for all eight reference paths and require all eight to appear without `-f`. Do not unignore generated candidate thumbnails or runtime captures under task directories.

- [ ] **Step 3: Run eight read-only plans**

For each contract, derive `asset_id` from JSON and run:

```bash
/opt/homebrew/bin/python3.11 tools/meshy_stage.py plan --project-root . --contract data/asset_generation/contracts/biomass_human_arm_v1.json --reference-root assets/_staging/meshy/biomass_human_arm_v1/_references --reference three_quarter=three_quarter.png
```

Repeat with the other seven exact IDs. Run each plan twice and compare canonical request packet hashes. Confirm each plan costs at most 20 credits and the aggregate bound is 160.

- [ ] **Step 4: Re-run runtime and protected-path gates**

Run Tasks 1-11 focused tests and compare protected runtime snapshots before/after all plan commands. Expected: zero provider POSTs and zero protected mutations.

- [ ] **Step 5: Commit references and dry-run proof**

```bash
git add .gitignore assets/_staging/meshy/biomass_*_v1/_references/three_quarter.png docs/superpowers/proofs/procedural-biomass-pilot.md
/opt/homebrew/bin/python3.11 -c 'import subprocess; names=subprocess.check_output(["git","diff","--cached","--name-only","--","assets/_staging/meshy"], text=True).splitlines(); refs=[n for n in names if n.endswith("/_references/three_quarter.png")]; assert len(refs)==8, refs'
git commit -m "art: stage biomass pilot references"
```

---

### Task 13: Paid candidate generation and visual selection

**Files:**
- Generated only under: `assets/_staging/meshy/<asset_id>/<task_id>/`
- Modify: `docs/superpowers/proofs/procedural-biomass-pilot.md`

**Interfaces:**
- Consumes: approved Task 12 plans and Meshy credential supplied through the existing secret-safe environment path.
- Produces: exactly four staged candidates per part, journals, thumbnails, contact sheets, and one selected task per part.

- [ ] **Step 1: Verify committed artifact bounds, record live balance, and approve the aggregate credit bound**

Before any provider call, run:

```bash
PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 PYTHONPATH=. /opt/homebrew/bin/python3.11 -m pytest -q \
  tests/test_meshy_stage.py::test_historical_94588220_byte_glb_survives_generate_and_verify
/opt/homebrew/bin/python3.11 -c 'from tools import meshy_stage as s; assert s._GLB_MAX_BYTES == 128 * 1024 * 1024; assert s._DOWNLOAD_TOTAL_MAX_BYTES == 256 * 1024 * 1024; print("MESHY ARTIFACT LIMITS PASS glb_mib=128 aggregate_mib=256")'
```

Stop before reading credentials or calling Meshy if either command fails. Then read balance once through the existing Meshy client/tool, record only the integer balance, and verify it is at least 160. Do not log credentials or authorization headers.

- [ ] **Step 2: Generate one asset at a time**

Run one part at a time with the live CLI shape below, substituting each of the eight exact Task 2 IDs; wait for the command and its journal reconciliation to finish before starting the next:

```bash
/opt/homebrew/bin/python3.11 tools/meshy_stage.py generate \
  --project-root . \
  --contract data/asset_generation/contracts/<asset_id>.json \
  --approved-credits 20 \
  --reference-root assets/_staging/meshy/<asset_id>/_references \
  --reference three_quarter=three_quarter.png \
  --output-license paid-private \
  --deadline-seconds 7200
```

Do not parallelize paid POSTs. On ambiguous creation failure, stop and reconcile the journal; never retry a POST blindly.

- [ ] **Step 3: Verify each batch offline**

For each completed batch run the live offline verifier with the exact emitted journal path:

```bash
/opt/homebrew/bin/python3.11 tools/meshy_stage.py verify \
  --project-root . \
  --contract data/asset_generation/contracts/<asset_id>.json \
  --batch-journal assets/_staging/meshy/<asset_id>/_batches/<batch_id>.json
```

Require four unique task IDs, SUCCEEDED generation records, raw GLBs/thumbnails with bound hashes, no secrets/signed URLs, aggregate actual credits at or below 160, and no protected runtime mutation.

- [ ] **Step 4: Build and inspect eight contact sheets**

Review root/proximal volume, silhouette at the locked-isometric gameplay view, low-poly cohesion with the other seven parts, topology cleanup/decimation cost, dimension fit, catalog attachment-zone clearance, distal readability, and compatibility with at least two other pilot parts. Prefer candidates already near the low-poly target. Reject candidates with disconnected islands at attachment zones, collapsed proximal geometry, excessive thin shells, high-frequency surface noise, dense topology that cannot reach the hard cap without changing the silhouette, or cleanup that changes the design.

- [ ] **Step 5: Select exactly one candidate per part**

For each chosen task run:

```bash
/opt/homebrew/bin/python3.11 tools/meshy_candidate_review.py select \
  --project-root . \
  --task-dir assets/_staging/meshy/<asset_id>/<selected_task_id> \
  --reviewer christopherwilloughby \
  --check silhouette_readable \
  --check proportions_match_contract \
  --check functional_volume_present \
  --check movable_parts_separable \
  --check cleanup_bounded \
  --check camera_readability
```

All six checks are explicit and true by presence. Reject all non-selected candidates with `meshy_candidate_review.py reject --project-root . --task-dir <task-dir> --reviewer christopherwilloughby --reason <bounded-explicit-reason>` rather than leaving ambiguous pending decisions.

- [ ] **Step 6: Commit only bounded staging evidence**

Stage the eight asset staging directories and proof updates; `git add` intentionally captures only non-ignored journals, generation records, candidate-review JSON, licenses, and hash manifests. Raw GLBs and generated thumbnails/contact sheets stay local/ignored under the existing policy; do not force-add them. Require every Task 13 Step 3 `meshy_stage.py verify` result to have already passed its no-secrets/no-signed-URLs check, then inspect `git diff --cached --stat` before commit.

```bash
git add assets/_staging/meshy/biomass_*_v1 docs/superpowers/proofs/procedural-biomass-pilot.md
git diff --cached --stat
git commit -m "art: select biomass pilot candidates"
```

---

### Task 14: Canonical visual masters, guide review, and per-part runtime review

**Files:**
- External masters/evidence under `/Volumes/Untitled/SynapticSeaAssets/meshy/`
- Publish only selected task-local `cleaned.glb`, `blender-validation.json`, review transition files, and fixed per-part runtime evidence under `artifacts/validation-previews/meshy/<asset_id>/`.
- Modify: `docs/superpowers/proofs/procedural-biomass-pilot.md`

**Interfaces:**
- Consumes: eight selected tasks, Task 10 recipe, and the bound repository part-catalog hash.
- Produces: eight `promotion_ready` visual-only candidates with non-exported socket-fit guide evidence and per-part runtime evidence.

- [ ] **Step 1: Archive the selected raw source, then create the canonical external master**

For each selected task, set and reuse the following exact shell variables through Steps 1–3:

```bash
ASSET_ID=<asset_id>
TASK_ID=<selected_task_id>
CONTRACT="data/asset_generation/contracts/${ASSET_ID}.json"
TASK_DIR="assets/_staging/meshy/${ASSET_ID}/${TASK_ID}"
CATALOG="data/combat/biomass_part_catalog.json"
EVIDENCE_DIR="/Volumes/Untitled/SynapticSeaAssets/meshy/live-pilot/${ASSET_ID}/${TASK_ID}"
CATALOG_SHA256=$(shasum -a 256 "$CATALOG" | cut -d' ' -f1)
/opt/homebrew/bin/python3.11 tools/meshy_biomass_part_recipe.py \
  --project-root . --contract "$CONTRACT" --part-catalog "$CATALOG" \
  --expected-part-catalog-sha256 "$CATALOG_SHA256" --task-dir "$TASK_DIR" \
  --evidence-dir "$EVIDENCE_DIR" --mode archive-raw
/opt/homebrew/bin/python3.11 tools/meshy_blender_master.py \
  --project-root . --contract "$CONTRACT" --task-dir "$TASK_DIR" \
  --reviewer christopherwilloughby
```

Require `source.raw.glb` and `source-raw-manifest.json` to read back as regular, non-symlink files bound to the selected task’s generation hash before running the master command. Verify the canonical external master path `/Volumes/Untitled/SynapticSeaAssets/meshy/source/<asset_id>/<asset_id>_master.blend`, raw-source binding, and reviewer.

- [ ] **Step 2: Render recipe previews without publishing cleaned GLBs**

Run the complete preview command for each master:

```bash
/opt/homebrew/bin/python3.11 tools/meshy_biomass_part_recipe.py \
  --project-root . --contract "$CONTRACT" --part-catalog "$CATALOG" \
  --expected-part-catalog-sha256 "$CATALOG_SHA256" --task-dir "$TASK_DIR" \
  --evidence-dir "$EVIDENCE_DIR" --mode preview
```

Inspect front/side/three-quarter/guide overlay/contact sheet. Reject any planned catalog socket guide inside solid geometry, distal attachment region with no usable clearance, pivot mismatch, inconsistent low-poly density/style, high-frequency detail that disappears at the locked-isometric gameplay view, unreadable silhouette, or connector that cannot cover the seam. Guides remain outside the exported GLB.

- [ ] **Step 3: Publish selected cleaned GLBs only after visual approval**

For each approved part, rerun the same exact invocation with `--mode publish-cleaned`:

```bash
/opt/homebrew/bin/python3.11 tools/meshy_biomass_part_recipe.py \
  --project-root . --contract "$CONTRACT" --part-catalog "$CATALOG" \
  --expected-part-catalog-sha256 "$CATALOG_SHA256" --task-dir "$TASK_DIR" \
  --evidence-dir "$EVIDENCE_DIR" --mode publish-cleaned
```

Read the recorded `target_polycount` and `hard_max` from `biomass-part-recipe.json`; do not compare against the raw union-typed budget field. Verify task-local destination, raw/archive/master/cleaned hashes, dimensions, material/UV limits, immutable source preservation, and no runtime path mutation. Treat measured triangles at or below `target_polycount` as preferred; triangles above target but at or below `hard_max` require the structured low-poly-target warning and explicit visual-review acceptance; triangles above `hard_max` fail publication.

- [ ] **Step 4: Publish independent Blender validation**

Run the generic validator exactly:

```bash
/opt/homebrew/bin/python3.11 tools/meshy_blender_validate.py \
  --project-root . --contract "$CONTRACT" --task-dir "$TASK_DIR"
```

Require PASS, Blender reimport hash, `master_provenance: null`, and explicit confirmation that the cleaned GLB contains no socket/marker/helper nodes or collision objects. Separately verify that `$EVIDENCE_DIR/biomass-part-recipe.json` binds the exact catalog hash, raw archive, canonical master path/hash, and the same cleaned GLB hash reported by `blender-validation.json`; never add those fields to the closed generic validation schema.

- [ ] **Step 5: Run real locked-isometric runtime review**

For each selected task run the existing CLI exactly:

```bash
/opt/homebrew/bin/python3.11 tools/meshy_runtime_review.py \
  --project-root . \
  --contract data/asset_generation/contracts/<asset_id>.json \
  --task-dir assets/_staging/meshy/<asset_id>/<selected_task_id> \
  --preview-dir artifacts/validation-previews/meshy/<asset_id>
```

Do not supply an external preview path: `_fixed_preview_path()` permits only `artifacts/validation-previews/meshy/<asset_id>`. Require the fixed leaf to contain exactly the six final captures, twelve staged/reference auxiliary captures, and canonical `runtime-review.json`; camera distance at least 4.0 m; exact cleaned/contract/report hash binding; visibility across normal/emergency/dark lighting; and zero protected runtime mutation. External Blender masters remain inputs by bound path/hash but runtime evidence is committed in-repository so `verify_evidence_chain()` can derive it.

- [ ] **Step 6: Bind monotonic review evidence**

For each selected task run:

```bash
/opt/homebrew/bin/python3.11 tools/meshy_candidate_review.py bind \
  --project-root . \
  --task-dir assets/_staging/meshy/<asset_id>/<selected_task_id>
```

`bind` accepts no caller-supplied evidence path; it calls `meshy_runtime_review.verify_evidence_chain(project_root, task_dir)` and derives the fixed preview leaf. Verify final state is exactly `promotion_ready`; no manual editing of review JSON.

- [ ] **Step 7: Create eight review-only promotion packets**

For each part, compute `CATALOG_SHA256=$(shasum -a 256 data/combat/biomass_part_catalog.json | cut -d' ' -f1)` and run:

```bash
/opt/homebrew/bin/python3.11 tools/meshy_promotion_packet.py biomass-part \
  --project-root . \
  --contract data/asset_generation/contracts/<asset_id>.json \
  --task-dir assets/_staging/meshy/<asset_id>/<selected_task_id> \
  --evidence-dir /Volumes/Untitled/SynapticSeaAssets/meshy/live-pilot/<asset_id>/<selected_task_id> \
  --part-catalog data/combat/biomass_part_catalog.json \
  --expected-part-catalog-sha256 "$CATALOG_SHA256"
```

Verify proposal targets, bound catalog hash, exact proposed Godot socket nodes from the existing catalog entry, visual-only GLB policy, provenance, secret scan, and protected runtime snapshot equality.

- [ ] **Step 8: Commit governed review evidence**

Commit selected task-local JSON/hash evidence, all eight fixed `artifacts/validation-previews/meshy/<asset_id>/` leaves, and proof updates only. Raw/cleaned GLBs and task-local thumbnails remain deliberately ignored under `assets/_staging/meshy/**`; do not use `git add -f` or claim those binaries are committed. External raw archives, raw manifests, recipe manifests, preview renders, and canonical masters remain under the exact `live-pilot/<asset_id>/<task_id>` and `source/<asset_id>` roots and are referenced by path/hash from the committed promotion packet/proof. Task 15 must re-verify those external regular files before any promotion write.

```bash
git add assets/_staging/meshy/biomass_*_v1 artifacts/validation-previews/meshy/biomass_*_v1 docs/superpowers/proofs/procedural-biomass-pilot.md
git commit -m "art: validate visual-only biomass pilot masters"
```

---

### Task 15: Manual promotion, wrapper integration, and playable pilot acceptance

**Files:**
- Create: eight `assets/imported/threats/biomass/<asset_id>.glb` files plus eight tracked `<asset_id>.glb.import` descriptors generated by the recorded Godot version. Never commit `.godot/imported/**` cache files.
- Create: eight `scenes/wrappers/biomass/<asset_id>.tscn` files.
- Modify: `data/combat/biomass_part_catalog.json`
- Modify: `docs/superpowers/proofs/procedural-biomass-pilot.md`

**Interfaces:**
- Consumes: eight verified promotion packets and existing runtime catalog entries.
- Produces: eight live wrappers, catalog paths, and a real-art assembled-threat gameplay proof.

- [ ] **Step 1: Reconcile every proposal and rehydrate ignored binaries before writing runtime state**

For each asset compare cleaned GLB hash, Blender report with `master_provenance: null`, canonical `source-raw-manifest.json`, canonical `biomass-part-recipe.json`, per-part runtime report, review state, bound part-catalog hash/socket inventory, proposed wrapper/catalog entry, and target paths. First verify the exact external evidence leaf `/Volumes/Untitled/SynapticSeaAssets/meshy/live-pilot/<asset_id>/<selected_task_id>` and canonical master file are regular, non-symlink files with the hashes committed in `asset-provenance.json`. Then run the complete idempotent recovery sequence, even when the ignored task-local binaries are already present:

```bash
ASSET_ID=<asset_id>
TASK_ID=<selected_task_id>
CONTRACT="data/asset_generation/contracts/${ASSET_ID}.json"
TASK_DIR="assets/_staging/meshy/${ASSET_ID}/${TASK_ID}"
CATALOG="data/combat/biomass_part_catalog.json"
EVIDENCE_DIR="/Volumes/Untitled/SynapticSeaAssets/meshy/live-pilot/${ASSET_ID}/${TASK_ID}"
CATALOG_SHA256=$(shasum -a 256 "$CATALOG" | cut -d' ' -f1)
/opt/homebrew/bin/python3.11 tools/meshy_biomass_part_recipe.py \
  --project-root . --contract "$CONTRACT" --part-catalog "$CATALOG" \
  --expected-part-catalog-sha256 "$CATALOG_SHA256" --task-dir "$TASK_DIR" \
  --evidence-dir "$EVIDENCE_DIR" --mode rehydrate-raw
/opt/homebrew/bin/python3.11 tools/meshy_biomass_part_recipe.py \
  --project-root . --contract "$CONTRACT" --part-catalog "$CATALOG" \
  --expected-part-catalog-sha256 "$CATALOG_SHA256" --task-dir "$TASK_DIR" \
  --evidence-dir "$EVIDENCE_DIR" --mode publish-cleaned
```

`rehydrate-raw` performs no provider call and must restore only the exact generation-bound `raw.glb`; `publish-cleaned` must deterministically reproduce the cleaned hash in the committed proposal, recipe manifest, Blender report, and runtime report. A missing/mismatched external raw archive, raw manifest, recipe manifest, canonical master, or output hash is a hard block—not permission to call Meshy, select another candidate, or continue partially. Assert the GLB has no socket/marker/helper nodes and abort the entire asset’s promotion on any mismatch.

- [ ] **Step 2: Copy imported assets atomically**

Copy each verified cleaned GLB to its exact imported target through a temporary sibling and atomic rename. Re-hash destination and compare to proposal. Run `/opt/homebrew/bin/godot --headless --editor --path . --quit` twice with the exact Godot version recorded in the proof; require each `<asset_id>.glb.import` descriptor to exist and remain byte-identical across the second import. Track those descriptors because the repository already versions `.glb.import`; do not stage `.godot/imported/**`. Do not copy staging metadata, review files, previews, or credentials.

- [ ] **Step 3: Create thin Godot wrappers**

Each wrapper root is `Node3D`, instances exactly one visual-only imported GLB, and authors one plain `Node3D` socket per repository catalog entry with the exact catalog name/local transform. It adds no animation authority and contains only Godot-owned runtime metadata. Run `BiomassWrapperValidator.validate_part()` against every wrapper before saving. Collision remains created by `BiomassAssembler` from catalog descriptors; wrappers contain no `CollisionObject3D`.

- [ ] **Step 4: Apply catalog paths only**

Set each existing part entry’s `wrapper_scene_path` to `res://scenes/wrappers/biomass/<asset_id>.tscn`. Do not change roles, sockets, collision descriptors, fallbacks, or budgets. Re-run host and Godot catalog validation.

- [ ] **Step 5: Run all biomass and adjacent threat gates**

```bash
PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 PYTHONPATH=. /opt/homebrew/bin/python3.11 -m pytest -q tests/test_biomass_catalog_validate.py tests/test_biomass_composite_review.py tests/test_meshy_asset_contract.py tests/test_meshy_stage.py tests/test_meshy_blender_tools.py tests/test_meshy_biomass_part_recipe.py tests/test_meshy_promotion_packet.py
/opt/homebrew/bin/godot --headless --path . --script res://scripts/validation/biomass_catalog_smoke.gd
/opt/homebrew/bin/godot --headless --path . --script res://scripts/validation/biomass_recipe_generator_smoke.gd
/opt/homebrew/bin/godot --headless --path . --script res://scripts/validation/biomass_wrapper_authority_smoke.gd
/opt/homebrew/bin/godot --headless --path . --script res://scripts/validation/biomass_assembly_smoke.gd
/opt/homebrew/bin/godot --headless --path . --script res://scripts/validation/biomass_threat_manager_smoke.gd
/opt/homebrew/bin/godot --headless --path . --script res://scripts/validation/biomass_revisit_persistence_smoke.gd
/opt/homebrew/bin/godot --headless --path . --script res://scripts/validation/threat_path_follow_smoke.gd
/opt/homebrew/bin/godot --headless --path . --script res://scripts/validation/threat_los_perception_smoke.gd
/opt/homebrew/bin/godot --headless --path . --script res://scripts/validation/threat_kill_removal_smoke.gd
/opt/homebrew/bin/godot --headless --path . --script res://scripts/validation/topdown_threat_smoke.gd
/opt/homebrew/bin/godot --headless --path . --script res://scripts/validation/topdown_vertical_slice_smoke.gd
/opt/homebrew/bin/python3.11 tools/biomass_composite_review.py run --project-root . --godot /opt/homebrew/bin/godot --output-root artifacts/validation-previews/biomass-assembly-real --report artifacts/validation-previews/biomass-assembly-real/review.json
/opt/homebrew/bin/python3.11 tools/biomass_composite_review.py verify --project-root . --report artifacts/validation-previews/biomass-assembly-real/review.json
```

Expected: all new markers pass, all eight catalog entries report non-empty wrappers, no primitive fallback is used, and adjacent threat behavior remains unchanged.

- [ ] **Step 6: Run the production playable scene and inspect at gameplay camera distance**

Launch `scenes/main.tscn`, inject all six archetypes, capture normal/emergency/dark lighting, move threats through each gait, kill/remove one, save/reload, and confirm the exact same assembly graph returns. Reject promotion for visible gaps, inverted parts, floor penetration, unreadable silhouettes, unstable gait, misplaced hit volumes, or save/load drift.

- [ ] **Step 7: Complete fresh evidence and status updates**

Record commit, tool versions, all eight imported hashes, wrapper paths, catalog/recipe hashes, test outputs, both 30-case composite report hashes/captures, performance/node/triangle maxima, credit consumption, and known bounded v1 limitations. Update ADR-0059 status from Proposed to Accepted and the feature status to Implemented only after every gate passes.

- [ ] **Step 8: Commit Task 15**

```bash
git add assets/imported/threats/biomass scenes/wrappers/biomass data/combat/biomass_part_catalog.json docs/game/adr/0059-procedural-biomass-assembly.md docs/game/features/procedural_biomass_assembly.md docs/superpowers/proofs/procedural-biomass-pilot.md artifacts/validation-previews/biomass-assembly-real
git commit -m "feat: promote procedural biomass threat pilot"
```

---

## Requirement Coverage

| Requirement | Implementing tasks | Verification |
|---|---|---|
| REQ-BIO-001 Body-part catalog and visual-generation contract | 1, 2 | Host schema tests, existing-shape contract validation, and lifecycle gates |
| REQ-BIO-002 Repository-owned socket authoring | 1, 5, 9, 10, 14, 15 | Wrapper-authority smoke, non-exported Blender guides, GLB helper rejection |
| REQ-BIO-003 BiomassRecipe resource | 1, 3 | Host graph validator and `BIOMASS CATALOG SMOKE PASS` |
| REQ-BIO-004 Runtime assembly | 5, 7 | Alignment/body-collision/LOS smoke and six-archetype manager smoke |
| REQ-BIO-005 Random recipe generation | 4 | 100 deterministic seeds, at least 20 distinct valid graphs |
| REQ-BIO-006 Five locomotion gait profiles | 6, 8 | Bounded deterministic biped/quadruped/crawl/drag/slither proof |
| REQ-BIO-007 Exact assembly save/load persistence | 7, 15 | Manager summary equality plus real `PlayableGeneratedShip` cell-revisit/round-trip equality |
| REQ-BIO-008 Pilot part set | 2, 12, 13, 14, 15 | 8 governed contracts through visual-only GLBs and Godot wrappers |
| REQ-BIO-009 Runtime review of assembled threats | 8, 14, 15 | Separate 30-case placeholder composite report, per-part governed review, final 30-case real-art report |
| REQ-BIO-010 No auto-promotion | 1, 9, 10, 11, 12, 13, 14 | Protected-path snapshots, immutable lifecycle evidence, and review-only proposal boundary |

The coverage review found no unassigned REQ-BIO requirement after Task 1 restores the missing REQ-BIO-006 and REQ-BIO-007 definitions.

## Final Acceptance Gate

Run from a clean isolated worktree at the final commit:

```bash
git status --short
PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 PYTHONPATH=. /opt/homebrew/bin/python3.11 -m pytest -q tests/test_biomass_catalog_validate.py tests/test_biomass_composite_review.py tests/test_meshy_asset_contract.py tests/test_meshy_stage.py tests/test_meshy_blender_tools.py tests/test_meshy_biomass_part_recipe.py tests/test_meshy_promotion_packet.py tests/test_meshy_candidate_review.py tests/test_meshy_runtime_review.py
/opt/homebrew/bin/godot --headless --path . --editor --quit-after 2
/opt/homebrew/bin/godot --headless --path . --script res://scripts/validation/biomass_catalog_smoke.gd
/opt/homebrew/bin/godot --headless --path . --script res://scripts/validation/biomass_recipe_generator_smoke.gd
/opt/homebrew/bin/godot --headless --path . --script res://scripts/validation/biomass_wrapper_authority_smoke.gd
/opt/homebrew/bin/godot --headless --path . --script res://scripts/validation/biomass_assembly_smoke.gd
/opt/homebrew/bin/godot --headless --path . --script res://scripts/validation/biomass_threat_manager_smoke.gd
/opt/homebrew/bin/godot --headless --path . --script res://scripts/validation/biomass_revisit_persistence_smoke.gd
/opt/homebrew/bin/godot --headless --path . --script res://scripts/validation/threat_path_follow_smoke.gd
/opt/homebrew/bin/godot --headless --path . --script res://scripts/validation/threat_los_perception_smoke.gd
/opt/homebrew/bin/godot --headless --path . --script res://scripts/validation/threat_kill_removal_smoke.gd
/opt/homebrew/bin/godot --headless --path . --script res://scripts/validation/topdown_threat_smoke.gd
/opt/homebrew/bin/godot --headless --path . --script res://scripts/validation/topdown_vertical_slice_smoke.gd
/opt/homebrew/bin/python3.11 tools/biomass_composite_review.py verify --project-root . --report artifacts/validation-previews/biomass-assembly-placeholder/review.json
/opt/homebrew/bin/python3.11 tools/biomass_composite_review.py verify --project-root . --report artifacts/validation-previews/biomass-assembly-real/review.json
git diff --check
```

Acceptance requires:

- Task 0’s ADR-0060 is accepted, explicitly superseding ADR-0048’s conflicting production clauses;
- clean git status;
- 8 valid active biomass contracts and byte-identical in-place historical singular-threat contracts/evidence governed by the lifecycle manifest;
- 8 catalog parts, 5 curated recipes, 6 archetype pools;
- deterministic 100-seed generation with at least 20 distinct valid graphs;
- exact repository-owned socket alignment, GLBs free of helper nodes, locked-isometric low-poly silhouette/readability, target-versus-hard-cap triangle accounting, depth/attachment/node limits, mask-1 body collision/LOS, and five bounded gait profiles;
- all six 3D threat archetypes use assembled visuals with primitive fallback unused in the promoted pilot;
- exact recipe graph/seed persistence through both manager summary and real ship cell revisit/save-load lifecycle;
- all 8 live wrappers hash-bound to governed visual-only GLBs and exact catalog-authored Godot socket nodes;
- no secrets/signed URLs and no generation-time protected runtime writes;
- both 30-case placeholder and real-art composite reports verify, with human visual approval at gameplay camera distance under normal/emergency/dark lighting;
- proof document contains fresh commands, markers, hashes, credit use, captures, and limitations.

## Execution Handoff

This plan has 16 ordered tasks (`Task 0` through `Task 15`). Use subagent-driven execution with TDD and independent review gates. Complete and verify Task 0 before dispatching Task 1. Execute Tasks 1-11 before any paid provider call; Task 12 is a no-cost dry run; Task 13 is the first paid stage and must run serially with journal reconciliation. Do not start the next task from worker self-report: inspect the diff and run that task’s listed verification commands from the isolated worktree first.
