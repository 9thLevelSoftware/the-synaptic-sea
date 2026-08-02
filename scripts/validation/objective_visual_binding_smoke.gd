extends SceneTree

const PLAYABLE_SCENE: PackedScene = preload("res://scenes/procgen/playable_coherent_ship.tscn")
const PlayableGeneratedShipScript: GDScript = preload("res://scripts/procgen/playable_generated_ship.gd")

const COHERENT_003_LAYOUT: String = "res://data/procgen/golden/coherent_ship_003/layout.json"
const COHERENT_003_GAMEPLAY: String = "res://data/procgen/golden/coherent_ship_003/gameplay_slice.json"
const COHERENT_002_LAYOUT: String = "res://data/procgen/golden/coherent_ship_002/layout.json"
const COHERENT_002_GAMEPLAY: String = "res://data/procgen/golden/coherent_ship_002/gameplay_slice.json"
const KIT_PATH: String = "res://data/kits/ship_structural_v0.json"

const EXPECTED_PLACEMENT_IDS: Array[String] = [
	"cargo_supply_cache",
	"maintenance_breaker_panel",
	"medbay_terminal",
	"reactor_control_panel",
]

var first_ship: Node
var second_ship: Node
var fallback_ship: Node
var phase: int = 0
var frame_count: int = 0
var finished: bool = false


func _initialize() -> void:
	_start_first_ship()
	process_frame.connect(_on_process_frame)


func _on_process_frame() -> void:
	if finished:
		return
	frame_count += 1
	match phase:
		0:
			if _ship_ready(first_ship):
				_validate_coherent_001(first_ship)
				if finished:
					return
				phase = 1
				frame_count = 0
			elif frame_count > 600:
				_fail("coherent_ship_001 did not become ready")
		1:
			if first_ship != null and is_instance_valid(first_ship):
				first_ship.queue_free()
			first_ship = null
			phase = 2
			frame_count = 0
		2:
			_start_second_ship()
			phase = 3
			frame_count = 0
		3:
			if _ship_ready(second_ship):
				_validate_coherent_003(second_ship)
				if finished:
					return
				phase = 4
				frame_count = 0
			elif frame_count > 600:
				_fail("coherent_ship_003 did not become ready")
		4:
			if second_ship != null and is_instance_valid(second_ship):
				second_ship.queue_free()
			second_ship = null
			phase = 5
			frame_count = 0
		5:
			_start_fallback_ship()
			phase = 6
			frame_count = 0
		6:
			if _ship_ready(fallback_ship):
				_validate_coherent_002_fallback(fallback_ship)
				if finished:
					return
				finished = true
				print("OBJECTIVE VISUAL BINDING PASS coherent001=true coherent003=true imported=4 interactions=5 bridge_fallback=true fallback=true")
				_cleanup_and_quit(0)
			elif frame_count > 600:
				_fail("coherent_ship_002 did not become ready")


func _start_first_ship() -> void:
	first_ship = PLAYABLE_SCENE.instantiate() as Node
	if first_ship == null:
		_fail("could not instantiate coherent_ship_001 playable scene")
		return
	get_root().add_child(first_ship)


func _start_second_ship() -> void:
	second_ship = PlayableGeneratedShipScript.new() as Node
	if second_ship == null:
		_fail("could not instantiate direct playable ship")
		return
	second_ship.set("layout_path", COHERENT_003_LAYOUT)
	second_ship.set("kit_path", KIT_PATH)
	second_ship.set("gameplay_slice_path", COHERENT_003_GAMEPLAY)
	get_root().add_child(second_ship)


func _start_fallback_ship() -> void:
	fallback_ship = PlayableGeneratedShipScript.new() as Node
	if fallback_ship == null:
		_fail("could not instantiate coherent_ship_002 fallback playable ship")
		return
	fallback_ship.set("layout_path", COHERENT_002_LAYOUT)
	fallback_ship.set("kit_path", KIT_PATH)
	fallback_ship.set("gameplay_slice_path", COHERENT_002_GAMEPLAY)
	get_root().add_child(fallback_ship)


func _ship_ready(ship: Node) -> bool:
	if ship == null or not is_instance_valid(ship):
		return false
	var loader: Variant = ship.get("loader")
	return bool(ship.get("playable_started")) \
		and loader != null \
		and loader.has_method("has_loaded_ship") \
		and bool(loader.has_loaded_ship())


func _validate_coherent_001(ship: Node) -> void:
	var loader: Node = ship.get("loader") as Node
	var interactables: Array = ship.get("interactables") as Array
	_assert(interactables.size() == 5, "coherent_ship_001 retains five interactables")
	var placement_ids: Dictionary = {}
	for interactable_variant in interactables:
		var interactable: Node = interactable_variant as Node
		_assert(interactable != null and interactable is Area3D, "interactable remains an Area3D")
		var placement_id: String = str(interactable.get_meta("placement_id", ""))
		if not placement_id.is_empty():
			placement_ids[placement_id] = true
		var collision: CollisionShape3D = interactable.get_node_or_null("InteractionCollisionShape3D") as CollisionShape3D
		_assert(collision != null and collision.shape is SphereShape3D, "interaction volume remains a sphere")
	for expected_id in EXPECTED_PLACEMENT_IDS:
		_assert(placement_ids.has(expected_id), "%s placement ID retained" % expected_id)

	var affordance_root: Node = ship.get("affordance_root") as Node
	_assert(affordance_root != null, "affordance root exists")
	var imported_visual_count: int = 0
	for child_variant in affordance_root.get_children():
		var child: Node = child_variant as Node
		if str(child.get_meta("visual_source", "")) == "imported":
			imported_visual_count += 1
			_assert(child.get_parent() == affordance_root, "imported objective visual is under affordance root")
	_assert(imported_visual_count == 4, "four physical imported objective visuals")

	var objective_root: Node = loader.get("objective_root") as Node
	var volumes: Array = loader.get("objective_volumes") as Array
	_assert(objective_root != null and volumes.size() == 4, "four gameplay objective volumes remain")
	for volume_variant in volumes:
		var volume: Node = volume_variant as Node
		_assert(volume != null and volume.get_parent() == objective_root, "objective volume remains under ObjectiveRoot")
		_assert(volume is Area3D, "objective volume remains an Area3D")
	for child_variant in objective_root.get_children():
		var child: Node = child_variant as Node
		_assert(str(child.get_meta("visual_source", "")) != "imported", "ObjectiveRoot has no imported visual")


func _validate_coherent_003(ship: Node) -> void:
	var interactables: Array = ship.get("interactables") as Array
	_assert(interactables.size() == 6, "coherent_ship_003 retains both repair steps")
	var source_by_placement: Dictionary = {}
	var affordance_root: Node = ship.get("affordance_root") as Node
	_assert(affordance_root != null, "coherent_ship_003 affordance root exists")
	for child_variant in affordance_root.get_children():
		var child: Node = child_variant as Node
		var placement_id: String = str(child.get_meta("placement_id", ""))
		if not placement_id.is_empty():
			source_by_placement[placement_id] = str(child.get_meta("visual_source", ""))
	_assert(source_by_placement.get("life_support_console", "") == "fallback", "unsupported life-support placement uses procedural fallback")
	_assert(source_by_placement.get("reactor_control_panel", "") == "imported", "supported reactor placement uses imported visual")
	_assert(source_by_placement.get("maintenance_breaker_panel", "") == "imported", "supported repair placement uses imported visual")
	_assert(source_by_placement.get("medbay_terminal", "") == "imported", "supported medbay placement uses imported visual")
	_assert(source_by_placement.get("supply_cache", "") == "imported", "supported supply placement uses imported visual")


func _validate_coherent_002_fallback(ship: Node) -> void:
	var affordance_root: Node = ship.get("affordance_root") as Node
	_assert(affordance_root != null, "coherent_ship_002 affordance root exists")
	for child_variant in affordance_root.get_children():
		var child: Node = child_variant as Node
		if str(child.get_meta("placement_id", "")) == "bridge_power_distribution":
			_assert(str(child.get_meta("visual_source", "")) == "fallback", "unsupported bridge placement uses procedural fallback")
			return
	_fail("coherent_ship_002 bridge placement visual was not rendered")


func _assert(condition: bool, reason: String) -> void:
	if condition:
		return
	_fail(reason)


func _fail(reason: String) -> void:
	if finished:
		return
	finished = true
	push_error("OBJECTIVE VISUAL BINDING FAIL reason=%s" % reason)
	_cleanup_and_quit(1)


func _cleanup_and_quit(code: int) -> void:
	if first_ship != null and is_instance_valid(first_ship):
		first_ship.queue_free()
	if second_ship != null and is_instance_valid(second_ship):
		second_ship.queue_free()
	if fallback_ship != null and is_instance_valid(fallback_ship):
		fallback_ship.queue_free()
	quit(code)
