extends SceneTree

## PKG-B2.4b: station tier from components, batch queue, recipe schema fields.
## Marker: STATION TIERS BATCH PASS tier=true queue=true gate=true schema=true batch=true

const StationStateScript := preload("res://scripts/systems/station_state.gd")
const CraftingStateScript := preload("res://scripts/systems/crafting_state.gd")
const ComponentCatalogScript := preload("res://scripts/systems/component_catalog.gd")
const InventoryStateScript := preload("res://scripts/systems/inventory_state.gd")


func _initialize() -> void:
	# --- StationState queue + batch ---
	var st = StationStateScript.new()
	st.configure({"station_kind": "fabricator", "level": 0, "powered": true, "max_queue": 3})
	if st.effective_tier() != 0:
		_fail("base tier 0"); return
	st.apply_component_tier(2)
	if st.effective_tier() != 2:
		_fail("component tier should raise effective_tier"); return
	st.level = 3
	if st.effective_tier() != 3:
		_fail("level can raise effective_tier above component bonus"); return
	st.level = 0
	st.apply_component_tier(1)
	if st.effective_tier() != 1:
		_fail("tier 1 expected"); return

	if not st.enqueue("a"):
		_fail("enqueue a"); return
	if st.enqueue_batch("b", 5) != 2:
		_fail("batch should fill remaining 2 of max_queue=3"); return
	if st.queue.size() != 3:
		_fail("queue full size"); return
	if st.enqueue("c"):
		_fail("full queue should reject"); return
	if st.queue_space() != 0:
		_fail("no space"); return
	var snap: Dictionary = st.get_summary()
	if int(snap.get("tier", -1)) != 1 or int(snap.get("max_queue", 0)) != 3:
		_fail("summary missing tier/max_queue"); return
	var st2 = StationStateScript.new()
	st2.apply_summary(snap)
	if st2.queue.size() != 3 or st2.effective_tier() != 1:
		_fail("summary round-trip"); return

	# --- CraftingState schema + tier gate ---
	var craft = CraftingStateScript.new()
	if craft.recipe_count() < 5:
		_fail("recipes not loaded"); return
	if craft.get_work_verb("weld_plating") != "weld":
		_fail("work_verb weld_plating"); return
	if craft.get_station_tier_min("craft_sensor_module") < 1:
		_fail("sensor_module should require tier>=1"); return
	if craft.get_station_tier_min("craft_thruster_nozzle") < 2:
		_fail("thruster_nozzle should require tier>=2"); return
	if craft.get_knowledge_source("craft_thruster_nozzle") != "book":
		_fail("thruster knowledge_source book"); return

	var inv = InventoryStateScript.new()
	# Give materials for craft_sensor_module
	inv.add_item("sensor_array", 2)
	inv.add_item("optical_lens", 2)
	inv.add_item("circuit_board", 2)
	if craft.can_craft("craft_sensor_module", inv, null, 0):
		_fail("tier 0 should fail sensor_module"); return
	if not craft.can_craft("craft_sensor_module", inv, null, 1):
		_fail("tier 1 should allow sensor_module"); return

	var entries: Array = craft.list_recipe_entries("fabricator", inv, 5, 0)
	var found_blocked: bool = false
	for e in entries:
		if str(e.get("recipe_id", "")) == "craft_sensor_module":
			if str(e.get("status", "")) != "insufficient_tier":
				_fail("list should mark insufficient_tier"); return
			found_blocked = true
	if not found_blocked:
		_fail("sensor_module missing from list"); return

	# --- derive tier from components ---
	var cat = ComponentCatalogScript.new()
	if not cat.load_default():
		_fail("component catalog"); return
	var placed: Array = [
		{
			"component_id": "reactor_console",
			"mounted": true,
			"station_tier_bonus": 0,  # force catalog lookup
		},
		{
			"component_id": "console_generic",
			"mounted": true,
		},
	]
	var derived: int = CraftingStateScript.derive_tier_from_components("fabricator", placed, cat)
	if derived < 2:
		_fail("reactor_console should give fabricator tier 2, got %d" % derived); return
	var t: int = craft.refresh_station_tier("fabricator", placed, cat)
	if t < 2:
		_fail("refresh_station_tier"); return

	# --- batch enqueue via crafting state ---
	var accepted: int = craft.enqueue_craft("craft_power_cell", 4)
	if accepted < 1:
		_fail("enqueue_craft should accept"); return
	var fab = craft.get_station("fabricator")
	if fab == null or fab.queue.size() < 1:
		_fail("fabricator queue empty"); return

	# begin_craft respects station tier
	var mat = preload("res://scripts/systems/material_state.gd").new()
	if mat.has_method("configure"):
		mat.configure({})
	# Ensure materials for power cell
	inv.add_item("scrap_metal", 5)
	inv.add_item("wiring_bundle", 5)
	inv.add_item("reactive_gel", 5)
	if not craft.begin_craft("craft_power_cell", inv, mat, 5):
		_fail("begin_craft power_cell should work at tier 2"); return

	print("STATION TIERS BATCH PASS tier=true queue=true gate=true schema=true batch=true")
	quit(0)


func _fail(msg: String) -> void:
	print("STATION TIERS BATCH FAIL: %s" % msg)
	quit(1)
