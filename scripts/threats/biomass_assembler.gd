extends RefCounted

## Biomass assembler — per-manager recipe → visual graph service.
##
## Owns no Node children. `build(recipe, parts)` validates inputs against
## the pre-loaded `BiomassRecipeScript` and `BiomassPartCatalogScript`, then
## constructs one `BiomassThreatVisual` entirely off-tree, validates limits,
## and either returns the visual or returns null and records diagnostics.
##
## Diagnostics are stable, sorted, and deduplicated across repeated invalid
## builds. The assembler never mutates the input recipe or part catalog and
## never returns a partial visual.

const PartCatalogScript: GDScript = preload("res://scripts/systems/biomass_part_catalog.gd")
const RecipeScript: GDScript = preload("res://scripts/systems/biomass_recipe.gd")
const VisualScript: GDScript = preload("res://scripts/threats/biomass_threat_visual.gd")
const FactoryScript: GDScript = preload("res://scripts/tools/biomass_placeholder_factory.gd")

const CONNECTOR_PART_ID: String = "biomass_gunk_connector_v1"
const MAX_RUNTIME_NODES: int = 160
const MAX_TRIANGLES: int = 30000

var _diagnostics: PackedStringArray = PackedStringArray()
var _last_visual: CharacterBody3D = null
var _connector_entry_cache: Dictionary = {}

## Builds the visual graph for the validated recipe and returns the assembled
## `BiomassThreatVisual`, or null on failure. Inputs are deep-copied before
## use; the caller retains ownership.
func build(recipe: Variant, parts: Variant) -> Variant:
	_diagnostics = PackedStringArray()
	_last_visual = null
	_connector_entry_cache = parts.get_part(CONNECTOR_PART_ID) if (parts is Object) else {}
	if not _valid_inputs(recipe, parts):
		return null
	var recipe_document: Dictionary = (recipe as Object).to_dict()
	var visual: CharacterBody3D = VisualScript.new()
	visual.name = StringName("BiomassThreatVisual")
	visual.collision_layer = 1
	visual.collision_mask = 1
	if not _assemble_visual(visual, recipe_document, parts):
		visual.queue_free()
		_last_visual = null
		return null
	_last_visual = visual
	return visual

## Returns the diagnostics from the most recent `build()` call.
func last_diagnostics() -> PackedStringArray:
	return _stable_diagnostics(_diagnostics)

## Returns the most recent successfully built visual, or null on failure.
## The reference is borrowed; the caller owns lifetime.
func last_visual() -> CharacterBody3D:
	return _last_visual

# ---------------------------------------------------------------------------
# Input validation
# ---------------------------------------------------------------------------

func _valid_inputs(recipe: Variant, parts: Variant) -> bool:
	if recipe == null or parts == null:
		_record("assembler.build: recipe and parts are required")
		return false
	if not recipe is Object:
		_record("assembler.build: recipe must be a BiomassRecipe object")
		return false
	if (recipe as Object).get_script() != RecipeScript:
		_record("assembler.build: recipe has the wrong script identity")
		return false
	if not parts is Object or (parts as Object).get_script() != PartCatalogScript:
		_record("assembler.build: parts must be a BiomassPartCatalog object")
		return false
	# Loader-validity proxy: a loaded catalog returns a non-empty part entry.
	if (parts as Object).get_part("biomass_human_arm_v1").is_empty():
		_record("assembler.build: parts catalog is not loaded")
		return false
	if not (recipe as Object).is_valid():
		var recipe_diags: PackedStringArray = (recipe as Object).diagnostics()
		for d in recipe_diags:
			_record(d)
		return false
	return true

# ---------------------------------------------------------------------------
# Off-tree assembly
# ---------------------------------------------------------------------------

func _assemble_visual(visual: CharacterBody3D, recipe_document: Dictionary, parts: Variant) -> bool:
	var core_value: Variant = recipe_document.get("core")
	if not core_value is Dictionary:
		_record("assembler.build: missing recipe.core")
		return false
	var core: Dictionary = core_value
	var core_instance_id: String = String(core.get("instance_id", ""))
	var core_part_id: String = String(core.get("part_id", ""))
	if core_instance_id.is_empty() or core_part_id.is_empty():
		_record("assembler.build: core instance_id or part_id missing")
		return false
	var core_entry: Dictionary = parts.get_part(core_part_id)
	if core_entry.is_empty():
		_record("assembler.build: core part_id '%s' missing from catalog" % core_part_id)
		return false
	visual._set_recipe_document(recipe_document)
	visual._set_part_to_visual(core_instance_id, Transform3D.IDENTITY)
	var core_root: Node3D = _instantiate_part(core_part_id, core_entry)
	if core_root == null:
		_record("assembler.build: core part instantiation failed for %s" % core_part_id)
		return false
	visual.add_child(core_root)
	visual._register_part(core_instance_id, core_root, _socket_full_names(core_entry))
	visual._set_part_rest(core_instance_id, core_root.transform)
	var socket_to_visual_map: Dictionary = {core_instance_id: _compute_socket_to_visual_map(core_root, core_entry, Transform3D.IDENTITY)}
	var attachments_value: Variant = recipe_document.get("attachments")
	if not attachments_value is Array:
		_record("assembler.build: attachments is not an array")
		return false
	var attachments: Array = attachments_value
	for edge_value in attachments:
		if not edge_value is Dictionary:
			_record("assembler.build: attachment edge is not a dictionary")
			return false
		var edge: Dictionary = edge_value
		var instance_id: String = String(edge.get("instance_id", ""))
		var part_id: String = String(edge.get("part_id", ""))
		var parent_instance_id: String = String(edge.get("parent_instance_id", ""))
		var parent_socket_name: String = String(edge.get("parent_socket", ""))
		var child_socket_name: String = String(edge.get("child_socket", ""))
		var connector_part_id: String = String(edge.get("connector_part_id", ""))
		if instance_id.is_empty() or part_id.is_empty() or parent_instance_id.is_empty():
			_record("assembler.build: attachment edge has empty instance/parent/part fields")
			return false
		if not socket_to_visual_map.has(parent_instance_id):
			_record("assembler.build: attachment %s references unknown parent %s" % [instance_id, parent_instance_id])
			return false
		var parent_map: Dictionary = socket_to_visual_map[parent_instance_id]
		if not parent_map.has(parent_socket_name):
			_record("assembler.build: attachment %s references missing parent socket %s on %s" % [instance_id, parent_socket_name, parent_instance_id])
			return false
		if connector_part_id != CONNECTOR_PART_ID:
			_record("assembler.build: attachment %s connector must be %s" % [instance_id, CONNECTOR_PART_ID])
			return false
		var entry: Dictionary = parts.get_part(part_id)
		if entry.is_empty():
			_record("assembler.build: attachment %s part '%s' missing from catalog" % [instance_id, part_id])
			return false
		# Instantiate child under a fresh mount.
		var child_root: Node3D = _instantiate_part(part_id, entry)
		if child_root == null:
			_record("assembler.build: attachment %s instantiation failed for %s" % [instance_id, part_id])
			return false
		var child_socket_full: String = "socket_" + child_socket_name
		var child_socket_node: Node3D = _find_socket_node(child_root, child_socket_full)
		if child_socket_node == null:
			_record("assembler.build: attachment %s missing child socket %s" % [instance_id, child_socket_full])
			child_root.free()
			return false
		var parent_socket_xform: Transform3D = parent_map[parent_socket_name]
		var mount: Node3D = Node3D.new()
		mount.name = StringName("Attachment_%s" % instance_id)
		visual.add_child(mount)
		visual._register_mount(instance_id, mount)
		mount.transform = parent_socket_xform
		visual._set_attachment_rest(instance_id, parent_socket_xform)
		mount.add_child(child_root)
		child_root.transform = child_socket_node.transform.affine_inverse()
		visual._register_part(instance_id, child_root, _socket_full_names(entry))
		visual._set_part_rest(instance_id, child_root.transform)
		# Connector under the same mount, root-socket inverse.
		var connector_root: Node3D = _instantiate_part(CONNECTOR_PART_ID, _connector_entry_cache)
		if connector_root == null:
			_record("assembler.build: connector instantiation failed for %s" % instance_id)
			return false
		var connector_root_socket: Node3D = _find_socket_node(connector_root, "socket_root_0")
		if connector_root_socket == null:
			_record("assembler.build: connector missing root_0 socket")
			connector_root.free()
			return false
		mount.add_child(connector_root)
		connector_root.transform = connector_root_socket.transform.affine_inverse()
		visual._set_connector_to_visual(instance_id, mount.transform * connector_root.transform)
		visual._set_part_to_visual(instance_id, mount.transform * child_root.transform)
		socket_to_visual_map[instance_id] = _compute_socket_to_visual_map(child_root, entry, mount.transform)
	if not _add_collision_nodes(visual, recipe_document, parts):
		return false
	var node_total: int = _count_subtree(visual)
	var triangle_total: int = _compute_triangle_budget(recipe_document, parts)
	if node_total > MAX_RUNTIME_NODES:
		_record("assembler.build: runtime node limit exceeded (%d > %d)" % [node_total, MAX_RUNTIME_NODES])
		return false
	if triangle_total > MAX_TRIANGLES:
		_record("assembler.build: triangle limit exceeded (%d > %d)" % [triangle_total, MAX_TRIANGLES])
		return false
	visual._set_accounting(node_total, triangle_total)
	return true

# ---------------------------------------------------------------------------
# Collision placement
# ---------------------------------------------------------------------------

func _add_collision_nodes(visual: CharacterBody3D, recipe_document: Dictionary, parts: Variant) -> bool:
	var core_value: Variant = recipe_document.get("core")
	if not core_value is Dictionary:
		return false
	var core: Dictionary = core_value
	var core_instance_id: String = String(core.get("instance_id", ""))
	var core_part_id: String = String(core.get("part_id", ""))
	var core_entry: Dictionary = parts.get_part(core_part_id)
	if not _add_part_collision(visual, core_instance_id, core_entry):
		return false
	var attachments_value: Variant = recipe_document.get("attachments")
	if not attachments_value is Array:
		return false
	var attachments: Array = attachments_value
	for edge_value in attachments:
		var edge: Dictionary = edge_value
		var instance_id: String = String(edge.get("instance_id", ""))
		var part_id: String = String(edge.get("part_id", ""))
		var entry: Dictionary = parts.get_part(part_id)
		if not _add_part_collision(visual, instance_id, entry):
			return false
		if not _add_connector_collision(visual, instance_id):
			return false
	return true

func _add_part_collision(visual: CharacterBody3D, instance_id: String, entry: Dictionary) -> bool:
	var owner_xform: Transform3D = visual._get_part_to_visual(instance_id)
	var collisions_value: Variant = entry.get("collision_shapes", [])
	if not collisions_value is Array:
		_record("assembler.build: collision_shapes missing for %s" % instance_id)
		return false
	var collisions: Array = collisions_value
	for collision_value in collisions:
		if not collision_value is Dictionary:
			return false
		var shape_kind: String = String((collision_value as Dictionary).get("shape", ""))
		if shape_kind != "box" and shape_kind != "capsule" and shape_kind != "sphere":
			_record("assembler.build: unsupported collision shape '%s'" % shape_kind)
			return false
		var shape: Shape3D = _build_collision_shape(collision_value as Dictionary, shape_kind)
		if shape == null:
			_record("assembler.build: collision shape construction failed for %s" % instance_id)
			return false
		var shape_node: CollisionShape3D = CollisionShape3D.new()
		shape_node.name = StringName("Collision_%s" % instance_id)
		shape_node.shape = shape
		shape_node.disabled = false
		shape_node.transform = owner_xform * _descriptor_local_transform(collision_value as Dictionary)
		visual.add_child(shape_node)
	return true

func _add_connector_collision(visual: CharacterBody3D, instance_id: String) -> bool:
	if _connector_entry_cache.is_empty():
		_record("assembler.build: connector catalog entry missing")
		return false
	var owner_xform: Transform3D = visual._get_connector_to_visual(instance_id)
	var collisions_value: Variant = _connector_entry_cache.get("collision_shapes", [])
	if not collisions_value is Array:
		return false
	var collisions: Array = collisions_value
	for collision_value in collisions:
		if not collision_value is Dictionary:
			return false
		var shape_kind: String = String((collision_value as Dictionary).get("shape", ""))
		if shape_kind != "box" and shape_kind != "capsule" and shape_kind != "sphere":
			return false
		var shape: Shape3D = _build_collision_shape(collision_value as Dictionary, shape_kind)
		if shape == null:
			return false
		var shape_node: CollisionShape3D = CollisionShape3D.new()
		shape_node.name = StringName("ConnectorCollision_%s" % instance_id)
		shape_node.shape = shape
		shape_node.disabled = true
		shape_node.transform = owner_xform * _descriptor_local_transform(collision_value as Dictionary)
		visual.add_child(shape_node)
	return true

# ---------------------------------------------------------------------------
# Factory / wrapper instantiation
# ---------------------------------------------------------------------------

func _instantiate_part(part_id: String, entry: Dictionary) -> Node3D:
	var wrapper_path: String = String(entry.get("wrapper_scene_path", ""))
	if wrapper_path.is_empty():
		return FactoryScript.build(part_id, entry)
	if not ResourceLoader.exists(wrapper_path, "PackedScene"):
		_record("assembler.build: wrapper scene '%s' is not a PackedScene" % wrapper_path)
		return null
	var resource: Resource = load(wrapper_path)
	if not resource is PackedScene:
		_record("assembler.build: wrapper '%s' is not a PackedScene" % wrapper_path)
		return null
	var packed: PackedScene = resource
	var instance: Node = packed.instantiate()
	if not instance is Node3D:
		if instance != null:
			instance.free()
		_record("assembler.build: wrapper '%s' root is not Node3D" % wrapper_path)
		return null
	if _contains_forbidden_physics(instance):
		instance.free()
		_record("assembler.build: wrapper '%s' contains forbidden physics" % wrapper_path)
		return null
	if not _has_every_catalog_socket(instance as Node3D, entry):
		instance.free()
		_record("assembler.build: wrapper '%s' missing required sockets" % wrapper_path)
		return null
	return instance as Node3D

func _contains_forbidden_physics(node: Node) -> bool:
	if node is CollisionObject3D or node is CollisionShape3D:
		return true
	for child in node.get_children():
		if _contains_forbidden_physics(child):
			return true
	return false

func _has_every_catalog_socket(node: Node3D, entry: Dictionary) -> bool:
	var sockets_value: Variant = entry.get("sockets", [])
	if not sockets_value is Array:
		return false
	var expected: Dictionary = {}
	for socket_value in sockets_value:
		if not socket_value is Dictionary:
			return false
		expected[String((socket_value as Dictionary).get("name", ""))] = 0
	_collect_socket_names(node, expected)
	if expected.is_empty():
		return false
	for socket_name in expected.keys():
		if int(expected[socket_name]) != 1:
			return false
	return true

func _collect_socket_names(node: Node, expected: Dictionary) -> void:
	if expected.is_empty():
		return
	var node_name: String = String(node.name)
	for socket_name in expected.keys():
		if node_name == socket_name:
			expected[socket_name] = expected[socket_name] + 1
	for child in node.get_children():
		_collect_socket_names(child, expected)

# ---------------------------------------------------------------------------
# Geometry / transform helpers
# ---------------------------------------------------------------------------

func _find_socket_node(part_root: Node3D, full_name: String) -> Node3D:
	for child in part_root.get_children():
		if child is Node3D and String(child.name) == full_name:
			return child
	return null

func _socket_full_names(entry: Dictionary) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	var sockets_value: Variant = entry.get("sockets", [])
	if not sockets_value is Array:
		return result
	for socket_value in sockets_value:
		if not socket_value is Dictionary:
			continue
		var socket_name: String = String((socket_value as Dictionary).get("name", ""))
		if not socket_name.is_empty():
			result.append(socket_name)
	return result

func _compute_socket_to_visual_map(part_root: Node3D, entry: Dictionary, base: Transform3D) -> Dictionary:
	var result: Dictionary = {}
	var sockets_value: Variant = entry.get("sockets", [])
	if not sockets_value is Array:
		return result
	var sockets: Array = sockets_value
	for index in range(sockets.size()):
		var socket_value: Variant = sockets[index]
		if not socket_value is Dictionary:
			continue
		var socket: Dictionary = socket_value
		var socket_name: String = String(socket.get("name", ""))
		var short_name: String = socket_name.substr("socket_".length())
		var child_index: int = index + 1
		if child_index >= part_root.get_child_count():
			continue
		var socket_node_value: Variant = part_root.get_child(child_index)
		if not socket_node_value is Node3D:
			continue
		var socket_node: Node3D = socket_node_value
		result[short_name] = base * socket_node.transform
	return result

func _build_collision_shape(collision: Dictionary, shape_kind: String) -> Shape3D:
	match shape_kind:
		"box":
			var box: BoxShape3D = BoxShape3D.new()
			var dims_value: Variant = collision.get("dimensions_m", [])
			if not dims_value is Array or (dims_value as Array).size() != 3:
				return null
			var dims: Array = dims_value
			box.size = Vector3(float(dims[0]), float(dims[1]), float(dims[2]))
			return box
		"sphere":
			var sphere: SphereShape3D = SphereShape3D.new()
			sphere.radius = float(collision.get("radius_m", 0.0))
			return sphere
		"capsule":
			var capsule: CapsuleShape3D = CapsuleShape3D.new()
			capsule.radius = float(collision.get("radius_m", 0.0))
			capsule.height = float(collision.get("height_m", 0.0))
			return capsule
	return null

func _descriptor_local_transform(collision: Dictionary) -> Transform3D:
	var position_value: Variant = collision.get("position_m", [0, 0, 0])
	var rotation_value: Variant = collision.get("rotation_deg", [0, 0, 0])
	var position: Array = position_value
	var rotation: Array = rotation_value
	return Transform3D(Basis.from_euler(Vector3(deg_to_rad(float(rotation[0])), deg_to_rad(float(rotation[1])), deg_to_rad(float(rotation[2])))), Vector3(float(position[0]), float(position[1]), float(position[2])))

func _count_subtree(node: Node) -> int:
	var total: int = 1
	for child in node.get_children():
		total += _count_subtree(child)
	return total

func _compute_triangle_budget(recipe_document: Dictionary, parts: Variant) -> int:
	var total: int = 0
	var core_value: Variant = recipe_document.get("core")
	if core_value is Dictionary:
		total += int(parts.get_part(String((core_value as Dictionary).get("part_id", ""))).get("triangle_budget", 0))
	var attachments_value: Variant = recipe_document.get("attachments")
	if attachments_value is Array:
		for edge_value in attachments_value:
			if not edge_value is Dictionary:
				continue
			var edge: Dictionary = edge_value
			total += int(parts.get_part(String(edge.get("part_id", ""))).get("triangle_budget", 0))
			total += int(parts.get_part(CONNECTOR_PART_ID).get("triangle_budget", 0))
	return total

# ---------------------------------------------------------------------------
# Diagnostics
# ---------------------------------------------------------------------------

func _record(message: String) -> void:
	_diagnostics.append(message)

func _stable_diagnostics(messages: PackedStringArray) -> PackedStringArray:
	var seen: Dictionary = {}
	var unique: Array = []
	for m in messages:
		var key: String = String(m)
		if seen.has(key):
			continue
		seen[key] = true
		unique.append(key)
	unique.sort()
	var result: PackedStringArray = PackedStringArray()
	for m in unique:
		result.append(m)
	return result