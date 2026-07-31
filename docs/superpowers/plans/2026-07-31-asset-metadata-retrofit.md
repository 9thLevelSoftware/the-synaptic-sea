# Asset Metadata Retrofit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a deterministic asset-metadata pipeline, retrofit all 26 imported prop GLBs with portable sidecars, repair validation for existing structural variants, and bind imported component/objective GLBs into the playable ship without changing gameplay ownership.

**Architecture:** Each imported prop GLB owns one canonical adjacent `.sidecar.json`; the repository generates one committed runtime lookup index from those sidecars. The runtime catalog resolves that derived index, and the visual binder instances GLBs as visual-only children below existing component markers and objective-affordance roots. Structural wrappers remain the authority for sockets, collision, and integrity-state switching; their validator is repaired to recognize the variant nodes already used by the runtime.

**Tech Stack:** Godot 4.7.1 headless import/test workflow; typed GDScript; Python 3 standard library (`json`, `hashlib`, `struct`, `pathlib`, `unittest`); glTF 2.0 GLB JSON/BIN parsing; JSON Schema document validation.

## Global Constraints

- Do not re-export, rewrite, embed metadata into, or otherwise mutate any `.glb` file.
- Prop sidecars are the only hand-authored visual metadata authority. `data/props/visual_bindings.generated.json` is generated from sidecars and must never be edited directly.
- Sidecars reserve an `extensions` object for forward-compatible studio data. The generator/refresh path must preserve it semantically and must never delete or rewrite an extension key.
- Every GLB under `assets/imported/props/` has exactly one same-basename `.sidecar.json`: 11 components, 11 dressing props, and 4 objectives.
- Component gameplay behavior remains in `data/components/component_catalog.json`; objective gameplay placement remains in `data/procgen/**/gameplay_slice.json`; live placement remains in `ComponentPlacementState` and `GeneratedShipLoader`.
- Prop sidecars contain no mass, condition, power, system link, role weighting, room, cell, approach cell, objective sequence, objective type, objective steps, or loot-table fields.
- Directly instanced prop GLBs are visual-only. Existing component markers and objective interactables continue to own collision, interaction, lifecycle, and gameplay state.
- Structural sockets, collision, navigation policy, and integrity state remain owned by the current structural wrapper/input/manifest/contract pipeline. Damaged and breached structural GLBs remain visual variants with no duplicated socket empties.
- Every Godot validation command begins with `/opt/homebrew/bin/godot --headless --editor --path . --quit`; Godot-generated `.godot` and `*.import` state is restored/cleaned before committing.
- Godot output containing unexpected `ERROR:` or `WARNING:` blocks task completion. A recognized pre-existing warning must be documented in the feature spec with an owner and a removal condition before it is tolerated.
- Use stable key ordering, compact JSON with a trailing newline, six decimal places for measured bounds, and SHA-256 for GLB hashes. Never emit timestamps.
- Work only on the task branch/worktree. Keep commits focused; do not include generated Godot cache files.

---

## File Structure

```text
assets/imported/props/
  components/<asset_id>.glb
  components/<asset_id>.sidecar.json
  dressing/<asset_id>.glb
  dressing/<asset_id>.sidecar.json
  objectives/<asset_id>.glb
  objectives/<asset_id>.sidecar.json

data/placement/schemas/prop_visual_binding_v1.schema.json
data/props/visual_bindings.generated.json

tools/prop_visual_metadata.py
tools/generate_prop_sidecars.py
tools/validate_prop_visual_bindings.py
tools/validate_structural_variant_bindings.py

tests/test_prop_visual_metadata.py
tests/test_validate_prop_visual_bindings.py

scripts/systems/prop_visual_binding_catalog.gd
scripts/procgen/runtime_prop_visual_binder.gd
scripts/validation/prop_visual_binding_smoke.gd
scripts/validation/objective_visual_binding_smoke.gd
scripts/validation/structural_variant_wrapper_smoke.gd

scripts/placement/validate_wrapper_scenes.gd
scripts/procgen/generated_ship_loader.gd
scripts/procgen/playable_generated_ship.gd
scripts/interaction/interactable.gd

docs/game/features/asset_metadata_pipeline.md
docs/game/adr/0052-asset-metadata-and-visual-binding-architecture.md
docs/game/05_requirements.md
docs/game/06_validation_plan.md
AGENTS.md
```

The Python metadata module owns format parsing, hash/bounds measurement, canonical serialization, and pure validation. The generator owns only missing-sidecar creation and derived-index regeneration. The runtime catalog owns lookup; the runtime binder owns visual scene instantiation; `PlayableGeneratedShip` retains component/objective lifecycle ownership.

### Task 1: Establish the governed feature contract and reproducible Godot baseline

**Files:**
- Create: `docs/game/features/asset_metadata_pipeline.md`
- Create: `docs/game/adr/0052-asset-metadata-and-visual-binding-architecture.md`
- Modify: `docs/game/adr/README.md`
- Modify: `docs/game/05_requirements.md`
- Modify: `docs/game/06_validation_plan.md`
- Modify: `AGENTS.md`

**Interfaces:**
- Produces requirement IDs `REQ-AVB-001` through `REQ-AVB-009` for all implementation cards.
- Produces ADR-0052, which sets sidecar authority, derived-index policy, direct-GLB visual-only binding, structural ownership, and fallback rules.
- Defines `GODOT_BIN=/opt/homebrew/bin/godot` as the validation command for this repository revision.

- [ ] **Step 1: Write the failing baseline record and classify the known smoke warning**

Run:

```bash
GODOT_BIN=/opt/homebrew/bin/godot
"$GODOT_BIN" --headless --editor --path . --quit
"$GODOT_BIN" --headless --path . --script res://scripts/placement/validate_wrapper_scenes.gd -- scenes/wrappers/structural/ship_structural_v0
```

Expected before Task 2: exit `1` and eight errors containing `missing VisualInstance node for generated.visual_scene_path` for the variant-aware wrapper scenes.

Also run:

```bash
"$GODOT_BIN" --headless --path . --script res://scripts/validation/component_markers_smoke.gd
```

Current verified baseline: the smoke prints `COMPONENT MARKERS PASS wired=true count=true rebuild=true` and then ``WARNING: 2 ObjectDB instances were leaked at exit (run with `--verbose` for details).``. Record that exact warning in the feature spec as an external baseline, name `ship-core` as owner, require its count to remain exactly two while this feature is implemented, and link its removal to blocked Kanban card `t_b9b4e4f9` (title: Investigate ObjectDB leak in component marker smoke). Any other warning or a count other than two fails this feature's validation.

- [ ] **Step 2: Write the feature spec**

Write `docs/game/features/asset_metadata_pipeline.md` with these acceptance criteria:

```markdown
- Every one of the 26 imported prop GLBs has exactly one valid same-basename `.sidecar.json`.
- Sidecar data resolves an imported visual for every component ID in `component_catalog.json` and every supported objective placement ID with a supplied objective GLB.
- Missing or invalid bindings keep the existing primitive/readability visual path alive and set `visual_source = "fallback"`.
- Component marker placement, mount, dismount, save/load, and system linkage retain their current owners and behavior.
- Objective interaction volumes and objective progression retain their current owners and behavior.
- Structural variant wrappers validate and switch intact/damaged/breached visuals without socket or collision drift.
```

List non-goals explicitly: GLB re-export, procedural structural assembly, collision generation for props, new objective gameplay, and runtime dressing placement.

- [ ] **Step 3: Write ADR-0052**

Record these decisions:

```markdown
1. A prop GLB and its same-basename sidecar form one portable visual asset record.
2. The generated runtime index is derived and is overwritten only by the generator.
3. Runtime prop visuals are direct GLB children with `collision_policy = "none_visual_only"`.
4. Structural wrapper contracts remain connector/collision/integrity authorities.
5. Objective resolution uses gameplay `placement_id`, never objective `type`.
6. Missing binding behavior is an intentional visual fallback, never a substituted unrelated GLB.
7. GLB-derived refreshes preserve sidecar `extensions` and all hand-authored binding/placement/provenance fields.
```

- [ ] **Step 4: Add requirement rows and validation commands**

Add `REQ-AVB-001` through `REQ-AVB-009` covering sidecar completeness, sidecar schema/path/hash/bounds validity, no gameplay-field duplication, component binding, objective placement-ID binding, fallback behavior, structural variant validation, deterministic generated-index freshness, and extension survival during explicit derived-field refresh.

Add these commands to `docs/game/06_validation_plan.md`:

```bash
GODOT_BIN=/opt/homebrew/bin/godot
"$GODOT_BIN" --headless --editor --path "$ROOT" --quit
python3 tools/validate_prop_visual_bindings.py --project-root "$ROOT" --check-index
python3 tools/validate_structural_variant_bindings.py --project-root "$ROOT"
"$GODOT_BIN" --headless --path "$ROOT" --script res://scripts/placement/validate_wrapper_scenes.gd -- scenes/wrappers/structural/ship_structural_v0
"$GODOT_BIN" --headless --path "$ROOT" --script res://scripts/validation/prop_visual_binding_smoke.gd
"$GODOT_BIN" --headless --path "$ROOT" --script res://scripts/validation/objective_visual_binding_smoke.gd
```

Update `AGENTS.md` from the unavailable Godot 4.6.2 path to the verified local Godot 4.7.1 path and retain the existing rule that unexpected diagnostics block completion.

- [ ] **Step 5: Verify documentation and commit**

Run:

```bash
git diff --check
python3 - <<'PY'
from pathlib import Path
paths = [
    Path('docs/game/features/asset_metadata_pipeline.md'),
    Path('docs/game/adr/0052-asset-metadata-and-visual-binding-architecture.md'),
]
for path in paths:
    text = path.read_text()
    assert ('TO' + 'DO') not in text and ('TB' + 'D') not in text
print('ASSET METADATA GOVERNANCE DOCS PASS')
PY
git add AGENTS.md \
  docs/game/features/asset_metadata_pipeline.md \
  docs/game/adr/0052-asset-metadata-and-visual-binding-architecture.md \
  docs/game/adr/README.md \
  docs/game/05_requirements.md \
  docs/game/06_validation_plan.md
git commit -m "docs: define asset metadata retrofit architecture"
```

Expected: `ASSET METADATA GOVERNANCE DOCS PASS` and one focused documentation commit.

### Task 2: Repair variant-aware structural wrapper validation before adding new gates

**Files:**
- Modify: `scripts/placement/validate_wrapper_scenes.gd:382-410`
- Create: `scripts/validation/structural_variant_wrapper_smoke.gd`

**Interfaces:**
- Produces validator support for exactly two legal visual forms:
  - legacy: `Visual/VisualInstance`
  - variant-aware: `Visual/VisualInstance_Intact`, `Visual/VisualInstance_Damaged`, `Visual/VisualInstance_Breached`
- The intact child must instance `manifest.generated.visual_scene_path`; damaged/breached children must be `PackedScene` resources under `Visual`.

- [ ] **Step 1: Capture the red case**

Run the Task 1 baseline command and save its eight `missing VisualInstance` errors in the task log. Do not alter the structural scenes or GLBs.

- [ ] **Step 2: Add a failing scene-parser smoke**

Create `scripts/validation/structural_variant_wrapper_smoke.gd` that loads and instantiates each of the eight variant-aware wrapper scenes, asserts `Visual/VisualInstance_Intact`, `Visual/VisualInstance_Damaged`, and `Visual/VisualInstance_Breached` exist as `Node3D`, and calls `IntegrityVisualResolver.apply_visual_state(wrapper, state)` for `intact`, `damaged`, `breached`, and `destroyed`. After each call it must assert that exactly the expected visual child is visible, or that all three are hidden for `destroyed`. It prints the marker:

```gdscript
print("STRUCTURAL VARIANT WRAPPER PASS wrappers=8 intact=true damaged=true breached=true")
```

Before implementation, it must not print that marker.

- [ ] **Step 3: Implement the smallest validator change**

Replace the single hard-coded `VisualInstance` lookup with this policy:

```gdscript
var visual_names: Array[String] = []
if nodes_by_name.has("VisualInstance"):
    visual_names = ["VisualInstance"]
elif nodes_by_name.has("VisualInstance_Intact"):
    visual_names = [
        "VisualInstance_Intact",
        "VisualInstance_Damaged",
        "VisualInstance_Breached",
    ]
else:
    errors.append("%s: missing VisualInstance or VisualInstance_Intact node for generated.visual_scene_path" % scene_path)
```

For every listed node, require parent `Visual`, a populated `instance` reference, and an ext-resource of type `PackedScene`. For the legacy node and `VisualInstance_Intact`, require that ext-resource path to equal `generated.visual_scene_path`. For damaged/breached nodes, require a non-empty `res://assets/imported/structural/` path but do not compare it to the intact path.

- [ ] **Step 4: Run green validation**

Run:

```bash
GODOT_BIN=/opt/homebrew/bin/godot
"$GODOT_BIN" --headless --editor --path . --quit
"$GODOT_BIN" --headless --path . --script res://scripts/placement/validate_wrapper_scenes.gd -- scenes/wrappers/structural/ship_structural_v0
"$GODOT_BIN" --headless --path . --script res://scripts/validation/structural_variant_wrapper_smoke.gd
```

Expected: no `ERROR:`/`WARNING:` lines, validator exit `0`, and `STRUCTURAL VARIANT WRAPPER PASS wrappers=8 intact=true damaged=true breached=true`.

- [ ] **Step 5: Commit**

```bash
git add scripts/placement/validate_wrapper_scenes.gd scripts/validation/structural_variant_wrapper_smoke.gd
git commit -m "fix: validate structural visual variants"
```

### Task 3: Implement the pure prop-sidecar schema, GLB inspection, and canonical serialization layer

**Files:**
- Create: `data/placement/schemas/prop_visual_binding_v1.schema.json`
- Create: `tools/prop_visual_metadata.py`
- Create: `tests/test_prop_visual_metadata.py`
- Create: `tests/fixtures/prop_visual_metadata/invalid_parent_path.sidecar.json`
- Create: `tests/fixtures/prop_visual_metadata/invalid_gameplay_field.sidecar.json`

**Interfaces:**
- `read_glb_metadata(path: Path) -> dict` returns `sha256`, `byte_size`, `gltf_version`, `mesh_count`, `local_min_m`, and `local_max_m`.
- `validate_sidecar(sidecar: dict, glb_path: Path, project_root: Path) -> list[str]` returns deterministic diagnostic strings; an empty list means valid.
- `write_canonical_json(path: Path, document: dict) -> None` writes sorted JSON and a final newline.

- [ ] **Step 1: Write pure Python red tests**

Add tests that fail before implementation:

```python
def test_reactor_console_glb_has_stable_hash_and_ordered_bounds() -> None:
    record = read_glb_metadata(PROJECT_ROOT / "assets/imported/props/components/reactor_console.glb")
    assert len(record["sha256"]) == 64
    assert record["mesh_count"] > 0
    assert record["local_min_m"][0] <= record["local_max_m"][0]


def test_sidecar_rejects_parent_path() -> None:
    errors = validate_sidecar(load_fixture("invalid_parent_path.sidecar.json"), REACTOR_GLB, PROJECT_ROOT)
    assert any("path must be a contained res:// path" in error for error in errors)


def test_sidecar_rejects_component_gameplay_fields() -> None:
    errors = validate_sidecar(load_fixture("invalid_gameplay_field.sidecar.json"), REACTOR_GLB, PROJECT_ROOT)
    assert any("forbidden gameplay field: mass" in error for error in errors)
```

Run:

```bash
python3 -m unittest -v tests.test_prop_visual_metadata
```

Expected before implementation: import failure for `prop_visual_metadata`.

- [ ] **Step 2: Define the schema**

Require these fields:

```json
{
  "schema_version": "1.0.0",
  "document_kind": "prop_visual_binding",
  "asset_id": "reactor_console",
  "prop_kind": "component",
  "visual_scene_path": "res://assets/imported/props/components/reactor_console.glb",
  "binding": {"namespace": "component_id", "ids": ["reactor_console"]},
  "placement": {"origin": "scene_origin", "offset_m": [0, 0, 0], "rotation_degrees": [0, 0, 0], "allowed_yaw_deg": [0, 90, 180, 270], "scale": 1.0},
  "source": {"sha256": "64 lowercase hex characters", "byte_size": 0, "mesh_count": 0, "gltf_version": "2.0"},
  "bounds": {"local_min_m": [0, 0, 0], "local_max_m": [0, 0, 0]},
  "collision_policy": "none_visual_only",
  "provenance": {"license_state": "self-authored", "source_platform": "self-authored"},
  "extensions": {}
}
```

Allow `placement.surface` only for `dressing` and `objective`; component mount surface remains owned by `component_catalog.json`.

- [ ] **Step 3: Implement the module**

Parse a GLB by checking the `glTF` header, reading the JSON chunk, reading accessor min/max values when available, and scanning POSITION accessors when min/max is absent. Reject malformed header lengths, absent meshes, non-finite bounds, mismatched sidecar basename, absolute paths, `..` path components, unsupported major schema versions, wrong `document_kind`, wrong `collision_policy`, duplicate IDs, and forbidden gameplay keys. Permit arbitrary JSON below `extensions`, but reject unknown root-level fields so all future root additions remain deliberate schema decisions.

Use this forbidden-key set exactly:

```python
FORBIDDEN_GAMEPLAY_FIELDS = {
    "mass", "power_draw", "condition_default", "linked_system", "linked_subcomponent",
    "role_weights", "room_id", "cell", "approach_cell", "sequence", "type", "kind",
    "steps", "loot_table", "item_form",
}
```

- [ ] **Step 4: Run the unit suite**

Run:

```bash
python3 -m unittest -v tests.test_prop_visual_metadata
```

Expected: all tests pass with no temporary files beneath `assets/imported/props`.

- [ ] **Step 5: Commit**

```bash
git add data/placement/schemas/prop_visual_binding_v1.schema.json tools/prop_visual_metadata.py tests/test_prop_visual_metadata.py tests/fixtures/prop_visual_metadata
git commit -m "feat: add prop visual sidecar schema"
```

### Task 4: Retroactively create and validate sidecars for all 26 imported prop GLBs

**Files:**
- Create: `tools/generate_prop_sidecars.py`
- Create: `tools/validate_prop_visual_bindings.py`
- Create: `tests/test_validate_prop_visual_bindings.py`
- Create: `assets/imported/props/components/*.sidecar.json` (11 files)
- Create: `assets/imported/props/dressing/*.sidecar.json` (11 files)
- Create: `assets/imported/props/objectives/*.sidecar.json` (4 files)
- Create: `data/props/visual_bindings.generated.json`

**Interfaces:**
- `generate_prop_sidecars.py --project-root . --write-missing --write-index` creates only missing sidecars and rebuilds the derived index.
- `generate_prop_sidecars.py --project-root . --refresh-derived --asset-id <asset_id> --write-index` updates only `source` and `bounds` for one existing sidecar, preserves `binding`, `placement`, `provenance`, and `extensions`, and rebuilds the derived index.
- `generate_prop_sidecars.py --project-root . --check` returns nonzero when a canonical sidecar or derived index differs from disk.
- `validate_prop_visual_bindings.py --project-root . --check-index` returns nonzero for any schema, GLB, hash, bounds, binding, count, path, or index mismatch.

- [ ] **Step 1: Write validator red tests**

Create fixture-copy helpers named `copied_project_without`, `copied_project_with_sidecar_value`, `copied_project_with_objective_alias`, and `copied_project_with_stale_index`, plus a `run_validator` helper that returns the newline-joined deterministic validator diagnostics. Prove the validator rejects each condition with these concrete tests:

```python
def test_validator_rejects_missing_sidecar() -> None:
    with copied_project_without("assets/imported/props/components/reactor_console.sidecar.json") as project_root:
        assert "missing sidecar" in run_validator(project_root)

def test_validator_rejects_stale_hash() -> None:
    with copied_project_with_sidecar_value("reactor_console", ["source", "sha256"], "0" * 64) as project_root:
        assert "sha256 mismatch" in run_validator(project_root)

def test_validator_rejects_unknown_component_id() -> None:
    with copied_project_with_sidecar_value("reactor_console", ["binding", "ids"], ["unknown_component"]) as project_root:
        assert "unknown component_id: unknown_component" in run_validator(project_root)

def test_validator_rejects_duplicate_objective_placement_binding() -> None:
    with copied_project_with_objective_alias("medbay_terminal", "reactor_control_panel") as project_root:
        assert "duplicate gameplay_placement_id: reactor_control_panel" in run_validator(project_root)

def test_validator_rejects_stale_generated_index() -> None:
    with copied_project_with_stale_index("components", "reactor_console") as project_root:
        assert "generated index differs from sidecars" in run_validator(project_root)

def test_refresh_preserves_extensions_and_hand_authored_fields() -> None:
    with copied_project_with_extension("reactor_console", {"studio": {"review_state": "approved"}}) as project_root:
        refresh_derived(project_root, "reactor_console")
        sidecar = load_sidecar(project_root, "components", "reactor_console")
        assert sidecar["extensions"] == {"studio": {"review_state": "approved"}}
        assert sidecar["binding"]["ids"] == ["reactor_console"]
        assert sidecar["placement"]["origin"] == "scene_origin"
```

Run:

```bash
python3 -m unittest -v tests.test_validate_prop_visual_bindings
```

Expected before implementation: import failure for `validate_prop_visual_bindings`.

- [ ] **Step 2: Implement explicit seed mappings**

Seed all 11 component sidecars with `binding.namespace = "component_id"` and exactly one ID equal to its GLB basename:

```text
air_recycler_unit, conduit_run, console_generic, hull_plating, locker_wall,
machinery_block, nav_console, pump_assembly, reactor_console, sensor_rack,
thruster_control
```

Seed all 11 dressing sidecars with `binding.namespace = "visual_prop_id"` and exactly one matching ID. Use these placement surfaces:

```text
wall: cable_tray, emergency_wall
ceiling: practical_overhead
floor: cargo_pallet, focused_work_lamp, generic_crate, generic_locker,
       maintenance_bench, medical_cabinet, salvage_cart, service_rack
```

Seed objective sidecars with `binding.namespace = "gameplay_placement_id"`:

```text
supply_cache: cargo_supply_cache, supply_cache
repair_junction: maintenance_breaker_panel
medbay_terminal: medbay_terminal
reactor_control_panel: reactor_control_panel
```

Set every existing prop sidecar to `collision_policy = "none_visual_only"` and `provenance = {"license_state": "self-authored", "source_platform": "self-authored"}`. Derive each hash, byte size, mesh count, and bounds from the actual GLB.

- [ ] **Step 3: Generate the derived index**

Emit `data/props/visual_bindings.generated.json` sorted by `asset_id` with this top-level shape:

```json
{
  "schema_version": "1.0.0",
  "document_kind": "prop_visual_binding_index",
  "components": {},
  "objectives": {},
  "dressing": {}
}
```

Each component key maps to one sidecar-derived record. Each objective placement ID maps to one sidecar-derived record, including both supply-cache aliases. Each dressing key maps to its sidecar-derived record.

- [ ] **Step 4: Run red-to-green generator checks**

Run:

```bash
python3 tools/generate_prop_sidecars.py --project-root . --check
python3 tools/generate_prop_sidecars.py --project-root . --write-missing --write-index
python3 tools/generate_prop_sidecars.py --project-root . --check
python3 tools/validate_prop_visual_bindings.py --project-root . --check-index
python3 -m unittest -v tests.test_validate_prop_visual_bindings
```

Expected sequence: initial check exits nonzero before sidecars exist; generation creates 26 sidecars and one index; final check/validator/test suite exit zero.

- [ ] **Step 5: Verify the exact retrofit inventory and commit**

Run:

```bash
python3 - <<'PY'
from pathlib import Path
root = Path('assets/imported/props')
for group, expected in [('components', 11), ('dressing', 11), ('objectives', 4)]:
    glbs = sorted((root / group).glob('*.glb'))
    sidecars = sorted((root / group).glob('*.sidecar.json'))
    assert len(glbs) == expected, (group, len(glbs))
    assert len(sidecars) == expected, (group, len(sidecars))
    assert {p.stem.removesuffix('.sidecar') for p in sidecars} == {p.stem for p in glbs}
print('PROP SIDECAR RETROFIT PASS components=11 dressing=11 objectives=4')
PY
git add assets/imported/props data/props tools/generate_prop_sidecars.py tools/validate_prop_visual_bindings.py tests/test_validate_prop_visual_bindings.py
git commit -m "feat: retrofit prop visual sidecars"
```

### Task 5: Add pure runtime catalog and visual-only GLB binder

**Files:**
- Create: `scripts/systems/prop_visual_binding_catalog.gd`
- Create: `scripts/procgen/runtime_prop_visual_binder.gd`
- Create: `scripts/validation/prop_visual_binding_smoke.gd`

**Interfaces:**

```gdscript
class_name PropVisualBindingCatalog
func load_from_path(path: String = "res://data/props/visual_bindings.generated.json") -> bool
func get_component_binding(component_id: String) -> Dictionary
func get_objective_binding(placement_id: String) -> Dictionary
func get_dressing_binding(visual_prop_id: String) -> Dictionary
func get_errors() -> Array[String]

class_name RuntimePropVisualBinder
static func mount_component_visual(marker: Node3D, binding: Dictionary) -> bool
static func create_objective_visual(binding: Dictionary) -> Node3D
static func clear_imported_visuals(root: Node) -> void
```

- [ ] **Step 1: Write the catalog/binder red smoke**

Create `prop_visual_binding_smoke.gd` with these assertions:

```gdscript
var catalog := PropVisualBindingCatalog.new()
_assert(catalog.load_from_path(), "catalog loads generated index")
_assert(not catalog.get_component_binding("reactor_console").is_empty(), "reactor console resolves")
_assert(not catalog.get_objective_binding("reactor_control_panel").is_empty(), "reactor panel resolves")
_assert(catalog.get_component_binding("missing_component").is_empty(), "unknown component is empty")
_assert(catalog.get_objective_binding("bridge_power_distribution").is_empty(), "unmapped objective is empty")
```

Run:

```bash
GODOT_BIN=/opt/homebrew/bin/godot
"$GODOT_BIN" --headless --editor --path . --quit
"$GODOT_BIN" --headless --path . --script res://scripts/validation/prop_visual_binding_smoke.gd
```

Expected before implementation: script-load failure because the catalog class does not exist.

- [ ] **Step 2: Implement strict catalog loading**

The catalog must parse the generated index, require `document_kind = "prop_visual_binding_index"`, accept only major schema version `1`, validate that all scene paths begin `res://assets/imported/props/`, and return `{}` for unknown keys. It must never fabricate a fallback binding.

- [ ] **Step 3: Implement the visual-only binder**

`mount_component_visual` must:

```gdscript
if marker == null or binding.is_empty():
    return false
var packed := load(str(binding.get("visual_scene_path", ""))) as PackedScene
if packed == null:
    return false
var visual := packed.instantiate() as Node3D
if visual == null:
    return false
visual.name = "ImportedVisual"
visual.set_meta("visual_source", "imported")
marker.add_child(visual)
return true
```

Apply `offset_m`, `rotation_degrees`, and `scale` only after verifying their array lengths and finite values. `create_objective_visual` follows the same loading/transform rules but returns the detached `Node3D`. The binder must not add collision nodes, `Area3D`, or interaction scripts.

- [ ] **Step 4: Run green smoke and commit**

Run:

```bash
GODOT_BIN=/opt/homebrew/bin/godot
"$GODOT_BIN" --headless --editor --path . --quit
"$GODOT_BIN" --headless --path . --script res://scripts/validation/prop_visual_binding_smoke.gd
git add scripts/systems/prop_visual_binding_catalog.gd scripts/procgen/runtime_prop_visual_binder.gd scripts/validation/prop_visual_binding_smoke.gd
git commit -m "feat: add prop visual binding runtime"
```

Expected: `PROP VISUAL BINDING PASS components=true objectives=true fallback=true` with no diagnostics.

### Task 6: Replace component-marker primitive visuals with imported GLBs while preserving fallback behavior

**Files:**
- Modify: `scripts/procgen/playable_generated_ship.gd:3494-3554`
- Modify: `scripts/validation/component_markers_smoke.gd`
- Create: `scripts/validation/component_imported_visual_smoke.gd`

**Interfaces:**
- Consumes `PropVisualBindingCatalog.get_component_binding(component_id)` and `RuntimePropVisualBinder.mount_component_visual(marker, binding)`.
- Produces component marker metadata `visual_source = "imported"` or `visual_source = "fallback"`.

- [ ] **Step 1: Add a failing visual-source assertion**

Extend the component marker smoke to require that a placed `reactor_console` marker has:

```gdscript
_assert(str(marker.get_meta("visual_source", "")) == "imported", "reactor console uses imported GLB")
_assert(marker.get_node_or_null("ImportedVisual") != null, "imported visual child exists")
```

Add a second test fixture/path that temporarily requests `missing_component`; it must create a marker with `visual_source = "fallback"` and retain the existing primitive mesh child.

- [ ] **Step 2: Run the red smoke**

Run:

```bash
GODOT_BIN=/opt/homebrew/bin/godot
"$GODOT_BIN" --headless --editor --path . --quit
"$GODOT_BIN" --headless --path . --script res://scripts/validation/component_imported_visual_smoke.gd
```

Expected before integration: missing `ImportedVisual` assertion.

- [ ] **Step 3: Integrate at the existing marker seam**

In `_rebuild_component_markers()`:

1. Preserve existing marker naming, position calculation, parent selection, component metadata, and `_clear_component_markers()` ownership.
2. Load the catalog once per rebuild.
3. Resolve the existing `component_id`.
4. Call `RuntimePropVisualBinder.mount_component_visual(marker, binding)`.
5. On success, call `marker.set_meta("visual_source", "imported")`.
6. On failure, call `marker.set_meta("visual_source", "fallback")` and run the current `BoxMesh` creation block unchanged.

Do not add visual path, visual transform, or binding data to `ComponentPlacementState`.

- [ ] **Step 4: Verify lifecycle regression coverage**

Run:

```bash
GODOT_BIN=/opt/homebrew/bin/godot
"$GODOT_BIN" --headless --editor --path . --quit
"$GODOT_BIN" --headless --path . --script res://scripts/validation/component_markers_smoke.gd
"$GODOT_BIN" --headless --path . --script res://scripts/validation/component_imported_visual_smoke.gd
"$GODOT_BIN" --headless --path . --script res://scripts/validation/component_mount_dismount_smoke.gd
```

Expected: imported `reactor_console` visual appears after rebuild; a malformed/missing binding uses the primitive fallback; dismount removes the marker and visual; remount rebuilds one visual without duplicates.

- [ ] **Step 5: Commit**

```bash
git add scripts/procgen/playable_generated_ship.gd scripts/validation/component_markers_smoke.gd scripts/validation/component_imported_visual_smoke.gd
git commit -m "feat: render components from prop bindings"
```

### Task 7: Preserve objective placement IDs and bind imported objective visuals without changing interaction volumes

**Files:**
- Modify: `scripts/procgen/generated_ship_loader.gd:368-380`
- Modify: `scripts/interaction/interactable.gd:35-86`
- Modify: `scripts/procgen/playable_generated_ship.gd:973-981`
- Create: `scripts/validation/objective_visual_binding_smoke.gd`
- Modify: `scripts/validation/readability_prop_factory_smoke.gd`

**Interfaces:**
- `GeneratedShipLoader._build_objective_specs()` adds `placement_id: String` to each emitted spec.
- `Interactable.configure_from_objective()` and `configure_from_step()` store the `placement_id` in node metadata.
- Objective visual lookup consumes `placement_id`; it never uses objective `type` as its lookup key.

- [ ] **Step 1: Write red objective-flow tests**

Create a smoke that loads `coherent_ship_001` and asserts:

```gdscript
_assert(placement_ids.has("cargo_supply_cache"), "supply cache placement ID retained")
_assert(placement_ids.has("maintenance_breaker_panel"), "repair junction placement ID retained")
_assert(placement_ids.has("medbay_terminal"), "medbay placement ID retained")
_assert(placement_ids.has("reactor_control_panel"), "reactor placement ID retained")
_assert(imported_visual_count == 4, "four physical imported objective visuals")
_assert(interactable_count == 5, "repair junction retains two gameplay interaction steps")
```

Add a coherent-ship-003 assertion that `bridge_power_distribution` and `life_support_console` use the existing procedural visual fallback rather than an unrelated imported GLB.

- [ ] **Step 2: Run the red test**

Run:

```bash
GODOT_BIN=/opt/homebrew/bin/godot
"$GODOT_BIN" --headless --editor --path . --quit
"$GODOT_BIN" --headless --path . --script res://scripts/validation/objective_visual_binding_smoke.gd
```

Expected before integration: missing `placement_id` assertion.

- [ ] **Step 3: Preserve and propagate `placement_id`**

Add this exact field to the objective spec dictionary in `generated_ship_loader.gd`:

```gdscript
"placement_id": str(objective.get("placement_id", "")),
```

In both `Interactable` configuration methods, set:

```gdscript
set_meta("placement_id", str(objective.get("placement_id", "")))
```

Keep all existing objective IDs, sequence, type, room, position, radius, step, and loot behavior unchanged.

- [ ] **Step 4: Bind objective visuals at the readability seam**

In `_build_objective_affordance_props()`:

1. Create `var rendered_placement_ids: Dictionary = {}` before iterating interactables.
2. Read `placement_id` from each interactable metadata.
3. If that ID is already rendered, skip imported rendering for the duplicate repair step.
4. Resolve the catalog objective binding by placement ID.
5. Call `RuntimePropVisualBinder.create_objective_visual(binding)`.
6. On success, set `visual_source = "imported"`, register it at the first matching interactable position, and mark the placement ID rendered.
7. On missing/invalid binding, call `ReadabilityPropFactoryScript.create_objective_prop(sequence, objective_type)` exactly as the current fallback does, set `visual_source = "fallback"`, and register it at the interactable position.

Do not parent visual meshes under `GeneratedShipLoader`'s `ObjectiveRoot`; that root remains gameplay-volume ownership. Do not delete, alter, or replace an `Interactable`/objective volume.

- [ ] **Step 5: Run objective and regression gates**

Run:

```bash
GODOT_BIN=/opt/homebrew/bin/godot
"$GODOT_BIN" --headless --editor --path . --quit
"$GODOT_BIN" --headless --path . --script res://scripts/validation/objective_visual_binding_smoke.gd
"$GODOT_BIN" --headless --path . --script res://scripts/validation/readability_prop_factory_smoke.gd
"$GODOT_BIN" --headless --path . --script res://scripts/validation/main_playable_slice_objective_variation_smoke.gd
"$GODOT_BIN" --headless --path . --script res://scripts/validation/main_playable_slice_completion_smoke.gd
```

Expected: four supplied objective GLBs appear once per physical placement in coherent ship 001; all five interactions remain; unsupported placement IDs use fallback visuals; objective progress/completion markers remain unchanged.

- [ ] **Step 6: Commit**

```bash
git add scripts/procgen/generated_ship_loader.gd scripts/interaction/interactable.gd scripts/procgen/playable_generated_ship.gd scripts/validation/objective_visual_binding_smoke.gd scripts/validation/readability_prop_factory_smoke.gd
git commit -m "feat: bind objective visuals by placement id"
```

### Task 8: Add structural variant audit, generated-data freshness checks, and the release regression bundle

**Files:**
- Create: `tools/validate_structural_variant_bindings.py`
- Create: `tests/test_validate_structural_variant_bindings.py`
- Modify: `docs/game/06_validation_plan.md`
- Modify: `docs/game/features/asset_metadata_pipeline.md`

**Interfaces:**
- `validate_structural_variant_bindings.py --project-root .` validates the eight intact/damaged/breached trios without modifying GLBs, scenes, manifests, or contracts.
- It returns zero only when each trio exists, every GLB has a stable SHA-256, the wrapper references all three paths, wrapper anchors remain present, and `IntegrityVisualResolver` names match the scene nodes.

- [ ] **Step 1: Add red structural-audit tests**

Write temporary-fixture helpers named `copied_structural_fixture_without`, `copied_structural_fixture_with_wrapper_ref`, `copied_structural_fixture_without_node`, `copied_non_variant_structural_fixture`, and `run_structural_audit`. Add these exact failure checks:

```python
def test_missing_breached_variant_is_rejected() -> None:
    with copied_structural_fixture_without("floor_1x1_breached.glb") as project_root:
        assert "missing breached GLB: floor_1x1" in run_structural_audit(project_root)

def test_wrapper_path_that_differs_from_variant_path_is_rejected() -> None:
    with copied_structural_fixture_with_wrapper_ref("floor_1x1", "VisualInstance_Damaged", "floor_1x1.glb") as project_root:
        assert "damaged wrapper path does not match damaged variant: floor_1x1" in run_structural_audit(project_root)

def test_missing_wrapper_socket_anchor_is_rejected() -> None:
    with copied_structural_fixture_without_node("floor_1x1", "Anchor_SOCK_N") as project_root:
        assert "missing required socket anchor Anchor_SOCK_N: floor_1x1" in run_structural_audit(project_root)

def test_non_variant_wrapper_is_ignored_when_it_has_no_integrity_triplet() -> None:
    with copied_non_variant_structural_fixture("wall_end_cap") as project_root:
        assert run_structural_audit(project_root) == []
```

- [ ] **Step 2: Implement the read-only audit**

Audit exactly these variant families:

```text
floor_1x1, floor_2x1, corridor_floor_1x1, corridor_floor_1x2,
wall_straight_1x1, doorway_frame_open_1x1, pillar_support_1x1, ramp_up_1x2
```

For each, verify the exact `intact`, `_damaged`, and `_breached` GLB paths referenced by its wrapper. Verify that the wrapper has `Anchor_FloorCenter`; confirm its existing `Anchor_SOCK_*` set remains stable; verify `VisualInstance_Intact`, `VisualInstance_Damaged`, and `VisualInstance_Breached` are direct children of `Visual`.

- [ ] **Step 3: Run the complete deterministic gate**

Run:

```bash
GODOT_BIN=/opt/homebrew/bin/godot
"$GODOT_BIN" --headless --editor --path . --quit
python3 tools/generate_prop_sidecars.py --project-root . --check
python3 tools/validate_prop_visual_bindings.py --project-root . --check-index
python3 tools/validate_structural_variant_bindings.py --project-root .
python3 -m unittest -v \
  tests.test_prop_visual_metadata \
  tests.test_validate_prop_visual_bindings \
  tests.test_validate_structural_variant_bindings
"$GODOT_BIN" --headless --path . --script res://scripts/placement/validate_wrapper_scenes.gd -- scenes/wrappers/structural/ship_structural_v0
"$GODOT_BIN" --headless --path . --script res://scripts/validation/structural_variant_wrapper_smoke.gd
"$GODOT_BIN" --headless --path . --script res://scripts/validation/prop_visual_binding_smoke.gd
"$GODOT_BIN" --headless --path . --script res://scripts/validation/component_imported_visual_smoke.gd
"$GODOT_BIN" --headless --path . --script res://scripts/validation/objective_visual_binding_smoke.gd
"$GODOT_BIN" --headless --path . --script res://scripts/validation/component_mount_dismount_smoke.gd
"$GODOT_BIN" --headless --path . --script res://scripts/validation/main_playable_slice_completion_smoke.gd
```

Expected: every command exits zero, all pass markers appear, and 26 sidecars/index are fresh. Eight structural trios validate; components use imported visual bindings; supplied objectives use imported visual bindings; unsupported objective placement IDs retain fallbacks. The exact documented ``WARNING: 2 ObjectDB instances were leaked at exit (run with `--verbose` for details).`` baseline is the sole allowed warning from the component smoke; any other diagnostic or a warning count other than two fails the gate.

- [ ] **Step 4: Restore generated engine state and verify repository scope**

Run:

```bash
git restore .godot
git clean -fd -- '*.import'
git diff --check
git status --short
git diff --name-only HEAD~1..HEAD
```

Expected: no `.godot` or `*.import` files remain; the diff contains only Task 8 audit/tests/docs files.

- [ ] **Step 5: Commit**

```bash
git add tools/validate_structural_variant_bindings.py tests/test_validate_structural_variant_bindings.py docs/game/06_validation_plan.md docs/game/features/asset_metadata_pipeline.md
git commit -m "test: audit structural variants and asset bindings"
```

## Final Acceptance Checklist

- [ ] The documentation establishes ADR-0052 and `REQ-AVB-001` through `REQ-AVB-009`.
- [ ] Godot validation imports before tests and uses the installed Godot 4.7.1 command.
- [ ] Structural wrapper validation accepts both legacy and integrity-variant visual forms.
- [ ] The eight structural variant trios validate without rewriting GLBs or duplicating sockets.
- [ ] Every imported prop GLB has one canonical adjacent sidecar: components=11, dressing=11, objectives=4.
- [ ] Sidecar hashes and bounds match actual GLB contents; generated index freshness is enforced.
- [ ] The runtime index is generated-only and has no hand-authored duplicate authority.
- [ ] Components render real imported GLBs beneath existing markers and retain the primitive fallback for invalid bindings.
- [ ] Objectives resolve by `placement_id`, render one visual per physical placement, and retain existing fallback behavior for unmapped IDs.
- [ ] Component mounting, objective interaction, objective progression, structural integrity visuals, and game completion all retain their current behavior under headless regression tests.
- [ ] The exact two-instance ObjectDB leak remains classified as the pre-existing `ship-core` baseline or is removed by its dedicated remediation card; no new or increased warning is accepted.
- [ ] No GLB byte changes, Godot cache files, `.import` artifacts, or unrelated refactors are committed.
