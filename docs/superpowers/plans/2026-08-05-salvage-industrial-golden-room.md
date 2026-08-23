# Salvage-Industrial Golden Room Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refine the staged focused-nine assets into a visually coherent salvage-industrial golden room without modifying runtime assets, wrappers, manifests, or procgen mappings.

**Architecture:** Extend the existing deterministic `focused_nine_blender_recipes.py` generated-only recipe system, preserving exact canonical material provenance and all existing connector/source contracts. Re-run the existing staged batch and room preview runners only after evidence validation passes; stage and preview artifacts remain outside the live runtime surface.

**Tech Stack:** Python 3.11, Blender 5.2 Python (`bpy`), Godot 4.7.1, focused-nine source/evidence/batch/preview tools, pytest, Ruff.

## Global Constraints

- Sources remain under `/Volumes/Untitled/SynapticSeaAssets/meshes/source/ship_structural_v0_focused_nine`; legacy structural sources stay immutable.
- Use only canonical material identities unless material-library provenance and tests are explicitly extended; never allow Blender `.001` collisions.
- Generated geometry stays in the `FocusedNine_<asset_id>_` namespace and must remain idempotent.
- Do not modify `assets/imported/`, `scenes/wrappers/`, live manifests, or procgen mappings.
- All previews use the staged-only airlock room runner and must remain 1600×900 with no Godot diagnostics.

---

### Task 1: Encode salvage-industrial detail recipes for floor, wall, ramp, pillar, and ceiling

**Files:**
- Modify: `tools/focused_nine_blender_recipes.py`
- Modify: `tests/test_focused_nine_blender_recipes.py`

**Interfaces:**
- Consumes: `apply_recipe(asset_id, ...)` and existing canonical material resolver.
- Produces: idempotent generated subassemblies with named panel, service-channel, conduit, vent, and practical-light objects.

- [ ] **Step 1: Write failing structural detail tests**

Add parameterized assertions that a fresh recipe result for `floor_1x1`, `wall_straight_1x1`, `ramp_up_1x2`, `pillar_support_1x1`, and `ceiling_cap_1x1` has its required generated detail-role names, preserves the asset root/contract connectors, and uses only canonical materials.

- [ ] **Step 2: Run the new focused test red**

Run: `PYTHONPATH=. /opt/homebrew/bin/python3.11 -m pytest -q tests/test_focused_nine_blender_recipes.py -k salvage_detail`

Expected: FAIL because the detail-role contract does not yet exist.

- [ ] **Step 3: Implement deterministic secondary geometry**

Add small generated helpers that create: floor service tracks and threshold ribs; wall panel hierarchy plus one conduit run; ramp anti-slip ribs; pillar ribs/brackets; ceiling service tray, vent rhythm, and one restrained emissive recess. Each helper must assign the existing canonical materials and mark every new object with the generated asset marker.

- [ ] **Step 4: Verify idempotence and Blender output**

Run the focused recipe test twice, then run one real Blender recipe for `floor_1x1` and assert no duplicate generated names, source contract error, or material suffix exists.

- [ ] **Step 5: Commit**

```bash
git add tools/focused_nine_blender_recipes.py tests/test_focused_nine_blender_recipes.py
git commit -m "feat: add salvage structural detail recipes"
```

### Task 2: Refine transitions, pressure-door states, and functional props

**Files:**
- Modify: `tools/focused_nine_blender_recipes.py`
- Modify: `tests/test_focused_nine_blender_recipes.py`
- Modify: `tests/test_focused_nine_staged_structural.py`
- Modify: `tests/test_focused_nine_staged_props.py`

**Interfaces:**
- Consumes: generated-only asset deletion rules, pressure-door intact/damaged/breached staged contract, and prop visual-sidecar contract.
- Produces: visual state differentiation while retaining unchanged asset identities, source metadata, and variant roles.

- [ ] **Step 1: Write failing tests for landmark detail contracts**

Test that the doorway has a threshold/seal/rail role, the pressure door has shared frame/rail roles plus state-specific `Intact`, `Damaged`, and `Breached` visual identifiers, the breach seal has mounting/hose/status roles, and the fire station has mounting/handle/indicator roles.

- [ ] **Step 2: Run tests red**

Run: `PYTHONPATH=. /opt/homebrew/bin/python3.11 -m pytest -q tests/test_focused_nine_blender_recipes.py tests/test_focused_nine_staged_structural.py tests/test_focused_nine_staged_props.py -k landmark`

Expected: FAIL because those visual-role contracts are absent.

- [ ] **Step 3: Implement minimal deterministic landmark geometry**

Create substantial door frames, mechanical rails and seals, and damage progression that preserves pressure-door role visibility. Create flush-mounted functional props with mounting plates, simple hose/cable/handle silhouettes, and restrained cyan/amber/red indicators. Do not add random or per-run damage.

- [ ] **Step 4: Verify staged role and prop contracts**

Run the focused structural/prop validator suites plus a real Blender recipe/export probe. Assert all role visibility and sidecar validation results are green.

- [ ] **Step 5: Commit**

```bash
git add tools/focused_nine_blender_recipes.py tests/test_focused_nine_blender_recipes.py tests/test_focused_nine_staged_structural.py tests/test_focused_nine_staged_props.py
git commit -m "feat: refine salvage landmarks and door states"
```

### Task 3: Produce a new staged golden-room candidate and enforce evidence gates

**Files:**
- Modify: `tools/focused_nine_batch.py`
- Modify: `tests/test_focused_nine_batch.py`
- Modify: `docs/superpowers/proofs/focused-nine-comparison.md`

**Interfaces:**
- Consumes: enhanced deterministic recipes and existing source/evidence validators.
- Produces: a schema-valid staged focused-nine report with per-asset evidence and no live-runtime mutation.

- [ ] **Step 1: Write a failing candidate-quality test**

Add an assertion that the batch report records expected generated detail-role counts/material set for every focused asset and rejects a report that omits them.

- [ ] **Step 2: Run test red**

Run: `PYTHONPATH=. /opt/homebrew/bin/python3.11 -m pytest -q tests/test_focused_nine_batch.py -k golden_room`

Expected: FAIL because candidate-quality proof fields are absent.

- [ ] **Step 3: Add bounded quality evidence to the batch report**

Record per-asset canonical material names, triangles, objects, and declared detail roles from the validated staged outputs. Preserve all current path-safety, validation-before-publication, rollback, and source-record behavior.

- [ ] **Step 4: Run the real staged batch**

Run the established `tools/focused_nine_batch.py` command with the focused parallel source root and legacy validation source root. Require the pass marker, all focused tests, source/prop validators, report schema validation, and runtime no-diff check.

- [ ] **Step 5: Commit**

```bash
git add tools/focused_nine_batch.py tests/test_focused_nine_batch.py docs/superpowers/proofs/focused-nine-comparison.md
git commit -m "feat: record golden room asset evidence"
```

### Task 4: Capture and visually accept the improved golden room

**Files:**
- Modify: `docs/superpowers/proofs/focused-nine-airlock-control-room.md`
- Modify: `artifacts/validation-previews/focused-nine/focused-nine-airlock-control-room.png`
- Test: `tests/test_focused_nine_airlock_control_room_preview.py`

**Interfaces:**
- Consumes: staged-only room scene and preview runner.
- Produces: one transactionally published 1600×900 PNG and proof, with no runtime changes.

- [ ] **Step 1: Add a failing proof-quality test**

Assert the proof requires the staged-only marker, 1600×900 dimensions, no Godot diagnostic text, and an explicit visual-inspection checklist covering panel hierarchy, door state readability, ceiling density, functional props, and connected-room readability.

- [ ] **Step 2: Run test red**

Run: `PYTHONPATH=. /opt/homebrew/bin/python3.11 -m pytest -q tests/test_focused_nine_airlock_control_room_preview.py -k proof_quality`

Expected: FAIL because the prior proof lacks the new inspection checklist.

- [ ] **Step 3: Run the real staged-only room preview**

Run:

```bash
PYTHONPATH=. /opt/homebrew/bin/python3.11 tools/focused_nine_airlock_control_room_preview.py \
  --project-root . \
  --staging-root assets/_staging/focused_nine \
  --preview-dir artifacts/validation-previews/focused-nine \
  --proof docs/superpowers/proofs/focused-nine-airlock-control-room.md
```

Require `FOCUSED_NINE_AIRLOCK_ROOM_PREVIEW PASS`, a valid PNG signature, 1600×900 dimensions, and a clean runtime snapshot.

- [ ] **Step 4: Inspect the actual PNG**

Verify the room reads as a connected salvage-industrial environment and explicitly reject featureless tiled surfaces, floating props, repeated identical damage, obscured thresholds, or diagnostic/error overlays.

- [ ] **Step 5: Commit**

```bash
git add docs/superpowers/proofs/focused-nine-airlock-control-room.md artifacts/validation-previews/focused-nine/focused-nine-airlock-control-room.png tests/test_focused_nine_airlock_control_room_preview.py
git commit -m "feat: stage salvage industrial golden room"
```

## Self-Review

- Spec coverage: Tasks 1–2 cover every scoped asset family and material/variant rule; Task 3 preserves evidence/no-promotion gates; Task 4 proves the visual quality bar in the actual staged room.
- No placeholders or alternate interpretations remain: every task names its files, required interface, test behavior, command, and commit boundary.
- Scope remains one staged golden-room slice; new corners, T-junctions, end caps, and expanded corridor families intentionally wait for a later plan derived from the accepted visual language.

### Task 9: Record canonical compiler parity and close the integration gate

**Files:**
- Create: `docs/superpowers/proofs/procgen-canonical-structural-compiler.md`
- Modify: `docs/superpowers/specs/2026-08-05-salvage-industrial-golden-room-design.md`
- Modify: `scripts/validation/procgen_golden_parity_smoke.gd`
- Modify: `tests/test_procgen_structural_compiler.py`

**Canonical policy:** `StructuralEdgePlan` is the sole boundary authority. The
legacy resolver and `structural_placer` are debug-only adapters/visualizers and
must not derive or place production boundaries. Runtime capture uses live wrapper
resources; staged capture uses the disposable overlay runner. The parity gate
compares the sorted structural `placement_id`/`edge_key` inventory, semantic
kind/state/module, canonical pose, and room IDs. GLB/material/scene-path changes
are visual-only exceptions; any structural plan drift is a failure.

- [x] Write source tests for the parity smoke, policy text, and proof contract;
  observe them fail before implementation.
- [x] Implement the parity smoke and record the staged overlay evidence.
- [x] Run the final integration gate in this order:

```bash
PYTHONPATH=. python3.11 -m pytest -q tests/test_procgen_structural_compiler.py tests/test_focused_nine_staged_derelict_preview.py
godot --headless --path . --script res://scripts/validation/procgen_structural_compiler_smoke.gd -- 17 23 41 73 101
godot --headless --path . --script res://scripts/validation/procgen_golden_parity_smoke.gd
git diff --check
```

The final report must include complete output and exit status for all four
commands. Do not claim a pass if any command emits an unexpected Godot
diagnostic, fails to print its explicit marker, or reports structural plan drift.
