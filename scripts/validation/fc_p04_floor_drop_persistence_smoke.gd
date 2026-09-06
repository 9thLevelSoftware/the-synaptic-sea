extends SceneTree

## Actual main-scene P04 floor-holder lifecycle. A nonstandard lot is partially
## scooped, restored through the world snapshot path, then survives leave/revisit.
## Marker: FC P04 FLOOR DROP PERSISTENCE PASS

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const ItemLotLedgerScript := preload("res://scripts/systems/item_lot_ledger.gd")
const WorkYieldDropScript := preload("res://scripts/tools/work_yield_drop.gd")
const TIMEOUT_FRAMES: int = 600

var main_node: Node
var playable
var frame_count: int = 0
var finished: bool = false

func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	get_root().add_child(main_node)
	process_frame.connect(_on_frame)

func _on_frame() -> void:
	if finished:
		return
	frame_count += 1
	if playable == null:
		playable = _find_playable(main_node)
	if playable == null or not playable.playable_started:
		if frame_count > TIMEOUT_FRAMES:
			_fail("playable not ready")
		return
	_validate()

func _validate() -> void:
	finished = true
	for system_id in ["power", "navigation", "scanners", "propulsion"]:
		var system = playable.get_ship_systems_manager().get_system(system_id)
		if system != null:
			for subcomponent in system.subcomponents:
				playable.get_ship_systems_manager().force_repair(system_id, subcomponent.subcomponent_id)
	var markers: Array = playable.get_synaptic_sea_world().markers_in_range(playable.scanner_state.range_radius)
	if markers.is_empty():
		_fail("no travel marker")
		return
	var marker_id: String = str(markers[0].marker_id)
	var travel: Dictionary = playable.travel_to_marker_id(marker_id)
	if not bool(travel.get("success", false)):
		_fail("initial travel failed: %s" % str(travel.get("reason", "")))
		return
	var owner = playable.get_current_ship()
	var drop_id: String = owner.allocate_floor_drop_id()
	var ledger = ItemLotLedgerScript.new({}, "floor:%s" % drop_id)
	if ledger.add_lot({
		"lot_id": "yield:nonstandard-live",
		"item_id": "scrap_metal",
		"quantity": 5,
		"quality_score": 0.82,
		"quality_tier": "excellent",
		"condition": 0.43,
		"origin": {"source": "live_partial"},
	}) != 5 or ledger.add_standard("ration_pack", 1) != 1:
		_fail("could not seed exact lots")
		return
	var saved_transform := Transform3D(Basis.from_euler(Vector3(0.0, 0.37, 0.0)), Vector3(3.25, 0.35, -2.5))
	if not owner.upsert_floor_drop_descriptor({
		"drop_id": drop_id,
		"ship_id": owner.ship_id,
		"transform": owner.transform_to_summary(saved_transform),
		"item_lots_v1": ledger.get_summary(),
	}):
		_fail("descriptor rejected")
		return
	if not playable._restore_floor_drops_for_ship(owner):
		_fail("initial materialization failed")
		return
	var drop = _drop_by_id(drop_id)
	if drop == null:
		_fail("materialized drop missing")
		return
	playable.inventory_state.remove_item("scrap_metal", playable.inventory_state.get_quantity("scrap_metal"))
	playable.inventory_state.add_item("scrap_metal", 18)
	drop.set_validation_player_in_range(playable.player)
	if not drop.try_interact(playable.player):
		_fail("partial scoop failed")
		return
	if drop.get_quantity("scrap_metal") != 3 or bool(drop.scooped_flag):
		_fail("partial residual wrong")
		return
	var residual: Dictionary = _lot_by_id(drop.get_lot_summary(), "yield:nonstandard-live")
	if residual.is_empty() or int(residual.quantity) != 3 \
			or float(residual.quality_score) != 0.82 or float(residual.condition) != 0.43 \
			or residual.origin != {"source": "live_partial"}:
		_fail("partial scoop changed exact lot metadata")
		return
	var partial_sequence: int = int(drop.get_lot_summary().sequence)
	var snapshot = playable._build_world_snapshot()
	if not playable._apply_world_snapshot(snapshot):
		_fail("fresh world restore rejected")
		return
	var restored_owner = playable.get_current_ship()
	var restored = _drop_by_id(drop_id)
	if restored == null or str(restored_owner.ship_id) != str(owner.ship_id):
		_fail("fresh restore drop missing")
		return
	if not _assert_exact_residual(restored, saved_transform, partial_sequence):
		return
	if not playable.travel_home():
		_fail("travel home failed")
		return
	var revisit: Dictionary = playable.travel_to_marker_id(marker_id)
	if not bool(revisit.get("success", false)):
		_fail("revisit failed: %s" % str(revisit.get("reason", "")))
		return
	var revisited = _drop_by_id(drop_id)
	if revisited == null or not _assert_exact_residual(revisited, saved_transform, partial_sequence):
		if revisited == null:
			_fail("revisited drop missing")
		return
	var matches: int = 0
	for candidate in playable.get_work_yield_drops_for_validation():
		if is_instance_valid(candidate) and str(candidate.drop_id) == drop_id:
			matches += 1
	if matches != 1:
		_fail("drop duplicated on revisit")
		return
	print("FC P04 FLOOR DROP PERSISTENCE PASS partial=true fresh_load=true revisit=true lots=true transform=true sequence=%d" % partial_sequence)
	_teardown(0)

func _assert_exact_residual(drop, expected_transform: Transform3D, expected_sequence: int) -> bool:
	var summary: Dictionary = drop.get_lot_summary()
	var lot: Dictionary = _lot_by_id(summary, "yield:nonstandard-live")
	if lot.is_empty() or int(lot.quantity) != 3 or float(lot.quality_score) != 0.82 \
			or float(lot.condition) != 0.43 or lot.origin != {"source": "live_partial"}:
		_fail("restored residual metadata changed")
		return false
	if int(summary.sequence) != expected_sequence:
		_fail("restored ledger sequence changed")
		return false
	if not drop.transform.is_equal_approx(expected_transform):
		_fail("restored ship-local transform changed")
		return false
	return true

func _lot_by_id(summary: Dictionary, lot_id: String) -> Dictionary:
	for raw in summary.get("lots", []) as Array:
		if raw is Dictionary and str((raw as Dictionary).get("lot_id", "")) == lot_id:
			return raw as Dictionary
	return {}

func _drop_by_id(drop_id: String):
	for drop in playable.get_work_yield_drops_for_validation():
		if is_instance_valid(drop) and str(drop.drop_id) == drop_id:
			return drop
	return null

func _find_playable(node: Node):
	if node is PlayableGeneratedShip:
		return node
	for child in node.get_children():
		var found = _find_playable(child)
		if found != null:
			return found
	return null

func _fail(reason: String) -> void:
	if not finished:
		finished = true
	push_error("FC P04 FLOOR DROP PERSISTENCE FAIL reason=%s" % reason)
	_teardown(1)

func _teardown(code: int) -> void:
	if main_node != null and is_instance_valid(main_node):
		main_node.free()
	quit(code)
