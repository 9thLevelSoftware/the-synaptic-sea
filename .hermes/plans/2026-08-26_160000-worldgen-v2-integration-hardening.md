# Worldgen v2 Integration Hardening — Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Make the worldgen v2 Rust pipeline the clean, validated, default generation path in The Synaptic Sea — no validation bypasses, live demo scene, proximity ceiling fade, and golden-hash export protection wired into CI.

**Architecture:** Five independent hardening items against `9thLevelSoftware/worldgen` (Rust core/GDExtension) and `9thLevelSoftware/the-synaptic-sea` (Godot consumer). Both repos were pushed current as of this session: worldgen at `88f9b2e`, Synaptic Sea at `005dd2a`. Cross-repo contract is the layout.json/gameplay_slice.json schema produced by `derelict_core::structural::export` and consumed by `GeneratedShipLoader.load_from_documents()`.

**Tech Stack:** Rust (derelict_core/derelict_godot/derelict_cli), GDScript (Godot 4.7.1), GitHub Actions CI.

---

## Current context / assumptions

Verified state from this session (do not re-verify during planning):

- **Upstream worldgen already emits `prototype` as a Dictionary.** `crates/derelict_core/src/structural/export.rs:319-322` produces `"prototype": {"start_room": ..., "goal_room": ...}`. The string-typed prototype failure seen earlier came from our now-deleted duplicate `derelict_godot/src/export.rs`. **Next-step item #1 may already be fixed — the first task below is a 2-minute confirmation, not an implementation.**
- Structural module is public: `crates/derelict_core/src/structural/mod.rs` exposes `compile`, `export`, `plan`, `project`, `sockets`, `validate`.
- CLI already has `--export-dir <DIR> --kit-id <ID>` which writes `layout.json` + `gameplay_slice.json` in the Synaptic Sea contract — this is the mechanism for regenerating the demo fixtures.
- CLI also has `--stress`: 1,800-ship fail-closed sweep (every archetype × 3 intactness bands × 150 seeds).
- `addons/derelict/derelict.gdextension` already declares the macOS library path; the built dylib is committed at `addons/derelict/bin/macos/libderelict_godot.dylib`.
- `worldgen_live_preview.gd` (committed at Synaptic Sea `005dd2a`) still contains validation bypasses (`structural_plan_validated = true` + `critical_path` erase) that must be removed once export validation passes.
- `GeneratedShipLoader` instantiates ceiling wrappers with names prefixed `Ceiling_` (verified: 123 ceiling nodes in a shuttle export).
- Preview camera/ceiling work is creative visual work — follow brainstorming discipline before any new view tuning not covered by the tasks below.

## Proposed approach

1. Confirm the prototype fix on current worldgen main (no-op if already correct).
2. Close the structural validation gap in the upstream exporter so `load_from_documents` passes `StructuralPlanValidator` without bypass.
3. Regenerate the demo fixtures from the CLI (`--export-dir`) so `playable_generated_ship.tscn` renders worldgen output.
4. Implement Zomboid-style proximity ceiling fade as a runtime system on the loader output.
5. Add export golden tests + CLI stress to worldgen CI.

Each task is independently committable. Tasks 1-2 belong in worldgen; Tasks 3-4 in Synaptic Sea; Task 5 spans worldgen CI only.

---

## Task 1: Confirm worldgen export emits Dictionary prototype (verification-only)

**Objective:** Prove the prototype field is already correct on current main, closing next-step item #1 with zero code changes.

**Files:**
- Read-only: `crates/derelict_core/src/structural/export.rs` (worldgen clone)

**Step 1: Run export and check prototype type**

Use the existing preview test harness shape:

```gdscript
# /tmp/check_prototype.gd
extends SceneTree
func _initialize():
	assert(ClassDB.class_exists("DerelictGenerator"), "extension not loaded")
	var gen = ClassDB.instantiate("DerelictGenerator")
	var layout = JSON.parse_string(str(gen.export_layout_json(42, {"archetype_id": "shuttle", "intactness_override": 9500}, "ship_structural_v0")))
	assert(layout is Dictionary)
	var layout_doc := layout as Dictionary
	var proto: Variant = layout_doc.get("prototype", null)
	assert(proto is Dictionary, "prototype must be Dictionary, got: %s" % typeof(proto))
	assert(str((proto as Dictionary).get("start_room", "")) != "", "start_room present")
	print("PROTOTYPE OK: ", JSON.stringify(proto))
	quit(0)
```

Run: `cd /Users/christopherwilloughby/Code/the-synaptic-sea && /opt/homebrew/bin/godot --path . --script /tmp/check_prototype.gd`
Expected: `PROTOTYPE OK: {"start_room":"airlock_..." ...}`, exit 0.

**Step 2: If it fails**

Do NOT patch Synaptic Sea. Fix upstream: the Dictionary object literal at `crates/derelict_core/src/structural/export.rs:319-322` is the contract; confirm the local clone wasn't stale, then rebuild dylib (`cargo build -p derelict_godot --release`) and reinstall to `addons/derelict/bin/macos/`.

**Step 3: Commit**

None expected. If the upstream file needed changes: `git commit -m "fix: emit prototype as dictionary in layout export"` in the worldgen repo and push.

---

## Task 2: Align upstream export with StructuralPlanValidator (no bypass)

**Objective:** `load_from_documents` succeeds on unpatched exporter output — no `structural_plan_validated` injection, no `critical_path` erase.

**Files:**
- Modify: `crates/derelict_core/src/structural/export.rs` (worldgen)
- Test: `crates/derelict_godot/tests/export_golden.rs` (add a fail-closed load contract test)

**Step 1: Capture the actual validation failures**

Write a smoke that loads unmodified exporter output through the real validator path:

```gdscript
# /tmp/check_validation.gd — no bypasses
extends SceneTree
func _initialize():
	var gen = ClassDB.instantiate("DerelictGenerator")
	var layout = JSON.parse_string(str(gen.export_layout_json(42, {"archetype_id": "shuttle", "intactness_override": 9500}, "ship_structural_v0"))) as Dictionary
	var gameplay = JSON.parse_string(str(gen.export_gameplay_slice_json(42, {"archetype_id": "shuttle", "intactness_override": 9500}))) as Dictionary
	var kit = JSON.parse_string(FileAccess.get_file_as_string("res://data/kits/ship_structural_v0.json")) as Dictionary
	var loader = preload("res://scripts/procgen/generated_ship_loader.gd").new()
	root.add_child(loader)
	var ok := loader.load_from_documents(layout, kit, gameplay, true)
	if ok:
		print("VALIDATION PASS: raw worldgen output loads clean")
	else:
		print("VALIDATION FAIL (expected errors above)")
	quit(0 if ok else 1)
```

Run it. Record the exact error strings — the known-suspect set is `socket_bindings missing` and `topology reachability room missing` / `portal edge was compiled as non-portal`.

**Step 2: Fix exporter-side mismatches, not the validator**

The validator is the authoritative contract (Synaptic Sea owns it; it is deliberately fail-closed). Fix in `export.rs`:

- **socket_bindings:** `export.rs:265` currently emits an empty array; line 280-282 builds from `ship.…socket_bindings`. Confirm the source field is populated by the pipeline, and if the pipeline has none, generate floor-adjacency bindings (one east/west and south/north pairing per adjacent occupied-cell pair — same shape as already proven in this session: `placement_id: "floor:<cell_key>"`, `socket_id`, `neighbor_placement_id`, `neighbor_socket_id`).
- **critical_path reachability:** ensure every `critical_path` `{from, to}` pair resolves to occupied cells on both ends (the failure "topology reachability room missing" means a path endpoint's room id isn't present in occupancy). Trace `name_of(ship.entry_room)` / `name_of(ship.goal_room)` in export.rs against the room-id naming used in `occupancy`.
- **portal edge consistency:** every portal in `portals`/`room_links` must have a matching `placements` edge record with `"portal": true` at the same normalized edge_key. The min-normalization fix from this session (`min(cell, neighbor)` per axis pair) is the reference behavior.

Regenerate goldens after each behavior change: `UPDATE_GOLDEN=1 cargo test -p derelict_godot --test export_golden`.

**Step 3: Re-run the raw-load smoke**

Run the same `/tmp/check_validation.gd`. Expected: `VALIDATION PASS`, exit 0 — with no edits to `worldgen_live_preview.gd` bypass blocks yet (Task 4 scope).

**Step 4: Commit worldgen**

```
git add crates/derelict_core/src/structural/export.rs crates/derelict_godot/tests/
git commit -m "fix(structural): align export with Synaptic Sea StructuralPlanValidator contracts"
git push origin main
```

Then rebuild + reinstall the macOS dylib into the Synaptic Sea repo (`cargo build -p derelict_godot --release` → `cp target/release/libderelict_godot.dylib …/addons/derelict/bin/macos/`) and re-run the smoke.

---

## Task 3: Wire worldgen output into the demo scene via regenerated fixtures

**Objective:** `playable_generated_ship.tscn` renders worldgen v2 output without editing scene wiring — by regenerating the static fixture files the scene already loads.

**Files:**
- Modify: `data/procgen/smoke/seed_000017/layout.json` (Synaptic Sea)
- Modify: `data/procgen/smoke/seed_000017/gameplay_slice.json` (Synaptic Sea)
- Test: `scripts/validation/seed_determinism_smoke.gd`, `scripts/validation/procgen_structural_compiler_smoke.gd`

**Step 1: Regenerate fixtures via the CLI export path**

```bash
cd <worldgen clone>  # currently /tmp/worldgen-review.6uPfCg; prefer a durable checkout
cargo run -p derelict_cli -- --seed 17 --archetype shuttle --intactness 0.6 \
  --export-dir /Users/christopherwilloughby/Code/the-synaptic-sea/data/procgen/smoke/seed_000017 \
  --kit-id ship_structural_v0
```

Expected: `layout.json` and `gameplay_slice.json` land in the fixture directory.

**Step 2: Headless validation of the regenerated fixtures**

```
/opt/homebrew/bin/godot --headless --path /Users/christopherwilloughby/Code/the-synaptic-sea \
  --script res://scripts/validation/procgen_structural_compiler_smoke.gd
/opt/homebrew/bin/godot --path /Users/christopherwilloughby/Code/the-synaptic-sea \
  --scene res://scenes/procgen/playable_generated_ship.tscn
```

Expected for the scene: log marker `PLAYABLE SHIP READY` with non-zero `collision_shapes`, no `ERROR:` lines from `_fail_load`. (Scene must quit via its own flow or be killed after capture.)

**Step 3: Commit Synaptic Sea**

```
git add data/procgen/smoke/seed_000017/
git commit -m "feat: regenerate seed 17 demo fixture from worldgen v2 export"
```

If `seed_determinism_smoke.gd` fails because its golden hash references the old fixture, that test is asserting against the legacy generator's bytes — update the committed golden in the same commit and note the intentional change in the commit message.

---

## Task 4: Zomboid-style proximity ceiling fade

**Objective:** Ceilings near the player remain for sight-blocking; distant ceilings fade out for isometric readability — replacing the preview's global `Ceiling_` hide.

**Files:**
- Create: `scripts/procgen/ceiling_fade_controller.gd` (Synaptic Sea)
- Modify: `scripts/procgen/playable_generated_ship.gd` (wire controller after `_on_ship_loaded`; do NOT touch loader)
- Test: `scripts/validation/ceiling_fade_smoke.gd` (new)

**Step 1: Write the failing smoke**

```gdscript
# scripts/validation/ceiling_fade_smoke.gd
extends SceneTree
# Marker: CEILING FADE PASS near=N far=M
func _initialize() -> void:
	# load generated ship (existing loader path), spawn controller,
	# teleport player to a room center, step 10 frames, assert:
	#   - ceilings within radius are visible
	#   - ceilings outside radius are not visible (or faded alpha < 0.2)
	...
	quit(0)
```

Run: `godot --path . --script res://scripts/validation/ceiling_fade_smoke.gd`
Expected: FAIL (marker absent) before implementation.

**Step 2: Implement the controller (minimal)**

`scripts/procgen/ceiling_fade_controller.gd`:

```gdscript
extends Node
class_name CeilingFadeController

@export var fade_radius_m: float = 12.0
@export var fade_alpha: float = 0.15

var _ceilings: Array[Node3D] = []
var _player: Node3D

func configure(loader_root: Node3D, player: Node3D) -> void:
	_ceilings.clear()
	_collect(loader_root)
	_player = player

func _collect(node: Node) -> void:
	if node is Node3D and (node as Node3D).name.begins_with("Ceiling_"):
		_ceilings.append(node)
	for child in node.get_children():
		_collect(child)

func _process(_delta: float) -> void:
	if _player == null:
		return
	var pp := _player.global_position
	for c in _ceilings:
		var d := c.global_position.distance_to(pp)
		var near := d <= fade_radius_m
		c.visible = true
		_set_alpha(c, 1.0 if near else fade_alpha)

func _set_alpha(node: Node3D, alpha: float) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			var mesh_instance := child as MeshInstance3D
			var mat := mesh_instance.get_active_material(0)
			if mat != null:
				var duped := mat.duplicate() as StandardMaterial3D
				duped.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				var col := duped.albedo_color
				col.a = alpha
				duped.albedo_color = col
				mesh_instance.set_surface_override_material(0, duped)
```

Wire from `playable_generated_ship.gd` inside `_on_ship_loaded` (after player spawn): instantiate controller, `add_child`, call `configure(loader, player)`.

**Step 3: Verify pass**

Run ceiling fade smoke → `CEILING FADE PASS`. Then run the playable scene windowed and capture a viewport PNG to confirm isometric readability with near intact ceilings.

**Step 4: Commit**

```
git add scripts/procgen/ceiling_fade_controller.gd scripts/procgen/playable_generated_ship.gd scripts/validation/ceiling_fade_smoke.gd
git commit -m "feat: zomboid-style proximity ceiling fade for isometric readability"
```

Note for the implementer: `_set_alpha` duplicates materials per-call; if profiling shows cost, cache duplicated materials per ceiling node on first fade. That optimization is out of scope for the first pass (YAGNI).

---

## Task 5: Golden-hash + stress gates in worldgen CI

**Objective:** Any change to the layout/gameplay export surface or generation output fails CI.

**Files:**
- Modify: `.github/workflows/ci.yml` (worldgen)

**Step 1: Add the export golden + stress steps**

Extend the existing `test` job (after the existing `Tests` step):

```yaml
      - name: Export golden (Synaptic Sea contract)
        run: cargo test -p derelict_godot --test export_golden
      - name: Structural stress sweep (fail-closed)
        run: cargo run -p derelict_cli -- --stress --release
```

**Step 2: Also gate gdextension compile on the lint job**

```yaml
      - name: GDExtension check
        run: cargo check -p derelict_godot --all-targets
```

**Step 3: Verify locally before push**

```
cd <worldgen clone>
cargo test -p derelict_godot --test export_golden   # 5 passed
cargo run -p derelict_cli -- --stress               # exit 0
```

**Step 4: Commit**

```
git add .github/workflows/ci.yml
git commit -m "ci: gate export golden hashes and fail-closed structural stress"
git push origin main
```

---

## Files likely to change (summary)

- worldgen: `crates/derelict_core/src/structural/export.rs`, `crates/derelict_godot/tests/export_golden.rs` (+ `hashes.txt` regeneration), `.github/workflows/ci.yml`
- Synaptic Sea: `data/procgen/smoke/seed_000017/{layout.json,gameplay_slice.json}`, `scripts/procgen/ceiling_fade_controller.gd` (new), `scripts/procgen/playable_generated_ship.gd`, `scripts/validation/ceiling_fade_smoke.gd` (new), and (after Task 2 lands) remove the bypass block in `scripts/validation/worldgen_live_preview.gd`

## Tests / validation

- `cargo test -p derelict_godot --test export_golden` — 5 passed
- `cargo test --workspace` — 49 passed
- `cargo run -p derelict_cli -- --stress` — 1,800 ships, exit 0
- `godot --headless --path . --script res://scripts/validation/procgen_structural_compiler_smoke.gd` — `PROCGEN_STRUCTURAL_COMPILER_PASS`
- `/tmp/check_validation.gd` — `VALIDATION PASS` on raw export (Task 2 gate)
- `res://scripts/validation/ceiling_fade_smoke.gd` — `CEILING FADE PASS`
- Playable scene run — `PLAYABLE SHIP READY` marker, no loader `_fail_load` errors

## Risks, tradeoffs, and open questions

- **Cross-repo versioning:** the dylib is committed in Synaptic Sea's repo. Rebuild/reinstall on every worldgen export change or scenes run stale. Consider documenting the rebuild step in Synaptic Sea's CLAUDE.md. (Open: automate via a `tools/` script later — YAGNI for now.)
- **Fixture regeneration determinism:** regenerating `seed_000017` changes its bytes; if `seed_determinism_smoke.gd` golden hashes the old generator output, update goldens in the same commit and call it out — do not silently churn.
- **Validator authority:** Task 2 treats `StructuralPlanValidator` as the contract and fixes the exporter. If a validator rule is actually wrong for multi-deck semantics, that's an ADR decision in Synaptic Sea (`docs/game/adr/`), not an exporter hack.
- **Ceiling fade performance:** per-frame material duplication is wasteful at 123+ nodes. First pass is correctness; cache on regression evidence only.
- **Scene wiring vs fixtures:** Task 3 chose fixture regeneration over a new scene because it exercises the exact production path (`load_from_paths`) players hit. The travel path (`generate_from_seed` → `DerelictGenerator`) continues to use in-memory `load_from_documents`.
