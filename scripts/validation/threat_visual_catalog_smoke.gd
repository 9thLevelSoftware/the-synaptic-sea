extends SceneTree

const CATALOG_PATH: String = "res://data/combat/threat_visual_catalog.json"
const Renderer: GDScript = preload("res://scripts/tools/threat_placeholder_renderer.gd")

func _initialize() -> void:
	var catalog: Dictionary = _load_catalog()
	if catalog.get("version", "") != "threat-visual-1":
		_fail("version=%s" % str(catalog.get("version", "")))
		return
	var archetypes: Dictionary = catalog.get("archetypes", {}) as Dictionary
	for required_id in ["biomatter_swarm", "stalker", "hull_tendril"]:
		if not archetypes.has(required_id):
			_fail("missing=%s" % required_id)
			return

	var nodes: Array[Node3D] = []
	var meshes: Array[Mesh] = []
	var colors: Array[Color] = []
	for archetype_id in ["biomatter_swarm", "stalker", "hull_tendril"]:
		var node: Node3D = Renderer.build_placeholder(archetype_id, [], Vector3.ZERO)
		nodes.append(node)
		if node.get_child_count() == 0 or not (node.get_child(0) is MeshInstance3D):
			_fail("missing MeshInstance3D archetype=%s" % archetype_id)
			_free_nodes(nodes)
			return
		var mesh_instance := node.get_child(0) as MeshInstance3D
		if mesh_instance.mesh == null:
			_fail("missing mesh archetype=%s" % archetype_id)
			_free_nodes(nodes)
			return
		meshes.append(mesh_instance.mesh)
		colors.append((mesh_instance.material_override as StandardMaterial3D).albedo_color)

	var mesh_types_distinct: bool = meshes[0].get_class() != meshes[1].get_class() and meshes[1].get_class() != meshes[2].get_class() and meshes[0].get_class() != meshes[2].get_class()
	var colors_distinct: bool = colors[0] != colors[1] and colors[1] != colors[2] and colors[0] != colors[2]
	_free_nodes(nodes)
	if not mesh_types_distinct and not colors_distinct:
		_fail("slice visuals are indistinguishable")
		return
	print("THREAT VISUAL CATALOG PASS")
	quit(0)

func _load_catalog() -> Dictionary:
	if not FileAccess.file_exists(CATALOG_PATH):
		_fail("catalog missing")
		return {}
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	if file == null:
		_fail("catalog unreadable")
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		_fail("catalog JSON is not an object")
		return {}
	return parsed as Dictionary

func _free_nodes(nodes: Array[Node3D]) -> void:
	for node in nodes:
		if is_instance_valid(node):
			node.free()

func _fail(reason: String) -> void:
	print("THREAT VISUAL CATALOG FAIL reason=%s" % reason)
	quit(1)
