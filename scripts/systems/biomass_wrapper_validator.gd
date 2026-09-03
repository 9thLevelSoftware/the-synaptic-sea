extends RefCounted
class_name BiomassWrapperValidator

## Godot-owned biomass wrapper authority validator.
##
## Mesh/visual content may be supplied by a wrapper, but socket nodes and their
## transforms are repository-owned. This validator is intentionally independent
## of the assembler so it can validate both factory placeholders and PackedScene
## wrappers before either is retained by a live assembly.

const VisualScript: GDScript = preload("res://scripts/threats/biomass_threat_visual.gd")
const RecipeScript: GDScript = preload("res://scripts/systems/biomass_recipe.gd")
const PartCatalogScript: GDScript = preload("res://scripts/systems/biomass_part_catalog.gd")

const CONNECTOR_PART_ID: String = "biomass_gunk_connector_v1"
const POSITION_EPSILON: float = 0.001
const ROTATION_EPSILON: float = deg_to_rad(0.1)
const SCALE_EPSILON: float = 0.0001
const ORTHONORMAL_EPSILON: float = 0.0001
const FORBIDDEN_SOCKET_CHILD_TYPES: Array[StringName] = [
	&"MeshInstance3D",
	&"CollisionObject3D",
	&"CollisionShape3D",
	&"PhysicsBody3D",
]

## Validates one factory placeholder or wrapper root against its authoritative
## catalog entry. `part_id` is deliberately separate because catalog entries
## are closed dictionaries and do not carry their map key.
static func validate_part(instance: Node3D, part_id: String, entry: Dictionary) -> PackedStringArray:
	var diagnostics: Array[String] = []
	if instance == null or not is_instance_valid(instance):
		_append(diagnostics, "wrapper.part[%s]: instance must be a valid Node3D" % part_id)
		return _stable(diagnostics)
	if part_id.is_empty():
		_append(diagnostics, "wrapper.part: part_id must be a non-empty string")
	if entry.is_empty():
		_append(diagnostics, "wrapper.part[%s]: catalog entry is required" % part_id)
		return _stable(diagnostics)
	if not instance.has_meta("biomass_part_id"):
		_append(diagnostics, "wrapper.part[%s]: missing biomass_part_id metadata" % part_id)
	else:
		var actual_id: Variant = instance.get_meta("biomass_part_id")
		if (not actual_id is String and not actual_id is StringName) or String(actual_id) != part_id:
			_append(diagnostics, "wrapper.part[%s]: biomass_part_id metadata mismatch" % part_id)

	var expected_value: Variant = entry.get("sockets", null)
	if not expected_value is Array or (expected_value as Array).is_empty():
		_append(diagnostics, "wrapper.part[%s]: catalog sockets must be a non-empty array" % part_id)
		return _stable(diagnostics)
	var expected: Dictionary = {}
	for socket_value in expected_value as Array:
		if not socket_value is Dictionary:
			_append(diagnostics, "wrapper.part[%s]: catalog socket must be an object" % part_id)
			continue
		var socket: Dictionary = socket_value as Dictionary
		var name_value: Variant = socket.get("name", null)
		if not name_value is String or String(name_value).is_empty():
			_append(diagnostics, "wrapper.part[%s]: catalog socket name is invalid" % part_id)
			continue
		var name: String = String(name_value)
		if expected.has(name):
			_append(diagnostics, "wrapper.part[%s].%s: duplicate catalog socket" % [part_id, name])
			continue
		expected[name] = socket

	var named_nodes: Dictionary = {}
	_collect_socket_candidates(instance, expected, named_nodes, diagnostics, part_id)
	for socket_name in expected.keys():
		var matches: Array = named_nodes.get(socket_name, [])
		if matches.is_empty():
			_append(diagnostics, "wrapper.part[%s].%s: missing socket" % [part_id, socket_name])
			continue
		if matches.size() != 1:
			_append(diagnostics, "wrapper.part[%s].%s: duplicate socket path" % [part_id, socket_name])
			continue
		var candidate: Node = matches[0]
		if not candidate is Node3D:
			_append(diagnostics, "wrapper.part[%s].%s: socket must be Node3D" % [part_id, socket_name])
			continue
		var socket_node: Node3D = candidate as Node3D
		if _has_forbidden_socket_child(socket_node):
			_append(diagnostics, "wrapper.part[%s].%s: socket has mesh/collision/physics child" % [part_id, socket_name])
		var root_local_value: Variant = _transform_to_ancestor(socket_node, instance)
		if not root_local_value is Transform3D:
			_append(diagnostics, "wrapper.part[%s].%s: socket path does not terminate at part root" % [part_id, socket_name])
			continue
		var expected_transform_value: Variant = _catalog_transform(expected[socket_name] as Dictionary, diagnostics, part_id, socket_name)
		if not expected_transform_value is Transform3D:
			continue
		_compare_transform(
			root_local_value as Transform3D,
			expected_transform_value as Transform3D,
			"wrapper.part[%s].%s" % [part_id, socket_name],
			diagnostics,
		)
	return _stable(diagnostics)

## Validates an assembled visual against the exact preloaded production
## identities, recipe/catalog authority, every part wrapper, and every
## connector wrapper. The returned diagnostics are sorted and deduplicated.
static func validate_assembly(visual: Variant, recipe: Variant, parts: Variant) -> PackedStringArray:
	var diagnostics: Array[String] = []
	if visual == null or not visual is Object:
		_append(diagnostics, "wrapper.assembly: visual is required")
	else:
		var visual_object: Object = visual as Object
		if visual_object.get_script() != VisualScript:
			_append(diagnostics, "wrapper.assembly: visual has the wrong script identity")
	if recipe == null or not recipe is Object:
		_append(diagnostics, "wrapper.assembly: recipe is required")
	else:
		var recipe_object: Object = recipe as Object
		if recipe_object.get_script() != RecipeScript:
			_append(diagnostics, "wrapper.assembly: recipe has the wrong script identity")
	if parts == null or not parts is Object:
		_append(diagnostics, "wrapper.assembly: parts is required")
	else:
		var parts_object: Object = parts as Object
		if parts_object.get_script() != PartCatalogScript:
			_append(diagnostics, "wrapper.assembly: parts has the wrong script identity")
	if not diagnostics.is_empty():
		return _stable(diagnostics)

	var visual_object: Object = visual as Object
	var recipe_object: Object = recipe as Object
	var parts_object: Object = parts as Object
	if not bool(recipe_object.call("is_valid")):
		var recipe_diagnostics: Variant = recipe_object.call("diagnostics")
		if recipe_diagnostics is PackedStringArray:
			for diagnostic in recipe_diagnostics as PackedStringArray:
				_append(diagnostics, String(diagnostic))
		else:
			_append(diagnostics, "wrapper.assembly: recipe is invalid")
		return _stable(diagnostics)
	if not bool(visual_object.call("is_built")):
		_append(diagnostics, "wrapper.assembly: visual is not built")
		return _stable(diagnostics)
	if not visual_object.has_method("recipe_document"):
		_append(diagnostics, "wrapper.assembly: visual has no recipe_document accessor")
		return _stable(diagnostics)
	var recipe_document_value: Variant = recipe_object.call("to_dict")
	var visual_document_value: Variant = visual_object.call("recipe_document")
	if not recipe_document_value is Dictionary or not visual_document_value is Dictionary or (visual_document_value as Dictionary) != (recipe_document_value as Dictionary):
		_append(diagnostics, "wrapper.assembly: visual recipe document mismatch")
		return _stable(diagnostics)

	var expected_part_roots: Dictionary = {}
	var expected_connector_roots: Array[Node3D] = []
	var core_value: Variant = (recipe_document_value as Dictionary).get("core", null)
	if not core_value is Dictionary:
		_append(diagnostics, "wrapper.assembly: recipe core is missing")
	else:
		var core: Dictionary = core_value as Dictionary
		_validate_occurrence(visual_object, parts_object, String(core.get("instance_id", "")), String(core.get("part_id", "")), "core", expected_part_roots, diagnostics)

	var attachments_value: Variant = (recipe_document_value as Dictionary).get("attachments", null)
	if not attachments_value is Array:
		_append(diagnostics, "wrapper.assembly: recipe attachments are missing")
	else:
		for edge_value in attachments_value as Array:
			if not edge_value is Dictionary:
				_append(diagnostics, "wrapper.assembly: attachment edge is not an object")
				continue
			var edge: Dictionary = edge_value as Dictionary
			var instance_id: String = String(edge.get("instance_id", ""))
			var part_id: String = String(edge.get("part_id", ""))
			_validate_occurrence(visual_object, parts_object, instance_id, part_id, "attachment.%s" % instance_id, expected_part_roots, diagnostics)
			var mount_value: Variant = visual_object.call("attachment_mount", instance_id)
			if not mount_value is Node3D:
				_append(diagnostics, "wrapper.assembly.%s: attachment mount is missing" % instance_id)
				continue
			var connector_matches: Array[Node3D] = []
			for child in (mount_value as Node3D).get_children():
				if child is Node3D and (child as Node3D).has_meta("biomass_part_id") and String((child as Node3D).get_meta("biomass_part_id")) == CONNECTOR_PART_ID:
					connector_matches.append(child as Node3D)
			if connector_matches.size() != 1:
				_append(diagnostics, "wrapper.assembly.%s: connector wrapper count is %d" % [instance_id, connector_matches.size()])
			else:
				var connector_entry: Dictionary = parts_object.call("get_part", CONNECTOR_PART_ID)
				_append_all(diagnostics, validate_part(connector_matches[0], CONNECTOR_PART_ID, connector_entry))
				expected_connector_roots.append(connector_matches[0])

	var actual_part_roots: Array[Node3D] = []
	_collect_part_roots(visual as Node, actual_part_roots)
	for root in actual_part_roots:
		if not expected_part_roots.has(root) and not expected_connector_roots.has(root):
			_append(diagnostics, "wrapper.assembly: undeclared part wrapper '%s'" % String(root.get_meta("biomass_part_id", "")))
	return _stable(diagnostics)

static func _validate_occurrence(visual: Object, parts: Object, instance_id: String, part_id: String, label: String, expected_roots: Dictionary, diagnostics: Array[String]) -> void:
	if instance_id.is_empty() or part_id.is_empty():
		_append(diagnostics, "wrapper.assembly.%s: instance_id and part_id are required" % label)
		return
	var root_value: Variant = visual.call("part", instance_id)
	if not root_value is Node3D:
		_append(diagnostics, "wrapper.assembly.%s: part root is missing" % label)
		return
	var entry: Dictionary = parts.call("get_part", part_id)
	if entry.is_empty():
		_append(diagnostics, "wrapper.assembly.%s: catalog part '%s' is missing" % [label, part_id])
		return
	var root: Node3D = root_value as Node3D
	_append_all(diagnostics, validate_part(root, part_id, entry))
	expected_roots[root] = true

static func _collect_part_roots(node: Node, roots: Array[Node3D]) -> void:
	if node is Node3D and (node as Node3D).has_meta("biomass_part_id"):
		roots.append(node as Node3D)
	for child in node.get_children():
		_collect_part_roots(child, roots)

static func _collect_socket_candidates(node: Node, expected: Dictionary, candidates: Dictionary, diagnostics: Array[String], part_id: String) -> void:
	var node_name: String = String(node.name)
	var semantic_name: String = node_name
	if node.has_meta("biomass_socket_name"):
		var metadata_name: Variant = node.get_meta("biomass_socket_name")
		if not metadata_name is String and not metadata_name is StringName:
			_append(diagnostics, "wrapper.part[%s].%s: socket metadata is invalid" % [part_id, node_name])
		else:
			semantic_name = String(metadata_name)
			if semantic_name.is_empty():
				_append(diagnostics, "wrapper.part[%s].%s: socket metadata is invalid" % [part_id, node_name])
			if node_name.begins_with("socket_") and node_name != semantic_name:
				_append(diagnostics, "wrapper.part[%s].%s: socket metadata/name mismatch" % [part_id, node_name])
	if semantic_name.begins_with("socket_"):
		if not expected.has(semantic_name):
			_append(diagnostics, "wrapper.part[%s].%s: undeclared socket" % [part_id, semantic_name])
		else:
			var matches: Array = candidates.get(semantic_name, [])
			matches.append(node)
			candidates[semantic_name] = matches
	for child in node.get_children():
		_collect_socket_candidates(child, expected, candidates, diagnostics, part_id)

static func _has_forbidden_socket_child(socket_node: Node) -> bool:
	for child in socket_node.get_children():
		if _is_forbidden_socket_child(child) or _has_forbidden_socket_child(child):
			return true
	return false

static func _is_forbidden_socket_child(node: Node) -> bool:
	for type_name in FORBIDDEN_SOCKET_CHILD_TYPES:
		if node.is_class(type_name):
			return true
	return false

static func _catalog_transform(socket: Dictionary, diagnostics: Array[String], part_id: String, socket_name: String) -> Variant:
	var position_value: Variant = socket.get("position_m", null)
	var rotation_value: Variant = socket.get("rotation_deg", null)
	if not _finite_vector(position_value) or not _finite_vector(rotation_value):
		_append(diagnostics, "wrapper.part[%s].%s: catalog transform is nonfinite or malformed" % [part_id, socket_name])
		return null
	var position: Array = position_value as Array
	var rotation: Array = rotation_value as Array
	return Transform3D(
		Basis.from_euler(Vector3(deg_to_rad(float(rotation[0])), deg_to_rad(float(rotation[1])), deg_to_rad(float(rotation[2])))),
		Vector3(float(position[0]), float(position[1]), float(position[2])),
	)

static func _finite_vector(value: Variant) -> bool:
	if not value is Array or (value as Array).size() != 3:
		return false
	for item in value as Array:
		if (item is bool) or (item is int and not is_finite(float(item))) or (item is float and not is_finite(item)):
			return false
		if not item is int and not item is float:
			return false
	return true

static func _transform_to_ancestor(node: Node3D, ancestor: Node3D) -> Variant:
	var result: Transform3D = Transform3D.IDENTITY
	var cursor: Node = node
	while cursor != ancestor:
		if cursor == null or not cursor is Node3D:
			return null
		result = (cursor as Node3D).transform * result
		cursor = cursor.get_parent()
	return result

static func _compare_transform(actual: Transform3D, expected: Transform3D, label: String, diagnostics: Array[String]) -> void:
	if not actual.origin.is_finite() or not actual.basis.is_finite():
		_append(diagnostics, label + ": transform is nonfinite")
		return
	if actual.basis.determinant() <= 0.0 or not is_finite(actual.basis.determinant()):
		_append(diagnostics, label + ": transform orientation is invalid")
		return
	for axis in [actual.basis.x, actual.basis.y, actual.basis.z]:
		if not axis.is_finite() or absf(axis.length() - 1.0) > SCALE_EPSILON:
			_append(diagnostics, label + ": transform scale is not one")
			return
	if absf(actual.basis.x.dot(actual.basis.y)) > ORTHONORMAL_EPSILON or absf(actual.basis.x.dot(actual.basis.z)) > ORTHONORMAL_EPSILON or absf(actual.basis.y.dot(actual.basis.z)) > ORTHONORMAL_EPSILON:
		_append(diagnostics, label + ": transform basis is not orthonormal")
		return
	if actual.origin.distance_to(expected.origin) > POSITION_EPSILON:
		_append(diagnostics, label + ": transform position drift")
	var actual_rotation: Quaternion = actual.basis.get_rotation_quaternion()
	var expected_rotation: Quaternion = expected.basis.get_rotation_quaternion()
	if not actual_rotation.is_finite() or not expected_rotation.is_finite() or actual_rotation.angle_to(expected_rotation) > ROTATION_EPSILON:
		_append(diagnostics, label + ": transform rotation drift")

static func _append_all(target: Array[String], values: PackedStringArray) -> void:
	for value in values:
		_append(target, String(value))

static func _append(target: Array[String], message: String) -> void:
	if not target.has(message):
		target.append(message)

static func _stable(values: Array[String]) -> PackedStringArray:
	var sorted: Array[String] = values.duplicate()
	sorted.sort()
	var result: PackedStringArray = PackedStringArray()
	for value in sorted:
		if not result.has(value):
			result.append(value)
	return result
