extends SceneTree

## Biomass assembly smoke — Task 5 contract.
##
## Strict RED→GREEN smoke. Requires the exact four new GDScripts and two
## fixtures. Covers the five-recipe oracle, every public accessor and
## rest-transform API, off-tree composition, collision policy, wrapper
## rejection paths, and the queue_free physics clearance contract.
##
## Preloads production scripts through `preload(...)` so that absent scripts
## fail at parse time (RED). When all four scripts are present and the
## implementation matches the contracts, the final marker is
## `BIOMASS ASSEMBLY PASS recipes=5 max_nodes=78 max_triangles=23000`.

const FactoryScript: GDScript = preload("res://scripts/tools/biomass_placeholder_factory.gd")
const VisualScript: GDScript = preload("res://scripts/threats/biomass_threat_visual.gd")
const AssemblerScript: GDScript = preload("res://scripts/threats/biomass_assembler.gd")
const PartCatalogScript: GDScript = preload("res://scripts/systems/biomass_part_catalog.gd")
const RecipeScript: GDScript = preload("res://scripts/systems/biomass_recipe.gd")
const RecipeLibraryScript: GDScript = preload("res://scripts/systems/biomass_recipe_library.gd")

const PARTS_PATH: String = "res://data/combat/biomass_part_catalog.json"
const RECIPES_PATH: String = "res://data/combat/biomass_recipe_catalog.json"
const INVALID_PARTS_PATH: String = "res://tests/fixtures/biomass_invalid_wrapper_catalog.json"
const FIXTURE_TORSO: String = "res://tests/fixtures/biomass_valid_core_wrapper.tscn"
const FIXTURE_CLAW: String = "res://tests/fixtures/biomass_valid_nested_wrapper.tscn"
const FIXTURE_TENTACLE: String = "res://tests/fixtures/biomass_node_overflow_wrapper.tscn"
const PREDELETE_MARKER: String = "user://biomass_predelete_probe.marker"

const EXPECTED: Dictionary = {
	"biped_puppet_v1": {"attachments": 4, "occurrences": 9, "collision_nodes": 9, "disabled_connectors": 4, "nodes": 58, "triangles": 17000},
	"four_legged_scrambler_v1": {"attachments": 6, "occurrences": 13, "collision_nodes": 13, "disabled_connectors": 6, "nodes": 78, "triangles": 23000},
	"tripod_hound_v1": {"attachments": 5, "occurrences": 11, "collision_nodes": 11, "disabled_connectors": 5, "nodes": 58, "triangles": 16500},
	"intestinal_dragger_v1": {"attachments": 3, "occurrences": 7, "collision_nodes": 7, "disabled_connectors": 3, "nodes": 39, "triangles": 11500},
	"tendril_knot_v1": {"attachments": 4, "occurrences": 9, "collision_nodes": 9, "disabled_connectors": 4, "nodes": 53, "triangles": 15000},
}
const RECIPE_IDS: Array[String] = [
	"biped_puppet_v1",
	"four_legged_scrambler_v1",
	"intestinal_dragger_v1",
	"tendril_knot_v1",
	"tripod_hound_v1",
]

var _max_nodes: int = 0
var _max_triangles: int = 0

func _initialize() -> void:
	_run()

func _run() -> void:
	var parts: Variant = PartCatalogScript.new()
	if not _need(parts.load_path(PARTS_PATH), "part catalog did not load"):
		return
	var library: Variant = RecipeLibraryScript.new()
	if not _need(library.load_path(RECIPES_PATH, parts), "recipe library did not load"):
		return
	if not _need(_fixture_loader_checks(), "fixture loader checks failed"):
		return
	if not _need(_fixture_catalog_checks(), "fixture catalog checks failed"):
		return
	if not _need(_factory_direct_checks(parts), "factory direct checks failed"):
		return
	if not _need(_factory_malformed_socket_probe(), "factory malformed-socket probe failed"):
		return
	if not _need(_recipe_acceptance_checks(parts, library), "recipe acceptance checks failed"):
		return
	if not _need(_nine_attachment_rejection_checks(parts), "9-attachment rejection failed"):
		return
	if not _need(_invalid_recipe_checks(parts, library), "invalid recipe checks failed"):
		return
	if not _need(_assembler_input_checks(parts, library), "assembler input checks failed"):
		return
	if not _need(_invalid_wrapper_fixture_checks(parts), "invalid wrapper fixture failed"):
		return
	if not _need(_fixture_scene_contract_checks(), "fixture scene contracts failed"):
		return
	if not _need(_node_overflow_fixture_probe(parts), "node overflow fixture probe failed"):
		return
	if not _need(_triangle_overflow_fixture_probe(parts, library), "triangle overflow fixture probe failed"):
		return
	if not _need(await _rest_accessors_and_oracle_checks(parts, library), "rest accessor / oracle checks failed"):
		return
	if not _need(await _reset_to_assembly_rest_probe(parts, library), "reset-to-assembly-rest probe failed"):
		return
	if not _need(_wrong_script_parts_probe(parts, library), "wrong-script parts probe failed"):
		return
	if not _need(await _physics_collision_checks(parts, library), "physics collision checks failed"):
		return
	if not _need(await _free_lifecycle_checks(parts, library), "queue_free lifecycle checks failed"):
		return
	print("BIOMASS ASSEMBLY PASS recipes=5 max_nodes=%d max_triangles=%d" % [_max_nodes, _max_triangles])
	quit(0)

# ---------------------------------------------------------------------------
# Factory direct checks
# ---------------------------------------------------------------------------

func _factory_direct_checks(parts: Variant) -> bool:
	for part_id in [
		"biomass_human_arm_v1",
		"biomass_insect_leg_v1",
		"biomass_cephalopod_tentacle_v1",
		"biomass_animal_skull_v1",
		"biomass_humanoid_torso_v1",
		"biomass_gunk_connector_v1",
		"biomass_claw_v1",
		"biomass_maw_v1",
	]:
		var entry: Dictionary = parts.get_part(part_id)
		if not _need(not entry.is_empty(), "missing part entry %s" % part_id):
			return false
		var node: Variant = FactoryScript.build(part_id, entry)
		if not _need(node != null and node is Node3D, "factory returned non-Node3D for %s" % part_id):
			return false
		var part_root: Node3D = node
		var mesh_count: int = 0
		var socket_count: int = 0
		var collision_count: int = 0
		for child in part_root.get_children():
			if child is MeshInstance3D:
				mesh_count += 1
			elif child is Node3D:
				socket_count += 1
			if child is CollisionObject3D or child is CollisionShape3D:
				collision_count += 1
		var expected_sockets: int = (entry.get("sockets", []) as Array).size()
		if not _need(mesh_count == 1, "factory mesh count != 1 for %s (got %d)" % [part_id, mesh_count]):
			part_root.free()
			return false
		if not _need(socket_count == expected_sockets, "factory socket count mismatch for %s: got %d expected %d" % [part_id, socket_count, expected_sockets]):
			part_root.free()
			return false
		if not _need(collision_count == 0, "factory created collision for %s" % part_id):
			part_root.free()
			return false
		# Capsule mesh: forward must be catalog +Z. The +90° X rotation maps the
		# capsule's local +Y axis onto the catalog's authoritative local +Z
		# forward. We check the *direction* of the basis Y column after
		# normalizing, because the scale property scales the basis columns.
		if entry.get("fallback", {}).get("primitive", "") == "capsule":
			var mesh_node: MeshInstance3D = null
			for child in part_root.get_children():
				if child is MeshInstance3D:
					mesh_node = child
					break
			if not _need(mesh_node != null, "capsule mesh node is null"):
				part_root.free()
				return false
			var basis_y_dir: Vector3 = mesh_node.transform.basis.y.normalized()
			if not _need(absf(basis_y_dir.z - 1.0) <= 0.001, "capsule long axis is not catalog +Z for %s (basis Y = %s)" % [part_id, basis_y_dir]):
				part_root.free()
				return false
		part_root.free()
	# Box mesh dimensions check.
	var skull: Dictionary = parts.get_part("biomass_animal_skull_v1")
	var skull_root: Node3D = FactoryScript.build("biomass_animal_skull_v1", skull)
	var skull_mesh: MeshInstance3D = skull_root.get_child(0)
	if not _need(skull_mesh.mesh is BoxMesh, "skull mesh is not BoxMesh"):
		skull_root.free()
		return false
	var skull_box: BoxMesh = skull_mesh.mesh
	var skull_dims: Array = skull.get("fallback", {}).get("dimensions_m", [])
	if not _need(absf(skull_box.size.x - skull_dims[0]) <= 0.001 and absf(skull_box.size.y - skull_dims[1]) <= 0.001 and absf(skull_box.size.z - skull_dims[2]) <= 0.001, "skull box dims mismatch"):
		skull_root.free()
		return false
	skull_root.free()
	return true

# ---------------------------------------------------------------------------
# Recipe acceptance (all 5 curated recipes produce a valid visual).
# ---------------------------------------------------------------------------

func _recipe_acceptance_checks(parts: Variant, library: Variant) -> bool:
	for recipe_id in RECIPE_IDS:
		var recipe: Variant = library.get_recipe(recipe_id)
		if not _need(recipe != null and recipe.is_valid(), "recipe %s not valid" % recipe_id):
			return false
		var assembler: Variant = AssemblerScript.new()
		var visual: Variant = assembler.build(recipe, parts)
		if not _need(visual != null, "assembler.build returned null for %s" % recipe_id):
			return false
		if not _need(visual.get_script() == VisualScript, "assembler returned wrong script for %s" % recipe_id):
			visual.queue_free()
			return false
		visual.queue_free()
	return true

# ---------------------------------------------------------------------------
# 9-attachment rejection.
# ---------------------------------------------------------------------------

func _nine_attachment_rejection_checks(parts: Variant) -> bool:
	var deep: Dictionary = {
		"recipe_id": "nine_attachment_recipe_v1",
		"locomotion_hint": "crawl",
		"core": {"instance_id": "core", "part_id": "biomass_animal_skull_v1"},
		"attachments": [],
	}
	for index in range(9):
		var socket_name: String = "appendage_%d" % (index % 6)
		deep["attachments"].append({
			"instance_id": "limb_%d" % index,
			"part_id": "biomass_insect_leg_v1",
			"parent_instance_id": "core" if index < 6 else "limb_0",
			"parent_socket": socket_name if index < 6 else "distal_0",
			"child_socket": "root_0",
			"connector_part_id": "biomass_gunk_connector_v1",
		})
	var deep_recipe: Variant = RecipeScript.from_dict(deep, parts)
	if not _need(deep_recipe != null and not deep_recipe.is_valid(), "9-attachment recipe was accepted"):
		return false
	var diag: PackedStringArray = deep_recipe.diagnostics()
	if not _need(diag.has("recipe.attachments: max attachments exceeded (9 > 8)"), "9-attachment diagnostic missing: %s" % diag):
		return false
	# Assembler.build must return null and surface the same diagnostic.
	var assembler: Variant = AssemblerScript.new()
	var visual: Variant = assembler.build(deep_recipe, parts)
	if not _need(visual == null, "assembler built a 9-attachment visual"):
		return false
	if not _need(assembler.last_diagnostics().has("recipe.attachments: max attachments exceeded (9 > 8)"), "assembler did not surface diagnostic"):
		return false
	# Stable diagnostics: build again and compare.
	var second: Variant = assembler.build(deep_recipe, parts)
	if not _need(second == null, "second 9-attachment build did not return null"):
		return false
	if not _need(assembler.last_diagnostics() == diag, "diagnostics not stable across repeated 9-attachment builds"):
		return false
	# No nodes left in the scene tree from these failed attempts.
	var root: Window = get_root()
	if not _need(_count_scene_nodes(root) == 0, "failed builds left nodes in scene tree"):
		return false
	return true

# ---------------------------------------------------------------------------
# Wrong-script / null / unloaded / invalid recipe inputs.
# ---------------------------------------------------------------------------

func _invalid_recipe_checks(parts: Variant, library: Variant) -> bool:
	# Dictionary recipe rejected.
	var fake_recipe: Dictionary = {"recipe_id": "fake"}
	if not _need(AssemblerScript.new().build(fake_recipe, parts) == null, "Dictionary recipe was accepted"):
		return false
	# Null recipe.
	var assembler: Variant = AssemblerScript.new()
	if not _need(assembler.build(null, parts) == null, "null recipe was accepted"):
		return false
	# Dictionary parts rejected.
	var fake_parts: Dictionary = {}
	if not _need(assembler.build(library.get_recipe("biped_puppet_v1"), fake_parts) == null, "Dictionary parts was accepted"):
		return false
	# Unloaded catalog.
	var unloaded_parts: Variant = PartCatalogScript.new()
	if not _need(assembler.build(library.get_recipe("biped_puppet_v1"), unloaded_parts) == null, "unloaded catalog was accepted"):
		return false
	# Null parts.
	if not _need(assembler.build(library.get_recipe("biped_puppet_v1"), null) == null, "null parts was accepted"):
		return false
	# An invalid BiomassRecipe (not from .is_valid()).
	var invalid: Variant = RecipeScript.from_dict({"recipe_id": "bad"}, parts)
	if not _need(not invalid.is_valid(), "invalid recipe builder accepted bad input"):
		return false
	if not _need(assembler.build(invalid, parts) == null, "invalid BiomassRecipe was assembled"):
		return false
	# Stable, sorted, deduplicated diagnostics.
	var first_diag: PackedStringArray = assembler.last_diagnostics().duplicate()
	assembler.build(invalid, parts)
	var second_diag: PackedStringArray = assembler.last_diagnostics()
	if not _need(not first_diag.is_empty() and first_diag == second_diag, "invalid-recipe diagnostics not stable"):
		return false
	var sorted: PackedStringArray = first_diag.duplicate()
	sorted.sort()
	if not _need(first_diag == sorted, "invalid-recipe diagnostics not sorted"):
		return false
	var seen: Dictionary = {}
	for d in first_diag:
		if seen.has(d):
			return _fail_with("invalid-recipe diagnostics not deduplicated")
		seen[d] = true
	return true

# ---------------------------------------------------------------------------
# Wrapper rejection: non-PackedScene + forbidden-physics via fixture catalog.
# ---------------------------------------------------------------------------

func _invalid_wrapper_fixture_checks(parts: Variant) -> bool:
	var fixture_parts: Variant = PartCatalogScript.new()
	if not _need(fixture_parts.load_path(INVALID_PARTS_PATH), "invalid-wrapper fixture catalog did not load"):
		return false
	# Verify two specific parts' wrapper paths were altered.
	var insect_entry: Dictionary = fixture_parts.get_part("biomass_insect_leg_v1")
	if not _need(insect_entry.get("wrapper_scene_path", "") == "res://project.godot", "fixture catalog did not redirect insect leg wrapper"):
		return false
	var maw_entry: Dictionary = fixture_parts.get_part("biomass_maw_v1")
	if not _need(maw_entry.get("wrapper_scene_path", "") == "res://tests/fixtures/biomass_forbidden_physics_wrapper.tscn", "fixture catalog did not redirect maw wrapper"):
		return false
	var assembler: Variant = AssemblerScript.new()
	# Non-PackedScene probe: torso (empty wrapper, core role) + insect_leg
	# attachment with non-PackedScene wrapper path.
	var non_packed_doc: Dictionary = _attachment_recipe(
		"wrapper_probe_non_packed",
		"biomass_humanoid_torso_v1",
		"limb_0",
		"biomass_insect_leg_v1",
	)
	var non_packed_recipe: Variant = RecipeScript.from_dict(non_packed_doc, fixture_parts)
	if not _need(non_packed_recipe != null and non_packed_recipe.is_valid(), "non-PackedScene probe recipe was invalid: %s" % non_packed_recipe.diagnostics()):
		return false
	_clear_predelete_marker()
	var first_a: Variant = assembler.build(non_packed_recipe, fixture_parts)
	if not _need(first_a == null, "non-PackedScene wrapper was accepted"):
		return false
	if not _need(_predelete_marker_exists(), "non-PackedScene outer visual was not freed synchronously"):
		return false
	_clear_predelete_marker()
	var first_diag: PackedStringArray = assembler.last_diagnostics()
	var second_a: Variant = assembler.build(non_packed_recipe, fixture_parts)
	if not _need(second_a == null, "second non-PackedScene wrapper build was non-null"):
		return false
	if not _need(not first_diag.is_empty() and first_diag == assembler.last_diagnostics(), "non-PackedScene diagnostics not stable"):
		return false
	var sorted_a: PackedStringArray = first_diag.duplicate()
	sorted_a.sort()
	if not _need(first_diag == sorted_a, "non-PackedScene diagnostics not sorted"):
		return false
	# Forbidden-physics probe: torso core + arm + maw on appendage_2.
	var physics_doc: Dictionary = _attachment_recipe(
		"wrapper_probe_physics",
		"biomass_humanoid_torso_v1",
		"limb_0",
		"biomass_human_arm_v1",
		"biomass_maw_v1",
	)
	var physics_recipe: Variant = RecipeScript.from_dict(physics_doc, fixture_parts)
	if not _need(physics_recipe != null and physics_recipe.is_valid(), "forbidden-physics probe recipe was invalid: %s" % physics_recipe.diagnostics()):
		return false
	_clear_predelete_marker()
	var first_p: Variant = assembler.build(physics_recipe, fixture_parts)
	if not _need(first_p == null, "forbidden-physics wrapper was accepted"):
		return false
	if not _need(_predelete_marker_exists(), "forbidden-physics outer visual was not freed synchronously"):
		return false
	_clear_predelete_marker()
	var physics_diag: PackedStringArray = assembler.last_diagnostics()
	var second_p: Variant = assembler.build(physics_recipe, fixture_parts)
	if not _need(second_p == null, "second forbidden-physics build was non-null"):
		return false
	if not _need(not physics_diag.is_empty() and physics_diag == assembler.last_diagnostics(), "forbidden-physics diagnostics not stable"):
		return false
	var sorted_p: PackedStringArray = physics_diag.duplicate()
	sorted_p.sort()
	if not _need(physics_diag == sorted_p, "forbidden-physics diagnostics not sorted"):
		return false
	# No nodes leaked from rejected builds.
	var root: Window = get_root()
	if not _need(_count_scene_nodes(root) == 0, "rejected wrapper builds leaked scene nodes"):
		return false
	return true

func _attachment_recipe(recipe_id: String, core_part_id: String, parent_socket: String, child_part_id: String, second_part_id: String = "") -> Dictionary:
	var attachments: Array = [
		{
			"instance_id": "child",
			"part_id": child_part_id,
			"parent_instance_id": "core",
			"parent_socket": parent_socket,
			"child_socket": "root_0",
			"connector_part_id": "biomass_gunk_connector_v1",
		},
	]
	if not second_part_id.is_empty():
		attachments.append(
			{
				"instance_id": "second",
				"part_id": second_part_id,
				"parent_instance_id": "core",
				"parent_socket": "head_0" if second_part_id == "biomass_animal_skull_v1" else ("appendage_2" if second_part_id == "biomass_maw_v1" else "limb_2"),
				"child_socket": "root_0",
				"connector_part_id": "biomass_gunk_connector_v1",
			}
		)
	return {
		"recipe_id": recipe_id,
		"locomotion_hint": "crawl",
		"core": {"instance_id": "core", "part_id": core_part_id},
		"attachments": attachments,
	}

# ---------------------------------------------------------------------------
# Assembler inputs (script identity, input mutation).
# ---------------------------------------------------------------------------

func _assembler_input_checks(parts: Variant, library: Variant) -> bool:
	var assembler: Variant = AssemblerScript.new()
	var recipe: Variant = library.get_recipe("biped_puppet_v1")
	var first: Variant = assembler.build(recipe, parts)
	if not _need(first != null, "first valid build returned null"):
		return false
	var recipe_doc: Dictionary = recipe.to_dict()
	recipe_doc["recipe_id"] = "mutated"
	(recipe_doc["attachments"] as Array).clear()
	var arm_entry: Dictionary = parts.get_part("biomass_human_arm_v1")
	arm_entry["category"] = "mutated"
	# Reload parts into a fresh catalog to prove the assembler did not retain caller state.
	var mutated_parts: Variant = PartCatalogScript.new()
	if not _need(mutated_parts.load_path(PARTS_PATH), "could not reload parts"):
		first.queue_free()
		return false
	var second: Variant = assembler.build(library.get_recipe("biped_puppet_v1"), mutated_parts)
	if not _need(second != null, "second valid build returned null after caller mutation"):
		first.queue_free()
		return false
	if not _need(second.runtime_node_count() == EXPECTED["biped_puppet_v1"]["nodes"], "mutated build did not match oracle node count"):
		second.queue_free()
		first.queue_free()
		return false
	# Verify recipe.to_dict() has not changed.
	if not _need(recipe.to_dict()["recipe_id"] == "biped_puppet_v1", "recipe leaked caller mutation"):
		second.queue_free()
		first.queue_free()
		return false
	if not _need(not (recipe.to_dict()["attachments"] as Array).is_empty(), "recipe attachments was cleared"):
		second.queue_free()
		first.queue_free()
		return false
	first.queue_free()
	second.queue_free()
	return true

# ---------------------------------------------------------------------------
# Rest accessors + five-recipe oracle (off-tree composition).
# ---------------------------------------------------------------------------

func _rest_accessors_and_oracle_checks(parts: Variant, library: Variant) -> bool:
	for recipe_id in RECIPE_IDS:
		var recipe: Variant = library.get_recipe(recipe_id)
		var visual: Variant = AssemblerScript.new().build(recipe, parts)
		if not _need(visual != null, "oracle build returned null for %s" % recipe_id):
			return false
		var doc: Dictionary = recipe.to_dict()
		get_root().add_child(visual)
		await process_frame
		await physics_frame

		# recipe_document() must match recipe.to_dict() exactly.
		var returned_doc: Dictionary = visual.recipe_document()
		if not _need(returned_doc == doc, "recipe_document mismatch for %s" % recipe_id):
			return false

		# Mutate returned_doc and prove a subsequent read is unchanged.
		returned_doc["recipe_id"] = "mutated"
		var core_field: Variant = returned_doc.get("core")
		if core_field is Dictionary:
			(core_field as Dictionary)["part_id"] = "mutated"
		(returned_doc["attachments"] as Array).clear()
		if not _need(visual.recipe_document() == doc, "recipe_document leaked caller mutation for %s" % recipe_id):
			return false

		var exp: Dictionary = EXPECTED[recipe_id]
		var actual_nodes: int = visual.runtime_node_count()
		var actual_triangles: int = visual.triangle_budget()
		if not _need(actual_nodes == exp["nodes"], "runtime_node_count mismatch for %s: got %d expected %d" % [recipe_id, actual_nodes, exp["nodes"]]):
			return false
		if not _need(actual_triangles == exp["triangles"], "triangle_budget mismatch for %s: got %d expected %d" % [recipe_id, actual_triangles, exp["triangles"]]):
			return false
		_max_nodes = max(_max_nodes, actual_nodes)
		_max_triangles = max(_max_triangles, actual_triangles)

		# every part occurrence, every socket, one mount per edge.
		var core_id_value: Variant = doc.get("core")
		if not _need(core_id_value is Dictionary, "core is not a dict for %s" % recipe_id):
			return false
		var core_instance_id: String = String((core_id_value as Dictionary).get("instance_id", ""))
		if not _need(visual.part(core_instance_id) != null, "missing core part for %s" % recipe_id):
			return false
		var edges: Array = doc.get("attachments", []) as Array
		if not _need(edges.size() == exp["attachments"], "attachment edge count mismatch for %s" % [recipe_id]):
			return false
		var mount_count: int = 0
		for edge_value in edges:
			var edge: Dictionary = edge_value
			var instance_id: String = String(edge.get("instance_id", ""))
			var parent_id: String = String(edge.get("parent_instance_id", ""))
			var parent_socket: String = String(edge.get("parent_socket", ""))
			var child_socket: String = String(edge.get("child_socket", ""))
			if not _need(visual.part(instance_id) != null, "missing attachment part %s for %s" % [instance_id, recipe_id]):
				return false
			if not _need(visual.socket(parent_id, parent_socket) != null, "missing parent socket %s.%s for %s" % [parent_id, parent_socket, recipe_id]):
				return false
			if not _need(visual.socket(instance_id, child_socket) != null, "missing child socket %s.%s for %s" % [instance_id, child_socket, recipe_id]):
				return false
			if not _need(visual.attachment_mount(instance_id) != null, "missing attachment mount for %s in %s" % [instance_id, recipe_id]):
				return false
			mount_count += 1
		if not _need(mount_count == exp["attachments"], "mount count mismatch for %s" % recipe_id):
			return false

		# Off-tree composition: parent_socket.global_position == child_socket.global_position.
		for edge_value in edges:
			var edge: Dictionary = edge_value
			var parent_socket_node: Node3D = visual.socket(String(edge.get("parent_instance_id", "")), String(edge.get("parent_socket", "")))
			var child_socket_node: Node3D = visual.socket(String(edge.get("instance_id", "")), String(edge.get("child_socket", "")))
			if not _need(parent_socket_node.global_position.distance_to(child_socket_node.global_position) <= 0.001, "socket position drift %s in %s" % [edge.get("instance_id"), recipe_id]):
				return false
			if not _need(parent_socket_node.global_basis.z.dot(child_socket_node.global_basis.z) >= 0.999, "socket basis drift %s in %s" % [edge.get("instance_id"), recipe_id]):
				return false

		# CharacterBody3D + collision layer/mask = 1.
		if not _need(visual is CharacterBody3D, "visual is not CharacterBody3D for %s" % recipe_id):
			return false
		if not _need(visual.collision_layer == 1, "collision_layer != 1 for %s" % recipe_id):
			return false
		if not _need(visual.collision_mask == 1, "collision_mask != 1 for %s" % recipe_id):
			return false

		# Direct child CollisionShape3D count == oracle.
		var direct_collision_count: int = 0
		var disabled_count: int = 0
		var enabled_count: int = 0
		for child in visual.get_children():
			if child is CollisionShape3D:
				direct_collision_count += 1
				if (child as CollisionShape3D).disabled:
					disabled_count += 1
				else:
					enabled_count += 1
		if not _need(direct_collision_count == exp["collision_nodes"], "direct collision count mismatch for %s: got %d expected %d" % [recipe_id, direct_collision_count, exp["collision_nodes"]]):
			return false
		if not _need(disabled_count == exp["disabled_connectors"], "disabled connector count mismatch for %s: got %d expected %d" % [recipe_id, disabled_count, exp["disabled_connectors"]]):
			return false
		if not _need(enabled_count == exp["collision_nodes"] - exp["disabled_connectors"], "enabled collision count mismatch for %s" % recipe_id):
			return false

		# Rest transforms — known IDs return a Transform3D, unknown IDs return null.
		var core_part: Variant = visual.part(core_instance_id)
		var core_rest: Variant = visual.part_rest_transform(core_instance_id)
		if not _need(core_rest is Transform3D, "core rest is not Transform3D for %s" % recipe_id):
			return false
		if not _need((core_rest as Transform3D) == (core_part as Node3D).transform, "core rest != core part's parent-local transform for %s" % recipe_id):
			return false
		if not _need(visual.part_rest_transform("unknown_id") == null, "unknown part_rest did not return null for %s" % recipe_id):
			return false
		if not _need(visual.attachment_rest_transform("unknown_id") == null, "unknown attachment_rest did not return null for %s" % recipe_id):
			return false
		# Mutate returned rest and prove a subsequent read is unchanged.
		(core_rest as Transform3D).origin.x = 999.0
		if not _need(visual.part_rest_transform(core_instance_id).origin.x != 999.0, "part_rest_transform leaked mutable state for %s" % recipe_id):
			return false
		for edge_value in edges:
			var edge: Dictionary = edge_value
			var instance_id: String = String(edge.get("instance_id", ""))
			var mount: Node3D = visual.attachment_mount(instance_id)
			var mount_rest: Variant = visual.attachment_rest_transform(instance_id)
			if not _need(mount_rest is Transform3D, "attachment rest is not Transform3D for %s" % recipe_id):
				return false
			if not _need((mount_rest as Transform3D) == mount.transform, "attachment rest != mount transform for %s.%s" % [recipe_id, instance_id]):
				return false
			(mount_rest as Transform3D).origin.y = 999.0
			if not _need(visual.attachment_rest_transform(instance_id).origin.y != 999.0, "attachment_rest leaked mutable state for %s.%s" % [recipe_id, instance_id]):
				return false
			var child_part: Node3D = visual.part(instance_id)
			var child_rest: Variant = visual.part_rest_transform(instance_id)
			if not _need(child_rest is Transform3D, "child part rest missing for %s" % recipe_id):
				return false
			if not _need((child_rest as Transform3D) == child_part.transform, "child part rest != parent-local transform for %s.%s" % [recipe_id, instance_id]):
				return false

		# Limits enforced.
		if not _need(visual.runtime_node_count() <= 160, "runtime nodes exceed 160 for %s" % recipe_id):
			return false
		if not _need(visual.triangle_budget() <= 30000, "triangles exceed 30000 for %s" % recipe_id):
			return false

		visual.queue_free()
		await process_frame
		await physics_frame
	return true

# ---------------------------------------------------------------------------
# Physics raycast hit on body, post-free miss, no leaks.
# ---------------------------------------------------------------------------

func _physics_collision_checks(parts: Variant, library: Variant) -> bool:
	var recipe: Variant = library.get_recipe("biped_puppet_v1")
	var visual: Variant = AssemblerScript.new().build(recipe, parts)
	if not _need(visual != null, "physics build returned null"):
		return false
	get_root().add_child(visual)
	visual.global_position = Vector3.ZERO
	await process_frame
	await physics_frame
	var space_state: PhysicsDirectSpaceState3D = get_root().get_world_3d().direct_space_state
	var ray_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(Vector3(-5, 0, 0), Vector3(5, 0, 0))
	ray_query.collide_with_bodies = true
	ray_query.collide_with_areas = false
	ray_query.collision_mask = 1
	var hit: Dictionary = space_state.intersect_ray(ray_query)
	if not _need(not hit.is_empty(), "ray did not hit visual body"):
		visual.queue_free()
		await process_frame
		await physics_frame
		return false
	if not _need(hit.get("collider", null) == visual, "ray hit did not return the body as collider"):
		visual.queue_free()
		await process_frame
		await physics_frame
		return false
	var miss_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(Vector3(-5, 50, 0), Vector3(5, 50, 0))
	miss_query.collide_with_bodies = true
	miss_query.collide_with_areas = false
	miss_query.collision_mask = 1
	var miss: Dictionary = space_state.intersect_ray(miss_query)
	if not _need(miss.is_empty(), "ray unexpectedly hit at +Y=50"):
		visual.queue_free()
		await process_frame
		await physics_frame
		return false
	visual.queue_free()
	await process_frame
	await physics_frame
	return true

func _free_lifecycle_checks(parts: Variant, library: Variant) -> bool:
	var recipe: Variant = library.get_recipe("tripod_hound_v1")
	var visual: Variant = AssemblerScript.new().build(recipe, parts)
	if not _need(visual != null, "lifecycle build returned null"):
		return false
	get_root().add_child(visual)
	await process_frame
	await physics_frame
	visual.queue_free()
	await process_frame
	await physics_frame
	var space_state: PhysicsDirectSpaceState3D = get_root().get_world_3d().direct_space_state
	var ray_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(Vector3(-5, 0, 0), Vector3(5, 0, 0))
	ray_query.collide_with_bodies = true
	ray_query.collide_with_areas = false
	ray_query.collision_mask = 1
	var hit: Dictionary = space_state.intersect_ray(ray_query)
	if not _need(hit.is_empty(), "post-free ray still hit"):
		return false
	if not _need(not is_instance_valid(visual), "visual still valid after queue_free+frames"):
		return false
	var second: Variant = AssemblerScript.new().build(recipe, parts)
	if not _need(second != null, "post-free rebuild returned null"):
		return false
	second.free()
	return true

# ---------------------------------------------------------------------------
# Fixture loader / catalog probes (R4-R7 setup, run before all other probes).
# ---------------------------------------------------------------------------

func _fixture_loader_checks() -> bool:
	for path in [FIXTURE_TORSO, FIXTURE_CLAW, FIXTURE_TENTACLE, "res://tests/fixtures/biomass_forbidden_physics_wrapper.tscn"]:
		if not ResourceLoader.exists(path, "PackedScene"):
			return _fail_with("ResourceLoader.exists failed: " + path)
		var resource: Resource = load(path)
		if not resource is PackedScene:
			return _fail_with("load() did not return PackedScene: " + path)
		var inst: Node = (resource as PackedScene).instantiate()
		if not inst is Node3D:
			inst.free()
			return _fail_with("instantiate root is not Node3D: " + path)
		inst.free()
	return true

func _fixture_catalog_checks() -> bool:
	var fixture_parts: Variant = PartCatalogScript.new()
	if not fixture_parts.load_path(INVALID_PARTS_PATH):
		return _fail_with("invalid-wrapper fixture catalog did not load")
	var expected: Dictionary = {
		"biomass_insect_leg_v1": "res://project.godot",
		"biomass_animal_skull_v1": "",
		"biomass_maw_v1": "res://tests/fixtures/biomass_forbidden_physics_wrapper.tscn",
		"biomass_humanoid_torso_v1": FIXTURE_TORSO,
		"biomass_claw_v1": FIXTURE_CLAW,
		"biomass_cephalopod_tentacle_v1": FIXTURE_TENTACLE,
	}
	for part_id in expected.keys():
		var entry: Dictionary = fixture_parts.get_part(part_id)
		if entry.is_empty():
			return _fail_with("fixture catalog missing entry: " + part_id)
		if String(entry.get("wrapper_scene_path", "")) != expected[part_id]:
			return _fail_with("fixture catalog wrapper path wrong for: " + part_id)
	return true

func _fixture_scene_contract_checks() -> bool:
	var fixture_parts: Variant = PartCatalogScript.new()
	if not fixture_parts.load_path(INVALID_PARTS_PATH):
		return _fail_with("fixture catalog did not load for scene contract checks")
	for part_id in ["biomass_humanoid_torso_v1", "biomass_claw_v1", "biomass_cephalopod_tentacle_v1"]:
		var entry: Dictionary = fixture_parts.get_part(part_id)
		var resource: Resource = load(String(entry.get("wrapper_scene_path", "")))
		if not _need(resource is PackedScene, "fixture is not PackedScene for %s" % part_id):
			return false
		var root_value: Node = (resource as PackedScene).instantiate()
		if not _need(root_value is Node3D, "fixture root is not Node3D for %s" % part_id):
			if root_value != null:
				root_value.free()
			return false
		var root: Node3D = root_value as Node3D
		var visible_meshes: int = 0
		for mesh_value in root.find_children("*", "MeshInstance3D", true, false):
			if mesh_value is MeshInstance3D and (mesh_value as MeshInstance3D).mesh != null:
				visible_meshes += 1
		if not _need(visible_meshes >= 1, "fixture has no real mesh for %s" % part_id):
			root.free()
			_clear_predelete_marker()
			return false
		for socket_value in entry.get("sockets", []) as Array:
			var socket_entry: Dictionary = socket_value
			var socket_name: String = String(socket_entry.get("name", ""))
			var matches: Array[Node3D] = []
			_collect_named_node3d(root, socket_name, matches)
			if not _need(matches.size() == 1, "fixture socket count != 1 for %s.%s" % [part_id, socket_name]):
				root.free()
				_clear_predelete_marker()
				return false
			var actual: Transform3D = _transform_to_ancestor(matches[0], root)
			var position_value: Array = socket_entry.get("position_m", []) as Array
			var rotation_value: Array = socket_entry.get("rotation_deg", []) as Array
			var expected_transform := Transform3D(
				Basis.from_euler(Vector3(deg_to_rad(float(rotation_value[0])), deg_to_rad(float(rotation_value[1])), deg_to_rad(float(rotation_value[2])))),
				Vector3(float(position_value[0]), float(position_value[1]), float(position_value[2]))
			)
			if not _need(actual.origin.distance_to(expected_transform.origin) <= 0.001, "fixture socket position drift for %s.%s" % [part_id, socket_name]):
				root.free()
				_clear_predelete_marker()
				return false
			var angle: float = actual.basis.get_rotation_quaternion().angle_to(expected_transform.basis.get_rotation_quaternion())
			if not _need(angle <= deg_to_rad(0.1), "fixture socket rotation drift for %s.%s" % [part_id, socket_name]):
				root.free()
				_clear_predelete_marker()
				return false
		root.free()
		_clear_predelete_marker()
	return true

func _collect_named_node3d(node: Node, target_name: String, matches: Array[Node3D]) -> void:
	if node is Node3D and String(node.name) == target_name:
		matches.append(node as Node3D)
	for child in node.get_children():
		_collect_named_node3d(child, target_name, matches)

func _transform_to_ancestor(node: Node3D, ancestor: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var cursor: Node = node
	while cursor != ancestor:
		if cursor == null or not cursor is Node3D:
			return Transform3D.IDENTITY
		result = (cursor as Node3D).transform * result
		cursor = cursor.get_parent()
	return result

func _diagnostics_contain(diagnostics: PackedStringArray, needle: String) -> bool:
	for diagnostic in diagnostics:
		if String(diagnostic).contains(needle):
			return true
	return false

func _clear_predelete_marker() -> void:
	for path in [PREDELETE_MARKER, PREDELETE_MARKER + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _predelete_marker_exists() -> bool:
	return FileAccess.file_exists(PREDELETE_MARKER)

# ---------------------------------------------------------------------------
# Factory malformed-socket probe (R9). Build a part entry whose sockets list
# contains a malformed entry (non-array position_m); factory must return
# null and leave immediate OBJECT_NODE_COUNT unchanged.
# ---------------------------------------------------------------------------

func _factory_malformed_socket_probe() -> bool:
	var entry: Dictionary = {
		"category": "biomass_limb",
		"species_tags": ["human"],
		"assembly_roles": ["locomotor"],
		"wrapper_scene_path": "",
		"triangle_budget": 2500,
		"sockets": [
			{
				"name": "socket_root_0",
				"kind": "root",
				"accepts_categories": [],
				"position_m": "not-an-array",
				"rotation_deg": [0, 0, 0],
			},
		],
		"collision_shapes": [],
		"fallback": {
			"primitive": "capsule",
			"dimensions_m": [0.24, 0.24, 1.0],
			"albedo": "#8b5252",
		},
	}
	var before: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var node: Variant = FactoryScript.build("biomass_malformed_v1", entry)
	if not _need(node == null, "factory accepted malformed socket"):
		return false
	var after: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	if not _need(after == before, "factory leaked nodes for malformed socket: %d -> %d" % [before, after]):
		return false
	return true

# ---------------------------------------------------------------------------
# Wrong-script parts probe (R2). Pass valid recipe + a wrong-script Object
# (BiomassThreatVisualScript.new()) as parts. The current code calls
# parts.get_part() before script validation, producing SCRIPT ERROR.
# Required: build returns null, stable sorted diagnostics, zero SCRIPT ERROR.
# ---------------------------------------------------------------------------

func _wrong_script_parts_probe(parts: Variant, library: Variant) -> bool:
	var wrong_parts: Object = VisualScript.new()
	var assembler: Variant = AssemblerScript.new()
	var first: Variant = assembler.build(library.get_recipe("biped_puppet_v1"), wrong_parts)
	if not _need(first == null, "wrong-script parts was accepted"):
		return false
	var first_diag: PackedStringArray = assembler.last_diagnostics()
	if not _need(not first_diag.is_empty(), "wrong-script parts produced empty diagnostics"):
		return false
	var second: Variant = assembler.build(library.get_recipe("biped_puppet_v1"), wrong_parts)
	if not _need(second == null, "wrong-script parts second build was non-null"):
		return false
	if not _need(first_diag == assembler.last_diagnostics(), "wrong-script parts diagnostics not stable"):
		return false
	var sorted: PackedStringArray = first_diag.duplicate()
	sorted.sort()
	if not _need(first_diag == sorted, "wrong-script parts diagnostics not sorted"):
		return false
	var seen: Dictionary = {}
	for d in first_diag:
		if seen.has(d):
			wrong_parts.free()
			return _fail_with("wrong-script parts diagnostics not deduplicated")
		seen[d] = true
	wrong_parts.free()
	return true

# ---------------------------------------------------------------------------
# Node-overflow fixture probe (R7). Fixture catalog's cephalopod_tentacle has
# a wrapper with many benign descendants so a small BiomassRecipe-valid
# recipe's actual subtree exceeds 160 nodes. Build must return null with
# stable node-limit diagnostic and immediate OBJECT_NODE_COUNT equality.
# ---------------------------------------------------------------------------

func _node_overflow_fixture_probe(parts: Variant) -> bool:
	var fixture_parts: Variant = PartCatalogScript.new()
	if not fixture_parts.load_path(INVALID_PARTS_PATH):
		return _fail_with("fixture catalog did not load for node overflow probe")
	var recipe_doc: Dictionary = {
		"recipe_id": "node_overflow_probe_v1",
		"locomotion_hint": "drag",
		"core": {"instance_id": "core", "part_id": "biomass_humanoid_torso_v1"},
		"attachments": [
			{
				"instance_id": "tentacle",
				"part_id": "biomass_cephalopod_tentacle_v1",
				"parent_instance_id": "core",
				"parent_socket": "limb_0",
				"child_socket": "root_0",
				"connector_part_id": "biomass_gunk_connector_v1",
			},
		],
	}
	var recipe: Variant = RecipeScript.from_dict(recipe_doc, fixture_parts)
	if not _need(recipe != null and recipe.is_valid(), "node-overflow probe recipe was invalid: " + str(recipe.diagnostics())):
		return false
	var assembler: Variant = AssemblerScript.new()
	_clear_predelete_marker()
	var before: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var visual: Variant = assembler.build(recipe, fixture_parts)
	var after: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	if not _need(visual == null, "node-overflow build returned non-null"):
		return false
	if not _need(after == before, "node-overflow build left nodes: %d -> %d" % [before, after]):
		return false
	var diag: PackedStringArray = assembler.last_diagnostics()
	if not _need(_diagnostics_contain(diag, "runtime node limit exceeded"), "node-overflow did not reach node limit: %s" % diag):
		return false
	if not _need(_predelete_marker_exists(), "node-overflow outer visual was not freed synchronously"):
		return false
	_clear_predelete_marker()
	var second: Variant = assembler.build(recipe, fixture_parts)
	if not _need(second == null, "node-overflow second build was non-null"):
		return false
	if not _need(assembler.last_diagnostics() == diag, "node-overflow diagnostics not stable"):
		return false
	return true

# ---------------------------------------------------------------------------
# Triangle overflow fixture probe (R8). Canonical biped recipe from canonical
# library + fixture parts (arms=9000) recompute >30000. Build must return
# null with stable diagnostics and immediate OBJECT_NODE_COUNT equality.
# ---------------------------------------------------------------------------

func _triangle_overflow_fixture_probe(parts: Variant, library: Variant) -> bool:
	var fixture_parts: Variant = PartCatalogScript.new()
	if not fixture_parts.load_path(INVALID_PARTS_PATH):
		return _fail_with("fixture catalog did not load for triangle overflow probe")
	var recipe_doc: Dictionary = {
		"recipe_id": "triangle_overflow_probe_v1",
		"locomotion_hint": "crawl",
		"core": {"instance_id": "core", "part_id": "biomass_humanoid_torso_v1"},
		"attachments": [
			{"instance_id": "arm_0", "part_id": "biomass_human_arm_v1", "parent_instance_id": "core", "parent_socket": "limb_0", "child_socket": "root_0", "connector_part_id": "biomass_gunk_connector_v1"},
			{"instance_id": "arm_1", "part_id": "biomass_human_arm_v1", "parent_instance_id": "core", "parent_socket": "limb_1", "child_socket": "root_0", "connector_part_id": "biomass_gunk_connector_v1"},
			{"instance_id": "arm_2", "part_id": "biomass_human_arm_v1", "parent_instance_id": "core", "parent_socket": "limb_2", "child_socket": "root_0", "connector_part_id": "biomass_gunk_connector_v1"},
		],
	}
	var canonical_recipe: Variant = RecipeScript.from_dict(recipe_doc, parts)
	if not _need(canonical_recipe != null and canonical_recipe.is_valid(), "canonical triangle-overflow recipe was invalid: %s" % canonical_recipe.diagnostics()):
		return false
	var assembler: Variant = AssemblerScript.new()
	_clear_predelete_marker()
	var before: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var visual: Variant = assembler.build(canonical_recipe, fixture_parts)
	var after: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	if not _need(visual == null, "triangle-overflow build returned non-null"):
		return false
	if not _need(after == before, "triangle-overflow build left nodes: %d -> %d" % [before, after]):
		return false
	var diag: PackedStringArray = assembler.last_diagnostics()
	if not _need(_diagnostics_contain(diag, "triangle limit exceeded"), "triangle-overflow did not reach triangle limit: %s" % diag):
		return false
	if not _need(_predelete_marker_exists(), "triangle-overflow outer visual was not freed synchronously"):
		return false
	_clear_predelete_marker()
	var sorted: PackedStringArray = diag.duplicate()
	sorted.sort()
	if not _need(diag == sorted, "triangle-overflow diagnostics not sorted"):
		return false
	var seen: Dictionary = {}
	for d in diag:
		if seen.has(d):
			return _fail_with("triangle-overflow diagnostics not deduplicated")
		seen[d] = true
	var second: Variant = assembler.build(canonical_recipe, fixture_parts)
	if not _need(second == null, "triangle-overflow second build was non-null"):
		return false
	if not _need(assembler.last_diagnostics() == diag, "triangle-overflow diagnostics not stable"):
		return false
	return true

# ---------------------------------------------------------------------------
# Reset-to-assembly-rest probe (R1). Build a canonical recipe, attach to the
# scene tree, deliberately mutate every mount and part transform, then call
# visual._reset_to_assembly_rest(). Assert exact stored mount visual-local
# and part immediate-parent-local restoration. Includes a nested-wrapper
# claw child to exercise the recursive-composition path.
# ---------------------------------------------------------------------------

func _reset_to_assembly_rest_probe(parts: Variant, library: Variant) -> bool:
	var fixture_parts: Variant = PartCatalogScript.new()
	if not fixture_parts.load_path(INVALID_PARTS_PATH):
		return _fail_with("fixture catalog did not load for reset probe")
	# Build a fixture-valid biped recipe that exercises the nonidentity torso
	# root and a nested claw child under an arm's distal socket.
	var recipe_doc: Dictionary = {
		"recipe_id": "fixture_reset_probe_v1",
		"locomotion_hint": "biped",
		"core": {"instance_id": "core", "part_id": "biomass_humanoid_torso_v1"},
		"attachments": [
			{"instance_id": "arm_left", "part_id": "biomass_human_arm_v1", "parent_instance_id": "core", "parent_socket": "limb_0", "child_socket": "root_0", "connector_part_id": "biomass_gunk_connector_v1"},
			{"instance_id": "arm_right", "part_id": "biomass_human_arm_v1", "parent_instance_id": "core", "parent_socket": "limb_1", "child_socket": "root_0", "connector_part_id": "biomass_gunk_connector_v1"},
			{"instance_id": "head", "part_id": "biomass_animal_skull_v1", "parent_instance_id": "core", "parent_socket": "head_0", "child_socket": "root_0", "connector_part_id": "biomass_gunk_connector_v1"},
			{"instance_id": "claw", "part_id": "biomass_claw_v1", "parent_instance_id": "arm_left", "parent_socket": "distal_0", "child_socket": "root_0", "connector_part_id": "biomass_gunk_connector_v1"},
		],
	}
	var recipe: Variant = RecipeScript.from_dict(recipe_doc, fixture_parts)
	if not _need(recipe != null and recipe.is_valid(), "reset probe recipe was invalid: " + str(recipe.diagnostics())):
		return false
	var assembler: Variant = AssemblerScript.new()
	var visual: Variant = assembler.build(recipe, fixture_parts)
	if not _need(visual != null, "reset probe build returned null"):
		return false
	get_root().add_child(visual)
	visual.global_position = Vector3.ZERO
	await process_frame
	await physics_frame
	if not visual.has_method("_reset_to_assembly_rest"):
		visual.queue_free()
		await process_frame
		await physics_frame
		return _fail_with("BiomassThreatVisual is missing _reset_to_assembly_rest()")
	# Capture every mount's visual-local rest and every part's immediate-parent-local rest.
	var mount_baseline: Dictionary = {}
	for edge_value in recipe.to_dict().get("attachments", []) as Array:
		var edge: Dictionary = edge_value
		var instance_id: String = String(edge.get("instance_id", ""))
		var mount: Node3D = visual.attachment_mount(instance_id)
		if mount != null:
			mount_baseline[instance_id] = mount.transform
		var part_node: Node3D = visual.part(instance_id)
		if part_node != null:
			mount_baseline["part_" + instance_id] = part_node.transform
	var core_doc: Variant = recipe.to_dict().get("core")
	if core_doc is Dictionary:
		var core_id: String = String((core_doc as Dictionary).get("instance_id", ""))
		var core_part: Node3D = visual.part(core_id)
		if core_part != null:
			mount_baseline["part_" + core_id] = core_part.transform
	# Deliberately mutate every mount and part transform off rest.
	var mutated: int = 0
	for instance_id in mount_baseline.keys():
		if String(instance_id).begins_with("part_"):
			continue
		var mount: Node3D = visual.attachment_mount(instance_id)
		if mount != null:
			mount.transform = Transform3D.IDENTITY.translated(Vector3(99.0, 99.0, 99.0))
			mutated += 1
	for instance_id in mount_baseline.keys():
		if not String(instance_id).begins_with("part_"):
			continue
		var part_id_short: String = instance_id.substr(5)
		var part_node: Node3D = visual.part(part_id_short)
		if part_node != null:
			part_node.transform = Transform3D.IDENTITY.translated(Vector3(-99.0, -99.0, -99.0))
			mutated += 1
	if not _need(mutated > 0, "reset probe did not find any mounts/parts to mutate"):
		visual.queue_free()
		await process_frame
		await physics_frame
		return false
	visual._reset_to_assembly_rest()
	# Assert exact restored baselines.
	for instance_id in mount_baseline.keys():
		var baseline: Transform3D = mount_baseline[instance_id]
		if String(instance_id).begins_with("part_"):
			var part_id_short: String = instance_id.substr(5)
			var part_node: Node3D = visual.part(part_id_short)
			if not _need(part_node != null and part_node.transform == baseline, "reset did not restore part %s (got %s expected %s)" % [part_id_short, part_node.transform, baseline]):
				visual.queue_free()
				await process_frame
				await physics_frame
				return false
		else:
			var mount: Node3D = visual.attachment_mount(instance_id)
			if not _need(mount != null and mount.transform == baseline, "reset did not restore mount %s (got %s expected %s)" % [instance_id, mount.transform, baseline]):
				visual.queue_free()
				await process_frame
				await physics_frame
				return false
	visual.queue_free()
	await process_frame
	await physics_frame
	_clear_predelete_marker()
	return true

func _count_scene_nodes(node: Node) -> int:
	var total: int = 0
	for child in node.get_children():
		total += 1 + _count_scene_nodes(child)
	return total

func _need(condition: bool, message: String) -> bool:
	if condition:
		return true
	print("BIOMASS ASSEMBLY FAIL: %s" % message)
	quit(1)
	return false

func _fail_with(message: String) -> bool:
	print("BIOMASS ASSEMBLY FAIL: %s" % message)
	quit(1)
	return false