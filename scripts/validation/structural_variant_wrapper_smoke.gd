extends SceneTree

const IntegrityVisualResolverScript: GDScript = preload("res://scripts/systems/integrity_visual_resolver.gd")
const VARIANT_WRAPPER_PATHS: PackedStringArray = [
	"res://scenes/wrappers/structural/ship_structural_v0/corridor_floor_1x1.tscn",
	"res://scenes/wrappers/structural/ship_structural_v0/corridor_floor_1x2.tscn",
	"res://scenes/wrappers/structural/ship_structural_v0/doorway_frame_open_1x1.tscn",
	"res://scenes/wrappers/structural/ship_structural_v0/floor_1x1.tscn",
	"res://scenes/wrappers/structural/ship_structural_v0/floor_2x1.tscn",
	"res://scenes/wrappers/structural/ship_structural_v0/pillar_support_1x1.tscn",
	"res://scenes/wrappers/structural/ship_structural_v0/ramp_up_1x2.tscn",
	"res://scenes/wrappers/structural/ship_structural_v0/wall_straight_1x1.tscn",
]

func _initialize() -> void:
	var failures: int = 0
	if not _expect(IntegrityVisualResolverScript != null, "resolver preload failed"):
		failures += 1
	var unique_paths: Dictionary = {}
	for scene_path in VARIANT_WRAPPER_PATHS:
		unique_paths[scene_path] = true
	if not _expect(
		VARIANT_WRAPPER_PATHS.size() == 8 and unique_paths.size() == 8,
		"expected exactly 8 unique variant wrapper paths",
	):
		failures += 1
	for scene_path in VARIANT_WRAPPER_PATHS:
		failures += _check_wrapper(scene_path)
	if failures != 0:
		push_error("STRUCTURAL VARIANT WRAPPER FAILURES: %d" % failures)
		quit(1)
		return
	print("STRUCTURAL VARIANT WRAPPER PASS wrappers=8 intact=true damaged=true breached=true")
	quit(0)


func _check_wrapper(scene_path: String) -> int:
	var failures: int = 0
	var packed_scene: PackedScene = load(scene_path) as PackedScene
	if not _expect(packed_scene != null, "%s did not load as PackedScene" % scene_path):
		return 1
	var instance: Node = packed_scene.instantiate()
	if not _expect(instance != null and instance is Node3D, "%s did not instantiate Node3D" % scene_path):
		if instance != null:
			instance.free()
		return 1
	var wrapper: Node3D = instance as Node3D
	get_root().add_child(wrapper)

	var visual_group: Node3D = wrapper.get_node_or_null("Visual") as Node3D
	if not _expect(visual_group != null, "%s missing Visual Node3D" % scene_path):
		_detach(wrapper)
		return 1
	var intact: Node3D = visual_group.get_node_or_null("VisualInstance_Intact") as Node3D
	var damaged: Node3D = visual_group.get_node_or_null("VisualInstance_Damaged") as Node3D
	var breached: Node3D = visual_group.get_node_or_null("VisualInstance_Breached") as Node3D
	if not _expect(intact != null, "%s missing intact Node3D" % scene_path):
		failures += 1
	if not _expect(damaged != null, "%s missing damaged Node3D" % scene_path):
		failures += 1
	if not _expect(breached != null, "%s missing breached Node3D" % scene_path):
		failures += 1
	if failures != 0:
		_detach(wrapper)
		return failures

	for state in ["intact", "damaged", "breached", "destroyed"]:
		var applied: bool = IntegrityVisualResolverScript.apply_visual_state(wrapper, state)
		if not _expect(applied, "%s resolver returned false for state=%s" % [scene_path, state]):
			failures += 1
		failures += _expect_state(scene_path, state, intact, damaged, breached)
	_detach(wrapper)
	return failures


func _expect_state(
	scene_path: String,
	state: String,
	intact: Node3D,
	damaged: Node3D,
	breached: Node3D,
) -> int:
	var expected_name: String = ""
	match state:
		"intact":
			expected_name = "VisualInstance_Intact"
		"damaged":
			expected_name = "VisualInstance_Damaged"
		"breached":
			expected_name = "VisualInstance_Breached"
		"destroyed":
			expected_name = ""
	var failures: int = 0
	for child in [intact, damaged, breached]:
		var should_be_visible: bool = state != "destroyed" and child.name == expected_name
		if not _expect(
			child.visible == should_be_visible,
			"%s state=%s visibility mismatch for %s" % [scene_path, state, child.name],
		):
			failures += 1
	return failures


func _detach(wrapper: Node3D) -> void:
	get_root().remove_child(wrapper)
	wrapper.free()


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("STRUCTURAL VARIANT WRAPPER FAILURE: %s" % message)
	return false
