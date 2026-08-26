extends Node
class_name CeilingFadeController

## Zomboid-style ceiling fade: ceilings near the player remain visible for
## sight-blocking; distant ceilings fade (alpha) for isometric readability.
##
## Expects the GeneratedShipLoader output structure: ceiling wrappers have
## names prefixed with "Ceiling_" and are children of the loader root.

@export var fade_radius_m: float = 12.0
@export var fade_alpha: float = 0.15

var _ceilings: Array[Node3D] = []
var _player: Node3D
var _material_cache: Dictionary = {}


func configure(loader_root: Node, player: Node3D) -> void:
	_ceilings.clear()
	_material_cache.clear()
	_collect(loader_root)
	_player = player


func _collect(node: Node) -> void:
	if node is Node3D and (node as Node3D).name.begins_with("Ceiling_"):
		_ceilings.append(node)
	for child in node.get_children():
		_collect(child)


func _process(_delta: float) -> void:
	if _player == null:
		return
	var pp: Vector3 = _player.global_position
	for c in _ceilings:
		var d: float = c.global_position.distance_to(pp)
		var near: bool = d <= fade_radius_m
		c.visible = true
		_apply_alpha(c, 1.0 if near else fade_alpha)


func _apply_alpha(node: Node3D, alpha: float) -> void:
	var key: String = node.get_path()
	var cached = _material_cache.get(key, null)
	if cached == null:
		for child in node.get_children():
			if child is MeshInstance3D:
				var mesh_instance: MeshInstance3D = child
				var mat: Material = mesh_instance.get_active_material(0)
				if mat is StandardMaterial3D:
					var duped: StandardMaterial3D = (mat as StandardMaterial3D).duplicate()
					duped.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					var col: Color = duped.albedo_color
					col.a = alpha
					duped.albedo_color = col
					mesh_instance.set_surface_override_material(0, duped)
		_material_cache[key] = true
	else:
		for child in node.get_children():
			if child is MeshInstance3D:
				var mesh_instance: MeshInstance3D = child
				var mat: Material = mesh_instance.get_active_material(0)
				if mat is StandardMaterial3D:
					var col: Color = (mat as StandardMaterial3D).albedo_color
					col.a = alpha
					(mat as StandardMaterial3D).albedo_color = col