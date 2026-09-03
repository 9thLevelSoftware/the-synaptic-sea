extends SceneTree

## Task 9 wrapper-authority smoke.
##
## This smoke keeps socket authority in the repository catalog and verifies
## that both primitive placeholders and PackedScene wrappers obey it. It also
## exercises the invalid seams that must fail closed before an assembly can be
## retained by a threat manager.

const ValidatorScript: GDScript = preload("res://scripts/systems/biomass_wrapper_validator.gd")
const FactoryScript: GDScript = preload("res://scripts/tools/biomass_placeholder_factory.gd")
const PartCatalogScript: GDScript = preload("res://scripts/systems/biomass_part_catalog.gd")
const RecipeLibraryScript: GDScript = preload("res://scripts/systems/biomass_recipe_library.gd")
const AssemblerScript: GDScript = preload("res://scripts/threats/biomass_assembler.gd")
const VisualScript: GDScript = preload("res://scripts/threats/biomass_threat_visual.gd")
const RecipeScript: GDScript = preload("res://scripts/systems/biomass_recipe.gd")

const PARTS_PATH: String = "res://data/combat/biomass_part_catalog.json"
const RECIPES_PATH: String = "res://data/combat/biomass_recipe_catalog.json"
const FIXTURE_TORSO: String = "res://tests/fixtures/biomass_valid_core_wrapper.tscn"
const FIXTURE_CLAW: String = "res://tests/fixtures/biomass_valid_nested_wrapper.tscn"
const PART_IDS: Array[String] = [
	"biomass_animal_skull_v1",
	"biomass_cephalopod_tentacle_v1",
	"biomass_claw_v1",
	"biomass_gunk_connector_v1",
	"biomass_human_arm_v1",
	"biomass_humanoid_torso_v1",
	"biomass_insect_leg_v1",
	"biomass_maw_v1",
]
const RECIPE_IDS: Array[String] = [
	"biped_puppet_v1",
	"four_legged_scrambler_v1",
	"intestinal_dragger_v1",
	"tendril_knot_v1",
	"tripod_hound_v1",
]

var _parts: Variant
var _library: Variant

func _initialize() -> void:
	_run()

func _run() -> void:
	_parts = PartCatalogScript.new()
	if not _need(_parts.load_path(PARTS_PATH), "part catalog did not load"):
		return
	_library = RecipeLibraryScript.new()
	if not _need(_library.load_path(RECIPES_PATH, _parts), "recipe library did not load"):
		return
	if not _need(_script_identity_checks(), "script identity checks failed"):
		return
	if not _need(_all_factory_parts_validate(), "factory socket validation failed"):
		return
	if not _need(_valid_wrapper_fixtures_validate(), "valid wrapper validation failed"):
		return
	if not _need(_invalid_part_probes(), "invalid wrapper probes failed"):
		return
	if not _need(_all_assemblies_validate(), "assembly validation failed"):
		return
	if not _need(_invalid_assembly_probe(), "invalid assembly probe failed"):
		return
	print("BIOMASS WRAPPER AUTHORITY PASS parts=8 recipes=5 glb_helpers=forbidden")
	quit(0)

func _script_identity_checks() -> bool:
	var visual: Variant = VisualScript.new()
	var recipe: Variant = _library.get_recipe("biped_puppet_v1")
	var diagnostics: PackedStringArray = ValidatorScript.validate_assembly(visual, recipe, _parts)
	visual.free()
	if not _need(not diagnostics.is_empty(), "unbuilt visual was accepted"):
		return false
	var sorted: PackedStringArray = diagnostics.duplicate()
	sorted.sort()
	return _need(diagnostics == sorted, "identity diagnostics were not sorted")

func _all_factory_parts_validate() -> bool:
	for part_id in PART_IDS:
		var entry: Dictionary = _parts.get_part(part_id)
		if not _need(not entry.is_empty(), "missing catalog part %s" % part_id):
			return false
		var root: Node3D = FactoryScript.build(part_id, entry)
		if not _need(root != null, "factory returned null for %s" % part_id):
			return false
		var diagnostics: PackedStringArray = ValidatorScript.validate_part(root, part_id, entry)
		if not _need(diagnostics.is_empty(), "factory diagnostics for %s: %s" % [part_id, diagnostics]):
			root.free()
			return false
		if not _need(_socket_count(root, entry) == (entry.get("sockets", []) as Array).size(), "socket count mismatch for %s" % part_id):
			root.free()
			return false
		root.free()
	return true

func _valid_wrapper_fixtures_validate() -> bool:
	var fixtures: Array = [
		[FIXTURE_TORSO, "biomass_humanoid_torso_v1"],
		[FIXTURE_CLAW, "biomass_claw_v1"],
	]
	for fixture_value in fixtures:
		var fixture: Array = fixture_value
		var resource: Resource = load(String(fixture[0]))
		if not _need(resource is PackedScene, "wrapper fixture did not load: %s" % fixture[0]):
			return false
		var root_value: Node = (resource as PackedScene).instantiate()
		if not _need(root_value is Node3D, "wrapper fixture root is not Node3D: %s" % fixture[0]):
			if root_value != null:
				root_value.free()
			return false
		var root: Node3D = root_value as Node3D
		var part_id: String = String(fixture[1])
		var diagnostics: PackedStringArray = ValidatorScript.validate_part(root, part_id, _parts.get_part(part_id))
		if not _need(diagnostics.is_empty(), "fixture diagnostics for %s: %s" % [part_id, diagnostics]):
			root.free()
			return false
		root.free()
	return true

func _invalid_part_probes() -> bool:
	var torso_id: String = "biomass_humanoid_torso_v1"
	var torso_entry: Dictionary = _parts.get_part(torso_id)
	var expected_sockets: Array = torso_entry.get("sockets", []) as Array
	if not _need(expected_sockets.size() >= 2, "torso fixture needs multiple sockets for probes"):
		return false
	var target_name: String = String((expected_sockets[0] as Dictionary).get("name", ""))
	var probes: Array[String] = [
		"missing",
		"extra",
		"duplicate",
		"wrong_type",
		"nonfinite",
		"scaled",
		"drift",
		"path_duplicate",
		"metadata",
		"socket_child",
	]
	for probe in probes:
		var root: Node3D = FactoryScript.build(torso_id, torso_entry)
		if not _need(root != null, "probe factory returned null: %s" % probe):
			return false
		if not _mutate_probe(root, probe, target_name):
			root.free()
			return false
		var first: PackedStringArray = ValidatorScript.validate_part(root, torso_id, torso_entry)
		var second: PackedStringArray = ValidatorScript.validate_part(root, torso_id, torso_entry)
		if not _need(not first.is_empty(), "invalid probe was accepted: %s diagnostics=%s nodes=%s" % [probe, first, _node_names(root)]):
			root.free()
			return false
		if not _need(first == second, "diagnostics changed between runs: %s" % probe):
			root.free()
			return false
		var sorted: PackedStringArray = first.duplicate()
		sorted.sort()
		if not _need(first == sorted, "diagnostics were not sorted: %s" % probe):
			root.free()
			return false
		root.free()
	# The explicit three-argument API must reject missing and mismatched identity
	# metadata rather than inferring a part ID from the root name.
	var missing_metadata: Node3D = FactoryScript.build(torso_id, torso_entry)
	missing_metadata.remove_meta("biomass_part_id")
	if not _need(not ValidatorScript.validate_part(missing_metadata, torso_id, torso_entry).is_empty(), "absent metadata was accepted"):
		missing_metadata.free()
		return false
	missing_metadata.free()
	var wrong_metadata: Node3D = FactoryScript.build(torso_id, torso_entry)
	wrong_metadata.set_meta("biomass_part_id", "biomass_claw_v1")
	if not _need(not ValidatorScript.validate_part(wrong_metadata, torso_id, torso_entry).is_empty(), "mismatched metadata was accepted"):
		wrong_metadata.free()
		return false
	wrong_metadata.free()
	var stringname_metadata: Node3D = FactoryScript.build(torso_id, torso_entry)
	stringname_metadata.set_meta("biomass_part_id", StringName(torso_id))
	if not _need(ValidatorScript.validate_part(stringname_metadata, torso_id, torso_entry).is_empty(), "matching StringName metadata was rejected"):
		stringname_metadata.free()
		return false
	stringname_metadata.free()
	return true

func _mutate_probe(root: Node3D, probe: String, target_name: String) -> bool:
	var target: Node = _find_named(root, target_name)
	if not _need(target != null, "probe target socket missing: %s" % probe):
		return false
	match probe:
		"missing":
			target.free()
		"extra":
			var extra: Node3D = Node3D.new()
			extra.name = StringName("socket_undeclared_0")
			root.add_child(extra)
		"duplicate":
			var duplicate: Node3D = Node3D.new()
			duplicate.name = StringName(target_name)
			duplicate.set_meta("biomass_socket_name", target_name)
			root.add_child(duplicate)
		"wrong_type":
			var replacement: Node = Node.new()
			replacement.name = StringName(target_name)
			var parent: Node = target.get_parent()
			parent.remove_child(target)
			target.free()
			parent.add_child(replacement)
		"nonfinite":
			(target as Node3D).position = Vector3(INF, 0.0, 0.0)
		"scaled":
			(target as Node3D).scale = Vector3(1.0002, 1.0, 1.0)
		"drift":
			(target as Node3D).position.x += 0.002
		"path_duplicate":
			var pivot: Node3D = Node3D.new()
			pivot.name = StringName("PathDuplicate")
			root.add_child(pivot)
			var duplicate_path: Node3D = Node3D.new()
			duplicate_path.name = StringName(target_name)
			pivot.add_child(duplicate_path)
		"metadata":
			root.set_meta("biomass_part_id", "biomass_claw_v1")
		"socket_child":
			var child: MeshInstance3D = MeshInstance3D.new()
			(target as Node3D).add_child(child)
		_:
			return false
	return true

func _all_assemblies_validate() -> bool:
	for recipe_id in RECIPE_IDS:
		var recipe: Variant = _library.get_recipe(recipe_id)
		if not _need(recipe != null and recipe.is_valid(), "recipe invalid: %s" % recipe_id):
			return false
		var assembler: Variant = AssemblerScript.new()
		var visual: Variant = assembler.build(recipe, _parts)
		if not _need(visual != null, "assembly build failed: %s %s" % [recipe_id, assembler.last_diagnostics()]):
			return false
		var diagnostics: PackedStringArray = ValidatorScript.validate_assembly(visual, recipe, _parts)
		if not _need(diagnostics.is_empty(), "assembly diagnostics for %s: %s" % [recipe_id, diagnostics]):
			visual.free()
			return false
		visual.free()
	return true

func _invalid_assembly_probe() -> bool:
	var recipe: Variant = _library.get_recipe("biped_puppet_v1")
	var assembler: Variant = AssemblerScript.new()
	var visual: Variant = assembler.build(recipe, _parts)
	if not _need(visual != null, "assembly invalidation setup failed"):
		return false
	var core: Node3D = visual.part("core")
	if not _need(core != null, "assembly core missing"):
		visual.free()
		return false
	var socket: Node = _find_named(core, "socket_root_0")
	if not _need(socket != null, "assembly root socket missing"):
		visual.free()
		return false
	socket.free()
	var diagnostics: PackedStringArray = ValidatorScript.validate_assembly(visual, recipe, _parts)
	if not _need(not diagnostics.is_empty(), "invalid mixed assembly was accepted"):
		visual.free()
		return false
	var sorted: PackedStringArray = diagnostics.duplicate()
	sorted.sort()
	if not _need(diagnostics == sorted, "assembly diagnostics were not sorted"):
		visual.free()
		return false
	visual.free()
	return true

func _socket_count(root: Node3D, entry: Dictionary) -> int:
	var count: int = 0
	for socket_value in entry.get("sockets", []) as Array:
		if socket_value is Dictionary and _find_named(root, String((socket_value as Dictionary).get("name", ""))) != null:
			count += 1
	return count

func _find_named(node: Node, target: String) -> Node:
	if String(node.name) == target:
		return node
	for child in node.get_children():
		var found: Node = _find_named(child, target)
		if found != null:
			return found
	return null

func _node_names(node: Node) -> Array[String]:
	var names: Array[String] = [String(node.name)]
	for child in node.get_children():
		names.append_array(_node_names(child))
	return names

func _need(condition: bool, message: String) -> bool:
	if condition:
		return true
	print("BIOMASS WRAPPER AUTHORITY FAIL " + message)
	quit(1)
	return false
