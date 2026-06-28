# Item Economy (hull_sealant + fire_extinguisher) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the breach-seal and fire-extinguish loops reachable in real play by defining `hull_sealant` (consumable) and `fire_extinguisher` (reusable tool) as uncommon loot + mid-tier recipes — no starting handout.

**Architecture:** Pure data additions (item definitions, loot tables, recipes) consumed by the already-wired `breach_seal_point` (`required_item: "hull_sealant"`) and `fire_suppression_point` (`required_tool: "fire_extinguisher"`). No node code changes. Two smokes: a data-validation smoke and a live reachability smoke that crafts each item through the real craft path then uses it through the real interact dispatcher.

**Tech Stack:** Godot 4.6.2, typed GDScript. JSON data files. Headless `--script` validation smokes; PASS marker is the contract.

## Global Constraints

- **Godot binary:** `C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe`. **Project root:** `C:/Users/dasbl/Documents/The Synaptic Sea`.
- Run a smoke: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/<name>.gd` (ROOT has a space — keep it quoted). **`--script` can exit 0 on parse errors — trust the PASS marker, not the exit code.**
- Allowlisted teardown noise (ignore): `ERROR: Capture not registered: 'gdaimcp'.` and `WARNING: ObjectDB instances leaked at exit`. Any other `ERROR:`/`WARNING:` line fails the bundle.
- Typed GDScript. **No code changes to `breach_seal_point.gd` / `fire_suppression_point.gd`** — they already reference these ids.
- **No starting handout:** neither item may be seeded into the run-setup starting inventory.
- Items are **uncommon** (`rarity: "uncommon"`, loot `weight: 2`). Recipes are mid-tier: `craft_hull_sealant` `required_skill_level: 2` @ `workbench`; `craft_fire_extinguisher` `required_skill_level: 3` @ `fabricator`.
- **Derelict-side fire is OUT of scope** (separate follow-up). Do NOT remove any `away_from_start` guard.
- Conventional Commits; commit trailers on every commit:
  ```
  Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_012rncQ3JTUdorqXH1b4eQNY
  ```
- **Selective `git add` only** — never `git add -A`/`.`; never stage `project.godot`, `.godot/`, `*.uid`, `addons/`.
- Register every new smoke in `docs/game/06_validation_plan.md`; bump the final `commands=NN` count by the number added. Confirm the full bundle stays clean.

---

## File Structure

- **Modify** `data/items/item_definitions.json` — add `hull_sealant`, `fire_extinguisher`. (Task 1)
- **Modify** `data/items/loot_tables.json` — add both to the named tables. (Task 1)
- **Modify** `data/recipes/recipe_definitions.json` — add `craft_hull_sealant`, `craft_fire_extinguisher`. (Task 1)
- **Create** `scripts/validation/item_economy_smoke.gd` — data validation. (Task 1)
- **Create** `scripts/validation/main_playable_item_economy_smoke.gd` — live reachability. (Task 2)
- **Modify** `docs/game/06_validation_plan.md` — register both smokes (Tasks 1, 2).
- **Modify** `docs/game/system_completion_audit.md` — M7 re-grade. (Task 3)

---

## Task 1: Item definitions, loot, recipes + data smoke

**Files:**
- Modify: `data/items/item_definitions.json`
- Modify: `data/items/loot_tables.json`
- Modify: `data/recipes/recipe_definitions.json`
- Test: `scripts/validation/item_economy_smoke.gd`
- Modify: `docs/game/06_validation_plan.md`

**Interfaces:**
- Produces (data): item ids `hull_sealant`, `fire_extinguisher`; loot entries in `salvage_cargo`, `repair_parts_common`, `generic_locker`, `salvage_engineering`; recipes `craft_hull_sealant`, `craft_fire_extinguisher`.

- [ ] **Step 1: Write the failing data smoke**

Create `scripts/validation/item_economy_smoke.gd`:

```gdscript
extends SceneTree

## Data-validation proof: hull_sealant + fire_extinguisher are defined, lootable, and
## craftable at the intended mid-tier — closing the breach-seal / fire-extinguish loops.
## Marker: ITEM ECONOMY PASS sealant_def=true ext_def=true sealant_loot=true ext_loot=true sealant_recipe=true ext_recipe=true skill_gated=true

func _initialize() -> void:
	var items: Dictionary = _read_json("res://data/items/item_definitions.json")
	var loot: Dictionary = _read_json("res://data/items/loot_tables.json")
	var recipes_doc: Dictionary = _read_json("res://data/recipes/recipe_definitions.json")

	# --- item definitions ---
	var sealant_def: bool = _is_dict(items.get("hull_sealant")) \
		and str(items["hull_sealant"].get("category", "")) == "part" \
		and str(items["hull_sealant"].get("rarity", "")) == "uncommon"
	var ext_def: bool = _is_dict(items.get("fire_extinguisher")) \
		and str(items["fire_extinguisher"].get("category", "")) == "tool" \
		and int(items["fire_extinguisher"].get("max_stack", 99)) == 1 \
		and str(items["fire_extinguisher"].get("rarity", "")) == "uncommon"

	# --- loot presence (any table) ---
	var sealant_loot: bool = _in_any_loot(loot, "hull_sealant")
	var ext_loot: bool = _in_any_loot(loot, "fire_extinguisher")

	# --- recipes ---
	var recipes: Array = recipes_doc.get("recipes", []) if recipes_doc.get("recipes", []) is Array else []
	var r_sealant: Dictionary = _recipe_producing(recipes, "hull_sealant")
	var r_ext: Dictionary = _recipe_producing(recipes, "fire_extinguisher")
	var sealant_recipe: bool = not r_sealant.is_empty() and str(r_sealant.get("station_kind", "")) == "workbench"
	var ext_recipe: bool = not r_ext.is_empty() and str(r_ext.get("station_kind", "")) == "fabricator"
	var skill_gated: bool = int(r_sealant.get("required_skill_level", -1)) == 2 \
		and int(r_ext.get("required_skill_level", -1)) == 3

	if sealant_def and ext_def and sealant_loot and ext_loot and sealant_recipe and ext_recipe and skill_gated:
		print("ITEM ECONOMY PASS sealant_def=true ext_def=true sealant_loot=true ext_loot=true sealant_recipe=true ext_recipe=true skill_gated=true")
		quit(0)
	else:
		push_error("ITEM ECONOMY FAIL sealant_def=%s ext_def=%s sealant_loot=%s ext_loot=%s sealant_recipe=%s ext_recipe=%s skill_gated=%s" % [
			sealant_def, ext_def, sealant_loot, ext_loot, sealant_recipe, ext_recipe, skill_gated])
		quit(1)

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

func _is_dict(v: Variant) -> bool:
	return typeof(v) == TYPE_DICTIONARY

func _in_any_loot(loot: Dictionary, item_id: String) -> bool:
	for table_id in loot:
		var table: Variant = loot[table_id]
		if not _is_dict(table):
			continue
		var entries: Variant = (table as Dictionary).get("entries", [])
		if entries is Array:
			for e in entries:
				if e is Dictionary and str((e as Dictionary).get("item_id", "")) == item_id:
					return true
	return false

func _recipe_producing(recipes: Array, item_id: String) -> Dictionary:
	for r in recipes:
		if r is Dictionary:
			var produces: Variant = (r as Dictionary).get("produces", {})
			if produces is Dictionary and str((produces as Dictionary).get("item_id", "")) == item_id:
				return r as Dictionary
	return {}
```

- [ ] **Step 2: Run; expect failure**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/item_economy_smoke.gd`
Expected: `ITEM ECONOMY FAIL ...` (items/loot/recipes not present yet).

- [ ] **Step 3: Add item definitions**

In `data/items/item_definitions.json`, add two entries (match the existing one-line style; place `hull_sealant` near `sealant`):

```jsonc
"hull_sealant":      { "display_name": "Hull Sealant",      "category": "part", "weight": 1.0, "max_stack": 10, "rarity": "uncommon" },
"fire_extinguisher": { "display_name": "Fire Extinguisher", "category": "tool", "weight": 3.0, "max_stack": 1,  "rarity": "uncommon" }
```

- [ ] **Step 4: Add loot entries**

In `data/items/loot_tables.json`, add an entry to each named table's `entries` array:

- `salvage_cargo`: `{ "item_id": "hull_sealant", "qty_min": 1, "qty_max": 2, "weight": 2, "rarity": "uncommon" }`
- `repair_parts_common`: `{ "item_id": "hull_sealant", "qty_min": 1, "qty_max": 1, "weight": 2, "rarity": "uncommon" }`
- `generic_locker`: `{ "item_id": "fire_extinguisher", "qty_min": 1, "qty_max": 1, "weight": 2, "rarity": "uncommon" }`
- `salvage_engineering`: `{ "item_id": "fire_extinguisher", "qty_min": 1, "qty_max": 1, "weight": 2, "rarity": "uncommon" }`

- [ ] **Step 5: Add recipes**

In `data/recipes/recipe_definitions.json`, append to the `recipes` array:

```jsonc
{
  "recipe_id": "craft_hull_sealant",
  "display_name": "Mix Hull Sealant",
  "category": "repair",
  "ingredients": { "sealant": 2, "adhesive_paste": 1 },
  "produces": { "item_id": "hull_sealant", "quantity": 1 },
  "craft_time_seconds": 12.0,
  "required_skill_level": 2,
  "station_kind": "workbench",
  "power_cost": 2.0,
  "batch_size": 1
},
{
  "recipe_id": "craft_fire_extinguisher",
  "display_name": "Assemble Fire Extinguisher",
  "category": "fabrication",
  "ingredients": { "scrap_metal": 2, "power_cell": 1, "reactive_gel": 1 },
  "produces": { "item_id": "fire_extinguisher", "quantity": 1 },
  "craft_time_seconds": 20.0,
  "required_skill_level": 3,
  "station_kind": "fabricator",
  "power_cost": 3.0,
  "batch_size": 1
}
```

Verify `adhesive_paste` is obtainable as an inventory ingredient (it is already an ingredient of the existing `weld_plating` recipe; defined in `data/materials/material_definitions.json`). If it turns out a player cannot acquire it, change `craft_hull_sealant` ingredients to `{ "sealant": 2, "scrap_metal": 1 }` (both are loot items) and note the change in the report.

- [ ] **Step 6: Run the data smoke; expect PASS**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/item_economy_smoke.gd`
Expected: `ITEM ECONOMY PASS sealant_def=true ext_def=true sealant_loot=true ext_loot=true sealant_recipe=true ext_recipe=true skill_gated=true`

Also sanity-check the JSON parses elsewhere by running an existing loot/craft smoke (no regression):
`"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_station_craft_smoke.gd` → `MAIN PLAYABLE STATION CRAFT PASS ...`

- [ ] **Step 7: Register + commit**

Add to `docs/game/06_validation_plan.md` (near the other model/data smokes):
```bash
run_clean 'item economy data smoke' 'ITEM ECONOMY PASS sealant_def=true ext_def=true sealant_loot=true ext_loot=true sealant_recipe=true ext_recipe=true skill_gated=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/item_economy_smoke.gd
```
Bump the `commands=NN` count by 1.

```bash
git add data/items/item_definitions.json data/items/loot_tables.json data/recipes/recipe_definitions.json scripts/validation/item_economy_smoke.gd docs/game/06_validation_plan.md
git commit  # "feat(economy): define hull_sealant + fire_extinguisher (loot + recipes)" + trailers
```

---

## Task 2: Live reachability smoke (craft → seal, craft → extinguish)

**Files:**
- Create: `scripts/validation/main_playable_item_economy_smoke.gd`
- Modify: `docs/game/06_validation_plan.md`

**Interfaces:**
- Consumes (coordinator seams, all existing): `crafting_state.begin_craft(recipe_id, inventory, material_state, player_skill_level)`, `advance_crafting_for_validation(delta)`, `crafting_state.get_or_create_station(kind).set_power(true)`, `get_breach_seal_points_for_validation()`, `teleport_player_to_breach_seal_point_for_validation(sp)`, `_on_player_interact_requested(player)`, `force_hull_breach_for_validation(cid, amount)`, `get_fire_suppression_points_for_validation()`, `teleport_player_to_fire_suppression_point_for_validation(fp)`, `get_extinguisher_state()`, `set_manual_power_route_for_validation("stations", 0.0)`, `fire_suppression_state`, `_build_fire_context()`, `_refresh_fire_zones()`.

- [ ] **Step 1: Write the failing reachability smoke**

Create `scripts/validation/main_playable_item_economy_smoke.gd`:

```gdscript
extends SceneTree

## Live reachability proof: BOTH fire-fighting items are obtained ONLY by crafting them
## through the real craft path (no add_item of the finished item), then used through the real
## interact dispatcher — proving the breach-seal and fire-extinguish loops are reachable in
## actual play (previously the items existed only via test injection).
## Marker: MAIN PLAYABLE ITEM ECONOMY PASS crafted_sealant=true sealed=true crafted_ext=true extinguished=true reachable=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 360

var main_node: Node
var playable: PlayableGeneratedShip
var frame_count: int = 0
var finished: bool = false

func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	if main_node == null:
		_fail("could not instantiate main scene"); return
	get_root().add_child(main_node)
	process_frame.connect(_on_process_frame)

func _on_process_frame() -> void:
	if finished:
		return
	frame_count += 1
	if playable == null:
		playable = _find_playable(main_node)
	if playable == null or playable.loader == null or not playable.loader.has_loaded_ship() or not playable.playable_started:
		if frame_count > TIMEOUT_FRAMES:
			_fail("playable did not become ready")
		return
	_validate()

func _validate() -> void:
	var inv = playable.inventory_state
	if inv == null or playable.crafting_state == null or playable.material_state == null:
		_fail("inventory/crafting models missing"); return
	playable.away_from_start = false
	if playable.threat_manager != null:
		playable.threat_manager.threats.clear()

	# --- 1) Craft hull_sealant via the REAL craft path (no add_item of hull_sealant) ---------
	inv.add_item("sealant", 2)
	inv.add_item("adhesive_paste", 1)
	playable.crafting_state.get_or_create_station("workbench").set_power(true)
	var sealant_before: int = inv.get_quantity("hull_sealant")
	if not playable.crafting_state.begin_craft("craft_hull_sealant", inv, playable.material_state, 5):
		_fail("begin_craft craft_hull_sealant failed (ingredients/recipe?)"); return
	playable.advance_crafting_for_validation(120.0)
	var crafted_sealant: bool = inv.get_quantity("hull_sealant") > sealant_before
	if not crafted_sealant:
		_fail("hull_sealant not produced by craft"); return

	# --- 2) Seal a breach through the REAL interact dispatcher (consumes the crafted sealant) -
	playable.force_hull_breach_for_validation("cargo", 0.7)
	var seal_points: Array = playable.get_breach_seal_points_for_validation()
	if seal_points.is_empty():
		_fail("no breach seal point for the forced breach"); return
	var sp = seal_points[0]
	playable.teleport_player_to_breach_seal_point_for_validation(sp)
	playable._on_player_interact_requested(playable.player)
	if not (sp.channeling or sp.sealed):
		_fail("interact did not start the seal channel (loop unreachable)"); return
	sp.advance_channel(10.0)
	var sealed: bool = playable.hull_integrity_state.get_breach_count() == 0 and inv.get_quantity("hull_sealant") < (sealant_before + 1)

	# --- 3) Craft fire_extinguisher via the REAL craft path (no add_item of the tool) --------
	inv.add_item("scrap_metal", 2)
	inv.add_item("power_cell", 1)
	inv.add_item("reactive_gel", 1)
	playable.crafting_state.get_or_create_station("fabricator").set_power(true)
	var ext_before: int = inv.get_quantity("fire_extinguisher")
	if not playable.crafting_state.begin_craft("craft_fire_extinguisher", inv, playable.material_state, 5):
		_fail("begin_craft craft_fire_extinguisher failed"); return
	playable.advance_crafting_for_validation(120.0)
	var crafted_ext: bool = inv.get_quantity("fire_extinguisher") > ext_before
	if not crafted_ext:
		_fail("fire_extinguisher not produced by craft"); return

	# --- 4) Ignite a fire, then extinguish via the REAL dispatcher using the crafted tool ----
	# Keep suppression UNPOWERED so powered auto-suppression does not beat the manual path
	# (same isolation the M7-B fire-loop smoke uses).
	playable.set_manual_power_route_for_validation("stations", 0.0)
	playable.life_support_expanded_state.oxygen_percent = 100.0
	for sub in playable.ship_systems_manager.get_system("power").subcomponents:
		sub.health = 0.1
	var steps := 0
	while not playable.fire_suppression_state.is_burning("engineering") and steps < 600:
		playable.fire_suppression_state.tick(0.1, playable._build_fire_context())
		steps += 1
	if not playable.fire_suppression_state.is_burning("engineering"):
		_fail("engineering never ignited"); return
	playable._refresh_fire_zones()
	playable.get_extinguisher_state().charge = playable.get_extinguisher_state().max_charge
	var fps: Array = playable.get_fire_suppression_points_for_validation()
	var fp = null
	for p in fps:
		if str(p.compartment_id) == "engineering":
			fp = p
	if fp == null:
		_fail("no engineering fire suppression point"); return
	playable.teleport_player_to_fire_suppression_point_for_validation(fp)
	playable._on_player_interact_requested(playable.player)
	if not (fp.channeling or fp.extinguished):
		_fail("interact did not start the extinguish channel (loop unreachable)"); return
	fp.advance_channel(10.0)
	var extinguished: bool = not playable.fire_suppression_state.is_burning("engineering")

	if crafted_sealant and sealed and crafted_ext and extinguished:
		print("MAIN PLAYABLE ITEM ECONOMY PASS crafted_sealant=true sealed=true crafted_ext=true extinguished=true reachable=true")
		finished = true
		_cleanup_and_quit(0)
	else:
		_fail("crafted_sealant=%s sealed=%s crafted_ext=%s extinguished=%s" % [crafted_sealant, sealed, crafted_ext, extinguished])

func _find_playable(node: Node) -> PlayableGeneratedShip:
	if node is PlayableGeneratedShip:
		return node as PlayableGeneratedShip
	for child in node.get_children():
		var f = _find_playable(child)
		if f != null:
			return f
	return null

func _fail(reason: String) -> void:
	if finished:
		return
	finished = true
	push_error("MAIN PLAYABLE ITEM ECONOMY FAIL reason=%s" % reason)
	_cleanup_and_quit(1)

func _cleanup_and_quit(code: int) -> void:
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
```

> Implementer notes: (1) All seam names above are used by existing smokes (`main_playable_slice_station_craft_smoke.gd` for the craft seams; `main_playable_life_support_vitals_smoke.gd` for the breach-seal seams; `main_playable_fire_loop_smoke.gd` for the fire seams) — grep those if a signature differs and adapt. (2) The breach compartment id `"cargo"` and system `"power"`/`"engineering"` mirror those smokes; if the boot ship uses different ids, reuse whatever the fire-loop / life-support smokes use. (3) `begin_craft` does not enforce skill level (the interaction layer does), so passing `5` is fine; the skill gate itself is asserted by the Task 1 data smoke.

- [ ] **Step 2: Run; expect failure, then PASS once Task 1 data exists**

If Task 1 is already merged into the branch, this should pass directly. Run:
`"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_item_economy_smoke.gd`
Expected: `MAIN PLAYABLE ITEM ECONOMY PASS crafted_sealant=true sealed=true crafted_ext=true extinguished=true reachable=true`

If it fails on a seam signature, adapt to the real signature (see implementer notes) — do not weaken the assertions (the craft→use chain with no item injection is the point).

- [ ] **Step 3: Register + commit**

Add to `docs/game/06_validation_plan.md`:
```bash
run_clean 'main item economy reachability smoke' 'MAIN PLAYABLE ITEM ECONOMY PASS crafted_sealant=true sealed=true crafted_ext=true extinguished=true reachable=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_item_economy_smoke.gd
```
Bump the `commands=NN` count by 1.

```bash
git add scripts/validation/main_playable_item_economy_smoke.gd docs/game/06_validation_plan.md
git commit  # "test(economy): live craft->seal and craft->extinguish reachability smoke" + trailers
```

---

## Task 3: Documentation — audit re-grade

**Files:**
- Modify: `docs/game/system_completion_audit.md`

- [ ] **Step 1: Re-grade M7 hull / fire-tool acquisition**

In `docs/game/system_completion_audit.md`:
- M7 `hull_integrity_state` row: drop the "`hull_sealant` is not yet a defined or obtainable item ... player-facing loop completion deferred" caveat — the breach-seal loop is now reachable (uncommon loot + `craft_hull_sealant`). Cite `item_definitions.json` / `loot_tables.json` / `recipe_definitions.json` and `main_playable_item_economy_smoke.gd`.
- M7-B deferred follow-ups list: move `fire_extinguisher` acquisition to RESOLVED (uncommon loot + `craft_fire_extinguisher`); the manual extinguish loop is now reachable in real play.
- Add a one-line note that **derelict-side fire** remains the open M7 follow-up, now unblocked by this economy.

- [ ] **Step 2: Commit**

```bash
git add docs/game/system_completion_audit.md
git commit  # "docs(economy): audit re-grade — breach/fire loops now reachable" + trailers
```

---

## Self-Review (completed)

- **Spec coverage:** items defined (Task 1 Step 3), uncommon loot in the four named tables (Step 4), mid-tier recipes at skill 2/3 + correct stations (Step 5), data smoke asserts all of it incl. skill gate (Step 1), live reachability via real craft + real dispatcher with NO item injection (Task 2), no node code changes, no starting handout (constraint + data smoke is data-only; the live smoke seeds only ingredients, never the finished items), derelict fire explicitly out of scope, docs re-grade (Task 3). Covered.
- **Placeholder scan:** no TBD/TODO; every code/data step shows the exact content. The `adhesive_paste` fallback is a concrete conditional, not a placeholder.
- **Type/id consistency:** item ids (`hull_sealant`, `fire_extinguisher`), recipe ids (`craft_hull_sealant`, `craft_fire_extinguisher`), station kinds (`workbench`, `fabricator`), skill levels (2, 3), and loot table names (`salvage_cargo`, `repair_parts_common`, `generic_locker`, `salvage_engineering`) are identical across the data steps, the data smoke, and the live smoke. The live smoke's craft ingredients exactly match the recipe ingredients in Step 5.
