extends SceneTree

## V3: production travel path generates a derelict with layout, nav graph, encounters.
## Marker: MAIN PLAYABLE DERELICT PIPELINE CONTRACT PASS layout=true nav=true biome=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 400

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
	if playable == null:
		playable = _find_playable(main_node)
	if playable == null or playable.loader == null or not playable.loader.has_loaded_ship() \
			or not playable.playable_started:
		if frame_count > TIMEOUT_FRAMES:
			_fail("playable not ready")
		return
	_validate()

func _validate() -> void:
	finished = true
	if playable.ship_generator == null:
		_fail("ship_generator missing")
		return
	# Mirror production run-context resolution for a mid-size wrecked marker seed.
	var ctx: Dictionary = playable._resolve_run_context(4242, 1, 2)
	var biome: String = str(ctx.get("biome", "abyssal_synaptic_sea"))
	var diff: String = str(ctx.get("difficulty", "standard"))
	playable.ship_generator.configure_run_context(biome, diff)
	var ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")
	var bp = ShipBlueprintScript.new(1, 2, 4242)
	var root: Node3D = playable.ship_generator.generate(bp, {})
	if root == null:
		_fail("generate returned null")
		return
	# Read layout via temp file the generator wrote, or from loader on root.
	var layout_path: String = "user://procgen_temp/layout.json"
	var layout: Dictionary = {}
	if FileAccess.file_exists(layout_path):
		var f := FileAccess.open(layout_path, FileAccess.READ)
		if f != null:
			var p: Variant = JSON.parse_string(f.get_as_text())
			f.close()
			if p is Dictionary:
				layout = p
	if layout.is_empty():
		_fail("temp layout empty after generate")
		return
	var stamped_biome: String = str(layout.get("biome_id", ""))
	if biome.is_empty():
		pass
	elif stamped_biome.is_empty():
		_fail("biome_id not stamped (expected %s)" % biome)
		return
	elif stamped_biome != biome:
		_fail("biome_id mismatch stamped=%s expected=%s" % [stamped_biome, biome])
		return
	var rooms: Array = layout.get("rooms", []) as Array
	if rooms.size() < 3:
		_fail("too few rooms %d" % rooms.size())
		return
	var ShipNavGraphScript := preload("res://scripts/systems/ship_nav_graph.gd")
	var graph = ShipNavGraphScript.new()
	var n: int = graph.build_from_layout(layout)
	if n < 4:
		_fail("nav nodes %d" % n)
		return
	var enc: Array = layout.get("encounters", []) as Array
	# With density > 0 some seeds may still roll zero encounters; require
	# encounters array present + well-formed when non-empty.
	if not layout.has("encounters"):
		_fail("encounters key missing")
		return
	for e in enc:
		if not (e is Dictionary) or str((e as Dictionary).get("room_id", "")).is_empty():
			_fail("malformed encounter entry")
			return
	if str(layout.get("hazard_source", "")) != "runtime":
		_fail("hazard_source not runtime")
		return
	if str(layout.get("kit_id", "")).is_empty():
		_fail("kit_id missing")
		return
	# Extended templates eligible whenever difficulty is set.
	if playable.ship_generator._extended_for(diff) != true:
		_fail("extended templates should unlock for difficulty=%s" % diff)
		return
	root.queue_free()
	print("MAIN PLAYABLE DERELICT PIPELINE CONTRACT PASS layout=true nav=true biome=true rooms=%d nodes=%d enc=%d" % [
		rooms.size(), n, enc.size()])
	_cleanup(0)

func _find_playable(node: Node) -> PlayableGeneratedShip:
	if node is PlayableGeneratedShip:
		return node as PlayableGeneratedShip
	for c in node.get_children():
		var f := _find_playable(c)
		if f != null:
			return f
	return null

func _fail(reason: String) -> void:
	push_error("MAIN PLAYABLE DERELICT PIPELINE CONTRACT FAIL reason=%s" % reason)
	finished = true
	_cleanup(1)

func _cleanup(code: int) -> void:
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
