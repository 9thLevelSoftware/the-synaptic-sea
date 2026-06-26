# Live Suit→Oxygen Wiring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the worn EVA hardsuit actually reduce live breach oxygen drain by wiring `EquipmentState.get_oxygen_drain_multiplier()` into `OxygenState` through a new model seam, stacking multiplicatively with the portable-oxygen-pump multiplier.

**Architecture:** `OxygenState` gains `apply_equipment_summary({"drain_multiplier": …})` mirroring its existing `apply_inventory_summary`. `_compute_drain_multiplier()` returns `inventory_mult × equipment_mult`, still hard-gated to 1.0 when the breach is sealed/closed. The coordinator's `_refresh_oxygen_state` calls the new seam every frame with `equipment_state.get_oxygen_drain_multiplier()` before `tick`. No persistence change (equipment already round-trips; the multiplier is recomputed live).

**Tech Stack:** Godot 4.6.2, typed GDScript, headless `--script` SceneTree validation smokes.

**Spec:** `docs/superpowers/specs/2026-06-24-phase7-suit-oxygen-wiring-design.md`

## Global Constraints

- **Validation is done-ness.** Every smoke prints exactly one `... PASS ...` marker line (the contract). Trust the marker, not the exit code (`--script` can exit 0 on parse/load errors).
- **Smoke style:** mirror `oxygen_state_smoke.gd` — fail via `push_error("… FAIL reason=…")` + `quit(1)` and early-return; print the PASS marker + `quit(0)` only at the end. Do NOT rely on `assert()` to abort (it does not abort a SceneTree `--script` run).
- **Headless class-cache:** construct new models via their established pattern — `EquipmentStateScript.create()` and `OxygenStateScript.new()` from `preload(...)` consts. Do not depend on `class_name` globals inside new smokes.
- **Multiplicative stacking, breach-gated:** combined breach multiplier = `inventory_mult × equipment_mult`; forced to `1.0` when `breach_sealed or not breach_open`.
- **No persistence change:** `OxygenState.apply_summary` must NOT restore the equipment multiplier (recomputed live each frame, symmetric with the inventory summary).
- **Authored values are fixed:** `hardsuit` = `oxygen_drain` 0.75; `portable_oxygen_pump` = 0.5. Do not re-tune (balance is sub-project D). No HUD changes (sub-project C).
- **Full-bundle runs:** `git stash push -- project.godot` before the bundle/Gate-1, `git stash pop` after. NEVER commit `project.godot`, `.godot/`, `*.uid`, or `addons/`. Stage only explicit script/doc paths.
- **Allowlisted baseline noise** (ignore): `Capture not registered: 'gdaimcp'.` and `ObjectDB instances leaked at exit`. Single-run-only drift (absent in the bundle): `Unrecognized UID`, `Resource file not found: res://`, `Failed to instantiate an autoload 'MCPRuntime'`.
- **Commits:** Conventional Commits; end each commit message with `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.

## File Structure

- `scripts/systems/oxygen_state.gd` (modify) — add the equipment seam + combined multiplier + summary field.
- `scripts/procgen/playable_generated_ship.gd` (modify) — one wiring call in `_refresh_oxygen_state`.
- `scripts/validation/oxygen_equipment_drain_smoke.gd` (create) — pure cross-model smoke.
- `scripts/validation/main_playable_slice_suit_oxygen_smoke.gd` (create) — main-scene wiring smoke.
- `docs/game/adr/0024-suit-oxygen-wiring.md` (create) — decision record.
- `docs/game/06_validation_plan.md` (modify) — register 2 smokes, 115 → 117.
- `docs/game/09_system_roadmap.md` (modify) — note the wiring done.

---

### Task 1: OxygenState equipment seam + combined multiplier (+ model smoke)

**Files:**
- Modify: `scripts/systems/oxygen_state.gd`
- Create (test): `scripts/validation/oxygen_equipment_drain_smoke.gd`

**Interfaces:**
- Consumes: `EquipmentState.create()` and `EquipmentState.equip(item_id) -> Dictionary` / `get_oxygen_drain_multiplier() -> float` (existing, unchanged); `OxygenState.configure/tick/seal_breach/apply_inventory_summary/get_summary` (existing).
- Produces (new on `OxygenState`):
  - `apply_equipment_summary(summary: Dictionary) -> void`
  - `_summary_drain_mult(summary: Dictionary) -> float` (private helper)
  - `get_summary()` gains key `"equipment_drain_multiplier": float`; existing `"drain_multiplier"` now equals the combined `inventory × equipment` (still gated to 1.0 sealed/closed).

- [ ] **Step 1: Write the failing test** — create `scripts/validation/oxygen_equipment_drain_smoke.gd`:

```gdscript
extends SceneTree

## Cross-model smoke for the suit->oxygen wiring (Phase 7 sub-project B):
## EquipmentState.get_oxygen_drain_multiplier() feeds OxygenState via
## apply_equipment_summary, stacking multiplicatively with the inventory
## (pump) multiplier and gated to 1.0 when the breach is sealed/closed.

const OxygenStateScript := preload("res://scripts/systems/oxygen_state.gd")
const EquipmentStateScript := preload("res://scripts/systems/equipment_state.gd")

func _initialize() -> void:
	# --- EquipmentState side: worn-suit multiplier (already implemented) ---
	var eq = EquipmentStateScript.create()
	if eq.get_oxygen_drain_multiplier() != 1.0:
		_fail("empty equipment should be neutral 1.0, got %s" % str(eq.get_oxygen_drain_multiplier()))
		return
	eq.equip("hardsuit")
	if eq.get_oxygen_drain_multiplier() != 0.75:
		_fail("hardsuit should give 0.75, got %s" % str(eq.get_oxygen_drain_multiplier()))
		return

	# --- OxygenState side: combined multiplier in an open, unsealed breach ---
	var ox = OxygenStateScript.new()
	ox.configure({
		"zone_ids": ["corridor_to_reactor"],
		"max_oxygen": 100.0,
		"drain_rate": 6.0,
		"regen_rate": 0.0,
		"recovery_threshold": 30.0,
		"safe_threshold": 35.0,
	})

	# Suit only (inventory neutral): effective drain = 6.0 * 0.75 = 4.5
	ox.apply_equipment_summary({"drain_multiplier": eq.get_oxygen_drain_multiplier()})
	ox.tick(1.0, true)
	var suit_only: Dictionary = ox.get_summary()
	if absf(float(suit_only.get("effective_drain_rate", -1.0)) - 4.5) > 0.001:
		_fail("suit-only effective_drain_rate should be 4.5, got %s" % str(suit_only.get("effective_drain_rate", -1.0)))
		return
	if absf(float(suit_only.get("equipment_drain_multiplier", -1.0)) - 0.75) > 0.001:
		_fail("equipment_drain_multiplier should be 0.75, got %s" % str(suit_only.get("equipment_drain_multiplier", -1.0)))
		return
	if absf(float(suit_only.get("drain_multiplier", -1.0)) - 0.75) > 0.001:
		_fail("suit-only combined drain_multiplier should be 0.75, got %s" % str(suit_only.get("drain_multiplier", -1.0)))
		return

	# Suit + pump: 0.75 * 0.5 = 0.375 -> effective 6.0 * 0.375 = 2.25
	ox.apply_inventory_summary({"drain_multiplier": 0.5})
	ox.tick(1.0, true)
	var combined: Dictionary = ox.get_summary()
	if absf(float(combined.get("drain_multiplier", -1.0)) - 0.375) > 0.001:
		_fail("suit+pump combined drain_multiplier should be 0.375, got %s" % str(combined.get("drain_multiplier", -1.0)))
		return
	if absf(float(combined.get("effective_drain_rate", -1.0)) - 2.25) > 0.001:
		_fail("suit+pump effective_drain_rate should be 2.25, got %s" % str(combined.get("effective_drain_rate", -1.0)))
		return

	# Sealing the breach forces the multiplier back to 1.0 (drain suppressed there).
	ox.seal_breach("corridor_to_reactor")
	var sealed: Dictionary = ox.get_summary()
	if absf(float(sealed.get("drain_multiplier", -1.0)) - 1.0) > 0.001:
		_fail("sealed breach should force drain_multiplier to 1.0, got %s" % str(sealed.get("drain_multiplier", -1.0)))
		return

	print("OXYGEN EQUIPMENT DRAIN SMOKE PASS suit=0.75 combined=0.375")
	quit(0)

func _fail(reason: String) -> void:
	push_error("OXYGEN EQUIPMENT DRAIN SMOKE FAIL reason=%s" % reason)
	quit(1)
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/oxygen_equipment_drain_smoke.gd 2>&1 | grep -E "PASS|FAIL|SCRIPT ERROR"
```
Expected: a `FAIL` line (e.g. `equipment_drain_multiplier should be 0.75` — the key does not exist yet, so `get(..., -1.0)` returns -1.0) and NO PASS marker. (`apply_equipment_summary` is also undefined; if the run surfaces a `SCRIPT ERROR`/missing-method instead, that equally confirms RED.)

- [ ] **Step 3: Add the equipment-summary field** in `scripts/systems/oxygen_state.gd`. After the existing line `var effective_drain_rate: float = DEFAULT_DRAIN_RATE` (the `_inventory_summary` block), add:

```gdscript
# Equipment summary cache populated by apply_equipment_summary(...). The worn
# suit's oxygen-drain multiplier stacks multiplicatively with the inventory
# (tool) multiplier; like the inventory summary it is recomputed live each
# frame by the coordinator and is intentionally not restored by apply_summary.
var _equipment_summary: Dictionary = {}
```

- [ ] **Step 4: Reset it in `configure()`** — find the line `_inventory_summary = {}` inside `configure(...)` and add the equipment reset immediately after it:

```gdscript
	_inventory_summary = {}
	_equipment_summary = {}
```

- [ ] **Step 5: Replace `_compute_drain_multiplier()`** with the combined version + helper. Replace the entire existing function:

```gdscript
func _compute_drain_multiplier() -> float:
	if breach_sealed or not breach_open:
		return 1.0
	var summary_multiplier: Variant = _inventory_summary.get("drain_multiplier", 1.0)
	if summary_multiplier is float or summary_multiplier is int:
		return float(summary_multiplier)
	return 1.0
```

with:

```gdscript
func _compute_drain_multiplier() -> float:
	if breach_sealed or not breach_open:
		return 1.0
	return _summary_drain_mult(_inventory_summary) * _summary_drain_mult(_equipment_summary)

# Reads a numeric "drain_multiplier" from a source summary (inventory or
# equipment), defaulting to the neutral 1.0 when absent or non-numeric.
func _summary_drain_mult(summary: Dictionary) -> float:
	var value: Variant = summary.get("drain_multiplier", 1.0)
	if value is float or value is int:
		return float(value)
	return 1.0
```

- [ ] **Step 6: Add the `apply_equipment_summary` seam** immediately after the existing `apply_inventory_summary(...)` function:

```gdscript
# Public seam: the scene coordinator calls this before each tick so the worn
# equipment's oxygen-drain multiplier (EquipmentState.get_oxygen_drain_multiplier())
# is current when the drain multiplier is evaluated. Stacks multiplicatively with
# the inventory (tool) multiplier; both are gated to 1.0 when the breach is
# sealed/closed by _compute_drain_multiplier().
func apply_equipment_summary(summary: Dictionary) -> void:
	_equipment_summary = summary.duplicate(true)
```

- [ ] **Step 7: Expose the equipment component in `get_summary()`** — find the line `"drain_multiplier": _compute_drain_multiplier(),` and add directly beneath it:

```gdscript
		"drain_multiplier": _compute_drain_multiplier(),
		"equipment_drain_multiplier": _summary_drain_mult(_equipment_summary),
```

- [ ] **Step 8: Run the test to verify it passes**

Run:
```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/oxygen_equipment_drain_smoke.gd 2>&1 | grep -E "PASS|FAIL|Assertion failed|SCRIPT ERROR|Parse Error"
```
Expected: `OXYGEN EQUIPMENT DRAIN SMOKE PASS suit=0.75 combined=0.375` and no FAIL/error line (drift `ERROR:` lines for UID/autoload are allowlisted single-run noise).

- [ ] **Step 9: Confirm no regression in the existing oxygen + equipment smokes**

Run:
```bash
for s in oxygen_state_smoke equipment_state_smoke hazard_contract_smoke; do
  "$GODOT" --headless --path "$ROOT" --script "res://scripts/validation/$s.gd" 2>&1 | grep -E "PASS|FAIL|Assertion failed|SCRIPT ERROR"
done
```
Expected: `OXYGEN STATE PASS …`, `EQUIPMENT STATE SMOKE PASS …`, `HAZARD CONTRACT … PASS …` — all present, no FAIL.

- [ ] **Step 10: Commit**

```bash
git add scripts/systems/oxygen_state.gd scripts/validation/oxygen_equipment_drain_smoke.gd
git commit -m "feat(oxygen): apply_equipment_summary seam + combined drain multiplier

OxygenState now stacks the worn-equipment oxygen-drain multiplier
multiplicatively with the inventory (pump) multiplier, breach-gated to 1.0.
New cross-model smoke proves suit=0.75, suit+pump=0.375, sealed=1.0.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Coordinator wiring + main-scene smoke

**Files:**
- Modify: `scripts/procgen/playable_generated_ship.gd` (in `_refresh_oxygen_state`)
- Create (test): `scripts/validation/main_playable_slice_suit_oxygen_smoke.gd`

**Interfaces:**
- Consumes: `OxygenState.apply_equipment_summary({"drain_multiplier": float})` (from Task 1); coordinator members `equipment_state` (`EquipmentState`), `inventory_state` (`InventoryState`), `oxygen_state`; coordinator methods `get_oxygen_summary() -> Dictionary`, `loader.has_loaded_ship() -> bool`; `EquipmentState.equip("hardsuit")`, `EquipmentState.slots` (Dictionary), `InventoryState.add_tool/has_tool`.
- Produces: live behavior — `get_oxygen_summary()["drain_multiplier"]` reflects `inventory × equipment` every frame.

- [ ] **Step 1: Write the failing test** — create `scripts/validation/main_playable_slice_suit_oxygen_smoke.gd`:

```gdscript
extends SceneTree

## Main-scene smoke for the live suit->oxygen wiring (Phase 7 sub-project B):
## proves _refresh_oxygen_state folds EquipmentState.get_oxygen_drain_multiplier()
## into OxygenState every frame. The breach is open at slice start, so the drain
## multiplier in get_oxygen_summary() reflects inventory(tool) * equipment(worn),
## independent of player position (the multiplier is gated by breach state only).

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const READY_TIMEOUT_FRAMES: int = 300
const SETTLE_FRAMES: int = 5

var main_node: Node
var playable: PlayableGeneratedShip
var frame_count: int = 0
var phase: String = "waiting_ready"
var phase_frames: int = 0
var finished: bool = false
var base_mult: float = 1.0

func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	if main_node == null:
		_fail("could not instantiate main scene")
		return
	get_root().add_child(main_node)
	process_frame.connect(_on_process_frame)

func _on_process_frame() -> void:
	if finished:
		return
	frame_count += 1
	if playable == null:
		playable = _find_playable(main_node)
	if playable == null or playable.loader == null or not playable.loader.has_loaded_ship():
		if frame_count > READY_TIMEOUT_FRAMES:
			_fail("playable did not become ready")
		return
	match phase:
		"waiting_ready":
			_setup()
		"settle_base":
			_capture_base()
		"settle_suit":
			_check_suit()
		"settle_pump":
			_check_combined()

func _setup() -> void:
	if playable.get("oxygen_state") == null:
		_fail("oxygen_state null")
		return
	if playable.get("equipment_state") == null:
		_fail("equipment_state null")
		return
	if playable.get("inventory_state") == null:
		_fail("inventory_state null")
		return
	var initial: Dictionary = playable.get_oxygen_summary()
	if not bool(initial.get("breach_open", false)):
		_fail("breach should be open at slice start")
		return
	if bool(initial.get("breach_sealed", true)):
		_fail("breach should not be sealed at slice start")
		return
	# Deterministic baseline: remove any worn equipment so the multiplier reflects
	# inventory-only (the coordinator itself clears slots this way on reload).
	playable.equipment_state.slots.clear()
	phase = "settle_base"
	phase_frames = 0

func _capture_base() -> void:
	phase_frames += 1
	if phase_frames < SETTLE_FRAMES:
		return
	base_mult = float(playable.get_oxygen_summary().get("drain_multiplier", -1.0))
	if base_mult <= 0.0:
		_fail("baseline drain_multiplier should be >0, got %s" % str(base_mult))
		return
	# Equip the suit on the same EquipmentState the coordinator owns.
	var res: Dictionary = playable.equipment_state.equip("hardsuit")
	if not bool(res.get("ok", false)):
		_fail("equipping hardsuit failed")
		return
	phase = "settle_suit"
	phase_frames = 0

func _check_suit() -> void:
	phase_frames += 1
	if phase_frames < SETTLE_FRAMES:
		return
	var s: Dictionary = playable.get_oxygen_summary()
	var suit_mult: float = float(s.get("drain_multiplier", -1.0))
	if absf(suit_mult - base_mult * 0.75) > 0.001:
		_fail("after equipping suit drain_multiplier should be base*0.75=%s, got %s" % [str(base_mult * 0.75), str(suit_mult)])
		return
	if absf(float(s.get("equipment_drain_multiplier", -1.0)) - 0.75) > 0.001:
		_fail("equipment_drain_multiplier should be 0.75, got %s" % str(s.get("equipment_drain_multiplier", -1.0)))
		return
	# Add the pump so the inventory component is deterministically 0.5.
	playable.inventory_state.add_tool("portable_oxygen_pump")
	if not playable.inventory_state.has_tool("portable_oxygen_pump"):
		_fail("pump not present after add_tool")
		return
	phase = "settle_pump"
	phase_frames = 0

func _check_combined() -> void:
	phase_frames += 1
	if phase_frames < SETTLE_FRAMES:
		return
	var c: Dictionary = playable.get_oxygen_summary()
	var combined: float = float(c.get("drain_multiplier", -1.0))
	if absf(combined - 0.375) > 0.001:
		_fail("suit+pump combined drain_multiplier should be 0.375, got %s" % str(combined))
		return
	finished = true
	print("SUIT OXYGEN SLICE SMOKE PASS suit_mult=0.75 combined_mult=0.375")
	_cleanup_and_quit(0)

func _find_playable(node: Node) -> PlayableGeneratedShip:
	if node is PlayableGeneratedShip:
		return node as PlayableGeneratedShip
	for child in node.get_children():
		var found: PlayableGeneratedShip = _find_playable(child)
		if found != null:
			return found
	return null

func _fail(reason: String) -> void:
	if finished:
		return
	finished = true
	push_error("SUIT OXYGEN SLICE SMOKE FAIL reason=%s" % reason)
	_cleanup_and_quit(1)

func _cleanup_and_quit(code: int) -> void:
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_suit_oxygen_smoke.gd 2>&1 | grep -E "PASS|FAIL|SCRIPT ERROR"
```
Expected: `SUIT OXYGEN SLICE SMOKE FAIL reason=after equipping suit drain_multiplier should be base*0.75=… got <base>` — because the coordinator does not yet fold equipment into oxygen, so equipping the suit leaves the multiplier unchanged. No PASS marker.

- [ ] **Step 3: Add the wiring** in `scripts/procgen/playable_generated_ship.gd`. In `_refresh_oxygen_state`, find:

```gdscript
	if inventory_state != null:
		oxygen_state.apply_inventory_summary(inventory_state.get_summary())
```

and add, immediately after that `if` block:

```gdscript
	if equipment_state != null:
		oxygen_state.apply_equipment_summary(
			{"drain_multiplier": equipment_state.get_oxygen_drain_multiplier()})
```

(It precedes both the `force_initial` branch and the per-tick branch, so it applies on every path.)

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_suit_oxygen_smoke.gd 2>&1 | grep -E "PASS|FAIL|Assertion failed|SCRIPT ERROR|Parse Error"
```
Expected: `SUIT OXYGEN SLICE SMOKE PASS suit_mult=0.75 combined_mult=0.375` and no FAIL/error line.

- [ ] **Step 5: Confirm no regression in the existing main-scene hazard + inventory-UI smokes**

Run:
```bash
for s in main_playable_slice_hazard_smoke main_playable_slice_inventory_ui_smoke; do
  "$GODOT" --headless --path "$ROOT" --script "res://scripts/validation/$s.gd" 2>&1 | grep -E "PASS|FAIL|Assertion failed|SCRIPT ERROR"
done
```
Expected: `MAIN PLAYABLE HAZARD PASS …` and `INVENTORY UI SLICE SMOKE PASS …`, no FAIL.

- [ ] **Step 6: Commit**

```bash
git add scripts/procgen/playable_generated_ship.gd scripts/validation/main_playable_slice_suit_oxygen_smoke.gd
git commit -m "feat(oxygen): wire worn-suit multiplier into the live oxygen tick

_refresh_oxygen_state now applies equipment_state.get_oxygen_drain_multiplier()
to OxygenState before each tick, so equipping the hardsuit reduces live breach
drain (0.75; 0.375 with the pump). Main-scene smoke proves the end-to-end path.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: ADR + bundle registration + roadmap

**Files:**
- Create: `docs/game/adr/0024-suit-oxygen-wiring.md`
- Modify: `docs/game/06_validation_plan.md`
- Modify: `docs/game/09_system_roadmap.md`

**Interfaces:**
- Consumes: the two PASS markers from Tasks 1–2 (`OXYGEN EQUIPMENT DRAIN SMOKE PASS`, `SUIT OXYGEN SLICE SMOKE PASS`).
- Produces: full regression bundle green at `commands=117`.

- [ ] **Step 1: Write the ADR** — create `docs/game/adr/0024-suit-oxygen-wiring.md`:

```markdown
# ADR-0024: Live Suit→Oxygen Wiring (Phase 7 sub-project B)

Date: 2026-06-24
Status: Accepted

## Context
The `hardsuit` declared an `oxygen_drain` effect (0.75) and
`EquipmentState.get_oxygen_drain_multiplier()` already computed the product of
worn `oxygen_drain` effects, but that value never reached `OxygenState`, so
wearing the suit had no effect on live breach drain. The only gap was the
coordinator seam.

## Decisions
1. **Separate model seam** `OxygenState.apply_equipment_summary({"drain_multiplier": …})`
   mirrors `apply_inventory_summary`; the combination rule lives in the pure
   model, not the coordinator. `_inventory_summary` keeps meaning exactly what
   `InventoryState` reported.
2. **Multiplicative stacking** — effective breach multiplier =
   `inventory_mult × equipment_mult`, hard-gated to 1.0 when the breach is
   sealed/closed (drain is suppressed there anyway).
3. **No new persistence** — the equipment multiplier is recomputed live each
   frame from `equipment_state` (which already persists via `player_equipment`);
   `apply_summary` does not restore it (symmetric with the inventory summary).
4. The coordinator `_refresh_oxygen_state` applies the equipment summary before
   `tick` on every frame.

## Consequences
Equipping the hardsuit reduces live breach drain (×0.75; ×0.375 with the
portable oxygen pump). `OxygenState.get_summary()` exposes both the combined
`drain_multiplier` and the `equipment_drain_multiplier` component. Deferred:
HUD surfacing of the suit contribution (sub-project C); re-tuning the 0.75
value (sub-project D); suit air-supply depletion (future system).
```

- [ ] **Step 2: Register both smokes in the bundle** — in `docs/game/06_validation_plan.md`, find the line:

```bash
run_clean 'inventory widget layer' 'INVENTORY WIDGET SMOKE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/inventory_widget_smoke.gd
echo 'SYNAPTIC_SEA REGRESSION PASS commands=115 clean_output=true'
```

and replace it with:

```bash
run_clean 'inventory widget layer' 'INVENTORY WIDGET SMOKE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/inventory_widget_smoke.gd
run_clean 'oxygen+equipment drain' 'OXYGEN EQUIPMENT DRAIN SMOKE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/oxygen_equipment_drain_smoke.gd
run_clean 'suit oxygen slice' 'SUIT OXYGEN SLICE SMOKE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_suit_oxygen_smoke.gd
echo 'SYNAPTIC_SEA REGRESSION PASS commands=117 clean_output=true'
```

Also update any prose line in that file that states the command count (search for `commands=115` / "115" smoke-count references) to `117`.

- [ ] **Step 3: Update the roadmap** — in `docs/game/09_system_roadmap.md`, in the System 6 row, append to the built-evidence list (before the `*Remaining:*` marker): a clause noting `live suit→oxygen wiring (EquipmentState oxygen-drain multiplier folded into OxygenState via apply_equipment_summary, multiplicative with the pump) — ADR-0024 ✅`. Remove suit→oxygen wiring from any *Remaining:* phrasing if present (it is not currently listed, so no removal is expected).

- [ ] **Step 4: Run the FULL regression bundle** (stash drift first)

```bash
cd "C:/Users/dasbl/Documents/The Synaptic Sea"
git stash push -- project.godot
export GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
export ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
bash <(awk '/^## Regression bundle/{f=1} f && /^```bash$/ {c=1; next} f && c && /^```$/ {exit} f && c {print}' docs/game/06_validation_plan.md) 2>&1 | tail -6
git stash pop
```
Expected final line: `SYNAPTIC_SEA REGRESSION PASS commands=117 clean_output=true`.

- [ ] **Step 5: Commit**

```bash
git add docs/game/adr/0024-suit-oxygen-wiring.md docs/game/06_validation_plan.md docs/game/09_system_roadmap.md
git commit -m "docs(oxygen): ADR-0024 + register suit-oxygen smokes (115->117) + roadmap

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Notes for the implementer

- The two new smokes are pure additions; the only production edits are the `OxygenState` model (Task 1) and one `if` block in the coordinator (Task 2). Slice-1/slice-2 inventory smokes are untouched and must stay green.
- If `_refresh_oxygen_state` differs slightly from the snippet (line numbers drift), match on the `apply_inventory_summary(inventory_state.get_summary())` call — that is the stable anchor.
- Do not add a HUD/status-line for the suit here; `OxygenState.get_summary()` exposing `equipment_drain_multiplier` is the sub-project-C seam.
- **Coverage split (intentional):** the spec floats "measured oxygen drop over the tick" for the scene smoke; instead the scene smoke asserts the live `drain_multiplier` deterministically (frame-timed drop measurement is flaky and already proven loosely by `main_playable_slice_hazard_smoke`), while the **model smoke** asserts the exact reduced `effective_drain_rate` (4.5 suit-only, 2.25 suit+pump). Between them, "drain is actually reduced" is covered without timing flakiness.
