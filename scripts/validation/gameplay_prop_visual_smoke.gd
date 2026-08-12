extends SceneTree

## Marker: GAMEPLAY PROP VISUAL PASS

const CATALOG_PATH: String = "res://data/kits/gameplay_prop_v0.json"
const GameplayPropFactoryScript: GDScript = preload("res://scripts/placement/gameplay_prop_factory.gd")
const PROP_IDS: Array[String] = [
	"loot_crate",
	"extinguisher_station",
	"breach_patch_panel",
	"hatch_wheel",
	"workbench",
	"corpse_bag",
	"tool_case",
]

func _initialize() -> void:
	var catalog: Dictionary = _load_catalog()
	if catalog.get("version", "") != "gameplay-prop-v0":
		_fail("version=%s" % str(catalog.get("version", "")))
		return
	var props: Dictionary = catalog.get("props", {}) as Dictionary
	var nodes: Array[Node3D] = []
	var signatures: Array[String] = []
	for prop_id in PROP_IDS:
		if not props.has(prop_id):
			_fail("missing=%s" % prop_id)
			_free_nodes(nodes)
			return
		var node: Node3D = GameplayPropFactoryScript.build(prop_id, Vector3.ZERO)
		nodes.append(node)
		var mesh_instance: MeshInstance3D = node.get_node_or_null("Mesh") as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			_fail("missing MeshInstance3D prop=%s" % prop_id)
			_free_nodes(nodes)
			return
		var material: StandardMaterial3D = mesh_instance.material_override as StandardMaterial3D
		if material == null:
			_fail("missing material prop=%s" % prop_id)
			_free_nodes(nodes)
			return
		signatures.append("%s|%s" % [mesh_instance.mesh.get_class(), str(material.albedo_color)])

	var unique_signatures: Dictionary = {}
	for signature in signatures:
		unique_signatures[signature] = true
	var distinct: bool = unique_signatures.size() > 1
	_free_nodes(nodes)
	if not distinct:
		_fail("all props share mesh class and color")
		return
	print("GAMEPLAY PROP VISUAL PASS")
	quit(0)

func _load_catalog() -> Dictionary:
	if not FileAccess.file_exists(CATALOG_PATH):
		_fail("catalog missing")
		return {}
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	if file == null:
		_fail("catalog unreadable")
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		_fail("catalog JSON is not an object")
		return {}
	return parsed as Dictionary

func _free_nodes(nodes: Array[Node3D]) -> void:
	for node in nodes:
		if is_instance_valid(node):
			node.free()

func _fail(reason: String) -> void:
	print("GAMEPLAY PROP VISUAL FAIL reason=%s" % reason)
	quit(1)
