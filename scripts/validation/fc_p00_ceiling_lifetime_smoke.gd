extends SceneTree

## P00 regression for reload teardown order. The fade controller can outlive
## its current player/layout for a frame while save/load replaces scene nodes.
## It must never dereference the freed target, and configure() must make the
## replacement player drive fades again.
##
## Pass marker: FC P00 CEILING LIFETIME PASS freed_safe=true rebound=true

const CeilingFadeControllerScript := preload("res://scripts/procgen/ceiling_fade_controller.gd")

var world: Node3D
var loader_root: Node3D
var ceiling: Node3D
var controller: CeilingFadeController
var phase: int = 0


func _initialize() -> void:
	world = Node3D.new()
	get_root().add_child(world)
	loader_root = Node3D.new()
	world.add_child(loader_root)
	ceiling = Node3D.new()
	ceiling.name = "Ceiling_LifetimeProbe"
	loader_root.add_child(ceiling)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	mesh.material_override = material
	ceiling.add_child(mesh)
	controller = CeilingFadeControllerScript.new()
	world.add_child(controller)
	var original_player := Node3D.new()
	original_player.position = Vector3(100.0, 0.0, 0.0)
	world.add_child(original_player)
	controller.configure(loader_root, original_player)
	process_frame.connect(_on_process_frame)


func _on_process_frame() -> void:
	match phase:
		0:
			# process_frame is emitted before ordinary Node _process callbacks.
			# Let the controller receive one full frame with its far player.
			phase = 1
		1:
			if not _alpha_matches(controller.fade_alpha):
				_fail("far live player did not fade ceiling")
				return
			var old_player := controller._player
			old_player.queue_free()
			phase = 2
		2:
			# Reaching this frame without an ERROR proves the controller did not
			# access old_player.global_position after queue_free completed.
			if controller._player != null:
				_fail("freed player reference was not cleared")
				return
			var replacement := Node3D.new()
			replacement.position = Vector3.ZERO
			world.add_child(replacement)
			controller.configure(loader_root, replacement)
			phase = 3
		3:
			if not _alpha_matches(1.0):
				_fail("replacement player did not restore near ceiling opacity")
				return
			print("FC P00 CEILING LIFETIME PASS freed_safe=true rebound=true")
			_cleanup_and_quit(0)


func _alpha_matches(expected: float) -> bool:
	var mesh := ceiling.get_child(0) as MeshInstance3D
	var material := mesh.get_surface_override_material(0) as StandardMaterial3D
	return material != null and is_equal_approx(material.albedo_color.a, expected)


func _fail(reason: String) -> void:
	push_error("FC P00 CEILING LIFETIME FAIL reason=%s" % reason)
	_cleanup_and_quit(1)


func _cleanup_and_quit(code: int) -> void:
	if world != null and is_instance_valid(world):
		world.queue_free()
	quit(code)
