extends SceneTree

## Real salvage-objective overflow lifecycle: a completed objective with full
## destination stacks retains exact reward lots in ship-owned floor holders,
## restores them through a world snapshot and revisit, and collects them once.

const Playable := preload("res://scripts/procgen/playable_generated_ship.gd")
const ItemDefsScript := preload("res://scripts/systems/item_defs.gd")

var playable


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	playable = Playable.new()
	root.add_child(playable)
	for _frame in range(600):
		await process_frame
		if playable != null and bool(playable.playable_started):
			break
	if playable == null or not bool(playable.playable_started):
		_fail("playable did not become ready")
		return
	var manager = playable.get_ship_systems_manager()
	for system_id in ["power", "navigation", "scanners", "propulsion"]:
		var system = manager.get_system(system_id)
		if system != null:
			for subcomponent in system.subcomponents:
				manager.force_repair(system_id, subcomponent.subcomponent_id)
	playable.board_piloted_ship_for_validation()
	playable.recompute_occupancy()
	var markers: Array = playable.get_synaptic_sea_world().markers_in_range(
		playable.scanner_state.range_radius)
	if markers.is_empty():
		_fail("no reachable derelict")
		return
	var marker_id: String = str(markers[0].marker_id)
	var travel: Dictionary = playable.travel_to_marker_id(marker_id)
	if not bool(travel.get("success", false)):
		_fail("travel failed: %s" % str(travel))
		return
	var sequence: int = -1
	var objective_id: String = ""
	for interactable in playable.derelict_interactables:
		if str(interactable.objective_type) == "salvage":
			sequence = int(interactable.sequence)
			objective_id = str(interactable.objective_id)
			break
	if sequence < 0 or objective_id.is_empty():
		_fail("no real salvage objective")
		return
	var owner_ship_id: String = str(playable.current_ship.ship_id)
	var seed_source: String = "%s:%s" % [str(playable.current_ship.marker_id), objective_id]
	var rolled: Array = playable.LootDistributionScript.roll(
		playable._salvage_loot_tables[objective_id], seed_source, playable._loot_tables, {
			"biome_id":playable._resolve_current_loot_biome_id(),
			"loot_quality_modifier":playable._resolve_current_loot_quality_modifier(),
			"depth":playable._resolve_current_loot_depth(),
			"condition":playable._resolve_current_loot_condition(),
			"container_kind":"salvage_objective",
			"item_definitions":ItemDefsScript.load_definitions(),
			"unique_state":playable.unique_item_state,
		})
	if rolled.is_empty():
		_fail("salvage objective rolled no rewards")
		return
	var expected_lots: Dictionary = {}
	var expected_totals: Dictionary = {}
	for reward_index in range(rolled.size()):
		var reward: Dictionary = rolled[reward_index] as Dictionary
		var item_id: String = str(reward.get("item_id", ""))
		var quantity: int = int(reward.get("quantity", 0))
		if item_id.is_empty() or quantity <= 0:
			_fail("invalid authored reward")
			return
		var lot_id: String = "objective:%s:%03d" % [seed_source, reward_index]
		expected_lots[lot_id] = {
			"item_id":item_id,
			"quantity":quantity,
			"quality_score":clampf(float(reward.get(
				"quality_score", reward.get("quality", 0.5))), 0.0, 1.0),
			"seed_key":str(reward.get("seed_key", "")),
		}
		expected_totals[item_id] = int(expected_totals.get(item_id, 0)) + quantity
		playable.inventory_state.add_item(item_id, 999)
	if not playable.complete_derelict_objective_for_validation(sequence):
		_fail("real salvage objective did not complete")
		return
	var drop_ids: Array = playable.current_ship.floor_drop_descriptors.keys()
	drop_ids.sort()
	if drop_ids.size() != expected_lots.size():
		_fail("overflow did not create one persistent holder per reward")
		return
	if not _assert_floor_lots(expected_lots, drop_ids, "initial overflow"):
		return
	var snapshot = playable._build_world_snapshot()
	if not playable._apply_world_snapshot(snapshot):
		_fail("fresh world snapshot restore rejected")
		return
	if str(playable.current_ship.ship_id) != owner_ship_id:
		_fail("fresh restore changed owning ship")
		return
	if not _assert_floor_lots(expected_lots, drop_ids, "fresh restore"):
		return
	if not playable.travel_home():
		_fail("travel home failed")
		return
	var revisit: Dictionary = playable.travel_to_marker_id(marker_id)
	if not bool(revisit.get("success", false)):
		_fail("revisit failed: %s" % str(revisit))
		return
	if str(playable.current_ship.ship_id) != owner_ship_id:
		_fail("revisit changed owning ship")
		return
	if not _assert_floor_lots(expected_lots, drop_ids, "revisit"):
		return
	for item_id in expected_totals:
		playable.inventory_state.remove_item(
			str(item_id), playable.inventory_state.get_quantity(str(item_id)))
	for drop_id_variant in drop_ids:
		var drop = _drop_by_id(str(drop_id_variant))
		if drop == null:
			_fail("revisited overflow node missing: %s" % str(drop_id_variant))
			return
		drop.set_validation_player_in_range(playable.player)
		if not drop.try_interact(playable.player):
			_fail("overflow collection failed: %s" % str(drop_id_variant))
			return
	for item_id in expected_totals:
		if playable.inventory_state.get_quantity(str(item_id)) != int(expected_totals[item_id]):
			_fail("collected reward quantity changed for %s" % str(item_id))
			return
	if not _assert_inventory_lots(expected_lots):
		return
	if not playable.current_ship.floor_drop_descriptors.is_empty():
		_fail("collected overflow descriptors remain owned")
		return
	var collected_summary: Dictionary = playable.inventory_state.get_summary()
	if playable.complete_derelict_objective_for_validation(sequence):
		_fail("completed objective replayed")
		return
	var collected_snapshot = playable._build_world_snapshot()
	if not playable._apply_world_snapshot(collected_snapshot):
		_fail("post-collection restore rejected")
		return
	if playable.inventory_state.get_summary() != collected_summary \
			or not playable.current_ship.floor_drop_descriptors.is_empty():
		_fail("post-collection restore duplicated reward")
		return
	if not playable.travel_home() \
			or not bool(playable.travel_to_marker_id(marker_id).get("success", false)):
		_fail("post-collection revisit failed")
		return
	for drop_id_variant in drop_ids:
		if _drop_by_id(str(drop_id_variant)) != null:
			_fail("collected reward respawned on revisit")
			return
	if playable.inventory_state.get_summary() != collected_summary:
		_fail("post-collection revisit changed reward lots")
		return
	print("FC P04 OBJECTIVE LOTS PASS overflow=true fresh_load=true revisit=true exact_lots=true collect_once=true")
	_teardown(0)


func _assert_floor_lots(expected: Dictionary, drop_ids: Array, stage: String) -> bool:
	var actual: Dictionary = {}
	for drop_id_variant in drop_ids:
		var drop_id: String = str(drop_id_variant)
		var descriptor: Dictionary = playable.current_ship.floor_drop_descriptors.get(
			drop_id, {}) as Dictionary
		if descriptor.is_empty() or str(descriptor.get("ship_id", "")) != str(playable.current_ship.ship_id):
			_fail("%s lost ship-owned descriptor %s" % [stage, drop_id])
			return false
		var summary: Dictionary = descriptor.get("item_lots_v1", {}) as Dictionary
		for raw_lot in summary.get("lots", []) as Array:
			if raw_lot is Dictionary:
				actual[str((raw_lot as Dictionary).get("lot_id", ""))] = raw_lot
	if actual.size() != expected.size():
		_fail("%s changed overflow lot count" % stage)
		return false
	for lot_id in expected:
		if not _lot_matches(actual.get(lot_id, {}) as Dictionary, expected[lot_id] as Dictionary):
			_fail("%s changed exact overflow lot %s" % [stage, lot_id])
			return false
	return true


func _assert_inventory_lots(expected: Dictionary) -> bool:
	var actual: Dictionary = {}
	for raw_lot in playable.inventory_state.get_lot_summary().get("lots", []) as Array:
		if raw_lot is Dictionary:
			actual[str((raw_lot as Dictionary).get("lot_id", ""))] = raw_lot
	for lot_id in expected:
		if not _lot_matches(actual.get(lot_id, {}) as Dictionary, expected[lot_id] as Dictionary):
			_fail("collected exact lot changed: %s" % lot_id)
			return false
	return true


func _lot_matches(actual: Dictionary, expected: Dictionary) -> bool:
	if actual.is_empty() or str(actual.get("item_id", "")) != str(expected.item_id) \
			or int(actual.get("quantity", 0)) != int(expected.quantity) \
			or not is_equal_approx(float(actual.get("quality_score", -1.0)), float(expected.quality_score)) \
			or not is_equal_approx(float(actual.get("condition", -1.0)), 1.0):
		return false
	var origin: Dictionary = actual.get("origin", {}) as Dictionary
	return str(origin.get("seed_source", "")) != "" \
		and str(origin.get("seed_key", "")) == str(expected.seed_key) \
		and str(origin.get("source_condition", "")) != ""


func _drop_by_id(drop_id: String):
	for drop in playable.get_work_yield_drops_for_validation():
		if is_instance_valid(drop) and str(drop.drop_id) == drop_id:
			return drop
	return null


func _fail(reason: String) -> void:
	push_error("FC P04 OBJECTIVE LOTS FAIL reason=%s" % reason)
	_teardown(1)


func _teardown(code: int) -> void:
	if playable != null and is_instance_valid(playable):
		playable.free()
	quit(code)
