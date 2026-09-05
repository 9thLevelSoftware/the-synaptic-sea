extends SceneTree

const ShipGeneratorScript := preload("res://scripts/procgen/ship_generator.gd")
const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")
const MAX_SEED: int = 24


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _verify_blueprint_generation_context_round_trip():
		return
	if not ClassDB.class_exists("DerelictGenerator"):
		_fail("native DerelictGenerator class unavailable")
		return
	var selected_seed: int = -1
	var first_specs: Array = []
	var first_scene: Node3D = null
	for seed_value in range(1, MAX_SEED + 1):
		var generator: RefCounted = ShipGeneratorScript.new()
		var scene: Node3D = generator.generate_from_seed(seed_value, 0, 1)
		if scene == null:
			_fail("native scene generation returned null for seed %d" % seed_value)
			return
		var specs: Array = _arc_specs(scene)
		if specs.is_empty():
			scene.free()
			continue
		selected_seed = seed_value
		first_specs = specs.duplicate(true)
		first_scene = scene
		break
	if selected_seed < 0 or first_scene == null:
		_fail("no native seed 1..%d exposed builder arc zones" % MAX_SEED)
		return
	if not first_scene.has_method("get_arc_zone_markers") or (first_scene.get_arc_zone_markers() as Array).is_empty():
		first_scene.free()
		_fail("native layout arc descriptor did not create a scene marker position")
		return
	var repeat_generator: RefCounted = ShipGeneratorScript.new()
	var repeated_scene: Node3D = repeat_generator.generate_from_seed(selected_seed, 0, 1)
	if repeated_scene == null:
		first_scene.free()
		_fail("repeat native generation returned null")
		return
	var repeated_specs: Array = _arc_specs(repeated_scene)
	var deterministic: bool = JSON.stringify(first_specs) == JSON.stringify(repeated_specs)
	repeated_scene.free()
	first_scene.free()
	if not deterministic:
		_fail("same native seed produced different arc descriptors")
		return
	print("FC P00 NATIVE ARC PASS native_selected=true seed=%d deterministic=true scene_markers=true" % selected_seed)
	quit(0)


func _verify_blueprint_generation_context_round_trip() -> bool:
	var original = ShipBlueprintScript.new(1, 2, 341)
	var expected: Dictionary = {"biome": "abyssal_synaptic_sea", "difficulty": "hardened"}
	if not original.set_generation_context_v1(expected):
		_fail("blueprint rejected valid generation_context_v1")
		return false
	var restored = ShipBlueprintScript.from_dict(original.to_dict())
	if not restored.has_generation_context_v1() or not restored.is_generation_context_v1_valid() \
			or JSON.stringify(restored.generation_context_v1) != JSON.stringify(expected):
		_fail("blueprint generation_context_v1 did not round-trip")
		return false
	if int(restored.seed_value) != 341 or int(restored.size) != 1 or int(restored.condition) != 2 \
			or restored.room_count_range != Vector2i(4, 8):
		_fail("blueprint context round-trip changed generation inputs")
		return false
	var legacy = ShipBlueprintScript.from_dict({"size": 1, "condition": 2, "seed_value": 341})
	if legacy.has_generation_context_v1():
		_fail("legacy blueprint was not recognized as context-free")
		return false
	var malformed = ShipBlueprintScript.from_dict({"generation_context_v1": {"biome": "abyssal_synaptic_sea"}})
	var malformed_round_trip = ShipBlueprintScript.from_dict(malformed.to_dict())
	if not malformed.has_generation_context_v1() or malformed.is_generation_context_v1_valid() \
			or not malformed_round_trip.has_generation_context_v1() or malformed_round_trip.is_generation_context_v1_valid():
		_fail("malformed generation_context_v1 silently became legacy after round-trip")
		return false
	var unsupported = ShipBlueprintScript.from_dict({"generation_context_v2": {"biome": "x", "difficulty": "y"}})
	var unsupported_round_trip = ShipBlueprintScript.from_dict(unsupported.to_dict())
	if not unsupported.has_generation_context_v1() or unsupported.is_generation_context_v1_valid() \
			or not unsupported_round_trip.has_generation_context_v1() or unsupported_round_trip.is_generation_context_v1_valid():
		_fail("unsupported generation context silently became legacy after round-trip")
		return false
	var ambiguous = ShipBlueprintScript.from_dict({"generation_context_v1": expected, "generation_context_v2": {}})
	if ambiguous.is_generation_context_v1_valid():
		_fail("ambiguous v1 plus future generation context was accepted")
		return false
	if not original.set_generation_context_v1({"biome": ""}):
		if not original.is_generation_context_v1_valid() or JSON.stringify(original.generation_context_v1) != JSON.stringify(expected):
			_fail("failed context setter erased a prior valid context")
			return false
	else:
		_fail("invalid context setter unexpectedly succeeded")
		return false
	return true


func _arc_specs(scene: Node3D) -> Array:
	if scene.has_method("get_arc_zone_specs"):
		var specs: Variant = scene.get_arc_zone_specs()
		if specs is Array:
			return (specs as Array).duplicate(true)
	return []


func _fail(reason: String) -> void:
	push_error("FC P00 NATIVE ARC FAIL reason=%s" % reason)
	quit(1)
