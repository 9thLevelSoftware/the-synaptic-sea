extends SceneTree

## Marker: THREAT PLACEHOLDER RENDERER PASS swarm=true anchored=true default=true color=true

const Renderer := preload("res://scripts/tools/threat_placeholder_renderer.gd")

func _initialize() -> void:
	var swarm := Renderer.build_placeholder("biomatter_swarm", ["swarm"], Vector3(1, 2, 3))
	var anchored := Renderer.build_placeholder("hull_tendril", ["anchored"], Vector3.ZERO)
	var basic := Renderer.build_placeholder("stalker", [], Vector3.ZERO)
	var swarm_ok := swarm is Node3D and swarm.get_child_count() == 1 and (swarm.get_child(0) as MeshInstance3D).mesh is SphereMesh and swarm.position == Vector3(1, 2, 3)
	var anchored_ok := (anchored.get_child(0) as MeshInstance3D).mesh is CylinderMesh
	var default_ok := (basic.get_child(0) as MeshInstance3D).mesh is CapsuleMesh
	var color_ok := Renderer.color_for_archetype("biomatter_swarm") == Color(0.55, 1.0, 0.45) and Renderer.color_for_archetype("unknown_xyz") == Color(1.0, 0.35, 0.35)
	swarm.free(); anchored.free(); basic.free()
	if swarm_ok and anchored_ok and default_ok and color_ok:
		print("THREAT PLACEHOLDER RENDERER PASS swarm=true anchored=true default=true color=true")
		quit(0)
	else:
		push_error("THREAT PLACEHOLDER RENDERER FAIL swarm=%s anchored=%s default=%s color=%s" % [swarm_ok, anchored_ok, default_ok, color_ok])
		quit(1)
