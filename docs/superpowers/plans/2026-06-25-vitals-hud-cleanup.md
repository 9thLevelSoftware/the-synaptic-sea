# Vitals / HUD Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** De-duplicate player oxygen/load off the top-left objective tracker (vitals panel becomes the sole home), register the orphaned HUD smoke in the regression bundle, and bring `PlayerVitalsPanel` to `AccessibilitySettings` parity with `ObjectiveTracker`.

**Architecture:** Three production touches (`playable_generated_ship.gd` de-dup + accessibility wiring, `player_vitals_panel.gd` scaling parity) plus four validation touches (repoint the hazard smoke off the tracker block, register the HUD smoke, extend the text-scale smoke, bump the bundle). No model, gameplay, or persistence change; default text scale (1.0) is pixel-identical to today.

**Tech Stack:** Godot 4.6.2, typed GDScript, headless `--script` validation smokes (each prints one PASS marker).

## Global Constraints

- **Godot binary:** `C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe` (use the `_console` build so stdout/markers are captured). **Project root:** `C:/Users/dasbl/Documents/The Synaptic Sea`.
- **Run smokes headless:** `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/<smoke>.gd`. **Trust the PASS marker, never the exit code** — Godot `--script` can exit 0 on parse/load errors.
- **These three smokes abort on failure** (`_fail()` → `push_error(... FAIL ...)` → `quit(1)`): RED = a `… FAIL reason=…` line and no PASS marker; GREEN = the exact PASS marker present.
- **Allowlisted baseline noise (ignore):** `ERROR: Capture not registered: 'gdaimcp'.` and `WARNING: ObjectDB instances leaked at exit …`. Any other `ERROR:`/`WARNING:` line blocks completion.
- **Never stage/commit** `project.godot`, `.godot/`, `*.uid`, or `addons/`. Use selective `git add <explicit paths>` only. Before the full regression bundle: `git stash push -- project.godot`, run, then `git stash pop` (the local MCPRuntime-autoload drift breaks headless).
- **Conventional Commits**, each ending with a trailer line: `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
- **Bundle marker after this slice:** `SARGASSO REGRESSION PASS commands=120 clean_output=true` (was 119; Task 2 adds one smoke).
- **Vitals oxygen line format (sole home):** `Oxygen: N (BREACH)` / `Oxygen: N (SEALED)` / trailing ` LOW` when `N ≤ recovery_threshold`; no breach suffix when closed. There is **no `BLOCKED` token** in the vitals line (that token only existed in the retired tracker oxygen line).
- **Tracker keeps:** ship systems (Power/Reactor/Supplies/Main Power/Logs), Routes/Extraction, carried `Tool:`/`tool=`/`item=` lines (REQ-007), `Repair Skill:`. Tracker **drops:** `Oxygen:`, `Breach:`, `weight=`.

---

### Task 1: De-dup the tracker + repoint the hazard smoke

**Files:**
- Modify: `scripts/procgen/playable_generated_ship.gd` (`_combined_system_status_lines()`, ≈L2907)
- Test: `scripts/validation/main_playable_slice_hazard_smoke.gd` (repoint + de-dup guard)

**Interfaces:**
- Consumes: `playable.get_combined_system_status_lines() -> PackedStringArray` (tracker block, public), `playable.get_player_vitals_lines() -> PackedStringArray` (vitals model lines, public), `playable.get_oxygen_summary() -> Dictionary` (unchanged numeric source).
- Produces: a tracker block with no `Oxygen:`/`Breach:`/`weight=` lines; a hazard smoke whose oxygen/breach HUD-reflection assertions read the vitals panel.

TDD order: write the test changes first (repoint + add the de-dup guard) so the guard goes RED against the un-de-duped coordinator, then apply the coordinator de-dup to turn it GREEN.

- [ ] **Step 1: Repoint the hazard smoke to the vitals panel + add the de-dup guard**

In `scripts/validation/main_playable_slice_hazard_smoke.gd`:

(a) Change the helper at the bottom to read vitals lines:

```gdscript
func _first_status_line_starting_with(prefix: String) -> String:
	var lines: PackedStringArray = playable.get_player_vitals_lines()
	for line in lines:
		var text := String(line)
		if text.begins_with(prefix):
			return text
	return ""
```

(b) Replace the initial HUD check (currently the `# HUD must already contain an Oxygen: line routed through ObjectiveTracker.` block through the `Breach: OPEN` check, ending just before `phase = "complete_obj1"`) with:

```gdscript
	# ADR-0027: player oxygen + breach now live solely in the bottom-left
	# PlayerVitalsPanel; the vitals oxygen line embeds the breach state as
	# (BREACH)/(SEALED). The top-left tracker no longer mirrors them.
	var initial_oxygen_line: String = _first_status_line_starting_with("Oxygen:")
	if initial_oxygen_line.is_empty():
		_fail("initial vitals lines missing Oxygen: line")
		return
	if not initial_oxygen_line.contains("(BREACH)"):
		_fail("initial vitals oxygen line should report (BREACH), got %s" % initial_oxygen_line)
		return
	# De-dup guard (ADR-0027): the tracker's combined status block must NOT carry
	# oxygen/breach/weight any more — those belong to the vitals panel.
	for line in playable.get_combined_system_status_lines():
		var dedup_text := String(line)
		if dedup_text.begins_with("Oxygen:") or dedup_text.begins_with("Breach:") or dedup_text.begins_with("weight="):
			_fail("tracker combined status must not contain oxygen/breach/weight after ADR-0027 de-dup, got %s" % dedup_text)
			return
	phase = "complete_obj1"
```

(c) Replace the zero-drive HUD check (the `# HUD should now show the blocked marker.` block, currently asserting `.contains("BLOCKED")`) with:

```gdscript
	# Vitals oxygen line at zero is "Oxygen: 0 (BREACH) LOW" — there is no BLOCKED
	# token (passability_blocked is already asserted via the model + collision
	# count above). Prove the HUD reflects zero oxygen.
	hud_line_after_zero = _first_status_line_starting_with("Oxygen:")
	if not hud_line_after_zero.begins_with("Oxygen: 0"):
		_fail("after zero-drive vitals oxygen line should report 0, got %s" % hud_line_after_zero)
		return
```

(d) Replace the after-seal HUD check (the `# HUD status lines should include an oxygen line and a Breach: SEALED marker.` block through the `found_seal` fail, ending just before `phase = "complete_obj3_4"`) with:

```gdscript
	# ADR-0027: the vitals oxygen line carries the sealed state as (SEALED).
	hud_line_after_seal = _first_status_line_starting_with("Oxygen:")
	if hud_line_after_seal.is_empty():
		_fail("vitals lines missing Oxygen: line after seal")
		return
	if not hud_line_after_seal.contains("(SEALED)"):
		_fail("vitals oxygen line should report (SEALED) after seal, got %s" % hud_line_after_seal)
		return
	phase = "complete_obj3_4"
```

- [ ] **Step 2: Run the hazard smoke — confirm it goes RED on the de-dup guard**

```bash
GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_hazard_smoke.gd 2>&1 | grep -E "HAZARD (PASS|FAIL)"
```
Expected: `MAIN PLAYABLE HAZARD FAIL reason=tracker combined status must not contain oxygen/breach/weight …` (the guard fires because the coordinator still appends oxygen/weight). No PASS marker.

- [ ] **Step 3: Apply the coordinator de-dup**

In `scripts/procgen/playable_generated_ship.gd`, `_combined_system_status_lines()` — replace the oxygen + inventory blocks. Current:

```gdscript
	if oxygen_state != null:
		for line in oxygen_state.get_status_lines():
			lines.append(String(line))
	# REQ-007: surface carried tools on the HUD via inventory status lines.
	if inventory_state != null:
		for line in inventory_state.get_status_lines():
			lines.append(String(line))
```

New:

```gdscript
	# ADR-0027: player oxygen + breach now live solely in the bottom-left
	# PlayerVitalsPanel; the tracker no longer mirrors oxygen_state lines.
	# REQ-007: still surface carried tools/items, but the inventory weight
	# readout is owned by the vitals panel's Load line, so drop the weight= line.
	if inventory_state != null:
		for line in inventory_state.get_status_lines():
			var inv_text: String = String(line)
			if inv_text.begins_with("weight="):
				continue
			lines.append(inv_text)
```

(The `oxygen_state.get_status_lines()` loop is removed entirely. `oxygen_state.gd` / `inventory_state.gd` are NOT edited — their model smokes assert full output.)

- [ ] **Step 4: Run the hazard smoke — confirm GREEN**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_hazard_smoke.gd 2>&1 | grep -E "HAZARD (PASS|FAIL)"
```
Expected: `MAIN PLAYABLE HAZARD PASS oxygen=… breach_open=false breach_sealed=true …`

- [ ] **Step 5: Run the other tracker-block consumers + the vitals smoke — confirm none regressed**

```bash
for s in main_playable_slice_inventory_smoke main_playable_slice_junction_calibrator_smoke main_playable_slice_progression_smoke main_playable_slice_vitals_hud_smoke; do
  "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/$s.gd 2>&1 | grep -E "PASS|FAIL"
done
```
Expected four PASS markers: `MAIN PLAYABLE INVENTORY PASS …`, `MAIN PLAYABLE JUNCTION CALIBRATOR PASS …`, `MAIN PLAYABLE PROGRESSION PASS …`, `MAIN PLAYABLE VITALS HUD PASS …`. (They read `Tool:`/calibrator/`Repair Skill:` tokens that are kept, and the vitals panel render is unchanged.)

- [ ] **Step 6: Commit**

```bash
git add scripts/procgen/playable_generated_ship.gd scripts/validation/main_playable_slice_hazard_smoke.gd
git commit -m "$(printf 'refactor(hud): vitals panel is the sole home for oxygen/load; repoint hazard smoke\n\nDrop Oxygen:/Breach:/weight= from the objective tracker combined status\nblock (ADR-0027) and repoint the hazard smoke HUD-reflection asserts to\nget_player_vitals_lines(); numeric asserts stay on get_oxygen_summary().\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

### Task 2: Register the orphaned HUD smoke in the regression bundle

**Files:**
- Modify: `docs/game/06_validation_plan.md` (add one `run_clean` line; bump the tail marker)
- Test: `scripts/validation/main_playable_slice_hud_smoke.gd` (run standalone; not edited)

**Interfaces:**
- Consumes: existing `main_playable_slice_hud_smoke.gd` (marker `MAIN PLAYABLE SLICE HUD PASS …`).
- Produces: bundle count `commands=120`.

- [ ] **Step 1: Confirm the HUD smoke passes standalone (post-Task-1)**

```bash
GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_hud_smoke.gd 2>&1 | grep -E "SLICE HUD (PASS|FAIL)"
```
Expected: `MAIN PLAYABLE SLICE HUD PASS canvas_layer=true width=520 current_sequence=1`. (It asserts only objective/control tokens — unaffected by the Task-1 de-dup.)

- [ ] **Step 2: Register it in the bundle**

In `docs/game/06_validation_plan.md`, find the line registering the vitals HUD smoke:

```bash
run_clean 'player vitals hud' 'MAIN PLAYABLE VITALS HUD PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_vitals_hud_smoke.gd
```

Add this line immediately ABOVE it:

```bash
run_clean 'main playable slice hud' 'MAIN PLAYABLE SLICE HUD PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_hud_smoke.gd
```

Then bump the tail marker on the next line:

```bash
echo 'SARGASSO REGRESSION PASS commands=120 clean_output=true'
```
(was `commands=119`).

- [ ] **Step 3: Verify the bundle now references the smoke and the new count**

```bash
grep -nE "main_playable_slice_hud_smoke|commands=120|commands=119" docs/game/06_validation_plan.md
```
Expected: the new `run_clean` line is present, `commands=120` is present, and no `commands=119` remains. (The authoritative full-bundle run is Task 4.)

- [ ] **Step 4: Commit**

```bash
git add docs/game/06_validation_plan.md
git commit -m "$(printf 'test(hud): register main_playable_slice_hud_smoke in the regression bundle (119->120)\n\nThe top-left HUD smoke existed and passed but was never bundled, leaving a\ntracker regression unguarded.\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

### Task 3: Vitals-panel accessibility parity

**Files:**
- Modify: `scripts/ui/player_vitals_panel.gd` (full rewrite — A11Y scaling parity)
- Modify: `scripts/procgen/playable_generated_ship.gd` (`apply_accessibility_settings()` ≈L306; `_build_hud_layer()` ≈L2356)
- Test: `scripts/validation/main_playable_slice_text_scale_smoke.gd` (add vitals-panel scale asserts)

**Interfaces:**
- Consumes: `AccessibilitySettings.scaled_hud_panel_size(Vector2) / scaled_hud_minimum_size(Vector2) / scaled_hud_font_size(int)`; coordinator field `vitals_panel: PlayerVitalsPanel`.
- Produces: `PlayerVitalsPanel.apply_accessibility_settings(settings: RefCounted) -> void` (idempotent, mirrors `ObjectiveTracker`); the coordinator pushes its `accessibility_settings` into `vitals_panel`.

TDD order: extend the smoke first (RED at 1.5×/2.0× because the panel doesn't scale yet), then implement the panel + wiring (GREEN).

- [ ] **Step 1: Extend the text-scale smoke with vitals-panel assertions**

In `scripts/validation/main_playable_slice_text_scale_smoke.gd`, add two constants near the existing `DEFAULT_BASE_*` block:

```gdscript
const DEFAULT_BASE_VITALS_FONT_SIZE: int = 18
const DEFAULT_BASE_VITALS_SIZE: Vector2 = Vector2(360.0, 150.0)
```

Add this helper near `_find_playable`:

```gdscript
func _check_vitals_scale(playable: PlayableGeneratedShip, scale: float, tag: String) -> bool:
	var vitals: PlayerVitalsPanel = playable.vitals_panel as PlayerVitalsPanel
	if vitals == null:
		_fail("%s: vitals panel missing" % tag)
		return false
	var expected_font: int = int(round(float(DEFAULT_BASE_VITALS_FONT_SIZE) * scale))
	var actual_font: int = int(vitals.label.get_theme_font_size("font_size"))
	if actual_font != expected_font:
		_fail("%s: vitals font_size=%d expected %d" % [tag, actual_font, expected_font])
		return false
	var expected_cmin: Vector2 = Vector2(DEFAULT_BASE_VITALS_SIZE.x * scale, DEFAULT_BASE_VITALS_SIZE.y * scale)
	if vitals.custom_minimum_size != expected_cmin:
		_fail("%s: vitals cmin=%s expected %s" % [tag, str(vitals.custom_minimum_size), str(expected_cmin)])
		return false
	return true
```

Then call it in each scale validator, right before that validator's `print(...)`:
- In `_validate_default_scale`: `if not _check_vitals_scale(playable, 1.0, "default"): return`
- In `_validate_15x_scale`: `if not _check_vitals_scale(playable, 1.5, "1.5x"): return`
- In `_validate_20x_scale`: `if not _check_vitals_scale(playable, 2.0, "2.0x"): return`

- [ ] **Step 2: Run the text-scale smoke — confirm RED at 1.5×**

```bash
GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_text_scale_smoke.gd 2>&1 | grep -E "TEXT SCALE (PASS|FAIL)"
```
Expected: `MAIN PLAYABLE TEXT SCALE FAIL reason=1.5x: vitals font_size=18 expected 27` (default 1.0× passes; the panel doesn't scale yet). No final PASS marker.

- [ ] **Step 3: Rewrite `player_vitals_panel.gd` for accessibility parity**

Replace the entire contents of `scripts/ui/player_vitals_panel.gd` with:

```gdscript
extends Control
class_name PlayerVitalsPanel

## Bottom-left player-vitals HUD panel (Phase 7 sub-project C). Presentation only:
## the coordinator pushes pre-formatted ASCII lines via set_status_lines; this node
## renders them in a styled panel. No model access. Mirrors ObjectiveTracker's node
## construction (PanelContainer -> MarginContainer -> autowrap Label).
##
## A11Y parity (ADR-0027): font/panel/label sizes derive from an owned
## AccessibilitySettings instance, exactly like ObjectiveTracker. Default
## scale=1.0 reproduces the prior hard-coded sizes pixel-for-pixel. Because the
## panel is anchored BOTTOM_LEFT, its Y offset is computed from the SCALED panel
## height so a larger scale grows the panel upward from a fixed bottom margin
## instead of overflowing the screen bottom.

const AccessibilitySettingsScript := preload("res://scripts/ui/accessibility_settings.gd")

const BASE_PANEL_SIZE: Vector2 = Vector2(360.0, 150.0)
const BASE_LABEL_MIN_SIZE: Vector2 = Vector2(320.0, 0.0)
const BASE_HUD_FONT_SIZE: int = 18
const LEFT_MARGIN: float = 18.0
const BOTTOM_MARGIN: float = 18.0
const PANEL_COLOR: Color = Color(0.03, 0.05, 0.07, 0.82)
const PANEL_BORDER_COLOR: Color = Color(0.22, 0.72, 1.0, 0.65)

var panel: PanelContainer
var margin: MarginContainer
var label: Label
# A11Y parity (ADR-0027): owned AccessibilitySettings; default scale=1.0
# preserves the prior hard-coded layout exactly. Replace via
# apply_accessibility_settings() to enlarge the panel text.
var accessibility_settings: RefCounted = AccessibilitySettingsScript.new()
var _anchored: bool = false

func _ready() -> void:
	_ensure_nodes()

func set_status_lines(lines: PackedStringArray) -> void:
	_ensure_nodes()
	label.text = "\n".join(lines)

func get_hud_text() -> String:
	if label == null:
		return ""
	return label.text

## A11Y parity (ADR-0027): re-apply panel/label/font sizes from the supplied
## settings, updating existing nodes in place. Idempotent. Safe to call before
## _ready (stores the settings; _ready builds the nodes at the stored scale).
func apply_accessibility_settings(settings: RefCounted) -> void:
	if settings == null:
		return
	accessibility_settings = settings
	if label != null:
		_apply_scaled_layout()

func _ensure_nodes() -> void:
	if not _anchored:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		_anchored = true
	if panel == null:
		panel = PanelContainer.new()
		panel.name = "VitalsPanel"
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.position = Vector2.ZERO
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
		label.add_theme_color_override("font_color", Color.WHITE)
		label.add_theme_color_override("font_shadow_color", Color.BLACK)
		label.add_theme_constant_override("shadow_offset_x", 1)
		label.add_theme_constant_override("shadow_offset_y", 1)
		margin.add_child(label)
	_apply_scaled_layout()

func _apply_scaled_layout() -> void:
	var scaled_panel: Vector2 = accessibility_settings.scaled_hud_panel_size(BASE_PANEL_SIZE)
	var scaled_label_min: Vector2 = accessibility_settings.scaled_hud_minimum_size(BASE_LABEL_MIN_SIZE)
	var scaled_font: int = accessibility_settings.scaled_hud_font_size(BASE_HUD_FONT_SIZE)
	custom_minimum_size = scaled_panel
	size = scaled_panel
	# Bottom-anchored: grow upward from a fixed bottom margin so a larger scale
	# does not push the panel off the bottom edge.
	position = Vector2(LEFT_MARGIN, -(scaled_panel.y + BOTTOM_MARGIN))
	if panel != null:
		panel.size = scaled_panel
		panel.custom_minimum_size = scaled_panel
	if label != null:
		label.custom_minimum_size = scaled_label_min
		label.size = scaled_label_min
		label.add_theme_font_size_override("font_size", scaled_font)
```

(At scale 1.0 this yields font 18, size `(360,150)`, position `(18, -168)` — identical to the prior hard-coded panel.)

- [ ] **Step 4: Wire the coordinator to push settings into the vitals panel**

In `scripts/procgen/playable_generated_ship.gd`, `apply_accessibility_settings()` (≈L306) — after the tracker push, before `_apply_world_label_scale()`:

```gdscript
	if tracker != null and tracker.has_method("apply_accessibility_settings"):
		tracker.apply_accessibility_settings(settings)
	if is_instance_valid(vitals_panel) and vitals_panel.has_method("apply_accessibility_settings"):
		vitals_panel.apply_accessibility_settings(settings)
	_apply_world_label_scale()
```

In `_build_hud_layer()` (≈L2356), after the panel is created and named, before `hud_layer.add_child(vitals_panel)`:

```gdscript
	vitals_model = PlayerVitalsModelScript.new()
	vitals_panel = PlayerVitalsPanelScript.new()
	vitals_panel.name = "PlayerVitalsPanel"
	# A11Y parity (ADR-0027): drive the vitals panel font/size from the same
	# accessibility seam as the tracker, before it is parented (its _ready then
	# builds at the stored scale).
	if vitals_panel.has_method("apply_accessibility_settings"):
		vitals_panel.apply_accessibility_settings(accessibility_settings)
	hud_layer.add_child(vitals_panel)
```

- [ ] **Step 5: Run the text-scale smoke — confirm GREEN; then the vitals render smoke**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_text_scale_smoke.gd 2>&1 | grep -E "TEXT SCALE (PASS|FAIL)"
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_vitals_hud_smoke.gd 2>&1 | grep -E "VITALS HUD (PASS|FAIL)"
```
Expected: `MAIN PLAYABLE TEXT SCALE PASS scales=3 …` and `MAIN PLAYABLE VITALS HUD PASS …` (default-scale render unchanged).

- [ ] **Step 6: Commit**

```bash
git add scripts/ui/player_vitals_panel.gd scripts/procgen/playable_generated_ship.gd scripts/validation/main_playable_slice_text_scale_smoke.gd
git commit -m "$(printf 'feat(hud): vitals panel accessibility parity with the objective tracker\n\nPlayerVitalsPanel now scales font/panel/label from the AccessibilitySettings\nseam (bottom-anchor offset scaled too); the coordinator pushes settings into\nit alongside the tracker. Text-scale smoke asserts vitals scaling at 1/1.5/2x.\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

### Task 4: Docs (ADR-0027 + roadmap) + full bundle green at 120

**Files:**
- Create: `docs/game/adr/0027-vitals-hud-cleanup.md`
- Modify: `docs/game/09_system_roadmap.md` (System 6 row — note the cleanup shipped)

**Interfaces:** none (docs + authoritative regression run).

- [ ] **Step 1: Write ADR-0027**

Create `docs/game/adr/0027-vitals-hud-cleanup.md`:

```markdown
# ADR-0027: Vitals/HUD cleanup — single-home oxygen/load, bundle + A11Y parity

Date: 2026-06-25
Status: Accepted
Supersedes (in part): the duplicated player-vitals lines implicit in ADR-0025.

## Context

The player-vitals slice (ADR-0025) added a bottom-left PlayerVitalsPanel that
renders oxygen, suit effect, load, and repair progress. The top-left
ObjectiveTracker still redundantly mirrored a terse `Oxygen:` line, a `Breach:`
line, and an inventory `weight=` line via `_combined_system_status_lines()`. The
orphaned `main_playable_slice_hud_smoke` was never registered in the regression
bundle, and the vitals panel — unlike the tracker — ignored the A11Y-P1-001
`AccessibilitySettings` text-scale seam.

## Decision

1. **The vitals panel is the sole home for player oxygen + load.** The tracker's
   combined status block drops `Oxygen:`, `Breach:`, and `weight=`. It keeps
   objectives, ship-system status, Routes/Extraction, carried `Tool:`/`item=`
   lines (REQ-007), and `Repair Skill:`. The de-dup is a coordinator-side filter;
   the pure models (`oxygen_state`, `inventory_state`) are unchanged so their
   model smokes still assert full output.
2. **The hazard smoke reads oxygen/breach from the vitals panel.** Its
   HUD-reflection assertions repoint to `get_player_vitals_lines()` (mapping the
   old separate `Breach: OPEN/SEALED` line to the vitals oxygen line's embedded
   `(BREACH)`/`(SEALED)`, and the zero-drive `BLOCKED` check to a "reflects zero"
   check since the vitals line has no BLOCKED token). Numeric drain/seal/recovery
   assertions still read `get_oxygen_summary()`.
3. **`main_playable_slice_hud_smoke` is registered** in the regression bundle
   (commands 119 → 120).
4. **PlayerVitalsPanel reaches A11Y parity** with ObjectiveTracker: it scales
   font/panel/label from the `AccessibilitySettings` seam, the coordinator pushes
   settings into it alongside the tracker, and the text-scale smoke asserts its
   scaling at 1.0/1.5/2.0×. Because the panel is bottom-anchored, its Y offset is
   computed from the scaled height so it grows upward instead of overflowing.

## Consequences

- Each player-vitals fact appears in exactly one HUD location.
- A top-left HUD regression is now guarded by a bundled smoke.
- Text-scale accessibility now covers both HUD panels.
- No model, gameplay, or world-4 persistence change; default scale (1.0) is
  pixel-identical to before.
```

- [ ] **Step 2: Update the system roadmap**

In `docs/game/09_system_roadmap.md`, in the System 6 row's evidence cell, append after the ADR-0026 clause (`equip-from-container … — ADR-0026 ✅`):

```
; vitals/HUD cleanup (oxygen/load de-duplicated to the vitals panel, orphaned HUD smoke bundled [120], PlayerVitalsPanel A11Y parity) — ADR-0027 ✅
```

- [ ] **Step 3: Run the full regression bundle (authoritative, count=120)**

```bash
GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
export GODOT ROOT
git -C "$ROOT" stash push -- project.godot
bash <(awk '/^## Regression bundle/{f=1} f && /^```bash$/ {c=1; next} f && c && /^```$/ {exit} f && c {print}' "$ROOT/docs/game/06_validation_plan.md")
git -C "$ROOT" stash pop
```
Expected final line: `SARGASSO REGRESSION PASS commands=120 clean_output=true`. (If the stash pop is skipped on a bundle failure, re-run `git stash pop` manually — never commit `project.godot`.)

- [ ] **Step 4: Commit**

```bash
git add docs/game/adr/0027-vitals-hud-cleanup.md docs/game/09_system_roadmap.md
git commit -m "$(printf 'docs(hud): ADR-0027 vitals/HUD cleanup + roadmap; bundle 120 green\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

## Notes for the executor

- Run every smoke with the `_console` Godot build and grep the marker; do not trust exit codes.
- Stage only the explicit paths named in each commit step. Never `git add -A` (it would stage `project.godot` / `.godot/` drift).
- Task order matters: Task 1's de-dup must land before Task 2 registers the HUD smoke (Task 1 keeps the bundle green at 119; Task 2 takes it to 120). Task 3 changes no bundle count. Task 4 is the single authoritative full-bundle run.
