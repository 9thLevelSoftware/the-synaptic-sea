extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES := 360

var main_node: Node
var playable: PlayableGeneratedShip
var frame_count := 0
var finished := false


func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	root.add_child(main_node)
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	if finished:
		return
	frame_count += 1
	if not is_instance_valid(playable):
		playable = _find_playable(main_node)
	if not is_instance_valid(playable) or not is_instance_valid(playable.loader) \
			or not playable.loader.has_loaded_ship() or not playable.playable_started:
		if frame_count > TIMEOUT_FRAMES:
			_fail("playable did not become ready")
		return
	_validate()


func _validate() -> void:
	finished = true
	for system_id in ["power", "navigation", "scanners", "propulsion"]:
		var system = playable.get_ship_systems_manager().get_system(system_id)
		if system != null:
			for subcomponent in system.subcomponents:
				playable.get_ship_systems_manager().force_repair(system_id, subcomponent.subcomponent_id)
	var world = playable.get_synaptic_sea_world()
	var boarded := false
	for marker in world.markers_in_range(playable.scanner_state.range_radius).slice(0, 4):
		if bool(playable.travel_to_marker_id(String(marker.marker_id)).get("success", false)):
			boarded = true
			break
	if not boarded or playable.get_current_ship() == null:
		_fail("could not board a generated derelict")
		return
	# The travel smoke validates the derelict branch directly; clear any stale
	# lifeboat occupancy so the same field-suit pressure gate used while walking
	# the boarded hull is active for this focused assertion.
	playable.current_occupancy = null
	if not playable._is_field_suit_pressure_active():
		_fail("boarded derelict did not activate field suit pressure")
		return
	var active_loader = playable.get_current_ship().scene_root
	if not is_instance_valid(active_loader) or not active_loader.has_method("get_radiation_zone_at"):
		_fail("boarded ship is not the authored-field loader")
		return
	var local_player: Vector3 = active_loader.to_local(playable.player.global_position)
	var portals: Array[Area3D] = active_loader.get_authored_portal_nodes()
	if portals.is_empty():
		_fail("boarded derelict materialized no authored portal interactions")
		return
	var portal = portals[0]
	for candidate in portals:
		if str(candidate.portal_kind) == "DOOR":
			portal = candidate
			break
	portal.set_validation_player_in_range(true)
	var portal_shape: CollisionShape3D = portal.get_blocker_collision_shape()
	var portal_shape_disabled_before := portal_shape.disabled
	if not playable._try_authored_portal_interact(playable.player):
		_fail("playable interaction coordinator ignored an authored portal")
		return
	if not portal.is_exterior and str(portal.portal_kind) != "BREACH" \
			and portal_shape.disabled == portal_shape_disabled_before:
		_fail("playable authored portal interaction did not change collision")
		return
	var localized_markers: Array[Vector3] = [local_player]
	active_loader.radiation_zone_markers = localized_markers
	active_loader.radiation_zone_specs = [{"zone_id": "playable_radiation", "kind": "radiation"}]
	playable.radiation_state.configure({"radiation": 0.0, "in_radiation_zone": false})
	playable._tick_survival_attrition(1.0)
	if not playable.radiation_state.in_radiation_zone or playable.radiation_state.radiation <= 0.0:
		_fail("localized authored radiation did not reach the playable survival tick")
		return
	var original_loader = playable.loader
	var breach_markers: Array[Vector3] = [local_player, local_player + Vector3(4.0, 0.0, 0.0)]
	active_loader.breach_zone_markers = breach_markers
	active_loader.breach_zone_specs = [
		{"zone_id": "playable_breach_a", "kind": "hull_breach"},
		{"zone_id": "playable_breach_b", "kind": "hull_breach"},
	]
	playable.loader = active_loader
	playable._build_breach_zone()
	playable.loader = original_loader
	var breach_nodes: Array[StaticBody3D] = playable.get_breach_zone_nodes()
	if breach_nodes.size() != 2:
		_fail("playable did not materialize every authored breach zone")
		return
	var breach_ids := {}
	for breach_node in breach_nodes:
		breach_ids[str(breach_node.get_meta("breach_zone_id", ""))] = true
	if breach_ids.size() != 2 or playable.get_oxygen_summary().get("breach_zone_ids", []).size() != 2:
		_fail("playable breach zones did not preserve stable authored IDs")
		return

	var fire_state = playable.get_current_ship().get_fire()
	if fire_state != null:
		for compartment in fire_state.get_burning_compartments():
			fire_state.extinguish(str(compartment))
	active_loader.authored_atmosphere_specs = [{
		"room_id": "playable_test_room", "position": local_player,
		"oxygen_bp": 10000, "depressurized": false,
	}]
	playable.oxygen_state.configure({"max_oxygen": 100.0, "drain_rate": 8.0})
	playable._refresh_oxygen_state(false, 1.0)
	if playable.oxygen_state.oxygen < 99.999:
		_fail("fully oxygenated authored compartment still drained field oxygen")
		return
	var vacuum_spec: Dictionary = active_loader.authored_atmosphere_specs[0]
	vacuum_spec["oxygen_bp"] = 0
	active_loader.authored_atmosphere_specs[0] = vacuum_spec
	playable._refresh_oxygen_state(false, 1.0)
	if playable.oxygen_state.oxygen >= 99.999 or playable.oxygen_state.effective_drain_rate <= 0.0:
		_fail("vacuum-authored compartment did not drain field oxygen")
		return
	print("BUILDER PLAYABLE RUNTIME FIELDS PASS boarded=true portal_interaction=true localized_radiation=true multiple_breaches=true authored_atmosphere=true")
	quit(0)


func _find_playable(node: Node) -> PlayableGeneratedShip:
	if node is PlayableGeneratedShip:
		return node
	for child in node.get_children():
		var found := _find_playable(child)
		if found != null:
			return found
	return null


func _fail(message: String) -> void:
	finished = true
	push_error("BUILDER PLAYABLE RUNTIME FIELDS FAIL %s" % message)
	quit(1)
