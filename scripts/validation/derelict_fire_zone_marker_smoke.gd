extends SceneTree

## Tranche 5 (2026-07-06 audit HIGH, generated_ship_loader.gd:834/:934):
## get_fire_zone_markers() / get_fire_zone_specs() had ZERO callers — the
## loader computed layout-declared fire zone midpoints + specs on every load
## and nothing read them. The sibling hazards already consume their getters
## (_resolve_arc_zone_world_position, _resolve_breach_zone_world_position);
## fire visuals instead round-robined over _distributed_room_positions(), so
## a layout's declared fire location never influenced where the fire zone
## node landed.
##
## Wire under test (away branch only — home fire zones are lifeboat-local per
## the Codex P1 fix and must NOT read home-loader-frame markers):
## _build_fire_zones prefers the boarded derelict loader's layout-declared
## fire zone markers/specs for the first N burning compartments, falling back
## to the distributed positions beyond them. Procgen derelicts declare no
## fire_zones today, so this smoke boards a real derelict and then declares a
## sentinel marker on its loader (the loader arrays are the production seam
## the goldens populate via _add_fire_zone_markers).
##
## Pass marker: DERELICT FIRE ZONE MARKER PASS boarded=true marker_position_used=true spec_meta=true fallback_intact=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 300
const SENTINEL: Vector3 = Vector3(123.0, 4.0, -77.0)

var main_node: Node
var playable: PlayableGeneratedShip
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
	if not is_instance_valid(playable):
		playable = _find_playable(main_node)
	if not is_instance_valid(playable) or not is_instance_valid(playable.loader) \
			or not playable.loader.has_loaded_ship() or not playable.playable_started:
		if frame_count > TIMEOUT_FRAMES:
			_fail("playable not ready after %d frames" % frame_count)
		return
	_validate()

func _all_operational(mgr) -> void:
	for sid in ["power", "navigation", "scanners", "propulsion"]:
		var sys = mgr.get_system(sid)
		if sys == null:
			continue
		for sub in sys.subcomponents:
			mgr.force_repair(sid, sub.subcomponent_id)

func _validate() -> void:
	finished = true
	_all_operational(playable.get_ship_systems_manager())

	# --- Board a derelict via the real travel path ---
	var world = playable.get_synaptic_sea_world()
	var in_range: Array = world.markers_in_range(playable.scanner_state.range_radius)
	if in_range.is_empty():
		_fail("no markers in range")
		return
	var boarded: bool = false
	for m in in_range.slice(0, 4):
		if bool(playable.travel_to_marker_id(String(m.marker_id)).get("success", false)):
			boarded = true
			break
	if not boarded:
		_fail("travel_to_marker_id failed for the first 4 markers")
		return
	if not playable.away_from_start:
		_fail("travel succeeded but away_from_start is false")
		return
	var derelict_root: Node = playable.get_current_ship().scene_root
	if derelict_root == null or not derelict_root.has_method("get_fire_zone_markers"):
		_fail("derelict scene_root is not a GeneratedShipLoader")
		return

	# --- Declare a layout fire zone on the derelict's loader (the arrays the
	# goldens populate through _add_fire_zone_markers) and ignite a fire ---
	var declared_markers: Array[Vector3] = [SENTINEL]
	derelict_root.fire_zone_markers = declared_markers
	derelict_root.fire_zone_specs = [{
		"zone_id": "declared_test_fire", "kind": "timed_fire",
		"from_room": "room_a", "to_room": "room_b",
	}]
	var fs = playable.get_current_ship().get_fire()
	if fs == null:
		_fail("derelict has no fire state")
		return
	fs.ignite("cargo_hold", 1.0)
	playable._build_fire_zones()

	if playable.fire_zone_nodes.is_empty():
		_fail("no fire zone nodes built for a burning derelict compartment")
		return
	var marker_used: bool = false
	var spec_meta: bool = false
	for cid in playable.fire_zone_nodes:
		var zone = playable.fire_zone_nodes[cid]
		if zone is Node3D and (zone as Node3D).position.distance_to(SENTINEL) < 0.01:
			marker_used = true
			if str(zone.get_meta("fire_zone_layout_id", "")) == "declared_test_fire":
				spec_meta = true
			break
	if not marker_used:
		_fail("layout-declared fire marker ignored — no fire zone node at the declared position (loader getters dead)")
		return
	if not spec_meta:
		_fail("fire zone node at the declared position carries no layout spec metadata (get_fire_zone_specs dead)")
		return

	# --- Fallback: with no declared markers the distributed positions still
	# place every burning compartment's zone (the pre-existing behavior) ---
	var no_markers: Array[Vector3] = []
	derelict_root.fire_zone_markers = no_markers
	derelict_root.fire_zone_specs = []
	playable._build_fire_zones()
	if playable.fire_zone_nodes.is_empty():
		_fail("distributed-position fallback broken: no zones without declared markers")
		return
	for cid in playable.fire_zone_nodes:
		var zone = playable.fire_zone_nodes[cid]
		if zone is Node3D and (zone as Node3D).position.distance_to(SENTINEL) < 0.01:
			_fail("stale declared position used after markers were cleared")
			return

	print("DERELICT FIRE ZONE MARKER PASS boarded=true marker_position_used=true spec_meta=true fallback_intact=true")
	_cleanup(0)

func _find_playable(node: Node) -> PlayableGeneratedShip:
	if node is PlayableGeneratedShip:
		return node as PlayableGeneratedShip
	for child in node.get_children():
		var found: PlayableGeneratedShip = _find_playable(child)
		if found != null:
			return found
	return null

func _fail(reason: String) -> void:
	push_error("DERELICT FIRE ZONE MARKER FAIL reason=%s" % reason)
	finished = true
	_cleanup(1)

func _cleanup(code: int) -> void:
	if is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
