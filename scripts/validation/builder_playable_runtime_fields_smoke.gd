extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const AuthoredPortalRuntimeScript := preload("res://scripts/interaction/authored_portal_runtime.gd")
const ShipInstanceScript := preload("res://scripts/systems/ship_instance.gd")
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
	# Home and derelict breach environments are independent, while suit oxygen
	# follows the player. Seal home before boarding to catch cross-ship leakage.
	playable.oxygen_state.apply_summary({"hazard_kind": "oxygen", "oxygen": 91.0})
	if not playable.oxygen_state.seal_breach("home_breach"):
		_fail("could not seed sealed home breach before boarding")
		return
	var seeded_home_oxygen := playable.get_oxygen_summary()
	if absf(float(seeded_home_oxygen.get("oxygen", 0.0)) - 91.0) > 0.001:
		_fail("could not seed home player oxygen: %s" % str(seeded_home_oxygen))
		return
	var world = playable.get_synaptic_sea_world()
	var boarded := false
	for marker in world.markers_in_range(playable.scanner_state.range_radius).slice(0, 4):
		if bool(playable.travel_to_marker_id(String(marker.marker_id)).get("success", false)):
			boarded = true
			break
	if not boarded or playable.get_current_ship() == null:
		_fail("could not board a generated derelict")
		return
	var boarded_oxygen_summary := playable.get_oxygen_summary()
	if absf(float(boarded_oxygen_summary.get("oxygen", 0.0)) - 91.0) > 0.001 \
			or not bool(boarded_oxygen_summary.get("breach_open", false)) \
			or bool(boarded_oxygen_summary.get("breach_sealed", true)):
		_fail("sealed home breach leaked into freshly boarded derelict: %s" % str(boarded_oxygen_summary))
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
	var portal = null
	for candidate in portals:
		if str(candidate.portal_kind) == "DOOR" and not candidate.is_exterior:
			portal = candidate
			break
	if portal == null:
		for candidate in portals:
			if not candidate.is_exterior and str(candidate.portal_kind) != "BREACH":
				portal = candidate
				break
	if portal == null:
		_fail("boarded derelict has no non-exterior portal for collision validation")
		return
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

	# Spending the last bypass charge on an authored locked portal must persist
	# both its unlocked identity and open state through ShipInstance save/rebuild.
	var locked_portal = AuthoredPortalRuntimeScript.new()
	locked_portal.configure({
		"id": "playable_persistent_lock", "kind": "LOCKED",
		"lock_kind": "mechanical", "exterior": false,
	}, local_player)
	active_loader.add_child(locked_portal)
	active_loader.authored_portal_nodes.clear()
	active_loader.authored_portal_nodes.append(locked_portal)
	locked_portal.set_validation_player_in_range(true)
	playable.utility_item_state.active_flags["lockpick"] = {
		"item_id": "lockpick_set", "count": 1,
	}
	if not playable._try_authored_portal_interact(playable.player):
		_fail("playable authored lock did not accept its utility charge")
		return
	if playable.utility_item_state.active_flags.has("lockpick"):
		_fail("playable authored lock did not consume the last utility charge")
		return
	var active_ship = playable.get_current_ship()
	var persisted_ship = ShipInstanceScript.create(
		active_ship.ship_id, active_ship.marker_id, active_ship.blueprint,
		active_ship.systems_manager, active_ship.scene_root)
	if not persisted_ship.apply_summary(active_ship.get_summary()) \
			or not persisted_ship.authored_unlocked_portal_ids.has("playable_persistent_lock") \
			or not persisted_ship.authored_open_portal_ids.has("playable_persistent_lock"):
		_fail("ShipInstance did not round-trip authored portal persistence")
		return
	active_ship.authored_unlocked_portal_ids = persisted_ship.authored_unlocked_portal_ids.duplicate()
	active_ship.authored_open_portal_ids = persisted_ship.authored_open_portal_ids.duplicate()
	var rebuilt_locked = AuthoredPortalRuntimeScript.new()
	rebuilt_locked.configure({
		"id": "playable_persistent_lock", "kind": "LOCKED",
		"lock_kind": "mechanical", "exterior": false,
	}, local_player)
	active_loader.add_child(rebuilt_locked)
	active_loader.authored_portal_nodes.clear()
	active_loader.authored_portal_nodes.append(rebuilt_locked)
	playable._restore_authored_portal_states()
	if not rebuilt_locked.is_unlocked or not rebuilt_locked.is_open:
		_fail("boarded rebuild did not restore authored portal state")
		return
	rebuilt_locked.set_validation_player_in_range(true)
	if not playable._try_authored_portal_interact(playable.player) \
			or not playable._try_authored_portal_interact(playable.player) \
			or not rebuilt_locked.is_open:
		_fail("restored authored lock could not close and reopen without another charge")
		return

	# Boarded repair junctions must use one production Interactable per authored
	# step and complete their controller sequence only after the last step.
	active_loader.objective_specs = [{
		"id": "playable_repair_junction", "sequence": 1,
		"type": "restore_systems", "kind": "repair_junction",
		"room_id": "playable_test_room", "position": local_player,
		"steps": [
			{"step_id": "primary_coupling", "position": local_player},
			{"step_id": "secondary_coupling", "position": local_player + Vector3(1.0, 0.0, 0.0)},
		],
	}]
	playable.get_current_ship().objective_controller = null
	playable._build_derelict_objectives()
	if playable.derelict_interactables.size() != 2:
		_fail("boarded repair junction did not materialize every authored step")
		return
	var derelict_controller = playable.get_current_ship().get_objective_controller()
	for index in range(playable.derelict_interactables.size()):
		var step_interactable = playable.derelict_interactables[index]
		step_interactable.set_validation_player_in_range(playable.player)
		if not step_interactable.try_interact(playable.player):
			_fail("boarded repair-junction step was not interactable")
			return
		if index == 0 and derelict_controller.is_objective_complete(1):
			_fail("boarded repair junction completed after only its first step")
			return
	if not derelict_controller.is_objective_complete(1):
		_fail("boarded repair junction did not complete after every step")
		return

	# The production arc consumer must materialize every authored marker, not
	# only the first one that the builder preview happened to validate.
	var authored_arc_markers: Array[Vector3] = [
		local_player + Vector3(2.0, 0.0, 0.0),
		local_player + Vector3(6.0, 0.0, 0.0),
	]
	active_loader.arc_zone_markers = authored_arc_markers
	active_loader.arc_zone_specs = [
		{"id": "playable_arc_a", "zone_id": "playable_arc_a", "to_room": "room_a"},
		{"id": "playable_arc_b", "zone_id": "playable_arc_b", "to_room": "room_b"},
	]
	playable._build_arc_zone()
	if not playable.has_method("get_arc_zone_nodes"):
		_fail("production runtime exposes no plural arc scene consumers")
		return
	var arc_nodes: Array = playable.call("get_arc_zone_nodes")
	if arc_nodes.size() != authored_arc_markers.size():
		_fail("production runtime did not materialize every authored arc")
		return
	for index in range(arc_nodes.size()):
		var arc_node: Node3D = arc_nodes[index]
		if str(arc_node.get_meta("arc_zone_id", "")) != str(active_loader.arc_zone_specs[index].get("id", "")):
			_fail("production arc consumer lost its authored stable ID")
			return
		var expected_arc_world: Vector3 = active_loader.to_global(authored_arc_markers[index])
		if arc_node.global_position.distance_to(expected_arc_world) > 0.05:
			_fail("production arc consumer used the wrong authored marker position")
			return
	var localized_markers: Array[Vector3] = [local_player]
	active_loader.radiation_zone_markers = localized_markers
	active_loader.radiation_zone_specs = [{"zone_id": "playable_radiation", "kind": "radiation"}]
	playable.radiation_state.configure({"radiation": 0.0, "in_radiation_zone": false})
	playable._tick_survival_attrition(1.0)
	if not playable.radiation_state.in_radiation_zone or playable.radiation_state.radiation <= 0.0:
		_fail("localized authored radiation did not reach the playable survival tick")
		return
	var breach_markers: Array[Vector3] = active_loader.get_breach_zone_markers()
	if breach_markers.is_empty():
		# This generated fixture has no authored breach by default. Inject two into
		# the already-boarded loader and rebuild without swapping the home loader;
		# this exercises active-loader selection and coordinate conversion directly.
		breach_markers = [local_player, local_player + Vector3(4.0, 0.0, 0.0)]
		active_loader.breach_zone_markers = breach_markers
		active_loader.breach_zone_specs = [
			{"zone_id": "playable_breach_a", "kind": "hull_breach"},
			{"zone_id": "playable_breach_b", "kind": "hull_breach"},
		]
		playable._build_breach_zone()
	var breach_nodes: Array[StaticBody3D] = playable.get_breach_zone_nodes()
	if breach_nodes.size() != breach_markers.size():
		_fail("ship transition did not materialize every authored breach zone")
		return
	var breach_ids := {}
	for index in range(breach_nodes.size()):
		var breach_node: StaticBody3D = breach_nodes[index]
		breach_ids[str(breach_node.get_meta("breach_zone_id", ""))] = true
		var expected_world: Vector3 = active_loader.to_global(breach_markers[index])
		if breach_node.global_position.distance_to(expected_world) > 0.05:
			_fail("boarded breach zone did not transform from loader-local coordinates")
			return
	if breach_ids.size() != breach_markers.size() \
			or playable.get_oxygen_summary().get("breach_zone_ids", []).size() != breach_markers.size():
		_fail("playable breach zones did not preserve stable authored IDs")
		return

	var fire_state = playable.get_current_ship().get_fire()
	if fire_state != null:
		for compartment in fire_state.get_burning_compartments():
			fire_state.extinguish(str(compartment))
	active_loader.authored_atmosphere_specs = [{
		"room_id": "playable_test_room", "position": local_player,
		"oxygen_bp": 10000, "depressurized": false,
		"radiation_bp": 5000, "temperature_c": 60.0,
	}]
	active_loader.radiation_zone_markers.clear()
	active_loader.radiation_zone_specs.clear()
	playable.radiation_state.configure({"radiation": 0.0, "in_radiation_zone": false})
	playable.body_temperature_state.configure({})
	playable._tick_survival_attrition(30.0)
	if not playable.radiation_state.in_radiation_zone or playable.radiation_state.radiation <= 0.0:
		_fail("room radiation_bp did not reach RadiationState")
		return
	if not playable.body_temperature_state.in_extreme_zone or playable.body_temperature_state.is_safe():
		_fail("room temperature_c did not reach BodyTemperatureState")
		return
	var safe_spec: Dictionary = active_loader.authored_atmosphere_specs[0]
	safe_spec["radiation_bp"] = 0
	safe_spec["temperature_c"] = 22.0
	active_loader.authored_atmosphere_specs[0] = safe_spec
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
	var safe_room_position := local_player + Vector3(20.0, 0.0, 0.0)
	var hazardous_room_spec: Dictionary = active_loader.authored_atmosphere_specs[0].duplicate(true)
	hazardous_room_spec["radiation_bp"] = 5000
	var safe_room_spec: Dictionary = hazardous_room_spec.duplicate(true)
	safe_room_spec["room_id"] = "playable_safe_room"
	safe_room_spec["position"] = safe_room_position
	safe_room_spec["radiation_bp"] = 0
	safe_room_spec["temperature_c"] = 22.0
	active_loader.authored_atmosphere_specs = [hazardous_room_spec, safe_room_spec]
	active_loader.radiation_zone_markers.clear()
	active_loader.radiation_zone_specs.clear()
	playable.player.global_position = active_loader.to_global(safe_room_position)
	playable.radiation_state.configure({"radiation": 0.0, "in_radiation_zone": false})
	playable._tick_survival_attrition(1.0)
	if playable.radiation_state.in_radiation_zone:
		_fail("radiation from an authored room leaked into a safe authored room")
		return
	if playable.body_temperature_state.in_extreme_zone:
		_fail("temperature from an authored room leaked into a safe authored room")
		return
	# Leaving every authored atmosphere volume must not reactivate the legacy
	# ship-wide derelict heat when any room-scoped temperature source exists.
	playable.player.global_position = active_loader.to_global(safe_room_position + Vector3(100.0, 0.0, 0.0))
	playable.body_temperature_state.temperature = 40.0
	playable._tick_survival_attrition(1.0)
	if playable.body_temperature_state.in_extreme_zone \
			or playable.body_temperature_state.temperature >= 40.0:
		_fail("room-authored temperature leaked ship-wide outside its volume")
		return
	# Pressure/oxygen and radiation-only atmosphere records do not define a
	# thermal source.  The legacy derelict thermal hazard must remain active
	# rather than treating an omitted temperature as nominal recovery.
	active_loader.authored_atmosphere_specs = [{
		"room_id": "playable_pressure_only", "position": safe_room_position,
		"oxygen_bp": 10000, "depressurized": false,
	}]
	playable.body_temperature_state.configure({})
	playable._tick_survival_attrition(1.0)
	if not playable.body_temperature_state.in_extreme_zone:
		_fail("pressure-only atmosphere incorrectly synthesized thermal recovery")
		return
	active_loader.authored_atmosphere_specs = [{
		"room_id": "playable_radiation_only", "position": safe_room_position,
		"radiation_bp": 5000,
	}]
	playable.body_temperature_state.configure({})
	playable._tick_survival_attrition(1.0)
	if not playable.body_temperature_state.in_extreme_zone:
		_fail("radiation-only atmosphere incorrectly synthesized thermal recovery")
		return
	var derelict_breach_ids := breach_ids.duplicate()
	# Leave the derelict breach open while lowering player oxygen. Returning home
	# must preserve the oxygen but restore home's independently sealed environment.
	playable.oxygen_state.apply_summary({
		"hazard_kind": "oxygen",
		"oxygen": 47.0,
		"breach_open": true,
		"breach_sealed": false,
		"breach_zone_ids": breach_markers.map(func(_marker): return "playable_breach_a"),
	})
	var exterior_portal = null
	for candidate in active_loader.get_authored_portal_nodes():
		if candidate.is_exterior and str(candidate.portal_kind) != "BREACH":
			exterior_portal = candidate
			break
	if exterior_portal == null:
		exterior_portal = AuthoredPortalRuntimeScript.new()
		exterior_portal.configure({"id": "playable_exterior_exit", "kind": "DOOR", "exterior": true}, local_player)
		active_loader.add_child(exterior_portal)
	# Isolate the coordinator consequence under test. An earlier portal was put
	# into forced validation range above and would otherwise consume the same
	# interaction before this exterior portal can return its exit result.
	active_loader.authored_portal_nodes.clear()
	active_loader.authored_portal_nodes.append(exterior_portal)
	exterior_portal.set_validation_player_in_range(true)
	if not playable._try_authored_portal_interact(playable.player) or playable.away_from_start:
		_fail("authored exterior portal did not execute the production return-home consequence")
		return
	if active_ship.authored_open_portal_ids.has(str(exterior_portal.get("portal_id"))):
		_fail("exterior exit incorrectly persisted as open across a revisit")
		return
	var expected_home_breaches := maxi(1, playable.loader.get_breach_zone_markers().size())
	var home_breach_nodes: Array[StaticBody3D] = playable.get_breach_zone_nodes()
	if home_breach_nodes.size() != expected_home_breaches:
		_fail("return-home transition did not rebuild home breach zones")
		return
	var home_oxygen_summary := playable.get_oxygen_summary()
	if absf(float(home_oxygen_summary.get("oxygen", 0.0)) - 47.0) > 0.001 \
			or not bool(home_oxygen_summary.get("breach_sealed", false)):
		_fail("travel_home did not preserve oxygen and restore the sealed home breach")
		return
	for home_breach in home_breach_nodes:
		if not bool(home_breach.get_meta("breach_zone_sealed", false)):
			_fail("rebuilt home breach node did not reflect preserved sealed state")
			return
		if derelict_breach_ids.has(str(home_breach.get_meta("breach_zone_id", ""))):
			_fail("derelict breach zone leaked into the home ship")
			return
	# Revisit the same derelict and verify its independently open environment is
	# restored instead of inheriting home's sealed state.
	playable.board_piloted_ship_for_validation()
	playable.recompute_occupancy()
	var revisit_result: Dictionary = playable.travel_to_marker_id(str(active_ship.marker_id))
	if not bool(revisit_result.get("success", false)):
		_fail("could not revisit derelict for breach isolation: %s" % str(revisit_result))
		return
	var revisited_oxygen_summary := playable.get_oxygen_summary()
	if absf(float(revisited_oxygen_summary.get("oxygen", 0.0)) - 47.0) > 0.001 \
			or not bool(revisited_oxygen_summary.get("breach_open", false)) \
			or bool(revisited_oxygen_summary.get("breach_sealed", true)):
		_fail("revisited derelict did not restore its independent breach environment")
		return
	print("BUILDER PLAYABLE RUNTIME FIELDS PASS boarded=true portal_interaction=true authored_portal_persistence=true exterior_exit=true multi_step_objective=true multiple_arcs=true localized_radiation=true multiple_breaches=true authored_atmosphere=true atmosphere_survival=true transition_breaches=true")
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
