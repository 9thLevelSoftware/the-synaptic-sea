extends SceneTree

const Factory = preload("res://scripts/placement/gameplay_prop_factory.gd")
const SOURCE = "res://assets/imported/props/dressing/generic_crate.glb"

func _initialize() -> void:
	call_deferred("_run")

func _require(ok: bool, message: String) -> bool:
	if not ok:
		push_error("GAMEPLAY PROP IMPORTED VISUAL FAIL " + message)
		quit(1)
	return ok

func _run() -> void:
	if not _require(ResourceLoader.exists(SOURCE), "fixture GLB missing"):
		return
	Factory._catalog_path = Factory.DEFAULT_KIT_PATH
	Factory._catalog = {"props": {"import_probe": {
		"mesh_path": SOURCE, "scale": 2.0, "y_offset": 0.0
	}}}
	var prop: Node3D = Factory.build("import_probe")
	root.add_child(prop)
	var anchor := prop.get_node_or_null("Mesh") as MeshInstance3D
	if not _require(anchor != null, "legacy Mesh anchor missing"):
		return
	if not _require(anchor.mesh == null, "placeholder drawn beside imported model"):
		return
	var imported := anchor.get_node_or_null("CatalogMesh") as Node3D
	if not _require(imported != null, "imported model must inherit marker visibility"):
		return
	if not _require(anchor.scale == Vector3.ONE * 2.0, "catalog scale missing"):
		return
	if not _require(imported.scale == Vector3.ONE, "catalog scale applied twice"):
		return
	anchor.hide()
	if not _require(not imported.is_visible_in_tree(), "hidden owner leaves imported model visible"):
		return
	anchor.show()
	if not _require(imported.is_visible_in_tree(), "show does not restore imported model"):
		return
	prop.free()
	Factory._catalog_path = ""
	Factory._catalog = {}
	var fallback: Node3D = Factory.build("corpse_bag")
	root.add_child(fallback)
	var fallback_mesh := fallback.get_node_or_null("Mesh") as MeshInstance3D
	if not _require(fallback_mesh != null and fallback_mesh.mesh != null, "primitive fallback broken"):
		return
	fallback.free()
	print("GAMEPLAY PROP IMPORTED VISUAL PASS placeholder=false visibility_inherited=true scale_once=true fallback=true")
	quit(0)
