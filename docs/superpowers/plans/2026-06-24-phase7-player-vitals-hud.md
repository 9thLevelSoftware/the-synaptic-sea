# Player Vitals HUD Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Surface three live readouts the models already compute but never show — active repair progress/blocked, the worn-suit oxygen contribution, and the Heavy-Load encumbrance penalty — on a new dedicated bottom-left HUD panel.

**Architecture:** A pure `PlayerVitalsModel` (`RefCounted`) owns the formatting/warning rules and a transient blocked-message timer; a `PlayerVitalsPanel` (`Control`, bottom-left) renders pre-formatted lines; the coordinator (`playable_generated_ship.gd`) bridges the four sources (oxygen summary, inventory load, channeling `RepairPoint`, `repair_blocked` signal) into the model each frame via its existing `_refresh_oxygen_state` cadence. Purely additive — the objective tracker and `get_combined_system_status_lines()` are untouched.

**Tech Stack:** Godot 4.6.2, typed GDScript, headless `--script` validation smokes.

## Global Constraints

- **ASCII-only HUD output.** No `₂`/`−`/`…`/`·`. Exact strings: `Oxygen: 87 (BREACH)`, `Suit: -25% O2 drain`, `Load: 112% HEAVY (-30% move)`, `Repairing 47%`, `Repair blocked: missing parts`.
- **Purely additive.** Do NOT modify `objective_tracker.gd`, `_combined_system_status_lines()`, or `get_combined_system_status_lines()`. Every existing smoke must stay green unchanged.
- **No persistence.** `PlayerVitalsModel` is live-derived; it has no `get_summary`/`apply_summary` and is NOT a hazard (no ADR-0005 contract).
- **Smoke style:** `extends SceneTree`; fail via `push_error(...)` + `quit(1)` + early `return` (NOT `assert` — `assert` does not abort a `--script` SceneTree run); on success `print` the single PASS marker then `quit(0)`. Construct models via preload consts (`VitalsModelScript.new()`), never `class_name` globals (headless class-cache is unreliable).
- **Trust the PASS marker, not the exit code** (`--script` can exit 0 on parse/load errors). Always confirm the marker line is present and no unexpected `ERROR:`/`WARNING:` appears.
- **Allowlisted baseline noise (ignore):** `ERROR: Capture not registered: 'gdaimcp'.` and `WARNING: ObjectDB instances leaked at exit ...`. Any other `ERROR:`/`WARNING:` blocks completion.
- **Never stage/commit** `project.godot`, `.godot/`, `*.uid`, or `addons/`. Use selective `git add <explicit paths>` only.
- **Full regression bundle** must end `SYNAPSE_SEA REGRESSION PASS commands=119 clean_output=true`; stash `project.godot` before the run and pop after (it carries local MCPRuntime-autoload drift that breaks headless).
- Godot binary: `C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe`. Project root: `C:/Users/dasbl/Documents/The Synaptic Sea`. Branch: `phase7-vitals-hud`.

---

## File Structure

| File | Responsibility |
|---|---|
| `scripts/systems/player_vitals_model.gd` (new) | Pure `RefCounted`. Turns oxygen/inventory/repair inputs into ASCII status lines; owns the transient blocked-message timer. |
| `scripts/validation/player_vitals_model_smoke.gd` (new) | Pure-model smoke for the formatting rules. |
| `scripts/ui/player_vitals_panel.gd` (new) | `Control`. Bottom-left styled panel; renders `set_status_lines()`. Presentation only. |
| `scripts/procgen/playable_generated_ship.gd` (modify) | Build panel + model under `hud_layer`; connect `repair_blocked`; feed the model each frame; expose `get_player_vitals_lines()`. |
| `scripts/validation/main_playable_slice_vitals_hud_smoke.gd` (new) | Main-scene smoke: panel structure + live content feed end-to-end. |
| `docs/game/adr/0025-player-vitals-hud.md` (new) | Records the panel, the pure formatting seam, the additive stance, deferred follow-ups. |
| `docs/game/06_validation_plan.md` (modify) | Register both smokes; bump `commands=117` → `119`. |
| `docs/game/09_system_roadmap.md` (modify) | Note the player-vitals HUD under System 6 / Phase 7. |

Reference run command for a single smoke (used throughout):

```bash
GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/<smoke_name>.gd 2>&1
```

---

### Task 1: PlayerVitalsModel + pure-model smoke

**Files:**
- Create: `scripts/systems/player_vitals_model.gd`
- Test: `scripts/validation/player_vitals_model_smoke.gd`

**Interfaces:**
- Consumes: nothing (leaf model).
- Produces (relied on by Task 2):
  - `PlayerVitalsModel.new()` (via `preload`)
  - `apply_oxygen_summary(summary: Dictionary) -> void` — reads keys `oxygen` (float), `breach_open`/`breach_sealed` (bool), `recovery_threshold` (float, default 30.0), `equipment_drain_multiplier` (float, default 1.0).
  - `apply_inventory_load(load_ratio: float, move_multiplier: float) -> void`
  - `set_repair_progress(channeling: bool, progress: float) -> void`
  - `notify_repair_blocked(reason: String) -> void`
  - `tick(delta: float) -> void`
  - `get_status_lines() -> PackedStringArray`
  - `get_vitals_summary() -> Dictionary`
  - `const BLOCKED_DISPLAY_SECONDS: float = 3.0`

**Bundle note:** Do NOT register this smoke in `06_validation_plan.md` here — Task 3 registers BOTH new smokes together (117 → 119). This split is intentional; a reviewer should not flag the missing bundle entry as a Task 1 defect.

- [ ] **Step 1: Write the failing smoke**

Create `scripts/validation/player_vitals_model_smoke.gd`:

```gdscript
extends SceneTree

## Pure-model smoke for the player-vitals HUD formatting (Phase 7 sub-project C):
## PlayerVitalsModel turns oxygen/inventory/repair state into ASCII status lines,
## including the ADR-0024 suit contribution, the Encumbrance Heavy-Load penalty,
## and the transient repair-blocked message (delta-driven clear).

const VitalsModelScript := preload("res://scripts/systems/player_vitals_model.gd")

func _initialize() -> void:
	var m = VitalsModelScript.new()

	# Oxygen open + suit worn -> Oxygen line with (BREACH) + Suit -25% line.
	m.apply_oxygen_summary({
		"oxygen": 87.0,
		"breach_open": true,
		"breach_sealed": false,
		"recovery_threshold": 30.0,
		"equipment_drain_multiplier": 0.75,
	})
	m.apply_inventory_load(0.78, 1.0)
	var lines: PackedStringArray = m.get_status_lines()
	if not _has(lines, "Oxygen: 87 (BREACH)"):
		_fail("expected 'Oxygen: 87 (BREACH)', got %s" % str(lines))
		return
	if not _has(lines, "Suit: -25% O2 drain"):
		_fail("expected suit line, got %s" % str(lines))
		return
	if not _has(lines, "Load: 78%"):
		_fail("expected 'Load: 78%%', got %s" % str(lines))
		return
	if _has_prefix(lines, "Repairing") or _has_prefix(lines, "Repair blocked"):
		_fail("no repair line expected when idle, got %s" % str(lines))
		return

	# Sealed breach -> (SEALED), and no suit line when the multiplier is neutral.
	m.apply_oxygen_summary({
		"oxygen": 87.0, "breach_open": true, "breach_sealed": true,
		"recovery_threshold": 30.0, "equipment_drain_multiplier": 1.0,
	})
	lines = m.get_status_lines()
	if not _has(lines, "Oxygen: 87 (SEALED)"):
		_fail("expected '(SEALED)', got %s" % str(lines))
		return
	if _has(lines, "Suit: -25% O2 drain"):
		_fail("no suit line expected at equipment_drain_multiplier==1.0, got %s" % str(lines))
		return

	# Low oxygen -> LOW suffix at/under the recovery threshold.
	m.apply_oxygen_summary({
		"oxygen": 20.0, "breach_open": false, "breach_sealed": false,
		"recovery_threshold": 30.0, "equipment_drain_multiplier": 1.0,
	})
	if not _has(m.get_status_lines(), "Oxygen: 20 LOW"):
		_fail("expected 'Oxygen: 20 LOW', got %s" % str(m.get_status_lines()))
		return

	# Heavy load -> HEAVY with the move penalty.
	m.apply_inventory_load(1.12, 0.70)
	if not _has(m.get_status_lines(), "Load: 112% HEAVY (-30% move)"):
		_fail("expected Heavy-Load line, got %s" % str(m.get_status_lines()))
		return

	# Repair channeling -> Repairing N%.
	m.set_repair_progress(true, 0.47)
	if not _has(m.get_status_lines(), "Repairing 47%"):
		_fail("expected 'Repairing 47%%', got %s" % str(m.get_status_lines()))
		return

	# An active channel supersedes a stale block.
	m.notify_repair_blocked("missing_parts")
	if not _has(m.get_status_lines(), "Repairing 47%"):
		_fail("active channel should supersede a block, got %s" % str(m.get_status_lines()))
		return

	# Stop channeling -> the blocked message shows (within the display window).
	m.set_repair_progress(false, 0.0)
	if not _has(m.get_status_lines(), "Repair blocked: missing parts"):
		_fail("expected blocked line, got %s" % str(m.get_status_lines()))
		return

	# Tick past the display window -> the blocked line clears.
	m.tick(VitalsModelScript.BLOCKED_DISPLAY_SECONDS + 0.1)
	if _has_prefix(m.get_status_lines(), "Repair blocked"):
		_fail("blocked line should clear after the display window, got %s" % str(m.get_status_lines()))
		return

	print("PLAYER VITALS MODEL SMOKE PASS suit=-25 heavy=-30 repair=47")
	quit(0)

func _has(lines: PackedStringArray, needle: String) -> bool:
	for line in lines:
		if String(line) == needle:
			return true
	return false

func _has_prefix(lines: PackedStringArray, prefix: String) -> bool:
	for line in lines:
		if String(line).begins_with(prefix):
			return true
	return false

func _fail(reason: String) -> void:
	push_error("PLAYER VITALS MODEL SMOKE FAIL reason=%s" % reason)
	quit(1)
```

- [ ] **Step 2: Run the smoke to verify it fails**

Run:
```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/player_vitals_model_smoke.gd 2>&1
```
Expected: a load/parse error (the model script does not exist yet) and NO `PLAYER VITALS MODEL SMOKE PASS` line.

- [ ] **Step 3: Implement the model**

Create `scripts/systems/player_vitals_model.gd`:

```gdscript
extends RefCounted
class_name PlayerVitalsModel

## Pure formatting model for the player-vitals HUD panel (Phase 7 sub-project C).
## Turns raw model numbers (oxygen summary, inventory load, repair channel state)
## into player-facing ASCII status lines. No scene-tree access; no persistence
## (vitals are live-derived each frame). The coordinator feeds it via the setters
## below; the panel renders get_status_lines().

const BLOCKED_DISPLAY_SECONDS: float = 3.0
const DEFAULT_RECOVERY_THRESHOLD: float = 30.0

var _oxygen_summary: Dictionary = {}
var _load_ratio: float = 0.0
var _move_multiplier: float = 1.0
var _repair_channeling: bool = false
var _repair_progress: float = 0.0
var _blocked_reason: String = ""
var _blocked_remaining: float = 0.0

func apply_oxygen_summary(summary: Dictionary) -> void:
	_oxygen_summary = summary.duplicate(true)

func apply_inventory_load(load_ratio: float, move_multiplier: float) -> void:
	_load_ratio = maxf(0.0, load_ratio)
	_move_multiplier = move_multiplier

func set_repair_progress(channeling: bool, progress: float) -> void:
	_repair_channeling = channeling
	_repair_progress = clampf(progress, 0.0, 1.0)

func notify_repair_blocked(reason: String) -> void:
	_blocked_reason = reason
	_blocked_remaining = BLOCKED_DISPLAY_SECONDS

func tick(delta: float) -> void:
	if _blocked_remaining > 0.0:
		_blocked_remaining = maxf(0.0, _blocked_remaining - delta)
		if _blocked_remaining <= 0.0:
			_blocked_reason = ""

func get_status_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	lines.append(_oxygen_line())
	var suit: String = _suit_line()
	if suit != "":
		lines.append(suit)
	lines.append(_load_line())
	var repair: String = _repair_line()
	if repair != "":
		lines.append(repair)
	return lines

func get_vitals_summary() -> Dictionary:
	return {
		"oxygen": int(round(float(_oxygen_summary.get("oxygen", 0.0)))),
		"breach_state": _breach_state(),
		"suit_drain_percent": _suit_percent(),
		"load_percent": int(round(_load_ratio * 100.0)),
		"heavy": _load_ratio > 1.0,
		"move_penalty_percent": int(round((1.0 - _move_multiplier) * 100.0)),
		"repair_line": _repair_line(),
		"blocked_active": _blocked_remaining > 0.0 and not _repair_channeling,
	}

# --- line composers ---

func _oxygen_line() -> String:
	var oxygen: int = int(round(float(_oxygen_summary.get("oxygen", 0.0))))
	var line: String = "Oxygen: %d" % oxygen
	var state: String = _breach_state()
	if state == "breach":
		line += " (BREACH)"
	elif state == "sealed":
		line += " (SEALED)"
	var threshold: float = float(_oxygen_summary.get("recovery_threshold", DEFAULT_RECOVERY_THRESHOLD))
	if float(oxygen) <= threshold:
		line += " LOW"
	return line

func _breach_state() -> String:
	if bool(_oxygen_summary.get("breach_sealed", false)):
		return "sealed"
	if bool(_oxygen_summary.get("breach_open", false)):
		return "breach"
	return "closed"

func _suit_percent() -> int:
	var mult: float = float(_oxygen_summary.get("equipment_drain_multiplier", 1.0))
	return int(round((1.0 - mult) * 100.0))

func _suit_line() -> String:
	var mult: float = float(_oxygen_summary.get("equipment_drain_multiplier", 1.0))
	if mult >= 1.0:
		return ""
	return "Suit: -%d%% O2 drain" % _suit_percent()

func _load_line() -> String:
	var pct: int = int(round(_load_ratio * 100.0))
	if _load_ratio > 1.0:
		var penalty: int = int(round((1.0 - _move_multiplier) * 100.0))
		return "Load: %d%% HEAVY (-%d%% move)" % [pct, penalty]
	return "Load: %d%%" % pct

func _repair_line() -> String:
	if _repair_channeling:
		return "Repairing %d%%" % int(round(_repair_progress * 100.0))
	if _blocked_remaining > 0.0 and _blocked_reason != "":
		return "Repair blocked: %s" % _blocked_reason_text(_blocked_reason)
	return ""

func _blocked_reason_text(reason: String) -> String:
	if reason == "missing_parts":
		return "missing parts"
	if reason == "missing_tools":
		return "missing tools"
	if reason == "insufficient_skill":
		return "need higher repair skill"
	if reason == "already_functional":
		return "already repaired"
	return reason
```

- [ ] **Step 4: Run the smoke to verify it passes**

Run:
```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/player_vitals_model_smoke.gd 2>&1
```
Expected: a line `PLAYER VITALS MODEL SMOKE PASS suit=-25 heavy=-30 repair=47`, and no `ERROR:`/`WARNING:` beyond the two allowlisted baseline-noise lines.

- [ ] **Step 5: Commit**

```bash
git add scripts/systems/player_vitals_model.gd scripts/validation/player_vitals_model_smoke.gd
git commit -m "feat(hud): PlayerVitalsModel + pure-model smoke (sub-project C)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: PlayerVitalsPanel + coordinator wiring + main-scene smoke

**Files:**
- Create: `scripts/ui/player_vitals_panel.gd`
- Create: `scripts/validation/main_playable_slice_vitals_hud_smoke.gd`
- Modify: `scripts/procgen/playable_generated_ship.gd` (fields after `:117`; preloads near `:47`; `_build_hud_layer` after `:2345`; `_build_repair_points` after `:1963`; `_refresh_oxygen_state` at `:3146`; plus two new methods)

**Interfaces:**
- Consumes (from Task 1): `PlayerVitalsModel` and all its methods (see Task 1 Produces).
- Produces (relied on by Task 3 docs only — no code consumer): the new main-scene smoke marker `MAIN PLAYABLE VITALS HUD PASS panel=true breach=true suit=true heavy=true repair=true`.
  - `PlayerVitalsPanel.set_status_lines(lines: PackedStringArray) -> void`, `get_hud_text() -> String`.
  - Coordinator seam `PlayableGeneratedShip.get_player_vitals_lines() -> PackedStringArray`.
  - Coordinator fields `vitals_model`, `vitals_panel`.

**Bundle note:** Do NOT register the new main-scene smoke in `06_validation_plan.md` here — Task 3 registers both new smokes together (117 → 119).

- [ ] **Step 1: Write the failing main-scene smoke**

Create `scripts/validation/main_playable_slice_vitals_hud_smoke.gd`:

```gdscript
extends SceneTree

## Main-scene smoke for the player-vitals HUD panel (Phase 7 sub-project C):
## proves the coordinator builds the bottom-left PlayerVitalsPanel under hud_layer
## and feeds live state into it each frame — oxygen/breach, the worn-suit O2
## contribution, the Heavy-Load encumbrance penalty, and active repair progress +
## the repair_blocked reason.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const READY_TIMEOUT_FRAMES: int = 300
const SETTLE_FRAMES: int = 6

var main_node: Node
var playable: PlayableGeneratedShip
var frame_count: int = 0
var phase: String = "waiting_ready"
var phase_frames: int = 0
var finished: bool = false
var repair_point                       # the RepairPoint we drive directly

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
		"settle_breach":
			_check_breach()
		"settle_suit":
			_check_suit()
		"settle_heavy":
			_check_heavy()
		"settle_repair":
			_check_repair()
		"settle_blocked":
			_check_blocked()

func _setup() -> void:
	# Structural assertions on the panel itself.
	var hud_layer = playable.get("hud_layer")
	if hud_layer == null or not (hud_layer is CanvasLayer):
		_fail("hud_layer missing or not a CanvasLayer")
		return
	var panel = playable.get("vitals_panel")
	if panel == null or not (panel is Control):
		_fail("vitals_panel missing or not a Control")
		return
	if panel.get_parent() != hud_layer:
		_fail("vitals_panel is not parented under hud_layer")
		return
	if not is_equal_approx(panel.anchor_top, 1.0) or not is_equal_approx(panel.anchor_left, 0.0):
		_fail("vitals_panel is not anchored bottom-left (top=%s left=%s)" % [str(panel.anchor_top), str(panel.anchor_left)])
		return
	# Source models must exist.
	if playable.get("oxygen_state") == null or playable.get("inventory_state") == null or playable.get("equipment_state") == null:
		_fail("a source model (oxygen/inventory/equipment) is null")
		return
	if playable.repair_points == null or playable.repair_points.is_empty():
		_fail("no repair_points to drive")
		return
	# Put the player in the breach zone so the live scenario is faithful.
	playable.teleport_player_to_breach_zone_for_validation()
	# Deterministic baseline: clear worn equipment (the coordinator clears slots
	# this way on reload) so the suit assertion measures the hardsuit alone.
	playable.equipment_state.slots.clear()
	phase = "settle_breach"
	phase_frames = 0

func _check_breach() -> void:
	phase_frames += 1
	if phase_frames < SETTLE_FRAMES:
		return
	var lines: PackedStringArray = playable.get_player_vitals_lines()
	if not _line_with(lines, "Oxygen:", "(BREACH)"):
		_fail("expected an Oxygen line with (BREACH), got %s" % str(lines))
		return
	# Equip the hardsuit on the coordinator's own EquipmentState.
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
	if not _has(playable.get_player_vitals_lines(), "Suit: -25% O2 drain"):
		_fail("expected 'Suit: -25%% O2 drain', got %s" % str(playable.get_player_vitals_lines()))
		return
	# Over-encumber deterministically: 20 x scrap_metal (5.0 each = 100) vs 50 capacity.
	playable.inventory_state.add_item("scrap_metal", 20)
	phase = "settle_heavy"
	phase_frames = 0

func _check_heavy() -> void:
	phase_frames += 1
	if phase_frames < SETTLE_FRAMES:
		return
	if not _line_with(playable.get_player_vitals_lines(), "Load:", "HEAVY"):
		_fail("expected a Load line containing HEAVY, got %s" % str(playable.get_player_vitals_lines()))
		return
	# Drive an active repair channel directly on a repair point.
	repair_point = playable.repair_points[0]
	repair_point.channeling = true
	repair_point.progress = 0.47
	phase = "settle_repair"
	phase_frames = 0

func _check_repair() -> void:
	phase_frames += 1
	if phase_frames < SETTLE_FRAMES:
		return
	if not _has(playable.get_player_vitals_lines(), "Repairing 47%"):
		_fail("expected 'Repairing 47%%', got %s" % str(playable.get_player_vitals_lines()))
		return
	# End the channel and emit a blocked rejection through the real signal path.
	repair_point.channeling = false
	repair_point.progress = 0.0
	repair_point.emit_signal("repair_blocked", repair_point.system_id, repair_point.subcomponent_id, "missing_parts")
	phase = "settle_blocked"
	phase_frames = 0

func _check_blocked() -> void:
	phase_frames += 1
	if phase_frames < SETTLE_FRAMES:
		return
	if not _has(playable.get_player_vitals_lines(), "Repair blocked: missing parts"):
		_fail("expected 'Repair blocked: missing parts', got %s" % str(playable.get_player_vitals_lines()))
		return
	finished = true
	print("MAIN PLAYABLE VITALS HUD PASS panel=true breach=true suit=true heavy=true repair=true")
	_cleanup_and_quit(0)

func _has(lines: PackedStringArray, needle: String) -> bool:
	for line in lines:
		if String(line) == needle:
			return true
	return false

func _line_with(lines: PackedStringArray, prefix: String, contains: String) -> bool:
	for line in lines:
		var s: String = String(line)
		if s.begins_with(prefix) and s.contains(contains):
			return true
	return false

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
	push_error("MAIN PLAYABLE VITALS HUD FAIL reason=%s" % reason)
	_cleanup_and_quit(1)

func _cleanup_and_quit(code: int) -> void:
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
```

- [ ] **Step 2: Run the main-scene smoke to verify it fails**

Run:
```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_vitals_hud_smoke.gd 2>&1
```
Expected: FAIL — the panel/seam don't exist yet, so either a load error or `MAIN PLAYABLE VITALS HUD FAIL reason=vitals_panel missing ...`. No PASS line.

- [ ] **Step 3: Create the PlayerVitalsPanel Control**

Create `scripts/ui/player_vitals_panel.gd`:

```gdscript
extends Control
class_name PlayerVitalsPanel

## Bottom-left player-vitals HUD panel (Phase 7 sub-project C). Presentation only:
## the coordinator pushes pre-formatted ASCII lines via set_status_lines; this node
## renders them in a styled panel. No model access. Mirrors ObjectiveTracker's node
## construction (PanelContainer -> MarginContainer -> autowrap Label).

const PANEL_POSITION: Vector2 = Vector2(18.0, -168.0)
const PANEL_SIZE: Vector2 = Vector2(360.0, 150.0)
const LABEL_MIN_SIZE: Vector2 = Vector2(320.0, 0.0)
const HUD_FONT_SIZE: int = 18
const PANEL_COLOR: Color = Color(0.03, 0.05, 0.07, 0.82)
const PANEL_BORDER_COLOR: Color = Color(0.22, 0.72, 1.0, 0.65)

var panel: PanelContainer
var margin: MarginContainer
var label: Label

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	position = PANEL_POSITION
	custom_minimum_size = PANEL_SIZE
	_ensure_nodes()

func set_status_lines(lines: PackedStringArray) -> void:
	_ensure_nodes()
	label.text = "\n".join(lines)

func get_hud_text() -> String:
	if label == null:
		return ""
	return label.text

func _ensure_nodes() -> void:
	if panel == null:
		panel = PanelContainer.new()
		panel.name = "VitalsPanel"
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.position = Vector2.ZERO
		panel.size = PANEL_SIZE
		panel.custom_minimum_size = PANEL_SIZE
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.bg_color = PANEL_COLOR
		style.border_color = PANEL_BORDER_COLOR
		style.border_width_left = 2
		style.border_width_right = 2
		style.border_width_top = 2
		style.border_width_bottom = 2
		style.corner_radius_top_left = 8
		style.corner_radius_top_right = 8
		style.corner_radius_bottom_left = 8
		style.corner_radius_bottom_right = 8
		panel.add_theme_stylebox_override("panel", style)
		add_child(panel)
	if margin == null:
		margin = MarginContainer.new()
		margin.name = "VitalsMargin"
		margin.add_theme_constant_override("margin_left", 14)
		margin.add_theme_constant_override("margin_top", 12)
		margin.add_theme_constant_override("margin_right", 14)
		margin.add_theme_constant_override("margin_bottom", 12)
		panel.add_child(margin)
	if label == null:
		label = Label.new()
		label.name = "VitalsLabel"
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		label.custom_minimum_size = LABEL_MIN_SIZE
		label.add_theme_font_size_override("font_size", HUD_FONT_SIZE)
		label.add_theme_color_override("font_color", Color.WHITE)
		label.add_theme_color_override("font_shadow_color", Color.BLACK)
		label.add_theme_constant_override("shadow_offset_x", 1)
		label.add_theme_constant_override("shadow_offset_y", 1)
		margin.add_child(label)
```

- [ ] **Step 4: Add coordinator preloads + fields**

In `scripts/procgen/playable_generated_ship.gd`, add two preload consts immediately after the existing `const EncumbranceScript := preload("res://scripts/systems/encumbrance.gd")` line (`:47`):

```gdscript
const PlayerVitalsModelScript := preload("res://scripts/systems/player_vitals_model.gd")
const PlayerVitalsPanelScript := preload("res://scripts/ui/player_vitals_panel.gd")
```

Add two fields immediately after the existing `var tracker` declaration (`:117`):

```gdscript
var vitals_model            # PlayerVitalsModel
var vitals_panel            # PlayerVitalsPanel
```

- [ ] **Step 5: Build the panel + model in `_build_hud_layer`**

In `_build_hud_layer()`, immediately after the existing `hud_layer.add_child(tracker)` line (`:2345`), insert:

```gdscript
	vitals_model = PlayerVitalsModelScript.new()
	vitals_panel = PlayerVitalsPanelScript.new()
	vitals_panel.name = "PlayerVitalsPanel"
	hud_layer.add_child(vitals_panel)
```

- [ ] **Step 6: Connect `repair_blocked` in `_build_repair_points`**

In `_build_repair_points()`, immediately after the existing block that connects `rp.repair_completed` (`:1962-1963`), insert:

```gdscript
			if not rp.repair_blocked.is_connected(_on_repair_blocked):
				rp.repair_blocked.connect(_on_repair_blocked)
```

(Match the surrounding indentation — this sits inside the same per-`rp` loop/branch as the `repair_completed` connection.)

- [ ] **Step 7: Add the handler, the per-frame feed, and the seam**

Add the `_on_repair_blocked` handler immediately after the existing `_on_repair_completed(...)` function (around `:2024-2055`):

```gdscript
func _on_repair_blocked(_system_id: String, _subcomponent_id: String, reason: String) -> void:
	if vitals_model != null:
		vitals_model.notify_repair_blocked(reason)
```

Add the per-frame feed and the read seam (place both directly after `_refresh_oxygen_state(...)`, i.e. after `:3167`):

```gdscript
func _refresh_player_vitals(delta_seconds: float) -> void:
	if vitals_model == null or vitals_panel == null:
		return
	if oxygen_state != null:
		vitals_model.apply_oxygen_summary(oxygen_state.get_summary())
	if inventory_state != null:
		var ratio: float = inventory_state.get_load_ratio()
		vitals_model.apply_inventory_load(ratio, EncumbranceScript.move_speed_multiplier(ratio))
	var channeling: bool = false
	var progress: float = 0.0
	for rp in repair_points:
		if is_instance_valid(rp) and rp.channeling:
			channeling = true
			progress = rp.progress
			break
	vitals_model.set_repair_progress(channeling, progress)
	vitals_model.tick(delta_seconds)
	vitals_panel.set_status_lines(vitals_model.get_status_lines())

func get_player_vitals_lines() -> PackedStringArray:
	if vitals_model == null:
		return PackedStringArray()
	return vitals_model.get_status_lines()
```

- [ ] **Step 8: Call the feed from both `_refresh_oxygen_state` return paths**

In `_refresh_oxygen_state(force_initial, delta_seconds)`:

Insert `_refresh_player_vitals(delta_seconds)` as the last statement of the `force_initial` branch, immediately after `_refresh_tracker_system_status_lines()` (`:3161`) and BEFORE its `return` (`:3162`):

```gdscript
	if force_initial:
		oxygen_state.apply_ship_systems_summary({})  # no-op; recompute passability
		_apply_breach_zone_scene_state()
		_refresh_tracker_system_status_lines()
		_refresh_player_vitals(delta_seconds)
		return
```

Insert `_refresh_player_vitals(delta_seconds)` as the last statement of the per-tick path, immediately after `_refresh_tracker_system_status_lines()` (`:3167`):

```gdscript
	var player_in_zone: bool = is_player_in_breach_zone()
	oxygen_state.tick(delta_seconds, player_in_zone)
	_apply_breach_zone_scene_state()
	_refresh_tracker_system_status_lines()
	_refresh_player_vitals(delta_seconds)
```

(Leave the early `if oxygen_state == null:` return at `:3147-3149` unchanged — vitals are skipped before ship load, which is correct.)

- [ ] **Step 9: Run the main-scene smoke to verify it passes**

Run:
```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_vitals_hud_smoke.gd 2>&1
```
Expected: `MAIN PLAYABLE VITALS HUD PASS panel=true breach=true suit=true heavy=true repair=true`, no unexpected `ERROR:`/`WARNING:`.

- [ ] **Step 10: Regression-guard the existing HUD + the Task 1 model smoke**

Run both and confirm each still prints its PASS marker (the additive change must not regress the tracker or the model):
```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_hud_smoke.gd 2>&1
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/player_vitals_model_smoke.gd 2>&1
```
Expected: `MAIN PLAYABLE SLICE HUD PASS ...` and `PLAYER VITALS MODEL SMOKE PASS ...`.

- [ ] **Step 11: Commit**

```bash
git add scripts/ui/player_vitals_panel.gd scripts/validation/main_playable_slice_vitals_hud_smoke.gd scripts/procgen/playable_generated_ship.gd
git commit -m "feat(hud): bottom-left player-vitals panel wired to live state (sub-project C)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: Docs — ADR-0025, bundle registration (117 -> 119), roadmap

**Files:**
- Create: `docs/game/adr/0025-player-vitals-hud.md`
- Modify: `docs/game/06_validation_plan.md` (`:186-188`)
- Modify: `docs/game/09_system_roadmap.md` (System 6 row)

**Interfaces:** none (documentation + bundle wiring only).

- [ ] **Step 1: Write ADR-0025**

Create `docs/game/adr/0025-player-vitals-hud.md`:

```markdown
# ADR-0025: Player Vitals HUD Panel

Date: 2026-06-24
Status: Accepted
Phase: 7 (Integration & Polish), sub-project C

## Context

Three runtime states the models already computed were invisible in real play:
active repair progress (`RepairPoint.progress`) and its `repair_blocked` reason,
the worn-suit oxygen-drain contribution (ADR-0024's `equipment_drain_multiplier`),
and the Heavy-Load movement penalty (`Encumbrance.move_speed_multiplier`). The
objective tracker's flat "Systems:" block was already ~13 unsectioned lines.

## Decision

A dedicated, always-on **`PlayerVitalsPanel`** (`Control`, bottom-left, under the
existing `hud_layer`) renders player vitals, distinct from the objective tracker.
A pure **`PlayerVitalsModel`** (`RefCounted`, no scene tree, no persistence) owns
the formatting/warning rules and a transient blocked-message timer driven by the
per-frame `delta`. The coordinator bridges the four sources (oxygen summary,
inventory load, channeling `RepairPoint`, `repair_blocked` signal) into the model
inside its existing `_refresh_oxygen_state` cadence and pushes
`get_status_lines()` to the panel.

Output is ASCII-only (Windows headless console + smoke grep contracts).

## Additive stance

The objective tracker and `get_combined_system_status_lines()` are unchanged. The
four main-scene smokes assert oxygen/breach/weight tokens against that coordinator
getter, and `main_playable_slice_hazard_smoke.gd` is tightly coupled to the
oxygen/breach lines living there; moving them would force a hazard-smoke rewrite,
out of proportion for a polish slice. The bare `Oxygen: N` value therefore appears
both on the tracker (terse) and the vitals panel (player-facing); the panel earns
its place with the new info the tracker never had.

## Consequences

- Suit, Heavy-Load, and live repair status are now visible in play.
- Two new smokes (`player_vitals_model_smoke`, `main_playable_slice_vitals_hud_smoke`);
  regression bundle 117 -> 119.

## Deferred follow-ups

- Remove the redundant terse `Oxygen:`/`weight=` lines from the objective tracker
  and repoint `main_playable_slice_hazard_smoke.gd` (eliminates the duplication).
- Accessibility-scaling parity for the vitals panel (`apply_accessibility_settings`),
  matching the objective tracker's A11Y-P1-001 seam.
```

- [ ] **Step 2: Register both smokes in the regression bundle**

In `docs/game/06_validation_plan.md`, the current tail is (`:186-188`):

```bash
run_clean 'oxygen+equipment drain' 'OXYGEN EQUIPMENT DRAIN SMOKE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/oxygen_equipment_drain_smoke.gd
run_clean 'suit oxygen slice' 'SUIT OXYGEN SLICE SMOKE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_suit_oxygen_smoke.gd
echo 'SYNAPSE_SEA REGRESSION PASS commands=117 clean_output=true'
```

Replace it with (add two `run_clean` lines, bump the count to 119):

```bash
run_clean 'oxygen+equipment drain' 'OXYGEN EQUIPMENT DRAIN SMOKE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/oxygen_equipment_drain_smoke.gd
run_clean 'suit oxygen slice' 'SUIT OXYGEN SLICE SMOKE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_suit_oxygen_smoke.gd
run_clean 'player vitals model' 'PLAYER VITALS MODEL SMOKE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/player_vitals_model_smoke.gd
run_clean 'player vitals hud' 'MAIN PLAYABLE VITALS HUD PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_vitals_hud_smoke.gd
echo 'SYNAPSE_SEA REGRESSION PASS commands=119 clean_output=true'
```

Also update any human-readable "expected markers" list / count elsewhere in `06_validation_plan.md` that enumerates the smokes (search the file for `OXYGEN EQUIPMENT DRAIN SMOKE PASS` and for `commands=117`; add the two new markers to any such list and change `117` to `119` wherever it appears as the bundle total).

- [ ] **Step 3: Update the system roadmap**

In `docs/game/09_system_roadmap.md`, in the System 6 row (the `🟡` Inventory & Equipment cell), append a clause to the built list mirroring the existing ADR-0024 clause:

```
; player-vitals HUD panel (PlayerVitalsModel + bottom-left PlayerVitalsPanel surfacing live repair progress/blocked, the suit O2 contribution, and the Heavy-Load penalty) — ADR-0025 ✅
```

Leave the *Remaining:* list intact (the deferred tracker de-duplication and vitals-panel accessibility parity are recorded in ADR-0025, not the roadmap).

- [ ] **Step 4: Run the full regression bundle (stash the project.godot drift first)**

```bash
GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
export GODOT ROOT
git stash push -- project.godot
bash <(awk '/^## Regression bundle/{f=1} f && /^```bash$/ {c=1; next} f && c && /^```$/ {exit} f && c {print}' docs/game/06_validation_plan.md)
status=$?
git stash pop
echo "bundle exit=$status"
```
Expected final line: `SYNAPSE_SEA REGRESSION PASS commands=119 clean_output=true`. If `git stash push` reports "No local changes to save" (the drift may already be stashed/clean), proceed and still run the bundle; ensure the `git stash pop` is skipped if nothing was stashed.

- [ ] **Step 5: Commit**

```bash
git add docs/game/adr/0025-player-vitals-hud.md docs/game/06_validation_plan.md docs/game/09_system_roadmap.md
git commit -m "docs(hud): ADR-0025 + register vitals smokes (117->119) + roadmap (sub-project C)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Plan Self-Review

- **Spec coverage:** repair progress/blocked (Task 1 model `_repair_line` + Task 2 feed/signal), suit O2 (`_suit_line`), Heavy-Load (`_load_line`), dedicated bottom-left panel (Task 2), pure-model + main-scene smokes (Tasks 1-2), ADR-0025 + bundle 117→119 + roadmap (Task 3), ASCII-only + additive + no-persistence (Global Constraints). All spec sections map to a task.
- **Type consistency:** `PlayerVitalsModel` method names/signatures identical between Task 1 (definition) and Task 2 (feed call site); `get_player_vitals_lines()`/`vitals_panel`/`vitals_model` consistent across Task 2 and the main-scene smoke; `BLOCKED_DISPLAY_SECONDS` referenced via the preload const.
- **Placeholder scan:** no TBD/TODO; every code step carries complete code; every run step carries the exact command and expected marker.
- **Known soft spot flagged for the implementer:** the line-`:NNN` anchors are from the current `playable_generated_ship.gd`; if they have drifted, locate the named function/declaration (`_build_hud_layer`, `_build_repair_points`, `_refresh_oxygen_state`, `var tracker`, `EncumbranceScript`) rather than trusting the number.
```
