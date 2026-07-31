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
7. GLB-derived refreshes replace the full GLB-derived source evidence (`sha256`, `byte_size`, `mesh_count`, `gltf_version`, and bounds) and preserve only sidecar `extensions` and hand-authored binding/placement/provenance fields.
```

- [ ] **Step 4: Add requirement rows and validation commands**

Add `REQ-AVB-001` through `REQ-AVB-009` covering sidecar completeness, sidecar schema/path/hash/bounds validity, no gameplay-field duplication, component binding, objective placement-ID binding, fallback behavior, structural variant validation, deterministic generated-index freshness, and extension survival during explicit derived-field refresh.

Add these commands to `docs/game/06_validation_plan.md`:

```bash
GODOT_BIN=/opt/homebrew/bin/godot
ROOT="${ROOT:-.}"
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
- Create: `tests/fixtures/structural_variant_wrappers/mixed_legacy_variant.tscn`
- Create: `tests/fixtures/structural_variant_wrappers/mixed_legacy_variant.manifest.json`
- Create: `tests/fixtures/structural_variant_wrappers/mixed_legacy_variant.input.json`
- Create: `tests/fixtures/structural_variant_wrappers/partial_variant.tscn`
- Create: `tests/fixtures/structural_variant_wrappers/partial_variant.manifest.json`
- Create: `tests/fixtures/structural_variant_wrappers/partial_variant.input.json`
- Create: `tests/fixtures/structural_variant_wrappers/traversal_damaged_variant.tscn`
- Create: `tests/fixtures/structural_variant_wrappers/traversal_damaged_variant.manifest.json`
- Create: `tests/fixtures/structural_variant_wrappers/traversal_damaged_variant.input.json`
- Create: `tests/fixtures/structural_variant_wrappers/missing_damaged_resource.tscn`
- Create: `tests/fixtures/structural_variant_wrappers/missing_damaged_resource.manifest.json`
- Create: `tests/fixtures/structural_variant_wrappers/missing_damaged_resource.input.json`

**Interfaces:**
- Produces validator support for exactly two legal visual forms:
  - legacy: `Visual/VisualInstance`
  - variant-aware: `Visual/VisualInstance_Intact`, `Visual/VisualInstance_Damaged`, `Visual/VisualInstance_Breached`
- The intact child must instance `manifest.generated.visual_scene_path`; damaged/breached children must be `PackedScene` resources under `Visual`.

- [ ] **Step 1: Execute the validator red gate and construct fixture-based negative coverage**

First run the real-directory red gate before any Task 2 code changes. The helper below captures the validator output and checks the complete diagnostic signature: exact exit status, exact count of lines beginning `ERROR:`, every such error containing the required marker, and zero lines beginning `WARNING:`.

```bash
GODOT_BIN=/opt/homebrew/bin/godot

expect_exact_error_signature() {
  local label="$1"
  local expected_status="$2"
  local expected_error_count="$3"
  local marker="$4"
  shift 4
  local output status error_count warning_count unexpected_errors
  if output=$("$@" 2>&1); then
    status=0
  else
    status=$?
  fi
  printf '%s\n' "$output"

  if (( status != expected_status )); then
    printf '%s: expected exit %d, got %d\n' "$label" "$expected_status" "$status" >&2
    return 1
  fi
  error_count=$(awk 'BEGIN { count = 0 } /^ERROR:/ { count += 1 } END { print count }' <<<"$output")
  warning_count=$(awk 'BEGIN { count = 0 } /^WARNING:/ { count += 1 } END { print count }' <<<"$output")
  if (( error_count != expected_error_count )); then
    printf '%s: expected exactly %d ERROR: line(s), got %d\n' \
      "$label" "$expected_error_count" "$error_count" >&2
    return 1
  fi
  if (( warning_count != 0 )); then
    printf '%s: expected zero WARNING: lines, got %d\n' "$label" "$warning_count" >&2
    return 1
  fi
  unexpected_errors=$(awk -v marker="$marker" \
    'index($0, "ERROR:") == 1 && index($0, marker) == 0 { print }' <<<"$output")
  if [[ -n "$unexpected_errors" ]]; then
    printf '%s: ERROR: line without required marker %s:\n%s\n' \
      "$label" "$marker" "$unexpected_errors" >&2
    return 1
  fi
}

"$GODOT_BIN" --headless --editor --path . --quit
expect_exact_error_signature \
  "real structural directory baseline" 1 8 \
  "missing VisualInstance node for generated.visual_scene_path" \
  "$GODOT_BIN" --headless --path . \
  --script res://scripts/placement/validate_wrapper_scenes.gd -- \
  scenes/wrappers/structural/ship_structural_v0
printf 'STRUCTURAL VALIDATOR RED CONFIRMED errors=8\n'
```

This direct-directory gate is intentionally distinct from the fixture harness below. It must prove the current validator exits `1` with exactly eight matching errors and no warnings for the existing variant-aware wrappers; Step 3 must make this same directory command exit `0` without changing structural scenes or GLBs.

Create all four same-basename fixture triples by copying the three existing `corridor_floor_1x1` source files, then mutate only the copied `.tscn` in each triple. Do not write either copied companion JSON file:

```bash
FIXTURE_ROOT=tests/fixtures/structural_variant_wrappers
SOURCE_BASE=scenes/wrappers/structural/ship_structural_v0/corridor_floor_1x1
mkdir -p "$FIXTURE_ROOT"
for fixture in mixed_legacy_variant partial_variant traversal_damaged_variant missing_damaged_resource; do
  for suffix in tscn manifest.json input.json; do
    cp "$SOURCE_BASE.$suffix" "$FIXTURE_ROOT/$fixture.$suffix"
  done
done

python3 - "$FIXTURE_ROOT" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])

def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    assert text.count(old) == 1, (path, old, text.count(old))
    path.write_text(text.replace(old, new, 1))

# Mixed form: add the legacy child under Visual, reusing the copied intact resource.
mixed = root / "mixed_legacy_variant.tscn"
replace_once(
    mixed,
    '[node name="Visual" type="Node3D" parent="."]\n',
    '[node name="Visual" type="Node3D" parent="."]\n\n'
    '[node name="VisualInstance" parent="Visual" instance=ExtResource("1_visual")]\n',
)

# Partial form: remove only the breached variant node and its visibility property.
partial = root / "partial_variant.tscn"
replace_once(
    partial,
    '[node name="VisualInstance_Breached" parent="Visual" instance=ExtResource("3_visual_breached")]\nvisible = false\n',
    '',
)

# Traversal form: keep the text prefix but introduce a .. path component.
traversal = root / "traversal_damaged_variant.tscn"
replace_once(
    traversal,
    'path="res://assets/imported/structural/ship_structural_v0/corridor_floor_1x1/corridor_floor_1x1_damaged.glb"',
    'path="res://assets/imported/structural/../ship_structural_v0/corridor_floor_1x1/corridor_floor_1x1_damaged.glb"',
)

# Missing form: use a canonical structural PackedScene path that does not exist.
missing = root / "missing_damaged_resource.tscn"
replace_once(
    missing,
    'path="res://assets/imported/structural/ship_structural_v0/corridor_floor_1x1/corridor_floor_1x1_damaged.glb"',
    'path="res://assets/imported/structural/ship_structural_v0/missing_damaged_resource.tscn"',
)
PY
```

Run the exact baseline functions below against individual `.tscn` arguments. `expect_clean_accept` proves the mixed fixture is still accepted before the fix, while each `expect_exact_error_signature` call proves one and only one old missing-VisualInstance error with no warnings. The red harness succeeds only after proving this validator-under-test is currently red.

```bash
set -euo pipefail

expect_clean_accept() {
  local label="$1"
  shift
  local output status error_count warning_count
  if output=$("$@" 2>&1); then
    status=0
  else
    status=$?
  fi
  printf '%s\n' "$output"
  if (( status != 0 )); then
    printf '%s: expected exit 0, got %d\n' "$label" "$status" >&2
    return 1
  fi
  error_count=$(awk 'BEGIN { count = 0 } /^ERROR:/ { count += 1 } END { print count }' <<<"$output")
  warning_count=$(awk 'BEGIN { count = 0 } /^WARNING:/ { count += 1 } END { print count }' <<<"$output")
  if (( error_count != 0 || warning_count != 0 )); then
    printf '%s: expected zero ERROR:/WARNING: lines, got errors=%d warnings=%d\n' \
      "$label" "$error_count" "$warning_count" >&2
    return 1
  fi
  if ! grep -Fxq -- 'Validated 1 wrapper scene bundle(s).' <<<"$output"; then
    printf '%s: missing exact acceptance marker\n' "$label" >&2
    return 1
  fi
}

OLD_MISSING_VISUAL_MARKER='missing VisualInstance node for generated.visual_scene_path'

run_negative_fixture_red_suite() {
  expect_clean_accept \
    "mixed_legacy_variant pre-fix baseline" \
    "$GODOT_BIN" --headless --path . \
    --script res://scripts/placement/validate_wrapper_scenes.gd -- \
    "$FIXTURE_ROOT/mixed_legacy_variant.tscn"
  expect_exact_error_signature \
    "partial_variant pre-fix baseline" 1 1 "$OLD_MISSING_VISUAL_MARKER" \
    "$GODOT_BIN" --headless --path . \
    --script res://scripts/placement/validate_wrapper_scenes.gd -- \
    "$FIXTURE_ROOT/partial_variant.tscn"
  expect_exact_error_signature \
    "traversal_damaged_variant pre-fix baseline" 1 1 "$OLD_MISSING_VISUAL_MARKER" \
    "$GODOT_BIN" --headless --path . \
    --script res://scripts/placement/validate_wrapper_scenes.gd -- \
    "$FIXTURE_ROOT/traversal_damaged_variant.tscn"
  expect_exact_error_signature \
    "missing_damaged_resource pre-fix baseline" 1 1 "$OLD_MISSING_VISUAL_MARKER" \
    "$GODOT_BIN" --headless --path . \
    --script res://scripts/placement/validate_wrapper_scenes.gd -- \
    "$FIXTURE_ROOT/missing_damaged_resource.tscn"
}

# NEGATIVE-FIXTURE RED HARNESS: every baseline assertion is exact. Any setup,
# Godot, path, or unexpected validator result stops this block with failure.
run_negative_fixture_red_suite
printf 'NEGATIVE FIXTURE RED CONFIRMED mixed=accepted legacy_missing=3\n'

# This is intentionally separate from the pre-fix red harness. Step 4 invokes it
# only after Step 3, under set -euo pipefail, and it accepts exactly the four new
# deterministic diagnostics below.
run_negative_fixture_green_suite() {
  expect_exact_error_signature \
    "mixed_legacy_variant post-fix rejection" 1 1 \
    "mixed visual forms are forbidden" \
    "$GODOT_BIN" --headless --path . \
    --script res://scripts/placement/validate_wrapper_scenes.gd -- \
    "$FIXTURE_ROOT/mixed_legacy_variant.tscn"
  expect_exact_error_signature \
    "partial_variant post-fix rejection" 1 1 \
    "incomplete variant visual form; missing variants: VisualInstance_Breached" \
    "$GODOT_BIN" --headless --path . \
    --script res://scripts/placement/validate_wrapper_scenes.gd -- \
    "$FIXTURE_ROOT/partial_variant.tscn"
  expect_exact_error_signature \
    "traversal_damaged_variant post-fix rejection" 1 1 \
    "must use a canonical contained structural PackedScene path" \
    "$GODOT_BIN" --headless --path . \
    --script res://scripts/placement/validate_wrapper_scenes.gd -- \
    "$FIXTURE_ROOT/traversal_damaged_variant.tscn"
  expect_exact_error_signature \
    "missing_damaged_resource post-fix rejection" 1 1 \
    "references missing PackedScene resource" \
    "$GODOT_BIN" --headless --path . \
    --script res://scripts/placement/validate_wrapper_scenes.gd -- \
    "$FIXTURE_ROOT/missing_damaged_resource.tscn"
}
```

The red harness returns zero only by proving `mixed_legacy_variant` is accepted with the exact `Validated 1 wrapper scene bundle(s).` line and that the other three fixtures each produce exactly one old missing-VisualInstance error and no warnings; any different result fails the block. It therefore records the validator-under-test's pre-Step-3 red state rather than accepting an arbitrary failure. The separate `run_negative_fixture_green_suite` has no broad nonzero-only path: every post-Step-3 fixture must exit `1`, emit exactly one `ERROR:` line, emit zero `WARNING:` lines, and contain its listed marker. This negative-fixture evidence remains separate from the eight-error real-directory red gate.


- [ ] **Step 2: Add a baseline-green eight-scene wrapper characterization smoke**

Create `scripts/validation/structural_variant_wrapper_smoke.gd` with this implementation-ready smoke skeleton. It loads and instantiates the eight existing variant wrappers, but it does **not** invoke `validate_wrapper_scenes.gd` and is not a validator test:

```gdscript
extends SceneTree

const IntegrityVisualResolverScript: GDScript = preload("res://scripts/systems/integrity_visual_resolver.gd")
const VARIANT_WRAPPER_PATHS: PackedStringArray = [
	"res://scenes/wrappers/structural/ship_structural_v0/corridor_floor_1x1.tscn",
	"res://scenes/wrappers/structural/ship_structural_v0/corridor_floor_1x2.tscn",
	"res://scenes/wrappers/structural/ship_structural_v0/doorway_frame_open_1x1.tscn",
	"res://scenes/wrappers/structural/ship_structural_v0/floor_1x1.tscn",
	"res://scenes/wrappers/structural/ship_structural_v0/floor_2x1.tscn",
	"res://scenes/wrappers/structural/ship_structural_v0/pillar_support_1x1.tscn",
	"res://scenes/wrappers/structural/ship_structural_v0/ramp_up_1x2.tscn",
	"res://scenes/wrappers/structural/ship_structural_v0/wall_straight_1x1.tscn",
]

func _initialize() -> void:
	var failures: int = 0
	if not _expect(IntegrityVisualResolverScript != null, "resolver preload failed"):
		failures += 1
	var unique_paths: Dictionary = {}
	for scene_path in VARIANT_WRAPPER_PATHS:
		unique_paths[scene_path] = true
	if not _expect(
		VARIANT_WRAPPER_PATHS.size() == 8 and unique_paths.size() == 8,
		"expected exactly 8 unique variant wrapper paths",
	):
		failures += 1
	for scene_path in VARIANT_WRAPPER_PATHS:
		failures += _check_wrapper(scene_path)
	if failures != 0:
		push_error("STRUCTURAL VARIANT WRAPPER FAILURES: %d" % failures)
		quit(1)
		return
	print("STRUCTURAL VARIANT WRAPPER PASS wrappers=8 intact=true damaged=true breached=true")
	quit(0)


func _check_wrapper(scene_path: String) -> int:
	var failures: int = 0
	var packed_scene: PackedScene = load(scene_path) as PackedScene
	if not _expect(packed_scene != null, "%s did not load as PackedScene" % scene_path):
		return 1
	var instance: Node = packed_scene.instantiate()
	if not _expect(instance != null and instance is Node3D, "%s did not instantiate Node3D" % scene_path):
		if instance != null:
			instance.free()
		return 1
	var wrapper: Node3D = instance as Node3D
	get_root().add_child(wrapper)

	var visual_group: Node3D = wrapper.get_node_or_null("Visual") as Node3D
	if not _expect(visual_group != null, "%s missing Visual Node3D" % scene_path):
		_detach(wrapper)
		return 1
	var intact: Node3D = visual_group.get_node_or_null("VisualInstance_Intact") as Node3D
	var damaged: Node3D = visual_group.get_node_or_null("VisualInstance_Damaged") as Node3D
	var breached: Node3D = visual_group.get_node_or_null("VisualInstance_Breached") as Node3D
	if not _expect(intact != null, "%s missing intact Node3D" % scene_path):
		failures += 1
	if not _expect(damaged != null, "%s missing damaged Node3D" % scene_path):
		failures += 1
	if not _expect(breached != null, "%s missing breached Node3D" % scene_path):
		failures += 1
	if failures != 0:
		_detach(wrapper)
		return failures

	for state in ["intact", "damaged", "breached", "destroyed"]:
		var applied: bool = IntegrityVisualResolverScript.apply_visual_state(wrapper, state)
		if not _expect(applied, "%s resolver returned false for state=%s" % [scene_path, state]):
			failures += 1
		failures += _expect_state(scene_path, state, intact, damaged, breached)
	_detach(wrapper)
	return failures


func _expect_state(
	scene_path: String,
	state: String,
	intact: Node3D,
	damaged: Node3D,
	breached: Node3D,
) -> int:
	var expected_name: String = ""
	match state:
		"intact":
			expected_name = "VisualInstance_Intact"
		"damaged":
			expected_name = "VisualInstance_Damaged"
		"breached":
			expected_name = "VisualInstance_Breached"
		"destroyed":
			expected_name = ""
	var failures: int = 0
	for child in [intact, damaged, breached]:
		var should_be_visible: bool = state != "destroyed" and child.name == expected_name
		if not _expect(
			child.visible == should_be_visible,
			"%s state=%s visibility mismatch for %s" % [scene_path, state, child.name],
		):
			failures += 1
	return failures


func _detach(wrapper: Node3D) -> void:
	get_root().remove_child(wrapper)
	wrapper.free()


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("STRUCTURAL VARIANT WRAPPER FAILURE: %s" % message)
	return false
```

Run this smoke once before Step 3 and once after Step 3. It must be baseline-green both times and print:

```text
STRUCTURAL VARIANT WRAPPER PASS wrappers=8 intact=true damaged=true breached=true
```

The smoke is deliberately separate from validator coverage: it only proves that all eight existing `PackedScene` wrappers load, instantiate, expose `Visual` plus all three `Node3D` variant children, and return `true` from `IntegrityVisualResolver.apply_visual_state(...)` for `intact`, `damaged`, `breached`, and `destroyed`, with exact visibility (one matching child visible for the first three states and all three hidden for `destroyed`).

- [ ] **Step 3: Implement the smallest validator change with deterministic form and resource gates**

Replace the single hard-coded `VisualInstance` lookup with an explicit exactly-two-forms policy. Keep the existing `if not generated_visual_scene_path.is_empty():` guard around this block. Add `const STRUCTURAL_SCENE_PREFIX: String = "res://assets/imported/structural/"` with the other validator constants, then use this logic:

```gdscript
var variant_names: Array[String] = [
	"VisualInstance_Intact",
	"VisualInstance_Damaged",
	"VisualInstance_Breached",
]
var visual_names: Array[String] = []
var has_legacy: bool = nodes_by_name.has("VisualInstance")
var present_variants: Array[String] = []
for variant_name in variant_names:
	if nodes_by_name.has(variant_name):
		present_variants.append(variant_name)
var has_any_variant: bool = not present_variants.is_empty()
var has_all_variants: bool = present_variants.size() == variant_names.size()

if has_legacy and has_any_variant:
	errors.append(
		"%s: mixed visual forms are forbidden: VisualInstance plus %s" %
		[scene_path, ", ".join(PackedStringArray(present_variants))]
	)
elif has_legacy:
	visual_names = ["VisualInstance"]
elif has_all_variants:
	visual_names = variant_names.duplicate()
elif has_any_variant:
	var missing_variants: Array[String] = []
	for variant_name in variant_names:
		if not nodes_by_name.has(variant_name):
			missing_variants.append(variant_name)
	errors.append(
		"%s: incomplete variant visual form; missing variants: %s" %
		[scene_path, ", ".join(PackedStringArray(missing_variants))]
	)
else:
	errors.append(
		"%s: missing VisualInstance or variant visual nodes for generated.visual_scene_path" %
		scene_path
	)

for visual_name in visual_names:
	var visual_instance: Dictionary = nodes_by_name[visual_name]
	if str(visual_instance.get("parent", "")) != "Visual":
		errors.append("%s: %s must be parented to Visual" % [scene_path, visual_name])

	var visual_instance_ref: String = str(visual_instance.get("instance", ""))
	if visual_instance_ref.is_empty():
		errors.append("%s: %s must instance the generated visual scene" % [scene_path, visual_name])
		continue

	var instance_start: int = visual_instance_ref.find("\"")
	var instance_finish: int = visual_instance_ref.find("\"", instance_start + 1)
	if instance_start == -1 or instance_finish == -1:
		errors.append("%s: %s has malformed ext_resource reference" % [scene_path, visual_name])
		continue

	var resource_id: String = visual_instance_ref.substr(
		instance_start + 1,
		instance_finish - instance_start - 1
	)
	var visual_resource: Dictionary = extresources.get(resource_id, {})
	if visual_resource.is_empty():
		errors.append("%s: %s references missing ext_resource %s" % [scene_path, visual_name, resource_id])
		continue
	if str(visual_resource.get("type", "")) != "PackedScene":
		errors.append("%s: %s ext_resource must be a PackedScene" % [scene_path, visual_name])
		continue

	var resource_path: String = str(visual_resource.get("path", ""))
	if visual_name == "VisualInstance" or visual_name == "VisualInstance_Intact":
		# Preserve the existing intact contract: parent, PackedScene type, and exact manifest path.
		if resource_path != generated_visual_scene_path:
			errors.append("%s: %s ext_resource path does not match manifest.generated.visual_scene_path" % [scene_path, visual_name])
	else:
		# Damaged and breached references are text-checked before touching the loader.
		var canonical_contained_path: bool = (
			resource_path.begins_with(STRUCTURAL_SCENE_PREFIX)
			and not resource_path.split("/").has("..")
			and resource_path.simplify_path() == resource_path
		)
		if not canonical_contained_path:
			errors.append("%s: %s must use a canonical contained structural PackedScene path" % [scene_path, visual_name])
			continue
		if not ResourceLoader.exists(resource_path, "PackedScene"):
			errors.append("%s: %s references missing PackedScene resource" % [scene_path, visual_name])
```

The fixed `variant_names` order makes both the mixed-form and missing-variant diagnostics deterministic. Legacy is accepted only when no variant node is present; variant-aware form is accepted only when all three named nodes are present; any partial variant set is rejected. The four negative fixtures must therefore produce the exact substrings `mixed visual forms are forbidden`, `incomplete variant visual form; missing variants: VisualInstance_Breached`, `must use a canonical contained structural PackedScene path`, and `references missing PackedScene resource`. Do not edit structural scenes, source wrapper scenes, or GLBs; this step changes only validator logic.

- [ ] **Step 4: Run the complete green validator, negative-fixture, smoke, and source-integrity bundle**

Run the following as one shell block after defining the exact `expect_clean_accept`, `expect_exact_error_signature`, and `run_negative_fixture_green_suite` helpers from Step 1. The green commands run inside a subshell so the `EXIT` trap can preserve a primary test failure while still making cleanup failure fail an otherwise successful bundle.

```bash
set -euo pipefail

if (
  set -euo pipefail
  GODOT_BIN=/opt/homebrew/bin/godot
  FIXTURE_ROOT=tests/fixtures/structural_variant_wrappers
  SMOKE_LOG=$(mktemp)

  run_clean() {
    if (( $# == 0 )); then
      printf 'run_clean requires a command\n' >&2
      return 2
    fi
    local output status
    if output=$("$@" 2>&1); then
      status=0
    else
      status=$?
    fi
    printf '%s\n' "$output"
    if (( status != 0 )); then
      printf 'command failed with exit %d: %q\n' "$status" "$1" >&2
      return "$status"
    fi
    if grep -Fq -- 'ERROR:' <<<"$output" || grep -Fq -- 'WARNING:' <<<"$output"; then
      printf 'unexpected ERROR:/WARNING: diagnostic from command: %q\n' "$1" >&2
      return 1
    fi
  }

  cleanup_generated_state() {
    local cleanup_status=0
    if ! git restore -- .godot; then
      printf 'cleanup failed: git restore -- .godot\n' >&2
      cleanup_status=1
    fi
    if ! git clean -fd -- '*.import'; then
      printf "cleanup failed: git clean -fd -- '*.import'\n" >&2
      cleanup_status=1
    fi
    if ! rm -f "$SMOKE_LOG"; then
      printf 'cleanup failed: rm -f %s\n' "$SMOKE_LOG" >&2
      cleanup_status=1
    fi
    return "$cleanup_status"
  }

  finish_bundle() {
    local original_status="$1"
    local cleanup_status=0
    cleanup_generated_state || cleanup_status=$?
    if (( original_status != 0 )); then
      return "$original_status"
    fi
    return "$cleanup_status"
  }

  trap 'original_status=$?; finish_bundle "$original_status"; exit $?' EXIT

  # Import preflight: run_clean requires exit 0 and no ERROR:/WARNING: output.
  run_clean "$GODOT_BIN" --headless --editor --path . --quit

  # Real structural directory validator green gate.
  run_clean "$GODOT_BIN" --headless --path . \
    --script res://scripts/placement/validate_wrapper_scenes.gd -- \
    scenes/wrappers/structural/ship_structural_v0

  # Fixture-based negative gates: intentional ERROR: output is allowed only because
  # the separate suite asserts status 1, exactly one ERROR:, zero WARNING:, and the
  # exact marker for each fixture.
  run_negative_fixture_green_suite
  printf 'NEGATIVE FIXTURE GREEN CONFIRMED\n'

  # Exact eight-scene runtime wrapper smoke; this does not invoke the validator.
  run_clean "$GODOT_BIN" --headless --path . \
    --script res://scripts/validation/structural_variant_wrapper_smoke.gd \
    | tee "$SMOKE_LOG"
  if ! grep -Fxq -- \
    'STRUCTURAL VARIANT WRAPPER PASS wrappers=8 intact=true damaged=true breached=true' \
    "$SMOKE_LOG"; then
    printf 'missing exact structural wrapper smoke pass marker\n' >&2
    exit 1
  fi
); then
  bundle_status=0
else
  bundle_status=$?
fi

# These checks run only after the subshell returned successfully, which proves
# primary tests and cleanup both succeeded. They prove no generated state or
# structural source files remain before Step 5 can touch the index.
if (( bundle_status != 0 )); then
  exit "$bundle_status"
fi
generated_status=$(git status --short -- .godot ':(glob)**/*.import')
if [[ -n "$generated_status" ]]; then
  printf 'generated Godot state remains after cleanup:\n%s\n' "$generated_status" >&2
  exit 1
fi
source_status=$(git status --short -- \
  scenes/wrappers/structural \
  assets/_processed \
  assets/imported/structural)
if [[ -n "$source_status" ]]; then
  printf 'structural source files changed by validation:\n%s\n' "$source_status" >&2
  exit 1
fi
printf 'CLEANUP VERIFIED generated_state=empty structural_sources=clean\n'
```

`run_clean` captures and prints every command's output, propagates a nonzero command exit, and rejects any `ERROR:` or `WARNING:` diagnostic. The negative suite is the sole exception for intentional `ERROR:` output: each fixture must return status `1`, exactly one `ERROR:` line, zero `WARNING:` lines, and its exact marker through `expect_exact_error_signature`; the suite itself must return zero after all four exact rejections pass. The smoke's exact pass line is checked with `grep -Fxq`, while every other green command is enforced by exit status plus the diagnostic scan. The `EXIT` trap is installed before the first Godot command. `finish_bundle` captures the primary status, attempts every cleanup operation, returns the primary status when tests failed, and returns cleanup status when tests otherwise passed; cleanup failure is therefore never silently masked. The post-subshell generated-state and broad structural-source checks must both be empty before Step 5.

- [ ] **Step 5: Stage only Task 2 implementation artifacts and commit**

After the Step 4 shell block exits and its `cleanup_generated_state` `EXIT` trap has completed, stage only the validator, smoke, and all four fixture triples:

```bash
set -euo pipefail
TASK2_PATHS=(
  scripts/placement/validate_wrapper_scenes.gd
  scripts/validation/structural_variant_wrapper_smoke.gd
  tests/fixtures/structural_variant_wrappers/mixed_legacy_variant.tscn
  tests/fixtures/structural_variant_wrappers/mixed_legacy_variant.manifest.json
  tests/fixtures/structural_variant_wrappers/mixed_legacy_variant.input.json
  tests/fixtures/structural_variant_wrappers/partial_variant.tscn
  tests/fixtures/structural_variant_wrappers/partial_variant.manifest.json
  tests/fixtures/structural_variant_wrappers/partial_variant.input.json
  tests/fixtures/structural_variant_wrappers/traversal_damaged_variant.tscn
  tests/fixtures/structural_variant_wrappers/traversal_damaged_variant.manifest.json
  tests/fixtures/structural_variant_wrappers/traversal_damaged_variant.input.json
  tests/fixtures/structural_variant_wrappers/missing_damaged_resource.tscn
  tests/fixtures/structural_variant_wrappers/missing_damaged_resource.manifest.json
  tests/fixtures/structural_variant_wrappers/missing_damaged_resource.input.json
)
if (( ${#TASK2_PATHS[@]} != 14 )); then
  printf 'expected exactly 14 Task 2 paths, got %d\n' "${#TASK2_PATHS[@]}" >&2
  exit 1
fi

# Refuse to modify any pre-existing staged work. This protects concurrently staged
# changes and leaves the index untouched when the precondition fails.
if ! git diff --cached --quiet; then
  printf 'pre-existing staged work detected; refusing to modify the index:\n' >&2
  git diff --cached --name-only >&2
  exit 1
fi

git add "${TASK2_PATHS[@]}"

expected_paths=$(printf '%s\n' "${TASK2_PATHS[@]}" | LC_ALL=C sort)
actual_paths=$(git diff --cached --name-only | LC_ALL=C sort)
if [[ "$actual_paths" != "$expected_paths" ]]; then
  printf 'cached Task 2 path set mismatch\nexpected:\n%s\nactual:\n%s\n' \
    "$expected_paths" "$actual_paths" >&2
  exit 1
fi

git diff --cached --check
staged_placeholders=$(git diff --cached --unified=0 | awk '/^\+[^+]/ && /(TODO|TBD)/ { print }')
if [[ -n "$staged_placeholders" ]]; then
  printf 'staged Task 2 additions contain forbidden placeholders:\n%s\n' \
    "$staged_placeholders" >&2
  exit 1
fi

git commit -m "fix: validate structural visual variants"
committed_paths=$(git diff-tree --no-commit-id --name-only -r HEAD | LC_ALL=C sort)
if [[ "$committed_paths" != "$expected_paths" ]]; then
  printf 'committed Task 2 path set mismatch\nexpected:\n%s\nactual:\n%s\n' \
    "$expected_paths" "$committed_paths" >&2
  exit 1
fi
git diff HEAD^ HEAD --check
```

The clean-index precondition uses `git diff --cached --quiet`; when it fails, the script prints the existing staged names and exits before any index mutation, protecting concurrently staged work. The exact 14-element `TASK2_PATHS` array is the sole staging allowlist; the cached expected-vs-actual comparison fails with both sets on mismatch, so no Task 3+ files, source wrappers, GLBs, or generated Godot state can be staged. The staged whitespace check and added-line placeholder scan run before commit. After commit, `git diff-tree --no-commit-id --name-only -r HEAD | LC_ALL=C sort` must equal the same expected set, and `git diff HEAD^ HEAD --check` must pass. The commit therefore contains exactly the 14 Task 2 files and nothing else.

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
- `generate_prop_sidecars.py --project-root . --refresh-derived --asset-id <asset_id> --write-index` replaces the full GLB-derived source evidence (`sha256`, `byte_size`, `mesh_count`, `gltf_version`, and `bounds`) for one existing sidecar, preserves only authored `binding`, `placement`, `provenance`, and `extensions`, and rebuilds the derived index.
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
