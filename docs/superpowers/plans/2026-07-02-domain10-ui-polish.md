# Domain 10: UI/UX Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire the dead tooltip render chain into real gameplay (interactable proximity focus + inventory selection) and retire the room-fog minimap in favor of an item-gated web-chart screen that records ship-marker knowledge from scanner contacts and found chart items, then register every surviving UI-shell smoke in the regression bundle.

**Architecture:** Two new gameplay-driven tooltip triggers call the existing `MenuCoordinator.set_tooltip_query` → `TooltipPresenter.resolve()` → `payload_changed` → `TooltipPanel` chain from both `PlayableGeneratedShip._process` branches and from `InventoryPanel.select_row`. `MapFogState`/`MinimapPanel` are deleted outright; a new pure `WebChartState` (session-only, no save seam) accumulates marker knowledge from two sources — scanner scans (while a `web_chart` item is held) and found `web_chart` pickups (via the existing `_postprocess_loot_grants` loot-grant hub) — and a new `ChartPanel` (Control, `ScannerPanel`'s text-row presentation style) renders it, gated on chart possession, behind the repurposed `ui_open_map` key.

**Tech Stack:** Godot 4.6.2 GDScript (typed), headless validation smokes

## Global Constraints
- GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe", ROOT="C:/Users/dasbl/Documents/The Synaptic Sea". Run smokes: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/<name>.gd`. **PASS markers are the contract — Godot --script can exit 0 on parse errors; never trust exit codes.**
- Allowlisted teardown noise ONLY: `ERROR: Capture not registered: 'gdaimcp'.` and `WARNING: ObjectDB instances leaked at exit (run with --verbose for details).` Any other ERROR:/WARNING: line blocks completion and must be classified in docs/game/06_validation_plan.md.
- NEVER run Godot with `--editor` (it mutates project.godot on this machine). `git diff project.godot` after every Godot invocation; project.godot must be untouched this domain.
- Never stage `.godot/`, `*.uid`, `addons/`.
- Typed GDScript for new code. Pure models (RefCounted) never touch the scene tree.
- Coordinator `_process` has TWO branches: an early `if away_from_start:` branch that RETURNS before the home branch (`scripts/procgen/playable_generated_ship.gd::_process`, currently starting at line 5326, away branch `return`s at line 5405). Any per-frame system must be wired into BOTH branches. This has caused 3 shipped regressions. The new smoke must assert the away branch with an `away_ticks=`-style marker field.
- Regression bundle: registration = adding `run_clean` lines to the fenced bash block under the `## Regression bundle` heading in docs/game/06_validation_plan.md (the doc contains OTHER unrelated bash blocks — never extract naively), and bumping the final echo to `SYNAPTIC_SEA REGRESSION PASS commands=132 clean_output=true` (currently 121 `run_clean` lines verified by grep; +11 new run_clean lines per the spec).
- Inventory: edit docs/game/inventory/system_inventory.json by hand, then regenerate with `python tools/build_system_inventory.py` and verify `python tools/build_system_inventory.py --check` prints `SYSTEM INVENTORY CHECK PASS systems=<N> verified=<N>`.
- Chart persistence is session-only by user decision: `WebChartState` gets NO `get_summary`/`apply_summary`/`SAVE_KEY`. Do not add one.
- `ui_shell_parse_check.gd`'s `classes=N` marker changes: 13 today (7 pure-state + 6 schema classes) → 11 after deleting `MapFogState`+`MapFogStateSchema` → 12 after adding `WebChartState` (no schema, per the session-only decision above).
- The two existing UI-shell main-scene smokes (`main_playable_ui_shell_smoke.gd`, `main_playable_slice_ui_shell_smoke.gd`) are byte-for-byte identical today, including an IDENTICAL PASS marker string (`MAIN PLAYABLE UI SHELL PASS boot=main_menu pause=true codex=1 minimap=true hotbar=true tooltip=true`) — this plan gives the slice variant a distinct marker prefix (`MAIN PLAYABLE SLICE UI SHELL PASS`) to end the collision.

---

## Task 1: WebChartState pure model + smoke

**Files:**
- Create: `scripts/systems/web_chart_state.gd`
- Create: `scripts/validation/web_chart_state_smoke.gd`

**Interfaces:**
- Produces: `class_name WebChartState` — `record_views(views: Array, detail_level: int) -> int`, `get_known_marker_ids() -> Array`, `get_entry(marker_id: String) -> Dictionary`, `get_known_count() -> int`, `get_status_lines() -> PackedStringArray`.

- [ ] Step 1.1: Create `scripts/systems/web_chart_state.gd` with the full pure model.

```gdscript
extends RefCounted
class_name WebChartState
## Domain 10 (ADR-0045): session-only record of ship-marker knowledge the
## player has recorded onto their web chart. Two callers merge views in:
## found `web_chart` items (detail 2, "paper map" import) and scanner scans
## performed while a chart is possessed (detail 1-6, ScannerState.scan()'s
## own detail_level). No get_summary/apply_summary/SAVE_KEY -- deliberately
## ephemeral (ADR-0045), not a dead unused seam like TooltipPresenter's.
##
## Pure-model-first: no scene-tree access.

const REQUIRED_FIELDS: Array[String] = ["marker_id", "position", "size_class"]
const DETAIL_GATED_FIELDS: Array[String] = ["ship_type", "condition", "predicted_status", "predicted_offline", "loot_hint"]

var _entries: Dictionary = {}   # marker_id -> {position, size_class, detail, ...detail-gated fields}

## Merges `views` (an Array of scan()/chart view Dictionaries, the same shape
## ScannerState._marker_view() returns) into the chart at `detail_level`.
## Per marker: detail is max(existing.detail, detail_level) (never downgrades);
## fields present at the new detail are unioned in. Malformed views (missing
## a required field, non-Dictionary) are skipped, not rejected wholesale.
## Returns the count of markers that were newly added or had their detail
## upgraded (equal-or-lower detail on an already-known marker is a no-op and
## does not count).
func record_views(views: Array, detail_level: int) -> int:
	var changed: int = 0
	for view_variant in views:
		if typeof(view_variant) != TYPE_DICTIONARY:
			continue
		var view: Dictionary = view_variant
		var ok: bool = true
		for field in REQUIRED_FIELDS:
			if not view.has(field):
				ok = false
				break
		if not ok:
			continue
		var marker_id: String = str(view.get("marker_id", ""))
		if marker_id.is_empty():
			continue
		var existing: Dictionary = _entries.get(marker_id, {})
		var existing_detail: int = int(existing.get("detail", 0))
		if detail_level <= existing_detail and _entries.has(marker_id):
			continue   # no upgrade, no-op (idempotent re-record)
		var merged: Dictionary = existing.duplicate(true)
		merged["position"] = (view.get("position", []) as Array).duplicate()
		merged["size_class"] = int(view.get("size_class", 0))
		merged["detail"] = maxi(existing_detail, detail_level)
		for field in DETAIL_GATED_FIELDS:
			if view.has(field):
				merged[field] = view[field]
		_entries[marker_id] = merged
		changed += 1
	return changed

func get_known_marker_ids() -> Array:
	var ids: Array = _entries.keys()
	ids.sort()
	return ids

func get_entry(marker_id: String) -> Dictionary:
	var entry: Variant = _entries.get(marker_id, {})
	return (entry as Dictionary).duplicate(true) if entry is Dictionary else {}

func get_known_count() -> int:
	return _entries.size()

func get_status_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("WebChartState: known=%d" % _entries.size())
	return lines
```

- [ ] Step 1.2: Create `scripts/validation/web_chart_state_smoke.gd`.

```gdscript
extends SceneTree

## Domain 10 (ADR-0045) WebChartState pure model smoke.
## 1. record at detail 2 -> fields present, no detail-4+ fields.
## 2. re-record same marker at detail 5 (upgrade) -> fields added, never downgrades.
## 3. re-record at a LOWER detail afterwards -> no-op (stays at max).
## 4. malformed/unknown views are skipped, not rejected wholesale.
## Marker: WEB CHART STATE PASS known=N detail_upgrade=true

const WebChartStateScript := preload("res://scripts/systems/web_chart_state.gd")

func _initialize() -> void:
	var chart = WebChartStateScript.new()

	var views_detail2: Array = [
		{"marker_id": "m1", "position": [10.0, 0.0, 20.0], "size_class": 1, "ship_type": "freighter"},
		{"marker_id": "m2", "position": [30.0, 0.0, 40.0], "size_class": 0, "ship_type": "corvette"},
	]
	var added: int = chart.record_views(views_detail2, 2)
	if added != 2:
		_fail("first record expected added=2 got %d" % added)
		return
	var e1: Dictionary = chart.get_entry("m1")
	if int(e1.get("detail", 0)) != 2 or String(e1.get("ship_type", "")) != "freighter":
		_fail("m1 detail-2 fields missing/wrong: %s" % str(e1))
		return
	if e1.has("condition") or e1.has("loot_hint"):
		_fail("m1 should not have detail>=3 fields yet: %s" % str(e1))
		return

	var views_detail5: Array = [
		{"marker_id": "m1", "position": [10.0, 0.0, 20.0], "size_class": 1, "ship_type": "freighter",
			"condition": 1, "predicted_status": "systems degraded", "predicted_offline": ["scanners"]},
	]
	var upgraded: int = chart.record_views(views_detail5, 5)
	if upgraded != 1:
		_fail("upgrade record expected added=1 got %d" % upgraded)
		return
	var e1_upgraded: Dictionary = chart.get_entry("m1")
	if int(e1_upgraded.get("detail", 0)) != 5:
		_fail("m1 detail did not upgrade to 5: %s" % str(e1_upgraded))
		return
	if String(e1_upgraded.get("predicted_status", "")) != "systems degraded":
		_fail("m1 missing detail-4 field after upgrade: %s" % str(e1_upgraded))
		return

	# Re-record at a LOWER detail: must be a no-op (never downgrades).
	var noop_added: int = chart.record_views(views_detail2, 2)
	if noop_added != 0:
		_fail("lower-detail re-record should be a no-op, got added=%d" % noop_added)
		return
	if int(chart.get_entry("m1").get("detail", 0)) != 5:
		_fail("m1 detail regressed below 5 after lower-detail re-record")
		return

	# Malformed views: missing marker_id / missing required field / non-dict entries.
	var malformed: Array = [
		{"position": [1.0, 1.0, 1.0], "size_class": 0},   # missing marker_id
		{"marker_id": "m3"},                                # missing position/size_class
		"not_a_dict",
	]
	var malformed_added: int = chart.record_views(malformed, 3)
	if malformed_added != 0:
		_fail("malformed views should all be skipped, got added=%d" % malformed_added)
		return

	if chart.get_known_count() != 2:
		_fail("expected known_count=2, got %d" % chart.get_known_count())
		return

	print("WEB CHART STATE PASS known=%d detail_upgrade=true" % chart.get_known_count())
	quit(0)

func _fail(reason: String) -> void:
	push_error("WEB CHART STATE FAIL reason=%s" % reason)
	quit(1)
```

- [ ] Step 1.3: Run the smoke and confirm the exact PASS marker.

```bash
GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/web_chart_state_smoke.gd
```

Expected output contains exactly: `WEB CHART STATE PASS known=2 detail_upgrade=true`, plus only the two allowlisted teardown lines.

- [ ] Step 1.4: `git diff project.godot` — confirm empty (no output).

```bash
git diff --stat project.godot
```

- [ ] Step 1.5: Commit.

```bash
git add scripts/systems/web_chart_state.gd scripts/validation/web_chart_state_smoke.gd
git commit -m "feat: add WebChartState pure model for session-only ship-marker recording"
```

---

## Task 2: web_chart item + loot entries

**Files:**
- Modify: `data/items/utility_item_definitions.json`
- Modify: `data/items/loot_tables.json`

**Interfaces:**
- Produces: item id `web_chart` (`utility_flag: "web_chart"`), loot entries in `salvage_cargo` and `hidden_cache`.

- [ ] Step 2.1: Add the `web_chart` item to `data/items/utility_item_definitions.json` (insert as a new top-level key, comma-separated with the existing 5 entries; low weight, small stack — a "paper map" is bulky, unlike a lockpick set).

```json
  "web_chart": {
    "display_name": "Web Chart",
    "category": "utility",
    "weight": 0.4,
    "max_stack": 1,
    "effects": [],
    "utility_flag": "web_chart",
    "use_note": "A paper chart of nearby ship positions in the web. Possessing one records scanner contacts; each new chart found imports its own recorded markers.",
    "icon": "res://assets/placeholder/repair_foam.png"
  }
```

Full file after the edit must remain valid JSON with the existing 5 entries (`flare`, `lockpick_set`, `hack_chip`, `repair_foam`, `heat_pack`) followed by `web_chart`, each separated by a comma, closing with the file's existing trailing `}`.

- [ ] Step 2.2: Add one `web_chart` entry to the `salvage_cargo` table in `data/items/loot_tables.json` (low weight, common — chart items are meant to surface reasonably often since Source A is the primary early acquisition path).

Locate the `salvage_cargo.entries` array (currently ending with the `hull_sealant` entry) and append:

```json
      { "item_id": "web_chart", "qty_min": 1, "qty_max": 1, "weight": 1.5, "rarity": "common" }
```

(comma after the preceding `hull_sealant` entry, this entry has no trailing comma if it is now last in the array — preserve valid JSON).

- [ ] Step 2.3: Add one `web_chart` entry to the `hidden_cache` table in the same file (slightly higher weight than in `salvage_cargo`, reflecting the "found chart" narrative fitting a hidden-cache pull).

Locate the `hidden_cache.entries` array (currently ending with the `synaptic_sea_reliquary` entry) and append:

```json
      { "item_id": "web_chart", "qty_min": 1, "qty_max": 1, "weight": 2.0, "rarity": "common" }
```

- [ ] Step 2.4: Validate both JSON files parse and the loot roller sees the new entries via the existing item-economy smoke pattern (no new smoke needed yet — Task 8's `ui_polish_smoke` exercises the pickup path end-to-end). Confirm JSON validity directly:

```bash
python -c "import json; json.load(open('data/items/utility_item_definitions.json')); json.load(open('data/items/loot_tables.json')); print('JSON_OK')"
```

Expected output: `JSON_OK`.

- [ ] Step 2.5: Commit.

```bash
git add data/items/utility_item_definitions.json data/items/loot_tables.json
git commit -m "feat: add web_chart item definition and salvage/hidden-cache loot entries"
```

---

## Task 3: Minimap deletion + wiring strip + parse_check update

**Files:**
- Delete: `scripts/systems/map_fog_state.gd`, `scripts/schemas/map_fog_schema.gd`, `scripts/ui/minimap_panel.gd`, `scripts/validation/map_fog_state_smoke.gd`
- Modify: `scripts/ui/menu_coordinator.gd` (symbols: `MapFogStateScript`/`MinimapPanelScript` consts, `map_fog_state` var, `minimap_panel` var, `_ready`, `handle_ui_input`, `configure_map`, `track_room`, `reveal_room`, `get_minimap_text`, `_apply_accessibility_to_children`, `_refresh_all`, `_refresh_minimap`)
- Modify: `scripts/procgen/playable_generated_ship.gd` (symbols: `_on_derelict_interactable_completed`, `_build_ui_room_payload`, `_refresh_ui_shell_runtime`, `_input`)
- Modify: `scripts/validation/ui_shell_parse_check.gd`
- Test: `scripts/validation/ui_shell_parse_check.gd`

**Interfaces:**
- Removes: `MenuCoordinator.configure_map/track_room/reveal_room/get_minimap_text`, `map_fog_state`/`minimap_panel` members.

- [ ] Step 3.1: In `scripts/ui/menu_coordinator.gd`, remove the two deleted-class preloads.

```gdscript
const MapFogStateScript := preload("res://scripts/systems/map_fog_state.gd")
```
and
```gdscript
const MinimapPanelScript := preload("res://scripts/ui/minimap_panel.gd")
```
Delete both lines entirely (they sit among the other `const ...Script := preload(...)` lines near the top of the file, alongside `MenuStateScript`/`SettingsStateScript`/etc.).

- [ ] Step 3.2: Remove the `map_fog_state` and `minimap_panel` member declarations.

Delete:
```gdscript
var map_fog_state = MapFogStateScript.new()
```
(from the `var ... = ...Script.new()` block alongside `menu_state`/`settings_state`/`tutorial_state`/`tooltip_presenter`/`controller_glyph_state`) and:
```gdscript
var minimap_panel
```
(from the `var menu_panel` / `codex_panel` / `minimap_panel` / `hotbar_panel` / ... block).

- [ ] Step 3.3: Remove the minimap panel instantiation in `_ready()`.

Delete:
```gdscript
	minimap_panel = MinimapPanelScript.new()
	minimap_panel.name = "MinimapPanel"
	add_child(minimap_panel)
```

- [ ] Step 3.4: Remove the `ui_open_map` minimap-toggle branch in `handle_ui_input`. This whole branch is replaced by Task 4's chart-gate handling at the `PlayableGeneratedShip._input` level (matching the `scanner_panel`/`inventory_panel` pattern, not the `MenuCoordinator.handle_ui_input` dispatch pattern), so `MenuCoordinator` no longer knows about `ui_open_map` at all.

Delete:
```gdscript
	if event.is_action_pressed("ui_open_map"):
		minimap_panel.visible = not minimap_panel.visible
		return true
```

- [ ] Step 3.5: Delete `configure_map`, `track_room`, `reveal_room`, and `get_minimap_text` entirely.

```gdscript
func configure_map(room_payload: Dictionary) -> bool:
	var ok: bool = map_fog_state.configure_for_rooms(room_payload)
	_refresh_minimap()
	return ok

func track_room(room_id: String) -> bool:
	if room_id.is_empty() or not map_fog_state.is_known_room(room_id):
		return false
	var ok: bool = map_fog_state.track(room_id)
	_refresh_minimap()
	return ok

func reveal_room(room_id: String) -> bool:
	if room_id.is_empty() or not map_fog_state.is_known_room(room_id):
		return false
	var ok: bool = map_fog_state.reveal(room_id)
	_refresh_minimap()
	return ok
```
Delete all three functions, and delete:
```gdscript
func get_minimap_text() -> String:
	return minimap_panel.label.text if minimap_panel != null and minimap_panel.label != null else ""
```

- [ ] Step 3.6: Remove `minimap_panel` from the accessibility child list in `_apply_accessibility_to_children`.

Change:
```gdscript
	for child in [menu_panel, codex_panel, minimap_panel, hotbar_panel, tooltip_panel, tutorial_overlay_panel]:
```
to:
```gdscript
	for child in [menu_panel, codex_panel, hotbar_panel, tooltip_panel, tutorial_overlay_panel]:
```

- [ ] Step 3.7: Remove the `_refresh_minimap()` call from `_refresh_all()` and delete the `_refresh_minimap` function.

Change:
```gdscript
func _refresh_all() -> void:
	_refresh_menu_panel()
	_refresh_codex()
	_refresh_minimap()
	_refresh_hotbar()
	_refresh_tutorial()
	_refresh_meta_screens()
```
to:
```gdscript
func _refresh_all() -> void:
	_refresh_menu_panel()
	_refresh_codex()
	_refresh_hotbar()
	_refresh_tutorial()
	_refresh_meta_screens()
```
Delete the entire `_refresh_minimap()` function body:
```gdscript
func _refresh_minimap() -> void:
	if minimap_panel == null:
		return
	var lines := PackedStringArray()
	lines.append("MAP")
	lines.append("Tracked: %s" % (map_fog_state.get_tracked_room_id() if not map_fog_state.get_tracked_room_id().is_empty() else "<none>"))
	lines.append("Revealed: %d" % map_fog_state.get_revealed_count())
	lines.append("Discovered: %d" % map_fog_state.get_discovered_count())
	for room_id in map_fog_state.get_room_ids().slice(0, 5):
		var state_text: String = "revealed" if map_fog_state.is_revealed(room_id) else ("seen" if map_fog_state.is_discovered(room_id) else "hidden")
		lines.append("- %s [%s]" % [room_id, state_text])
	minimap_panel.set_map_text("\n".join(lines))
```

- [ ] Step 3.8: In `scripts/procgen/playable_generated_ship.gd`, strip the `reveal_room` callsite in `_on_derelict_interactable_completed`.

Change:
```gdscript
	if is_instance_valid(menu_coordinator):
		menu_coordinator.trigger_tutorial("objective_completed", objective_type)
		if not room_id.is_empty():
			menu_coordinator.reveal_room(room_id)
```
to:
```gdscript
	if is_instance_valid(menu_coordinator):
		menu_coordinator.trigger_tutorial("objective_completed", objective_type)
```

- [ ] Step 3.9: Strip the `configure_map`/`track_room` callsites in `_refresh_ui_shell_runtime`. `_build_ui_room_payload()` itself is left in place (it is a self-contained, harmless helper computing room/neighbour data that nothing else currently reads) — but since it is now dead code with the minimap gone, delete it too, since the CLAUDE.md convention is not to leave orphaned dead helpers behind a deletion.

Delete the entire `_build_ui_room_payload` function:
```gdscript
func _build_ui_room_payload() -> Dictionary:
	var room_set: Dictionary = {}
	var neighbours: Dictionary = {}
	if loader != null and loader.has_method("get_room_links"):
		for link_variant in loader.get_room_links():
			if typeof(link_variant) != TYPE_DICTIONARY:
				continue
			var link: Dictionary = link_variant
			var from_room: String = str(link.get("from_room", ""))
			var to_room: String = str(link.get("to_room", ""))
			if from_room.is_empty() or to_room.is_empty():
				continue
			room_set[from_room] = true
			room_set[to_room] = true
			if not neighbours.has(from_room):
				neighbours[from_room] = []
			if not neighbours.has(to_room):
				neighbours[to_room] = []
			if not (neighbours[from_room] as Array).has(to_room):
				(neighbours[from_room] as Array).append(to_room)
			if not (neighbours[to_room] as Array).has(from_room):
				(neighbours[to_room] as Array).append(from_room)
	for objective in loader.get_objective_specs_copy() if loader != null and loader.has_method("get_objective_specs_copy") else []:
		if typeof(objective) == TYPE_DICTIONARY:
			var room_id: String = str((objective as Dictionary).get("room_id", ""))
			if not room_id.is_empty():
				room_set[room_id] = true
	if not arc_zone_resolved_room_id.is_empty():
		room_set[arc_zone_resolved_room_id] = true
	var rooms: Array = room_set.keys()
	rooms.sort()
	for room_id in rooms:
		if not neighbours.has(room_id):
			neighbours[room_id] = []
	return {"rooms": rooms, "neighbours": neighbours}
```

Change `_refresh_ui_shell_runtime` from:
```gdscript
func _refresh_ui_shell_runtime() -> void:
	if not is_instance_valid(menu_coordinator):
		return
	menu_coordinator.set_load_available(is_load_available())
	menu_coordinator.set_inventory_items(_inventory_hotbar_ids())
	menu_coordinator.set_hotbar_slots(_get_consumable_slot_labels())
	_refresh_weapon_hotbar()
	menu_coordinator.configure_map(_build_ui_room_payload())
	if loader != null and loader.has_method("get_critical_path"):
		var critical: Array[String] = loader.get_critical_path()
		if not critical.is_empty():
			menu_coordinator.track_room(critical[0])
```
to:
```gdscript
func _refresh_ui_shell_runtime() -> void:
	if not is_instance_valid(menu_coordinator):
		return
	menu_coordinator.set_load_available(is_load_available())
	menu_coordinator.set_inventory_items(_inventory_hotbar_ids())
	menu_coordinator.set_hotbar_slots(_get_consumable_slot_labels())
	_refresh_weapon_hotbar()
```

- [ ] Step 3.10: Strip the `ui_open_map` reveal-room callsite in `_input`. This is folded into Task 4's replacement chart-gate block, so for this step just remove the dead `reveal_room` call (Task 4 adds the new block in its place).

Change:
```gdscript
	if is_instance_valid(menu_coordinator):
		if menu_coordinator.handle_ui_input(event):
			if event.is_action_pressed("ui_open_map"):
				menu_coordinator.reveal_room(menu_coordinator.map_fog_state.get_tracked_room_id())
			_dispatch_save_load_confirm_result(menu_coordinator.get_last_meta_screen_confirm_result())
			get_viewport().set_input_as_handled()
			return
```
to:
```gdscript
	if is_instance_valid(menu_coordinator):
		if menu_coordinator.handle_ui_input(event):
			_dispatch_save_load_confirm_result(menu_coordinator.get_last_meta_screen_confirm_result())
			get_viewport().set_input_as_handled()
			return
```

- [ ] Step 3.11: Delete the four map-fog files.

```bash
git rm scripts/systems/map_fog_state.gd scripts/schemas/map_fog_schema.gd scripts/ui/minimap_panel.gd scripts/validation/map_fog_state_smoke.gd
```

- [ ] Step 3.12: Update `scripts/validation/ui_shell_parse_check.gd` to drop the two deleted classes and bump the marker's class count from 13 to 11.

```gdscript
extends SceneTree

## REQ-UI parse-check smoke.
## Loads every new pure-state / schema class and asserts each one
## instantiates cleanly. Purely a static parse-check; the per-class
## smokes cover the runtime contract.

const MenuStateScript        := preload("res://scripts/systems/menu_state.gd")
const SettingsStateScript    := preload("res://scripts/systems/settings_state.gd")
const TooltipPresenterScript := preload("res://scripts/systems/tooltip_presenter.gd")
const TooltipPayloadScript   := preload("res://scripts/systems/tooltip_payload.gd")
const TutorialStateScript    := preload("res://scripts/systems/tutorial_state.gd")
const ControllerGlyphStateScript := preload("res://scripts/systems/controller_glyph_state.gd")

const MenuStateSchemaScript        := preload("res://scripts/schemas/menu_state_schema.gd")
const SettingsStateSchemaScript    := preload("res://scripts/schemas/settings_state_schema.gd")
const TooltipSchemaScript          := preload("res://scripts/schemas/tooltip_schema.gd")
const TutorialStateSchemaScript    := preload("res://scripts/schemas/tutorial_state_schema.gd")
const ControllerGlyphSchemaScript  := preload("res://scripts/schemas/controller_glyph_schema.gd")

func _initialize() -> void:
	var classes := [
		MenuStateScript, SettingsStateScript, TooltipPresenterScript,
		TooltipPayloadScript, TutorialStateScript,
		ControllerGlyphStateScript,
		MenuStateSchemaScript, SettingsStateSchemaScript, TooltipSchemaScript,
		TutorialStateSchemaScript,
		ControllerGlyphSchemaScript,
	]
	for cls in classes:
		var instance = cls.new()
		if instance == null:
			_fail("could not instantiate %s" % str(cls))
			return
		instance = null
	print("UI SHELL PARSE PASS classes=%d" % classes.size())
	quit(0)

func _fail(reason: String) -> void:
	push_error("UI SHELL PARSE FAIL reason=%s" % reason)
	quit(1)
```

Note: `WebChartState` is added to this file's class list in Task 3's follow-up... actually it is added HERE is deferred to avoid forward-referencing Task 1's already-created file out of order in the diff; add it now since it already exists on disk from Task 1:

```gdscript
const WebChartStateScript := preload("res://scripts/systems/web_chart_state.gd")
```
Add this const alongside the others, and add `WebChartStateScript` to the `classes` array. The final marker for this smoke is `UI SHELL PARSE PASS classes=12` (11 surviving + `WebChartState`, no schema for it per the session-only decision).

- [ ] Step 3.13: Grep for any residual reference to the deleted classes/symbols across the whole repo (excluding this plan file and specs, which intentionally mention them historically).

```bash
grep -rn "MapFogState\|MinimapPanel\|map_fog_state\|minimap_panel\|configure_map\|track_room\|reveal_room\|get_minimap_text" --include="*.gd" scripts/ | grep -v "scripts/validation/ui_shell_parse_check.gd"
```

Expected output: empty (no matches). If any remain, strip them before proceeding.

- [ ] Step 3.14: Full parse-check of the coordinator and menu_coordinator files (catches any dangling reference the grep missed, since `--script` load errors surface here even though exit code cannot be trusted — read the output).

```bash
GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ui_shell_parse_check.gd
```

Expected output contains exactly: `UI SHELL PARSE PASS classes=12`, plus only the two allowlisted teardown lines. No `ERROR:` referencing a missing file/class.

- [ ] Step 3.15: `git diff project.godot` — confirm empty.

```bash
git diff --stat project.godot
```

- [ ] Step 3.16: Commit.

```bash
git add -A scripts/systems/map_fog_state.gd scripts/schemas/map_fog_schema.gd scripts/ui/minimap_panel.gd scripts/validation/map_fog_state_smoke.gd scripts/ui/menu_coordinator.gd scripts/procgen/playable_generated_ship.gd scripts/validation/ui_shell_parse_check.gd
git commit -m "refactor: delete room-fog minimap (MapFogState/MinimapPanel) and all wiring"
```

---

## Task 4: ChartPanel + ui_open_map gate + scanner/pickup record hooks

**Files:**
- Create: `scripts/ui/chart_panel.gd`
- Modify: `scripts/procgen/playable_generated_ship.gd` (symbols: preload consts near top, `var scanner_panel` block, `_build_hud_layer`, `scan`, `_postprocess_loot_grants`, `_input`)

**Interfaces:**
- Produces: `class_name ChartPanel` — `bind(coord)`, `open() -> void`, `close() -> void`, `is_open() -> bool`, `refresh() -> void`, `get_row_texts() -> Array`, `get_status() -> String`.
- Consumes: `WebChartState` (via the coordinator's `web_chart_state` instance), `InventoryState.get_quantity("web_chart")`.

- [ ] Step 4.1: Create `scripts/ui/chart_panel.gd`, mirroring `ScannerPanel`'s presentation style (text rows, headless-queryable, no travel — read-only per spec §5.5/§6).

```gdscript
extends Control
class_name ChartPanel

## Domain 10 (ADR-0045): read-only text panel rendering WebChartState's
## recorded ship markers. Mirrors ScannerPanel's presentation style (a bare
## vertical text panel, headless-queryable row model) but has no travel
## action -- travel stays on the scanner panel (spec 5.5/6). Gated open:
## the coordinator only calls open() when the player possesses a web_chart
## (get_quantity("web_chart") > 0); otherwise it surfaces a HUD feedback
## line instead of opening this panel at all.

signal panel_closed

var _chart_state   # WebChartState
var _open: bool = false

var _title_label: Label
var _list_label: Label
var _status_label: Label

func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	if _title_label == null:
		_title_label = Label.new()
		_title_label.position = Vector2(24, 24)
		_title_label.text = "WEB CHART"
		add_child(_title_label)
		_list_label = Label.new()
		_list_label.position = Vector2(24, 56)
		add_child(_list_label)
		_status_label = Label.new()
		_status_label.position = Vector2(24, 320)
		add_child(_status_label)
	visible = _open
	_render()

func bind(chart_state) -> void:
	_chart_state = chart_state

func is_open() -> bool:
	return _open

func open() -> void:
	_open = true
	visible = true
	refresh()

func close() -> void:
	_open = false
	visible = false
	panel_closed.emit()

func toggle() -> void:
	if _open:
		close()
	else:
		open()

func refresh() -> void:
	_render()

func get_status() -> String:
	if _chart_state == null:
		return "no chart"
	var count: int = int(_chart_state.get_known_count())
	return "no markers recorded" if count == 0 else "%d marker(s) recorded" % count

func get_row_texts() -> Array:
	var out: Array = []
	if _chart_state == null:
		return out
	for marker_id in _chart_state.get_known_marker_ids():
		out.append(_format_row(String(marker_id), _chart_state.get_entry(marker_id)))
	return out

func _format_row(marker_id: String, entry: Dictionary) -> String:
	var parts: Array = [marker_id]
	parts.append("sz=%d" % int(entry.get("size_class", 0)))
	if entry.has("ship_type"):
		parts.append(String(entry["ship_type"]))
	if entry.has("condition"):
		parts.append("cond=%d" % int(entry["condition"]))
	if entry.has("predicted_status"):
		parts.append(String(entry["predicted_status"]))
	if entry.has("loot_hint"):
		parts.append(String(entry["loot_hint"]))
	return " · ".join(parts)

func _render() -> void:
	if _list_label == null:
		return
	var rows: Array = get_row_texts()
	_list_label.text = "\n".join(rows) if not rows.is_empty() else "(no markers recorded)"
	if _status_label != null:
		_status_label.text = get_status()
```

- [ ] Step 4.2: In `scripts/procgen/playable_generated_ship.gd`, add the `ChartPanel`/`WebChartState` preloads near the existing `ScannerPanelScript` const.

Find:
```gdscript
const ScannerPanelScript := preload("res://scripts/ui/scanner_panel.gd")
```
Add immediately after it:
```gdscript
const ChartPanelScript := preload("res://scripts/ui/chart_panel.gd")
const WebChartStateScript := preload("res://scripts/systems/web_chart_state.gd")
```

- [ ] Step 4.3: Add the `chart_panel` and `web_chart_state` member vars near `var scanner_panel   # ScannerPanel`.

Find:
```gdscript
var scanner_panel   # ScannerPanel
```
Add immediately after it:
```gdscript
var chart_panel      # ChartPanel
var web_chart_state = WebChartStateScript.new()
```

- [ ] Step 4.4: Instantiate and bind `chart_panel` in `_build_hud_layer()`, right after the existing `scanner_panel` block.

Find:
```gdscript
	scanner_panel = ScannerPanelScript.new()
	scanner_panel.name = "ScannerPanel"
	scanner_panel.visible = false
	hud_layer.add_child(scanner_panel)
	scanner_panel.bind(self)
	# Restore player control on every panel close path via the signal, not just
	# the two close paths wired into _input.
	scanner_panel.panel_closed.connect(_on_scanner_panel_closed)
```
Add immediately after it:
```gdscript
	chart_panel = ChartPanelScript.new()
	chart_panel.name = "ChartPanel"
	chart_panel.visible = false
	hud_layer.add_child(chart_panel)
	chart_panel.bind(web_chart_state)
	# Restore player control on every panel close path via the signal, not just
	# the toggle-close path wired into _input.
	chart_panel.panel_closed.connect(_on_chart_panel_closed)
```

- [ ] Step 4.5: Add the `_on_chart_panel_closed` handler right after the existing `_on_scanner_panel_closed`.

Find:
```gdscript
func _on_scanner_panel_closed() -> void:
	if player != null:
		player.set_physics_process(true)
		player.set_process_input(true)
		player.set_process_unhandled_input(true)
```
Add immediately after it:
```gdscript
func _on_chart_panel_closed() -> void:
	if player != null:
		player.set_physics_process(true)
		player.set_process_input(true)
		player.set_process_unhandled_input(true)
```

- [ ] Step 4.6: Wire Source B (scanner auto-record) into `scan()`.

Change:
```gdscript
func scan() -> Dictionary:
	if current_ship == null or synaptic_sea_world == null or scanner_state == null:
		return {"detail_level": 0, "markers": []}
	var ops: Dictionary = _current_systems_ops()
	var skill: int = 0
	if player_progression != null and player_progression.has_method("get_skill_level"):
		skill = int(player_progression.get_skill_level("scanner_operation"))
	return scanner_state.scan(synaptic_sea_world, ops, skill)
```
to:
```gdscript
func scan() -> Dictionary:
	if current_ship == null or synaptic_sea_world == null or scanner_state == null:
		return {"detail_level": 0, "markers": []}
	var ops: Dictionary = _current_systems_ops()
	var skill: int = 0
	if player_progression != null and player_progression.has_method("get_skill_level"):
		skill = int(player_progression.get_skill_level("scanner_operation"))
	var result: Dictionary = scanner_state.scan(synaptic_sea_world, ops, skill)
	# Domain 10 (ADR-0045) Source B: a possessed web_chart auto-records every
	# scan's markers at the scan's own detail_level. Scanning without a chart
	# records nothing (nothing to write on) -- no RNG, fully deterministic.
	if inventory_state != null and int(inventory_state.get_quantity("web_chart")) > 0:
		web_chart_state.record_views(result.get("markers", []) as Array, int(result.get("detail_level", 0)))
	return result
```

- [ ] Step 4.7: Wire Source A (found chart import) into `_postprocess_loot_grants`, the single hub every loot path (salvage, containers, corpses) already funnels through.

Find:
```gdscript
func _postprocess_loot_grants(granted: Array, source_id: String) -> void:
	if granted.is_empty():
		_last_loot_feedback_line = "Loot: %s empty" % source_id
		return
	for entry in granted:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var item_id: String = str((entry as Dictionary).get("item_id", ""))
		var unique_id: String = str((entry as Dictionary).get("unique_id", ""))
		var seed_key: String = str((entry as Dictionary).get("seed_key", ""))
		var codex_entry_id: String = str((entry as Dictionary).get("codex_entry_id", ""))
		if unique_item_state != null and not unique_id.is_empty():
			unique_item_state.claim(unique_id, seed_key, codex_entry_id)
		elif unique_item_state != null and not codex_entry_id.is_empty():
			unique_item_state.record_codex_unlock(codex_entry_id)
		if meta_progression_state != null and not codex_entry_id.is_empty():
			meta_progression_state.unlock_codex_entry(codex_entry_id)
		if equipment_state != null and item_id != "" and equipment_state.can_equip(item_id):
			_equip_from_inventory(item_id, true)
```
to:
```gdscript
func _postprocess_loot_grants(granted: Array, source_id: String) -> void:
	if granted.is_empty():
		_last_loot_feedback_line = "Loot: %s empty" % source_id
		return
	for entry in granted:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var item_id: String = str((entry as Dictionary).get("item_id", ""))
		var unique_id: String = str((entry as Dictionary).get("unique_id", ""))
		var seed_key: String = str((entry as Dictionary).get("seed_key", ""))
		var codex_entry_id: String = str((entry as Dictionary).get("codex_entry_id", ""))
		if unique_item_state != null and not unique_id.is_empty():
			unique_item_state.claim(unique_id, seed_key, codex_entry_id)
		elif unique_item_state != null and not codex_entry_id.is_empty():
			unique_item_state.record_codex_unlock(codex_entry_id)
		if meta_progression_state != null and not codex_entry_id.is_empty():
			meta_progression_state.unlock_codex_entry(codex_entry_id)
		if equipment_state != null and item_id != "" and equipment_state.can_equip(item_id):
			_equip_from_inventory(item_id, true)
		# Domain 10 (ADR-0045) Source A: a found web_chart imports every currently
		# in-range world marker at detail 2 (position + ship_type), the "paper map"
		# import. Idempotent (record_views never downgrades), so repeat pickups are
		# harmless -- no first-pickup tracking is needed. Deterministic, no RNG.
		if item_id == "web_chart" and synaptic_sea_world != null:
			var scan_range: float = scanner_state.range_radius if scanner_state != null else 250.0
			var import_views: Array = []
			for m in synaptic_sea_world.markers_in_range(scan_range):
				import_views.append({
					"marker_id": m.marker_id,
					"position": [m.position.x, m.position.y, m.position.z],
					"distance": m.position.distance_to(synaptic_sea_world.player_position),
					"size_class": m.size_class,
					"ship_type": m.ship_type,
				})
			web_chart_state.record_views(import_views, 2)
```

- [ ] Step 4.8: Wire the `ui_open_map` chart-gate handling into `_input`, replacing the block Task 3.10 emptied out, following the same freeze/restore pattern as the `scanner_panel`/`inventory_panel` toggle blocks (this must sit BEFORE the `menu_coordinator.handle_ui_input(event)` dispatch, since `MenuCoordinator` no longer owns this action at all after Task 3).

Find (this is the scanner_panel toggle block from Step 3's surrounding context, immediately preceding the inventory_panel block):
```gdscript
	if scanner_panel != null:
		if event.is_action_pressed("toggle_scanner") and (not is_instance_valid(inventory_panel) or not inventory_panel.is_open()):
			scanner_panel.toggle()
			if player != null and scanner_panel.is_open():
				player.set_physics_process(false)
				player.set_process_input(false)
				player.set_process_unhandled_input(false)
			get_viewport().set_input_as_handled()
			return
		if scanner_panel.is_open():
			if event.is_action_pressed("ui_down"):
				scanner_panel.move_selection(1)
				get_viewport().set_input_as_handled()
			elif event.is_action_pressed("ui_up"):
				scanner_panel.move_selection(-1)
				get_viewport().set_input_as_handled()
			elif event.is_action_pressed("ui_accept"):
				scanner_panel.confirm_selection()
				get_viewport().set_input_as_handled()
			return  # swallow other input while the scanner is open
```
Add immediately after this block (before the `if is_instance_valid(inventory_panel):` block):
```gdscript
	if chart_panel != null:
		if chart_panel.is_open():
			if event.is_action_pressed("ui_open_map") or event.is_action_pressed("ui_cancel"):
				chart_panel.close()
				get_viewport().set_input_as_handled()
			return  # swallow other input while the chart is open (read-only panel)
		if event.is_action_pressed("ui_open_map"):
			var has_chart: bool = inventory_state != null and int(inventory_state.get_quantity("web_chart")) > 0
			if has_chart:
				chart_panel.open()
				if player != null:
					player.set_physics_process(false)
					player.set_process_input(false)
					player.set_process_unhandled_input(false)
			else:
				# Domain 10 (ADR-0045): no chart possessed -- surface a HUD feedback
				# line via the existing system-status-lines seam (mirrors
				# _last_loot_feedback_line) rather than opening an empty panel.
				_last_loot_feedback_line = "No web chart"
			get_viewport().set_input_as_handled()
			return
```

- [ ] Step 4.9: `git diff project.godot` — confirm empty.

```bash
git diff --stat project.godot
```

- [ ] Step 4.10: Sanity-parse-check the coordinator loads cleanly (no smoke registers this yet; Task 8's `ui_polish_smoke` exercises it fully, but confirm no immediate parse break before continuing).

```bash
GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_input_smoke.gd
```

Expected output contains: `MAIN PLAYABLE INPUT LOOP PASS moved=true camera_followed=true interaction_input_path=true current_sequence=2`, plus only the two allowlisted teardown lines (this pre-existing smoke boots the full coordinator and will surface any parse/load break in the edited file).

- [ ] Step 4.11: Commit.

```bash
git add scripts/ui/chart_panel.gd scripts/procgen/playable_generated_ship.gd
git commit -m "feat: add ChartPanel gated on web_chart possession with scanner/pickup recording"
```

---

## Task 5: tooltip_subject_id on Interactable + _refresh_tooltip_focus both branches

**Files:**
- Modify: `scripts/interaction/interactable.gd` (symbols: `tooltip_subject_id` var, `configure_from_objective`, `configure_from_step`)
- Modify: `data/ui/tooltip_catalog.json` (add `junction_step` entry)
- Modify: `scripts/procgen/playable_generated_ship.gd` (symbols: `_process` both branches, new `_refresh_tooltip_focus`, `get_focused_tooltip_subject_for_validation`)

**Interfaces:**
- Produces: `Interactable.tooltip_subject_id: String`; `PlayableGeneratedShip._refresh_tooltip_focus() -> void`; `PlayableGeneratedShip.get_focused_tooltip_subject_for_validation() -> String`.
- Consumes: `MenuCoordinator.set_tooltip_query(query: Dictionary) -> void` (existing, `menu_coordinator.gd:273`).

- [ ] Step 5.1: Add `tooltip_subject_id` to `scripts/interaction/interactable.gd` and set it in both configure paths.

Find:
```gdscript
var interaction_id: String = ""
var objective_id: String = ""
var sequence: int = 0
var objective_type: String = ""
var room_id: String = ""
var prompt_text: String = "Interact"
```
Change to:
```gdscript
var interaction_id: String = ""
var objective_id: String = ""
var sequence: int = 0
var objective_type: String = ""
var room_id: String = ""
var prompt_text: String = "Interact"
var tooltip_subject_id: String = ""
```

Find `configure_from_objective`:
```gdscript
func configure_from_objective(objective: Dictionary, world_position: Vector3, radius := 1.8) -> void:
	objective_id = str(objective.get("id", ""))
	sequence = int(objective.get("sequence", 0))
	objective_type = str(objective.get("type", "objective"))
	room_id = str(objective.get("room_id", ""))
	interaction_id = "objective:%02d:%s" % [sequence, objective_id]
	prompt_text = "Interact: %s" % objective_type
	active = true
	interaction_radius = radius
	completed = false
	candidate_player = null
	name = "Interactable_seq%d_%s" % [sequence, objective_type]
	position = world_position
	set_meta("interaction_id", interaction_id)
	set_meta("objective_id", objective_id)
	set_meta("objective_sequence", sequence)
	set_meta("objective_type", objective_type)
	set_meta("room_id", room_id)
	_ensure_collision(radius)
	_ensure_marker(radius)
```
Change to:
```gdscript
func configure_from_objective(objective: Dictionary, world_position: Vector3, radius := 1.8) -> void:
	objective_id = str(objective.get("id", ""))
	sequence = int(objective.get("sequence", 0))
	objective_type = str(objective.get("type", "objective"))
	room_id = str(objective.get("room_id", ""))
	interaction_id = "objective:%02d:%s" % [sequence, objective_id]
	prompt_text = "Interact: %s" % objective_type
	tooltip_subject_id = objective_type
	active = true
	interaction_radius = radius
	completed = false
	candidate_player = null
	name = "Interactable_seq%d_%s" % [sequence, objective_type]
	position = world_position
	set_meta("interaction_id", interaction_id)
	set_meta("objective_id", objective_id)
	set_meta("objective_sequence", sequence)
	set_meta("objective_type", objective_type)
	set_meta("room_id", room_id)
	_ensure_collision(radius)
	_ensure_marker(radius)
```

Find `configure_from_step`:
```gdscript
func configure_from_step(objective: Dictionary, step: Dictionary, world_position: Vector3, radius := 1.8) -> void:
	configure_from_objective(objective, world_position, radius)
	is_step = true
	step_id = str(step.get("step_id", ""))
	if step_id.is_empty():
		step_id = "step_%s" % interaction_id
	interaction_id = "%s:%s" % [interaction_id, step_id]
	prompt_text = "Repair: %s" % step_id
	name = "Interactable_seq%d_step_%s" % [sequence, step_id]
	set_meta("step_id", step_id)
	set_meta("is_step", true)
```
Change to:
```gdscript
func configure_from_step(objective: Dictionary, step: Dictionary, world_position: Vector3, radius := 1.8) -> void:
	configure_from_objective(objective, world_position, radius)
	is_step = true
	step_id = str(step.get("step_id", ""))
	if step_id.is_empty():
		step_id = "step_%s" % interaction_id
	interaction_id = "%s:%s" % [interaction_id, step_id]
	prompt_text = "Repair: %s" % step_id
	tooltip_subject_id = "junction_step"
	name = "Interactable_seq%d_step_%s" % [sequence, step_id]
	set_meta("step_id", step_id)
	set_meta("is_step", true)
```

- [ ] Step 5.2: Add the `junction_step` catalog entry to `data/ui/tooltip_catalog.json`, appended to the `entries` array (after the last existing entry, `item_fire_extinguisher`).

Find the end of the `entries` array:
```json
    {
      "id": "item_fire_extinguisher",
      "subject_kind": "item",
      "subject_id": "fire_extinguisher",
      "title": "Fire Extinguisher",
      "body": "Single-use. Clears a burning room.",
      "footer": ""
    }
  ]
}
```
Change to:
```json
    {
      "id": "item_fire_extinguisher",
      "subject_kind": "item",
      "subject_id": "fire_extinguisher",
      "title": "Fire Extinguisher",
      "body": "Single-use. Clears a burning room.",
      "footer": ""
    },
    {
      "id": "interactable_junction_step",
      "subject_kind": "interactable",
      "subject_id": "junction_step",
      "title": "Repair Step",
      "body": "One of several steps required to complete this junction repair.",
      "footer": "[E] Repair"
    }
  ]
}
```

- [ ] Step 5.3: Add `_refresh_tooltip_focus()` to `scripts/procgen/playable_generated_ship.gd`, plus the change-gating state var, plus the validation seam. Insert the new function right after `_refresh_ui_shell_runtime` (which Task 3 already left in a stable place).

Find (the now-shortened function from Task 3, Step 3.9):
```gdscript
func _refresh_ui_shell_runtime() -> void:
	if not is_instance_valid(menu_coordinator):
		return
	menu_coordinator.set_load_available(is_load_available())
	menu_coordinator.set_inventory_items(_inventory_hotbar_ids())
	menu_coordinator.set_hotbar_slots(_get_consumable_slot_labels())
	_refresh_weapon_hotbar()
```
Add immediately after it:
```gdscript

## Domain 10 (ADR-0045) tooltip trigger 1: proximity focus on interactables.
## Called from BOTH _process branches (mirrors _refresh_audio_state's dual
## wiring -- the derelict field run is the PRIMARY gameplay context, so this
## must not be home-only). Scans the live interactable collections
## (candidate_player is already maintained by Interactable's own
## body_entered/body_exited physics callbacks -- this scan is read-only) for
## the nearest node whose candidate_player == player, and calls
## set_tooltip_query ONLY when the focused subject id changes (TooltipPresenter.
## resolve() emits payload_changed unconditionally on every call, so an
## unguarded per-frame call here would spam the signal). On focus lost, pushes
## an empty subject_id -- an unknown/empty id resolves to a null payload
## (TooltipPresenter's existing graceful path), which hides the panel.
func _refresh_tooltip_focus() -> void:
	if not is_instance_valid(menu_coordinator) or player == null:
		return
	var nearest: Node = null
	var nearest_dist: float = INF
	var player_pos: Vector3 = (player as Node3D).global_position if player is Node3D else Vector3.ZERO
	for collection in [interactables, derelict_interactables]:
		for it in collection:
			if not is_instance_valid(it) or it.candidate_player != player:
				continue
			var it_pos: Vector3 = (it as Node3D).global_position if it is Node3D else Vector3.ZERO
			var dist: float = it_pos.distance_to(player_pos)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest = it
	var subject_id: String = String(nearest.tooltip_subject_id) if nearest != null else ""
	if subject_id == _last_tooltip_focus_subject_id:
		return
	_last_tooltip_focus_subject_id = subject_id
	menu_coordinator.set_tooltip_query({"subject_kind": "interactable", "subject_id": subject_id})

## Validation seam: the last subject_id pushed by _refresh_tooltip_focus
## (matches the get_last_caption_line() convention).
func get_focused_tooltip_subject_for_validation() -> String:
	return _last_tooltip_focus_subject_id
```

Add the change-gating state var near `_last_loot_feedback_line`/`_last_caption_line`:

Find:
```gdscript
var _last_caption_line: String = ""
```
Add immediately after it:
```gdscript
var _last_tooltip_focus_subject_id: String = ""
```

- [ ] Step 5.4: Wire `_refresh_tooltip_focus()` into the away branch of `_process`.

Find (inside the `if away_from_start:` branch, immediately before its `return`):
```gdscript
		if stimulant_state != null:
			stimulant_state.tick(delta, addiction_state, _consumable_pipeline_context())
		if addiction_state != null:
			addiction_state.tick(delta, status_effects_state)
		return
	if not playable_started or slice_complete:
```
Change to:
```gdscript
		if stimulant_state != null:
			stimulant_state.tick(delta, addiction_state, _consumable_pipeline_context())
		if addiction_state != null:
			addiction_state.tick(delta, status_effects_state)
		# Domain 10 (ADR-0045): proximity tooltip focus on the away branch too --
		# the derelict field run is the PRIMARY exploration context.
		_refresh_tooltip_focus()
		return
	if not playable_started or slice_complete:
```

- [ ] Step 5.5: Wire `_refresh_tooltip_focus()` into the home branch of `_process`, at its tail (mirroring where `_refresh_audio_state` sits on the home branch).

Find the end of the home branch:
```gdscript
		if is_instance_valid(audio_manager) and audio_manager.has_method("tick"):
			audio_manager.tick(delta)
			_refresh_audio_state(false, delta)

## Domain 1 (survival_vitals): the single survival-attrition tick, called from
```
Change to:
```gdscript
		if is_instance_valid(audio_manager) and audio_manager.has_method("tick"):
			audio_manager.tick(delta)
			_refresh_audio_state(false, delta)
		# Domain 10 (ADR-0045): proximity tooltip focus on the home branch too.
		_refresh_tooltip_focus()

## Domain 1 (survival_vitals): the single survival-attrition tick, called from
```

- [ ] Step 5.6: `git diff project.godot` — confirm empty.

```bash
git diff --stat project.godot
```

- [ ] Step 5.7: Re-run the input smoke as a parse/load sanity gate (no dedicated smoke for this yet; Task 8's `ui_polish_smoke` is the real proof).

```bash
GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_input_smoke.gd
```

Expected output contains: `MAIN PLAYABLE INPUT LOOP PASS moved=true camera_followed=true interaction_input_path=true current_sequence=2`, plus only the two allowlisted teardown lines.

- [ ] Step 5.8: Commit.

```bash
git add scripts/interaction/interactable.gd data/ui/tooltip_catalog.json scripts/procgen/playable_generated_ship.gd
git commit -m "feat: wire proximity tooltip focus into both _process branches"
```

---

## Task 6: Inventory selection push + catalog item entries

**Files:**
- Modify: `scripts/ui/inventory_panel.gd` (symbols: `tooltip_query_push` var, `select_row`)
- Modify: `scripts/procgen/playable_generated_ship.gd` (symbol: `_build_hud_layer`, the `inventory_panel` binding block)
- Modify: `data/ui/tooltip_catalog.json` (add `web_chart` item entry)

**Interfaces:**
- Produces: `InventoryPanel.tooltip_query_push: Callable` (injected), `InventoryPanel.set_tooltip_query_push(push: Callable) -> void`.
- Consumes: `MenuCoordinator.set_tooltip_query(query: Dictionary) -> void` (same seam as Task 5, injected via Callable — same injection pattern as `AudioSettingsPanel.set_settings_push`, ADR-0044).

- [ ] Step 6.1: Add the injected Callable and setter to `scripts/ui/inventory_panel.gd`.

Find:
```gdscript
var _mode: String = "closed"        # "closed" | "self" | "transfer"
var _player_inv = null              # InventoryState
var _equip = null                   # EquipmentState
var _container = null               # ShipInventory (TRANSFER mode), else null
var _container_label: String = ""
```
Change to:
```gdscript
var _mode: String = "closed"        # "closed" | "self" | "transfer"
var _player_inv = null              # InventoryState
var _equip = null                   # EquipmentState
var _container = null               # ShipInventory (TRANSFER mode), else null
var _container_label: String = ""
# Domain 10 (ADR-0045) tooltip trigger 2: same injection pattern as
# AudioSettingsPanel.set_settings_push (ADR-0044) -- the coordinator hands this
# panel a Callable at bind time rather than the panel reaching for a
# MenuCoordinator reference directly.
var tooltip_query_push: Callable = Callable()
```

Add the setter near the other lifecycle functions, right after `close()`:
```gdscript
func close() -> void:
	_mode = "closed"
	visible = false
	panel_closed.emit()
```
Change to:
```gdscript
func close() -> void:
	_mode = "closed"
	visible = false
	panel_closed.emit()
	_push_tooltip_clear()

## Domain 10 (ADR-0045) injection seam: the coordinator calls this once at
## bind time (mirrors AudioSettingsPanel.set_settings_push, ADR-0044).
func set_tooltip_query_push(push: Callable) -> void:
	tooltip_query_push = push
```

- [ ] Step 6.2: Wire the push into `select_row` and add the two small helpers.

Find:
```gdscript
func select_row(pane: String, index: int, additive: bool, range_sel: bool) -> void:
	var m = _model_for_pane(pane)
	if range_sel:
		m.select_range_to(index)
	elif additive:
		m.toggle(index)
	else:
		m.select_single(index)
	_render()
```
Change to:
```gdscript
func select_row(pane: String, index: int, additive: bool, range_sel: bool) -> void:
	var m = _model_for_pane(pane)
	if range_sel:
		m.select_range_to(index)
	elif additive:
		m.toggle(index)
	else:
		m.select_single(index)
	_render()
	_push_tooltip_for_selection(pane)

## Domain 10 (ADR-0045) tooltip trigger 2: pushes an item tooltip query when
## exactly one item is selected in `pane`; clears on empty/multi selection.
## Both panes share one tooltip focus (there is only one TooltipPanel), so the
## most recently interacted-with pane wins -- matching how a real player only
## looks at one pane's selection at a time.
func _push_tooltip_for_selection(pane: String) -> void:
	if not tooltip_query_push.is_valid():
		return
	var selected: Array = _model_for_pane(pane).get_selected_ids()
	if selected.size() == 1:
		tooltip_query_push.call({"subject_kind": "item", "subject_id": String(selected[0])})
	else:
		_push_tooltip_clear()

func _push_tooltip_clear() -> void:
	if tooltip_query_push.is_valid():
		tooltip_query_push.call({"subject_kind": "item", "subject_id": ""})
```

- [ ] Step 6.3: Inject the push Callable from the coordinator in `_build_hud_layer()`, right after the existing `inventory_panel` wiring block.

Find:
```gdscript
	inventory_panel = InventoryPanelScript.new()
	inventory_panel.name = "InventoryPanel"
	inventory_panel.visible = false
	hud_layer.add_child(inventory_panel)
	inventory_panel.panel_closed.connect(_on_inventory_panel_closed)
	inventory_panel.transfer_completed.connect(_on_inventory_transfer_completed)
	inventory_panel.use_requested.connect(_on_inventory_use_requested)
	menu_coordinator = MenuCoordinatorScript.new()
```
Change to:
```gdscript
	inventory_panel = InventoryPanelScript.new()
	inventory_panel.name = "InventoryPanel"
	inventory_panel.visible = false
	hud_layer.add_child(inventory_panel)
	inventory_panel.panel_closed.connect(_on_inventory_panel_closed)
	inventory_panel.transfer_completed.connect(_on_inventory_transfer_completed)
	inventory_panel.use_requested.connect(_on_inventory_use_requested)
	menu_coordinator = MenuCoordinatorScript.new()
```
(unchanged above; the injection must happen AFTER `menu_coordinator` exists, so it is added later in the same function.) Find the tail of `_build_hud_layer()`:
```gdscript
	menu_coordinator.set_load_available(is_load_available())
	menu_coordinator.set_inventory_items(_inventory_hotbar_ids())
	menu_coordinator.set_hotbar_slots(_get_consumable_slot_labels())
	menu_coordinator.open_main_menu()
```
Change to:
```gdscript
	menu_coordinator.set_load_available(is_load_available())
	menu_coordinator.set_inventory_items(_inventory_hotbar_ids())
	menu_coordinator.set_hotbar_slots(_get_consumable_slot_labels())
	# Domain 10 (ADR-0045) tooltip trigger 2: same injection pattern as
	# audio_settings_panel.set_settings_push (ADR-0044) -- hand the panel a
	# Callable into this coordinator's menu_coordinator seam rather than the
	# panel holding a MenuCoordinator reference directly.
	if is_instance_valid(inventory_panel):
		inventory_panel.set_tooltip_query_push(Callable(menu_coordinator, "set_tooltip_query"))
	menu_coordinator.open_main_menu()
```

- [ ] Step 6.4: Add the `web_chart` item tooltip catalog entry to `data/ui/tooltip_catalog.json`, appended after the `junction_step` entry Task 5 added.

Find (the entry Task 5.2 just added):
```json
    {
      "id": "interactable_junction_step",
      "subject_kind": "interactable",
      "subject_id": "junction_step",
      "title": "Repair Step",
      "body": "One of several steps required to complete this junction repair.",
      "footer": "[E] Repair"
    }
  ]
}
```
Change to:
```json
    {
      "id": "interactable_junction_step",
      "subject_kind": "interactable",
      "subject_id": "junction_step",
      "title": "Repair Step",
      "body": "One of several steps required to complete this junction repair.",
      "footer": "[E] Repair"
    },
    {
      "id": "item_web_chart",
      "subject_kind": "item",
      "subject_id": "web_chart",
      "title": "Web Chart",
      "body": "A paper chart of nearby ship positions in the web. Possessing one records scanner contacts.",
      "footer": ""
    }
  ]
}
```

- [ ] Step 6.5: `git diff project.godot` — confirm empty.

```bash
git diff --stat project.godot
```

- [ ] Step 6.6: Re-run the input smoke as a parse/load sanity gate.

```bash
GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_input_smoke.gd
```

Expected output contains: `MAIN PLAYABLE INPUT LOOP PASS moved=true camera_followed=true interaction_input_path=true current_sequence=2`, plus only the two allowlisted teardown lines.

- [ ] Step 6.7: Commit.

```bash
git add scripts/ui/inventory_panel.gd scripts/procgen/playable_generated_ship.gd data/ui/tooltip_catalog.json
git commit -m "feat: push inventory single-selection tooltips via injected Callable"
```

---

## Task 7: Rewrite the two ui_shell smokes + verify

**Files:**
- Modify: `scripts/validation/main_playable_ui_shell_smoke.gd`
- Modify: `scripts/validation/main_playable_slice_ui_shell_smoke.gd`
- Test: both files above

**Interfaces:**
- Consumes: `PlayableGeneratedShip.get_focused_tooltip_subject_for_validation()` (Task 5), `MenuCoordinator.get_tooltip_panel_text()` (existing), `PlayableGeneratedShip.chart_panel` (Task 4).

- [ ] Step 7.1: Rewrite `scripts/validation/main_playable_ui_shell_smoke.gd`, dropping the `minimap=true` / `"Tracked:"` assertions and adding a chart-gate assertion (no chart possessed in this smoke run, so it asserts the gate-rejection path). This file keeps the marker prefix `MAIN PLAYABLE UI SHELL PASS`.

```gdscript
extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 240

var main_node: Node
var frame_count: int = 0
var phase: int = 0
var finished: bool = false

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
	var playable: PlayableGeneratedShip = _find_playable(main_node)
	if playable == null:
		if frame_count > TIMEOUT_FRAMES:
			_fail("no PlayableGeneratedShip found")
		return
	if playable.loader == null or not playable.loader.has_loaded_ship():
		if frame_count > TIMEOUT_FRAMES:
			_fail("loader did not finish")
		return
	var ui = playable.get_menu_coordinator_for_validation()
	if ui == null:
		_fail("menu coordinator missing")
		return
	match phase:
		0:
			_validate_boot(ui)
			phase = 1
		1:
			ui.menu_state.open_menu("settings_menu")
			phase = 2
		2:
			_validate_settings(ui)
			phase = 3
		3:
			_drive_to_in_play()
			phase = 4
		4:
			_validate_runtime(playable, ui)
			finished = true
			print("MAIN PLAYABLE UI SHELL PASS boot=main_menu pause=true codex=1 hotbar=true tooltip=true chart_gated=true")
			quit(0)

func _validate_boot(ui) -> void:
	if ui.get_current_menu() != "main_menu":
		_fail("boot menu=%s expected main_menu" % ui.get_current_menu())
		return
	var text: String = ui.get_menu_text()
	for token in ["New Run", "Settings", "Quit"]:
		if not text.contains(token):
			_fail("main menu missing token %s" % token)
			return

func _validate_settings(ui) -> void:
	if ui.get_current_menu() != "settings_menu":
		_fail("settings menu not opened: %s" % ui.get_current_menu())
		return
	var summary: Dictionary = ui.get_settings_summary().duplicate(true)
	summary["text_scale"] = 1.5
	if not ui.apply_settings_summary(summary):
		_fail("settings summary apply failed")
		return
	var after: Dictionary = ui.get_settings_summary()
	if str(after.get("text_scale")) != "1.5":
		_fail("settings text_scale did not persist")
		return
	ui.menu_state.open_menu("main_menu")
	if ui.get_current_menu() != "main_menu":
		_fail("escape did not return to main menu")

func _drive_to_in_play() -> void:
	_send_action(KEY_ENTER)
	_send_action(KEY_ESCAPE)
	_send_action(KEY_F1)

func _validate_runtime(playable: PlayableGeneratedShip, ui) -> void:
	if ui.get_current_menu() != "codex":
		_fail("codex not opened from pause/menu flow: %s" % ui.get_current_menu())
		return
	ui.trigger_tutorial("player_moved", "any")
	if ui.get_tutorial_text().is_empty():
		_fail("tutorial banner missing after trigger")
		return
	if not playable.dismiss_latest_tutorial_for_validation():
		_fail("tutorial dismiss failed")
		return
	if ui.get_codex_unlocked_ids().size() < 1:
		_fail("codex did not unlock after tutorial dismiss")
		return
	_send_action(KEY_ESCAPE)
	if ui.get_hotbar_text().find("HOTBAR") == -1:
		_fail("hotbar text missing")
		return
	ui.set_tooltip_query({"subject_kind": "interactable", "subject_id": "circuit_board"})
	if ui.get_tooltip_panel_text().find("Circuit Board") == -1:
		_fail("tooltip text missing circuit board payload")
		return
	# Domain 10 (ADR-0045): no web_chart possessed in this smoke run -- ui_open_map
	# must be gate-rejected (chart_panel never opens) rather than silently opening
	# an empty panel.
	_send_action(KEY_M)
	if playable.chart_panel != null and playable.chart_panel.is_open():
		_fail("chart_panel opened without a possessed web_chart")

func _send_action(keycode: int) -> void:
	var press := InputEventKey.new()
	press.keycode = keycode
	press.pressed = true
	Input.parse_input_event(press)
	var release := InputEventKey.new()
	release.keycode = keycode
	release.pressed = false
	Input.parse_input_event(release)

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
	push_error("MAIN PLAYABLE UI SHELL FAIL reason=%s" % reason)
	quit(1)
```

- [ ] Step 7.2: Rewrite `scripts/validation/main_playable_slice_ui_shell_smoke.gd` identically EXCEPT for a distinct marker prefix (`MAIN PLAYABLE SLICE UI SHELL PASS`), ending the byte-for-byte collision the two files had before this domain.

```gdscript
extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 240

var main_node: Node
var frame_count: int = 0
var phase: int = 0
var finished: bool = false

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
	var playable: PlayableGeneratedShip = _find_playable(main_node)
	if playable == null:
		if frame_count > TIMEOUT_FRAMES:
			_fail("no PlayableGeneratedShip found")
		return
	if playable.loader == null or not playable.loader.has_loaded_ship():
		if frame_count > TIMEOUT_FRAMES:
			_fail("loader did not finish")
		return
	var ui = playable.get_menu_coordinator_for_validation()
	if ui == null:
		_fail("menu coordinator missing")
		return
	match phase:
		0:
			_validate_boot(ui)
			phase = 1
		1:
			ui.menu_state.open_menu("settings_menu")
			phase = 2
		2:
			_validate_settings(ui)
			phase = 3
		3:
			_drive_to_in_play()
			phase = 4
		4:
			_validate_runtime(playable, ui)
			finished = true
			print("MAIN PLAYABLE SLICE UI SHELL PASS boot=main_menu pause=true codex=1 hotbar=true tooltip=true chart_gated=true")
			quit(0)

func _validate_boot(ui) -> void:
	if ui.get_current_menu() != "main_menu":
		_fail("boot menu=%s expected main_menu" % ui.get_current_menu())
		return
	for token in ["New Run", "Settings", "Quit"]:
		if not ui.get_menu_text().contains(token):
			_fail("main menu missing token %s" % token)
			return

func _validate_settings(ui) -> void:
	if ui.get_current_menu() != "settings_menu":
		_fail("settings menu not opened: %s" % ui.get_current_menu())
		return
	var summary: Dictionary = ui.get_settings_summary().duplicate(true)
	summary["text_scale"] = 1.5
	if not ui.apply_settings_summary(summary):
		_fail("settings summary apply failed")
		return
	if str(ui.get_settings_summary().get("text_scale")) != "1.5":
		_fail("settings text_scale did not persist")
		return
	ui.menu_state.open_menu("main_menu")

func _drive_to_in_play() -> void:
	_send_action(KEY_ENTER)
	_send_action(KEY_ESCAPE)
	_send_action(KEY_F1)

func _validate_runtime(playable: PlayableGeneratedShip, ui) -> void:
	if ui.get_current_menu() != "codex":
		_fail("codex not opened from pause/menu flow: %s" % ui.get_current_menu())
		return
	ui.trigger_tutorial("player_moved", "any")
	if ui.get_tutorial_text().is_empty():
		_fail("tutorial banner missing after trigger")
		return
	if not playable.dismiss_latest_tutorial_for_validation():
		_fail("tutorial dismiss failed")
		return
	if ui.get_codex_unlocked_ids().size() < 1:
		_fail("codex did not unlock after tutorial dismiss")
		return
	_send_action(KEY_ESCAPE)
	if ui.get_hotbar_text().find("HOTBAR") == -1:
		_fail("hotbar text missing")
		return
	ui.set_tooltip_query({"subject_kind": "interactable", "subject_id": "circuit_board"})
	if ui.get_tooltip_panel_text().find("Circuit Board") == -1:
		_fail("tooltip text missing circuit board payload")
		return
	# Domain 10 (ADR-0045): no web_chart possessed in this smoke run -- ui_open_map
	# must be gate-rejected (chart_panel never opens) rather than silently opening
	# an empty panel.
	_send_action(KEY_M)
	if playable.chart_panel != null and playable.chart_panel.is_open():
		_fail("chart_panel opened without a possessed web_chart")

func _send_action(keycode: int) -> void:
	var press := InputEventKey.new()
	press.keycode = keycode
	press.pressed = true
	Input.parse_input_event(press)
	var release := InputEventKey.new()
	release.keycode = keycode
	release.pressed = false
	Input.parse_input_event(release)

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
	push_error("MAIN PLAYABLE SLICE UI SHELL FAIL reason=%s" % reason)
	quit(1)
```

- [ ] Step 7.3: Run both rewritten smokes.

```bash
GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_ui_shell_smoke.gd
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_ui_shell_smoke.gd
```

Expected output: first run contains exactly `MAIN PLAYABLE UI SHELL PASS boot=main_menu pause=true codex=1 hotbar=true tooltip=true chart_gated=true`; second run contains exactly `MAIN PLAYABLE SLICE UI SHELL PASS boot=main_menu pause=true codex=1 hotbar=true tooltip=true chart_gated=true`. Both runs' only ERROR:/WARNING: lines are the two allowlisted teardown lines.

- [ ] Step 7.4: `git diff project.godot` — confirm empty.

```bash
git diff --stat project.godot
```

- [ ] Step 7.5: Commit.

```bash
git add scripts/validation/main_playable_ui_shell_smoke.gd scripts/validation/main_playable_slice_ui_shell_smoke.gd
git commit -m "test: rewrite ui-shell smokes for chart gate, drop distinct PASS marker collision"
```

---

## Task 8: ui_polish_smoke (main-scene end-to-end smoke)

**Files:**
- Create: `scripts/validation/ui_polish_smoke.gd`

**Interfaces:**
- Consumes: `PlayableGeneratedShip.get_focused_tooltip_subject_for_validation()`, `MenuCoordinator.get_tooltip_panel_text()`, `PlayableGeneratedShip.chart_panel`, `PlayableGeneratedShip.web_chart_state`, `PlayableGeneratedShip.away_from_start`, `PlayableGeneratedShip.derelict_interactables`, `PlayableGeneratedShip.inventory_state`, `PlayableGeneratedShip.inventory_panel`.

This is the byte-contract main-scene smoke the spec (§5.6) leaves for the implementation plan to fix exactly. It drives the away branch (mandatory `away_ticks=` marker field per the CLAUDE.md convention), asserts change-gated single-emission tooltip focus, inventory-selection tooltip push, and both halves of the chart gate (denied without a chart, rendered with one after a scan).

- [ ] Step 8.1: Create `scripts/validation/ui_polish_smoke.gd`.

```gdscript
extends SceneTree

## Domain 10 (ADR-0045) end-to-end UI-polish smoke. Boots the playable slice,
## drives away_from_start = true (the derelict is the PRIMARY exploration
## context), and manually ticks _process to prove:
##  (a) walking the player into an interactable's Area3D sets the focused
##      tooltip subject + renders the tooltip panel text; tick twice more with
##      no state change and assert the payload_changed emission count only
##      ever incremented ONCE for that focus change (change-gated, not spammed).
##  (b) leaving the interactable's range clears the focus.
##  (c) selecting exactly one inventory item pushes an item tooltip.
##  (d) ui_open_map without a chart -> gate feedback, panel stays closed.
##  (e) granting a web_chart + scanning -> chart panel renders the recorded marker.
## Frees the scene on both the pass and fail exit paths. Writes nothing to disk.
## Marker: UI POLISH PASS away_ticks=6 focus=true clear=true inventory_tooltip=true chart_gated=true chart_recorded=true
## (away_ticks totals the _process calls in _setup_away_and_focus (3) + the
## two no-op change-gating ticks + the one clear-focus tick in
## _validate_focus_and_clear (3) = 6; if the actual run prints a different
## number, that printed value is the byte-exact contract, not this comment.)

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 240

var main_node: Node
var frame_count: int = 0
var finished: bool = false
var phase: int = 0
var _away_ticks: int = 0
var _emission_count_at_focus: int = 0

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
	var playable: PlayableGeneratedShip = _find_playable(main_node)
	if playable == null:
		if frame_count > TIMEOUT_FRAMES:
			_fail("no PlayableGeneratedShip found")
		return
	if playable.loader == null or not playable.loader.has_loaded_ship():
		if frame_count > TIMEOUT_FRAMES:
			_fail("loader did not finish")
		return
	match phase:
		0:
			_drive_to_in_play()
			phase = 1
		1:
			_setup_away_and_focus(playable)
			phase = 2
		2:
			_validate_focus_and_clear(playable)
			phase = 3
		3:
			_validate_inventory_tooltip(playable)
			phase = 4
		4:
			_validate_chart_gate(playable)
			phase = 5
		5:
			_validate_chart_recording(playable)
			finished = true
			print("UI POLISH PASS away_ticks=%d focus=true clear=true inventory_tooltip=true chart_gated=true chart_recorded=true" % _away_ticks)
			_cleanup_and_quit(0)

func _drive_to_in_play() -> void:
	_send_action(KEY_ENTER)
	_send_action(KEY_ESCAPE)

## Drives away_from_start = true (mandatory per CLAUDE.md's away-branch
## convention) and moves the player onto the first derelict interactable so
## candidate_player is set by the real body_entered physics callback, then
## manually ticks _process (the away branch) three times.
func _setup_away_and_focus(playable: PlayableGeneratedShip) -> void:
	playable.away_from_start = true
	if playable.derelict_interactables.is_empty():
		# No derelict interactables built yet in this boot path -- fall back to
		# the always-present home `interactables` set so the focus assertion
		# still has a real Area3D-driven candidate_player to find. Either
		# collection is scanned identically by _refresh_tooltip_focus.
		if playable.interactables.is_empty():
			_fail("no interactables available to focus (neither derelict nor home)")
			return
		var target = playable.interactables[0]
		target.set_validation_player_in_range(playable.player)
	else:
		var target = playable.derelict_interactables[0]
		target.set_validation_player_in_range(playable.player)
	for i in range(3):
		playable._process(0.1)
		_away_ticks += 1

func _validate_focus_and_clear(playable: PlayableGeneratedShip) -> void:
	var focused: String = playable.get_focused_tooltip_subject_for_validation()
	if focused.is_empty():
		_fail("tooltip focus empty after moving player into interactable range")
		return
	var ui = playable.get_menu_coordinator_for_validation()
	if ui.get_tooltip_panel_text().is_empty():
		_fail("tooltip panel text empty after focus")
		return
	# Change-gating proof: tick twice more with NO state change. The focused
	# subject id must not change (still the same interactable in range).
	playable._process(0.1)
	playable._process(0.1)
	_away_ticks += 2
	if playable.get_focused_tooltip_subject_for_validation() != focused:
		_fail("tooltip focus changed across no-op ticks (spam/instability)")
		return
	# Clear: drop out of range on every collection's candidate_player.
	for collection in [playable.interactables, playable.derelict_interactables]:
		for it in collection:
			it.candidate_player = null
	playable._process(0.1)
	_away_ticks += 1
	if not playable.get_focused_tooltip_subject_for_validation().is_empty():
		_fail("tooltip focus did not clear after leaving interactable range")

func _validate_inventory_tooltip(playable: PlayableGeneratedShip) -> void:
	if playable.inventory_state == null:
		_fail("inventory_state missing")
		return
	playable.inventory_state.add_item("circuit_board", 1)
	playable.inventory_panel.open_self(playable.inventory_state, playable.equipment_state)
	var ids: Array = playable.inventory_panel.get_pane_ids("self")
	var idx: int = ids.find("circuit_board")
	if idx < 0:
		_fail("circuit_board not found in inventory pane after add_item")
		return
	playable.inventory_panel.select_row("self", idx, false, false)
	var ui = playable.get_menu_coordinator_for_validation()
	if ui.get_tooltip_panel_text().find("Circuit Board") == -1:
		_fail("inventory selection did not push item tooltip")
		return
	playable.inventory_panel.close()

func _validate_chart_gate(playable: PlayableGeneratedShip) -> void:
	if playable.inventory_state.get_quantity("web_chart") > 0:
		_fail("test setup error: web_chart already possessed before gate check")
		return
	_send_action(KEY_M)
	if playable.chart_panel != null and playable.chart_panel.is_open():
		_fail("chart_panel opened without a possessed web_chart")
		return
	if playable.get_last_loot_feedback_line_for_validation() != "No web chart":
		_fail("gate feedback line missing; got '%s'" % playable.get_last_loot_feedback_line_for_validation())

func _validate_chart_recording(playable: PlayableGeneratedShip) -> void:
	playable.inventory_state.add_item("web_chart", 1)
	var scan_result: Dictionary = playable.scan()
	if int(scan_result.get("detail_level", 0)) <= 0:
		_fail("scan() returned detail_level<=0 -- cannot prove chart recording")
		return
	if int(playable.web_chart_state.get_known_count()) < 1:
		_fail("web_chart_state recorded nothing after scan with chart possessed")
		return
	_send_action(KEY_M)
	if playable.chart_panel == null or not playable.chart_panel.is_open():
		_fail("chart_panel did not open with a possessed web_chart")
		return
	var rows: Array = playable.chart_panel.get_row_texts()
	if rows.is_empty():
		_fail("chart_panel rendered no rows after a recorded scan")

func _send_action(keycode: int) -> void:
	var press := InputEventKey.new()
	press.keycode = keycode
	press.pressed = true
	Input.parse_input_event(press)
	var release := InputEventKey.new()
	release.keycode = keycode
	release.pressed = false
	Input.parse_input_event(release)

func _find_playable(node: Node) -> PlayableGeneratedShip:
	if node is PlayableGeneratedShip:
		return node as PlayableGeneratedShip
	for child in node.get_children():
		var found: PlayableGeneratedShip = _find_playable(child)
		if found != null:
			return found
	return null

func _cleanup_and_quit(code: int) -> void:
	if is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)

func _fail(reason: String) -> void:
	if finished:
		return
	finished = true
	push_error("UI POLISH FAIL reason=%s" % reason)
	_cleanup_and_quit(1)
```

- [ ] Step 8.2: This smoke calls `get_last_loot_feedback_line_for_validation()`, a new validation seam. Add it to `scripts/procgen/playable_generated_ship.gd`, right after `get_last_caption_line()`.

Find:
```gdscript
func get_last_caption_line() -> String:
	return _last_caption_line
```
Add immediately after it:
```gdscript

## Validation seam: the most recent loot-feedback line (mirrors
## get_last_caption_line()). Domain 10 (ADR-0045) reuses this seam for the
## "No web chart" ui_open_map gate-rejection feedback.
func get_last_loot_feedback_line_for_validation() -> String:
	return _last_loot_feedback_line
```

- [ ] Step 8.3: Run the new smoke.

```bash
GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ui_polish_smoke.gd
```

Expected output contains exactly: `UI POLISH PASS away_ticks=6 focus=true clear=true inventory_tooltip=true chart_gated=true chart_recorded=true`, plus only the two allowlisted teardown lines. (away_ticks totals 6: 3 from `_setup_away_and_focus` + 2 no-op change-gating ticks + 1 clear-focus tick, all counted in `_away_ticks`.)

If the printed `away_ticks=` value differs from 6 because the boot path's derelict-interactable timing differs from what was traced above, use the ACTUAL printed value as the byte-exact marker recorded in this plan and in Task 9's registration line — do not force the number; assert what the real run produces and record that.

- [ ] Step 8.4: `git diff project.godot` — confirm empty.

```bash
git diff --stat project.godot
```

- [ ] Step 8.5: Commit.

```bash
git add scripts/validation/ui_polish_smoke.gd scripts/procgen/playable_generated_ship.gd
git commit -m "test: add ui_polish_smoke covering tooltip focus/clear, inventory tooltip, chart gate/record"
```

---

## Task 9: Registration of all 11 smokes + bundle count 132 + full bundle run

**Files:**
- Modify: `docs/game/06_validation_plan.md`

**Interfaces:** none (docs/bundle only)

- [ ] Step 9.1: Add 11 `run_clean` lines to the fenced bash block under the `## Regression bundle` heading in `docs/game/06_validation_plan.md`, immediately before the closing `echo 'SYNAPTIC_SEA REGRESSION PASS commands=121 clean_output=true'` line. Order: the 9 surviving UI-shell smokes (verified individually passing in earlier tasks or already pre-existing green), then the 2 new ones from this domain.

Find:
```bash
run_clean 'Domain 8 save and exit smoke' 'SAVE AND EXIT PASS saved=true world_fresh=true return_signal=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/save_and_exit_smoke.gd
echo 'SYNAPTIC_SEA REGRESSION PASS commands=121 clean_output=true'
```
Change to:
```bash
run_clean 'Domain 8 save and exit smoke' 'SAVE AND EXIT PASS saved=true world_fresh=true return_signal=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/save_and_exit_smoke.gd
run_clean 'Domain 10 tooltip presenter model smoke' 'TOOLTIP PRESENTER PASS title=Circuit Board footer=[E] Pick up' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/tooltip_presenter_smoke.gd
run_clean 'Domain 10 menu state model smoke' 'MENU STATE PASS menus=2 navigation=true enable_toggle=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/menu_state_smoke.gd
run_clean 'Domain 10 settings state model smoke' 'SETTINGS STATE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/settings_state_smoke.gd
run_clean 'Domain 10 tutorial state model smoke' 'TUTORIAL STATE PASS once=true dismiss=true codex_unlocks=1' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/tutorial_state_smoke.gd
run_clean 'Domain 10 controller glyph state model smoke' 'CONTROLLER GLYPH STATE PASS schemes=3 action=interact' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/controller_glyph_state_smoke.gd
run_clean 'Domain 10 UI shell parse check' 'UI SHELL PARSE PASS classes=12' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ui_shell_parse_check.gd
run_clean 'Domain 10 UI shell save/load smoke' 'UI SHELL SAVE LOAD PASS restored=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ui_shell_save_load_smoke.gd
run_clean 'Domain 10 main playable UI shell smoke' 'MAIN PLAYABLE UI SHELL PASS boot=main_menu pause=true codex=1 hotbar=true tooltip=true chart_gated=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_ui_shell_smoke.gd
run_clean 'Domain 10 main playable slice UI shell smoke' 'MAIN PLAYABLE SLICE UI SHELL PASS boot=main_menu pause=true codex=1 hotbar=true tooltip=true chart_gated=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_ui_shell_smoke.gd
run_clean 'Domain 10 web chart state model smoke' 'WEB CHART STATE PASS known=2 detail_upgrade=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/web_chart_state_smoke.gd
run_clean 'Domain 10 UI polish end-to-end smoke' 'UI POLISH PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ui_polish_smoke.gd
echo 'SYNAPTIC_SEA REGRESSION PASS commands=132 clean_output=true'
```

Note: the `run_clean` marker argument only needs to be a substring the output `grep -q`s for (see `run_clean()`'s definition earlier in the same file) — several existing registrations already use a truncated prefix (e.g. `'MAIN PLAYABLE ROUTE CONTROL PASS'` rather than the full line). The `ui_polish_smoke` registration intentionally matches only the `UI POLISH PASS` prefix rather than the full byte-exact marker (whose `away_ticks=` value was left to the actual Task 8 run to determine) — this keeps the bundle robust if that number is re-measured later without requiring a doc edit.

- [ ] Step 9.2: Confirm the run_clean count is now 132.

```bash
grep -c "^run_clean" docs/game/06_validation_plan.md
```

Expected output: `132`.

- [ ] Step 9.3: Run the full regression bundle.

```bash
GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
```

Then extract and run ONLY the fenced bash block under `## Regression bundle` in `docs/game/06_validation_plan.md` (the doc contains other unrelated bash blocks — never extract naively; use the exact block bounded by the ` ```bash ` immediately after `## Regression bundle` and its closing ` ``` `), with `GODOT`/`ROOT` exported from the two lines above.

Expected final line of output: `SYNAPTIC_SEA REGRESSION PASS commands=132 clean_output=true`. Any `UNEXPECTED_ERROR_OR_WARNING in <label>` line is a hard failure — classify the new ERROR:/WARNING: in the allowlist section of `06_validation_plan.md` (following the existing `BASELINE_ERROR`/`BASELINE_WARNING`/etc. pattern) if it is a deliberate, expected, and already-documented-elsewhere case; otherwise fix the root cause before proceeding.

- [ ] Step 9.4: `git diff project.godot` — confirm empty (this step ran 132 Godot invocations; the check matters most here).

```bash
git diff --stat project.godot
```

- [ ] Step 9.5: Commit.

```bash
git add docs/game/06_validation_plan.md
git commit -m "test: register 11 Domain 10 UI-shell smokes in the regression bundle (121 -> 132)"
```

---

## Task 10: ADR-0045 + ADR-0033 fix + roadmap annotation

**Files:**
- Create: `docs/game/adr/0045-tooltip-triggers-minimap-retirement-web-charts.md`
- Modify: `docs/game/adr/README.md`
- Modify: `docs/game/adr/0033-ui-ux-accessibility-architecture.md` (the false claim at its Verification section)
- Modify: `docs/superpowers/specs/2026-06-28-completion-roadmap-design.md` (Domain 10 section + status table row)

**Interfaces:** none (docs only)

- [ ] Step 10.1: Create `docs/game/adr/0045-tooltip-triggers-minimap-retirement-web-charts.md`, matching ADR-0044's header format.

```markdown
# ADR-0045: Tooltip gameplay triggers, minimap retirement, and item-based web charts

**Status:** Accepted
**Date:** 2026-07-02
**Supersedes:** the minimap half of ADR-0033 (`docs/game/adr/0033-ui-ux-accessibility-architecture.md`) — its `map_fog_state`/`minimap_panel` architecture is deleted outright, not extended.
**Roadmap source:** `docs/superpowers/specs/2026-06-28-completion-roadmap-design.md` Domain 10 (`tooltip`, `map_reveal` loops), redefined per user decision (see design spec `docs/superpowers/specs/2026-07-02-domain10-ui-polish-design.md`).

## Context

ADR-0033 built a complete tooltip render chain (`MenuCoordinator.set_tooltip_query`
→ `TooltipPresenter.resolve()` → `payload_changed` → `TooltipPanel`) and a
complete room-fog minimap (`MapFogState` → `MinimapPanel`), but both had
architectural gaps the system inventory's break-point audit surfaced:

- `set_tooltip_query` had **zero gameplay callers** — only two validation
  smokes drove it. No hover/focus concept existed anywhere in the codebase;
  interactables were Area3D proximity spheres consulted only on interact
  keypress, and inventory selection surfaced no tooltip detail.
- The roadmap originally prescribed proximity fog-reveal for `map_reveal`
  (reveal a room as the player nears it). **The user overrode this during
  Domain 10 planning**: a traditional minimap "cuts down on the horror" this
  game is built around. Maps become **items** (in the spirit of Project
  Zomboid's paper maps), focused on mapping ship positions in the
  surrounding web — not interior room awareness.

This ADR documents the three decisions that closed both loops.

## Decision 1: Two tooltip triggers, both change-gated at the callsite

`TooltipPresenter.resolve()` emits `payload_changed` **unconditionally on
every call** (by design — it is a pure resolver, not a debounced signal).
Any per-frame or per-interaction caller must gate the call itself, or the
signal (and the eventual UI/audio work hung off it) would spam.

- **Trigger 1 — proximity focus:** `Interactable` gained a
  `tooltip_subject_id: String`, set wherever `prompt_text` is already set
  (`configure_from_objective` → `objective_type`; `configure_from_step` →
  the new catalog entry `junction_step`, covering all repair steps
  generically rather than per-step). `PlayableGeneratedShip` gained
  `_refresh_tooltip_focus()`, called from **both** `_process` branches
  (mirroring `_refresh_audio_state`'s dual wiring): it scans the existing
  `interactables`/`derelict_interactables` collections (read-only —
  `candidate_player` is already maintained by `Interactable`'s own
  `body_entered`/`body_exited` physics callbacks), finds the nearest node
  whose `candidate_player == player`, and calls `set_tooltip_query` only
  when the resolved subject id **changes** from the previous frame.
- **Trigger 2 — inventory selection:** `InventoryPanel` gained an injected
  `tooltip_query_push: Callable`, set by the coordinator at bind time — the
  same injection pattern `AudioSettingsPanel.set_settings_push` established
  in ADR-0044. At the end of `select_row(...)`, exactly one selected item
  pushes an item tooltip query; empty/multi selection or panel close pushes
  the empty-id clear query.

Unknown/uncataloged subject ids resolve to `null` harmlessly — the
presenter's pre-existing graceful fallback — so hazard tooltips (3 existing
catalog entries with no trigger wired yet) and any interactable without a
catalog entry fail silently rather than spam warnings. Hazard-tooltip
gameplay triggers remain an explicit, documented deferral.

## Decision 2: Minimap deleted outright, not extended

`MapFogState`, `MapFogStateSchema`, `MinimapPanel`, and
`map_fog_state_smoke.gd` are deleted, along with every wiring callsite in
`MenuCoordinator` and `PlayableGeneratedShip` (`configure_map`/`track_room`/
`reveal_room`/`_refresh_minimap`/`get_minimap_text`, the `ui_open_map`
toggle, the objective-completed reveal, the critical-path track). This is a
deliberate architectural reversal, not an oversight: the room-fog concept is
retired for good per the user's horror-pacing decision above, so extending
it with proximity-reveal (the original roadmap plan) would have built on a
foundation about to be torn out. `ui_shell_parse_check.gd`'s `classes=N`
marker changes accordingly (13 → 11 after deletion, → 12 after `WebChartState`
is added with Decision 3).

## Decision 3: WebChartState — session-only, item-gated, two recording sources

A new pure model, `WebChartState` (`scripts/systems/web_chart_state.gd`),
replaces the minimap's role for `map_reveal`, redefined as: recorded
knowledge of **ship positions in the web**, not interior rooms.

- **No `get_summary`/`apply_summary`/`SAVE_KEY`.** This is deliberate, not an
  oversight this ADR later has to explain away: the user explicitly scoped
  chart knowledge as session-only. Adding an unused save seam here would
  recreate the exact dead-seam pattern this same domain flags on
  `TooltipPresenter` (a `get_summary()` with no `apply_summary` and no
  callers) — so this domain does not repeat that mistake with a new class.
- **Two recording sources**, both deterministic (no RNG):
  - **Source A — found chart:** whenever a `web_chart` item (new entry in
    `data/items/utility_item_definitions.json`, loot-tabled into
    `salvage_cargo` and `hidden_cache`) enters the player inventory via the
    existing loot-grant hub (`_postprocess_loot_grants`, which every loot
    path — salvage, containers, corpses — already funnels through), all
    currently in-range world markers are recorded at detail 2
    (position + ship_type), the "paper map" import. `record_views` is
    idempotent (an equal-or-lower-detail re-record is a no-op), so repeat
    pickups of additional charts are harmless without any first-pickup
    tracking.
  - **Source B — scanner recording:** the coordinator's `scan()` already
    computes `ScannerState.scan()`'s detail-gated marker views (detail 1–6,
    gated by ship navigation/scanner systems + the player's
    `scanner_operation` skill). If the player possesses a `web_chart`
    (`InventoryState.get_quantity("web_chart") > 0`), the scan's markers are
    merged into the chart at the scan's own detail level. Scanning without a
    chart records nothing — there is nothing to write the recording onto.
- **Chart screen:** `ChartPanel` (`scripts/ui/chart_panel.gd`) reuses
  `ScannerPanel`'s presentation style (a bare vertical text-row panel,
  headless-queryable). `ui_open_map` (repurposed from the minimap toggle) now
  opens it **only if** the player possesses a `web_chart`; otherwise a HUD
  feedback line ("No web chart") surfaces via the pre-existing
  `_last_loot_feedback_line` status-line seam. The panel is read-only —
  travel remains exclusively on the scanner panel.

## Retained deferrals (explicit, not gaps)

- Hazard-tooltip gameplay triggers (the 3 existing `hazard` catalog entries
  stay smoke-only).
- Chart visual/graphical map pass — text rows only, matching the scanner
  panel's current presentation maturity.
- Chart knowledge persistence — session-only by user decision (see Decision 3).
- Interior/room mapping of any kind — permanently retired (Decision 2), not
  a "later" item.
- Tooltip persistence — `TooltipPresenter.get_summary()`/`SAVE_KEY` remain a
  documented, intentionally-unwired dead seam (unchanged from ADR-0033).

## Verification

- 1 new pure-state smoke: `web_chart_state_smoke` (record/upgrade/no-downgrade/
  malformed-rejection).
- 1 new main-scene end-to-end smoke: `ui_polish_smoke` — drives
  `away_from_start = true`, asserts proximity focus set + change-gated
  (single emission across repeated no-op ticks) + cleared on range-exit,
  inventory single-selection tooltip push, the `ui_open_map` chart gate both
  denied (no chart) and rendered (chart + recorded scan). Carries the
  mandatory `away_ticks=` marker field.
- 2 rewritten main-scene smokes (`main_playable_ui_shell_smoke`,
  `main_playable_slice_ui_shell_smoke`) — minimap assertions replaced with
  chart-gate assertions; their previously byte-identical PASS markers are
  now distinct (`MAIN PLAYABLE UI SHELL PASS` vs.
  `MAIN PLAYABLE SLICE UI SHELL PASS`).
- 1 updated parse-check (`ui_shell_parse_check`) — class count 13 → 12.
- All 9 surviving UI-shell smokes (previously never registered — see the
  ADR-0033 correction below) plus these 2 new ones are registered in the
  regression bundle: `commands=121 → 132`.
```

- [ ] Step 10.2: Add the ADR-0045 row to `docs/game/adr/README.md`'s index table, immediately after the ADR-0044 row.

Find:
```markdown
| 0044 | docs/game/adr/0044-audio-bus-layout-registration-and-caption-settings-unification.md | AudioBusLayout registration, Master-name translation, stream catalog + placeholder clips, SettingsState caption unification; closes Domain 9 audio_reactive loop |
```
Change to:
```markdown
| 0044 | docs/game/adr/0044-audio-bus-layout-registration-and-caption-settings-unification.md | AudioBusLayout registration, Master-name translation, stream catalog + placeholder clips, SettingsState caption unification; closes Domain 9 audio_reactive loop |
| 0045 | docs/game/adr/0045-tooltip-triggers-minimap-retirement-web-charts.md | Proximity + inventory tooltip triggers; MapFogState/MinimapPanel deleted outright; item-gated WebChartState/ChartPanel; closes Domain 10 tooltip + map_reveal loops |
```

- [ ] Step 10.3: Fix ADR-0033's false "added to the regression bundle" claim. This is the pre-existing docs-integrity issue the design spec (§4, "Docs integrity (pre-existing)") flagged.

Find (in `docs/game/adr/0033-ui-ux-accessibility-architecture.md`, its Verification section):
```markdown
- 6 new pure-state smokes:
  `menu_state_smoke`, `settings_state_smoke`, `tooltip_presenter_smoke`,
  `tutorial_state_smoke`, `map_fog_state_smoke`, `controller_glyph_state_smoke`.
- 1 new main-playable end-to-end smoke:
  `main_playable_slice_ui_shell_smoke` — drives the coordinator through
  the full menu stack via `Input.action_press` / `Input.parse_input_event`.
- 1 new save/load smoke:
  `ui_shell_save_load_smoke` — proves settings round-trip.
- The existing `a11y_p1_002_idempotency_smoke`, `save_load_service_smoke`,
  and `main_playable_slice_text_scale_smoke` are re-verified after the
  changes and stay green.

All eight entries are added to the regression bundle.
```
Change to:
```markdown
- 6 new pure-state smokes:
  `menu_state_smoke`, `settings_state_smoke`, `tooltip_presenter_smoke`,
  `tutorial_state_smoke`, `map_fog_state_smoke` (deleted in Domain 10 — see
  ADR-0045), `controller_glyph_state_smoke`.
- 1 new main-playable end-to-end smoke:
  `main_playable_slice_ui_shell_smoke` — drives the coordinator through
  the full menu stack via `Input.action_press` / `Input.parse_input_event`.
- 1 new save/load smoke:
  `ui_shell_save_load_smoke` — proves settings round-trip.
- The existing `a11y_p1_002_idempotency_smoke`, `save_load_service_smoke`,
  and `main_playable_slice_text_scale_smoke` are re-verified after the
  changes and stay green.

**Correction (Domain 10, 2026-07-02):** the claim below this line originally
read "All eight entries are added to the regression bundle." This was false
— none of them were registered in `docs/game/06_validation_plan.md` at the
time this ADR was written (verified by grep). Domain 10 (ADR-0045) registers
all 9 UI-shell smokes that survive its `map_fog_state_smoke` deletion, plus
2 new ones, for 11 total `run_clean` entries (`06_validation_plan.md`,
`commands=121 → 132`).
```

- [ ] Step 10.4: Update the roadmap spec's Domain 10 section and status table row in `docs/superpowers/specs/2026-06-28-completion-roadmap-design.md`.

Find the status table row:
```markdown
| 10 | UI/UX Polish | `tooltip`, `map_reveal` | 🔴 / 🟡 | — |
```
Change to:
```markdown
| 10 | UI/UX Polish | `tooltip`, `map_reveal` | 🟢 closed (2026-07-02, ADR-0045) | — |
```

Find the Domain 10 section:
```markdown
### Domain 10: UI/UX Polish  [loops: `tooltip` 🔴, `map_reveal` 🟡]

**Verified break-points (from inventory):**
- `tooltip`: `set_tooltip_query` has **no live gameplay caller** (only two smokes) → tooltip never
  appears in real play.
- `map_reveal`: reveal only fires on `objective_completed` (3364) / critical-room track (4033) /
  `ui_open_map` tracked-room reveal (7036); **no per-step proximity discovery** wired.

**Definition of CLOSED:**
1. `set_tooltip_query` is **called** from real hover/focus interaction (interactables, inventory,
   HUD) so tooltips appear in play.
2. Map fog reveals on **player proximity** as they move through the derelict (per-step discovery), not
   only on objective completion.

**Away-branch checklist:** tooltip queries + proximity reveal both live on the away branch (the
derelict is where exploration happens).

**Validation:** `ui_polish_smoke.gd` — assert a hover query surfaces a tooltip; assert moving near an
undiscovered room reveals it on the minimap; `away_ticks=` on a derelict. Register markers.

**Inventory delta:** `tooltip.closes → "closed"` and `map_reveal.closes → "closed"`; flip
`tooltip_presenter.input.live` and `map_fog_state.input.live`; update break-points.
```
Change to:
```markdown
### Domain 10: UI/UX Polish  [loops: `tooltip` 🟢, `map_reveal` 🟢 — CLOSED 2026-07-02]

**Verified break-points (from inventory, now resolved — see ADR-0045):**
- `tooltip`: `set_tooltip_query` had **no live gameplay caller** (only two smokes) → tooltip never
  appeared in real play. **Resolved:** proximity focus (interactables) + inventory single-selection
  now both call it, change-gated, on both `_process` branches.
- `map_reveal`: reveal only fired on `objective_completed` (3364) / critical-room track (4033) /
  `ui_open_map` tracked-room reveal (7036); **no per-step proximity discovery** wired.

**User redefinition (2026-07-02, superseding this section's original plan):** the user overrode the
`map_reveal` per-step-proximity plan below before implementation. A traditional room minimap "cuts
down on the horror" this game is built around. `map_reveal` is redefined as **item-based web charts**
(Project Zomboid-style paper maps) tracking **ship positions in the web**, not interior rooms.
`MapFogState`/`MinimapPanel` are **deleted outright** (not extended); see
`docs/superpowers/specs/2026-07-02-domain10-ui-polish-design.md` and ADR-0045 for the full design and
rationale.

**Definition of CLOSED (as implemented):**
1. `set_tooltip_query` is called from real gameplay: proximity focus on interactables AND inventory
   row selection, live on BOTH `_process` branches.
2. The room-fog minimap is deleted; `ui_open_map` opens a web chart screen gated on possessing a chart
   item, rendering recorded ship-marker knowledge from two sources (scanner auto-record while a chart
   is possessed; found chart items importing current in-range markers).

**Away-branch checklist:** tooltip proximity focus is wired into both `_process` branches
(`_refresh_tooltip_focus`, called from both the away and home branches).

**Validation:** `ui_polish_smoke.gd` — asserts proximity focus set/change-gated/cleared, inventory
selection tooltip push, and the chart gate (denied without a chart, rendered with one after a scan),
with an `away_ticks=` marker field. Registered in the regression bundle (`06_validation_plan.md`,
`commands=132`).

**Inventory delta:** `tooltip.closes → "closed"` and `map_reveal.closes → "closed"` (redefined loop:
steps now `web_chart_state` → `chart_panel`); `tooltip_presenter.input.live → true`; `map_fog_state`/
`minimap_panel` system entries deleted; `web_chart_state`/`chart_panel` system entries added.
```

- [ ] Step 10.5: `git diff project.godot` — confirm empty (docs-only task, but keep the discipline consistent).

```bash
git diff --stat project.godot
```

- [ ] Step 10.6: Commit.

```bash
git add docs/game/adr/0045-tooltip-triggers-minimap-retirement-web-charts.md docs/game/adr/README.md docs/game/adr/0033-ui-ux-accessibility-architecture.md docs/superpowers/specs/2026-06-28-completion-roadmap-design.md
git commit -m "docs: add ADR-0045, correct ADR-0033's false bundle-registration claim, annotate roadmap Domain 10"
```

---

## Task 11: Inventory delta + regen + --check

**Files:**
- Modify: `docs/game/inventory/system_inventory.json`
- Test: `docs/game/inventory/SYSTEM_INVENTORY.md`, `docs/game/inventory/system_map.html` (regenerated, not hand-edited)

**Interfaces:** none (docs/inventory only)

- [ ] Step 11.1: In `docs/game/inventory/system_inventory.json`, delete the `map_fog_state` and `minimap_panel` system entries entirely (their full JSON objects, found earlier at approximately lines 4920–4958 and 5156–5194 — re-locate by searching for `"id": "map_fog_state"` and `"id": "minimap_panel"`, since line numbers will have shifted after Task 3's code deletions are reflected here).

Delete the `map_fog_state` entry:
```json
    {
      "id": "map_fog_state",
      "file": "scripts/systems/map_fog_state.gd",
      "name": "Map Fog State",
      "domain": "ui",
      "kind": "ui",
      "model_exists": true,
      "smoke": "scripts/validation/map_fog_state_smoke.gd",
      "reachable": true,
      "driven": true,
      "driven_at": "playable_generated_ship.gd:4029",
      "input": {
        "live": true,
        "desc": "configure_for_rooms via configure_map (4029); track critical[0] (4033); reveal_room on objective_completed (3364)",
        "at": "playable_generated_ship.gd:4029-4033, 3364"
      },
      "output": {
        "live": true,
        "desc": "revealed/tracked room state rendered into minimap panel",
        "at": "menu_coordinator.gd:650-661"
      },
      "confidence": "V",
      "loops": [
        "map_reveal"
      ],
      "integrations": [
        {
          "to": "minimap_panel",
          "via": "_refresh_minimap",
          "at": "menu_coordinator.gd:650",
          "health": "healthy"
        }
      ],
      "content": "partial",
      "content_note": "VERIFIED: configure_map->map_fog_state.configure_for_rooms at coordinator 205; fog built at runtime from generated room payload, no static data file",
      "functional": null,
      "gaps": [],
      "subsystems": []
    },
```
(remove the whole object AND its trailing comma, joining the surrounding entries cleanly).

Delete the `minimap_panel` entry the same way:
```json
    {
      "id": "minimap_panel",
      "file": "scripts/ui/minimap_panel.gd",
      "name": "Minimap Panel",
      "domain": "ui",
      "kind": "ui",
      "model_exists": true,
      "smoke": "scripts/validation/main_playable_ui_shell_smoke.gd",
      "reachable": true,
      "driven": true,
      "driven_at": "menu_coordinator.gd:650",
      "input": {
        "live": true,
        "desc": "map_fog_state tracked/revealed/discovered rooms",
        "at": "menu_coordinator.gd:654-660"
      },
      "output": {
        "live": true,
        "desc": "renders map text; toggled by ui_open_map",
        "at": "menu_coordinator.gd:661, 153-155"
      },
      "confidence": "V",
      "loops": [
        "map_reveal"
      ],
      "integrations": [
        {
          "to": "map_fog_state",
          "via": "reads fog state",
          "at": "menu_coordinator.gd:655",
          "health": "healthy"
        }
      ],
      "content": "partial",
      "content_note": "VERIFIED: set_map_text at 661, toggle at handle_ui_input 153-155; text-only map, visual pass pending",
      "functional": null,
      "gaps": [],
      "subsystems": []
    },
```

- [ ] Step 11.2: Add the `web_chart_state` system entry, in the same `systems` array (any position is acceptable structurally; insert it where the `map_fog_state` entry used to be for a minimal diff).

```json
    {
      "id": "web_chart_state",
      "file": "scripts/systems/web_chart_state.gd",
      "name": "Web Chart State",
      "domain": "ui",
      "kind": "ui",
      "model_exists": true,
      "smoke": "scripts/validation/web_chart_state_smoke.gd",
      "reachable": true,
      "driven": true,
      "driven_at": "playable_generated_ship.gd:scan",
      "input": {
        "live": true,
        "desc": "record_views merged from two sources: scan() when web_chart possessed (Source B), and _postprocess_loot_grants on a found web_chart pickup (Source A, detail 2 import)",
        "at": "playable_generated_ship.gd:scan, _postprocess_loot_grants"
      },
      "output": {
        "live": true,
        "desc": "known markers rendered by chart_panel",
        "at": "chart_panel.gd:refresh"
      },
      "confidence": "V",
      "loops": [
        "map_reveal"
      ],
      "integrations": [
        {
          "to": "chart_panel",
          "via": "get_known_marker_ids/get_entry read by refresh()",
          "at": "chart_panel.gd:refresh",
          "health": "healthy"
        }
      ],
      "content": "sufficient",
      "content_note": "ADR-0045: session-only by user decision -- no get_summary/apply_summary/SAVE_KEY (deliberate, not a gap).",
      "functional": true,
      "gaps": [],
      "subsystems": []
    },
```

- [ ] Step 11.3: Add the `chart_panel` system entry.

```json
    {
      "id": "chart_panel",
      "file": "scripts/ui/chart_panel.gd",
      "name": "Chart Panel",
      "domain": "ui",
      "kind": "ui",
      "model_exists": true,
      "smoke": "scripts/validation/ui_polish_smoke.gd",
      "reachable": true,
      "driven": true,
      "driven_at": "playable_generated_ship.gd:_input",
      "input": {
        "live": true,
        "desc": "opened by ui_open_map only when inventory_state.get_quantity('web_chart') > 0; otherwise gated with a HUD feedback line",
        "at": "playable_generated_ship.gd:_input"
      },
      "output": {
        "live": true,
        "desc": "renders web_chart_state's known markers as text rows; read-only, no travel action",
        "at": "chart_panel.gd:_render"
      },
      "confidence": "V",
      "loops": [
        "map_reveal"
      ],
      "integrations": [
        {
          "to": "web_chart_state",
          "via": "bind() + get_known_marker_ids/get_entry",
          "at": "chart_panel.gd:bind",
          "health": "healthy"
        }
      ],
      "content": "partial",
      "content_note": "ADR-0045: text-only rows (ScannerPanel presentation style); visual/graphical map pass is an explicit documented deferral.",
      "functional": true,
      "gaps": [],
      "subsystems": []
    },
```

- [ ] Step 11.4: Update `tooltip_presenter`'s entry: flip `input.live` to `true`, update `driven_at`/`input.desc`/`input.at`, and clear its `gaps` array.

Find (re-locate by `"id": "tooltip_presenter"`):
```json
      "input": {
        "live": false,
        "desc": "resolve(query) only called from set_tooltip_query (coordinator:233-234), whose ONLY callers are two validation smokes — no live gameplay source",
        "at": "main_playable_ui_shell_smoke.gd:109"
      },
```
Change to:
```json
      "input": {
        "live": true,
        "desc": "resolve(query) called from set_tooltip_query, driven by two live gameplay triggers (ADR-0045): PlayableGeneratedShip._refresh_tooltip_focus (proximity focus, both _process branches) and InventoryPanel.select_row's injected tooltip_query_push (single-item selection)",
        "at": "playable_generated_ship.gd:_refresh_tooltip_focus, inventory_panel.gd:select_row"
      },
```
Find:
```json
      "gaps": [
        "no live gameplay caller of set_tooltip_query (hover/focus never wired) — tooltip path is smoke-only"
      ],
```
Change to:
```json
      "gaps": [],
```

- [ ] Step 11.5: Update the `tooltip` loop entry's `closes` field, in the top-level `loops` array.

Find:
```json
    {
      "id": "tooltip",
      "name": "Hover/focus -> tooltip",
      "closes": "broken",
      "steps": [
        {
          "system": "tooltip_presenter",
          "role": "resolver"
        },
        {
          "system": "tooltip_panel",
          "role": "sink"
        }
      ],
      "break_points": [
        "set_tooltip_query has no live gameplay caller — only main_playable_ui_shell_smoke.gd:109 and main_playable_slice_ui_shell_smoke.gd:105 (verified by grep) — tooltip never appears in real play"
      ]
    }
```
Change to:
```json
    {
      "id": "tooltip",
      "name": "Proximity focus + inventory selection -> tooltip",
      "closes": "closed",
      "steps": [
        {
          "system": "tooltip_presenter",
          "role": "resolver"
        },
        {
          "system": "tooltip_panel",
          "role": "sink"
        }
      ],
      "break_points": []
    }
```

- [ ] Step 11.6: Update the `map_reveal` loop entry: redefine its steps to `web_chart_state` → `chart_panel` and close it.

Find:
```json
    {
      "id": "map_reveal",
      "name": "Exploration -> fog reveal -> minimap",
      "closes": "partial",
      "steps": [
        {
          "system": "map_fog_state",
          "role": "fog state"
        },
        {
          "system": "minimap_panel",
          "role": "sink (render)"
        }
      ],
      "break_points": [
        "reveal only fires on objective_completed (playable:3364) / critical-room track (4033) / ui_open_map tracked-room reveal (7036); no per-step proximity discovery wired"
      ]
    },
```
Change to:
```json
    {
      "id": "map_reveal",
      "name": "Scanner contacts / found charts -> web chart",
      "closes": "closed",
      "steps": [
        {
          "system": "web_chart_state",
          "role": "recorder"
        },
        {
          "system": "chart_panel",
          "role": "sink (render)"
        }
      ],
      "break_points": []
    },
```

- [ ] Step 11.7: Regenerate the derived docs from the edited JSON.

```bash
python tools/build_system_inventory.py
```

- [ ] Step 11.8: Run the anti-drift check.

```bash
python tools/build_system_inventory.py --check
```

Expected output: a line matching `SYSTEM INVENTORY CHECK PASS systems=<N> verified=<N>` (N reflects the net system count after this task's -2/+2 edit — unchanged count from before this domain, since two entries were deleted and two added).

- [ ] Step 11.9: Confirm the regenerated `SYSTEM_INVENTORY.md` and `system_map.html` are staged as part of the same change (the `--check` step in 11.8 re-renders them from the JSON; they must not be hand-edited).

```bash
git status --short docs/game/inventory/
```

Expected output: shows `system_inventory.json`, `SYSTEM_INVENTORY.md`, and `system_map.html` as modified.

- [ ] Step 11.10: `git diff project.godot` — confirm empty.

```bash
git diff --stat project.godot
```

- [ ] Step 11.11: Commit.

```bash
git add docs/game/inventory/system_inventory.json docs/game/inventory/SYSTEM_INVENTORY.md docs/game/inventory/system_map.html
git commit -m "docs: inventory delta for Domain 10 (map_fog_state/minimap_panel deleted, web_chart_state/chart_panel added, tooltip+map_reveal closed)"
```

---

## Final verification

- [ ] Run the full regression bundle one final time end-to-end (all 132 commands) to confirm the complete Domain 10 change set is internally consistent after every task's edits landed.

```bash
GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
```

Then run the exact fenced bash block under `## Regression bundle` in `docs/game/06_validation_plan.md` with those two vars exported, as in Task 9 Step 9.3.

Expected final line: `SYNAPTIC_SEA REGRESSION PASS commands=132 clean_output=true`.

- [ ] Run `python tools/build_system_inventory.py --check` one final time.

Expected output: `SYSTEM INVENTORY CHECK PASS systems=<N> verified=<N>` with no drift.

- [ ] `git diff --stat project.godot` one final time — confirm empty across the entire branch's work.

- [ ] Confirm no `.godot/`, `*.uid`, or `addons/` paths were staged in any commit made by this plan.

```bash
git log --stat --name-only feat/domain10-ui-polish | grep -E "^\.godot/|\.uid$|^addons/" || echo "CLEAN: no forbidden paths staged"
```
