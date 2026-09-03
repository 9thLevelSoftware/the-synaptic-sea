extends CharacterBody3D

## Biomass threat visual — assembled off-tree graph of primitive parts.
##
## Extends CharacterBody3D so the existing top-down LOS raycast
## (collide_with_bodies=true, mask=1) can register a hit against the outer
## body. The body does not move itself — ThreatManager copies the
## authoritative ThreatAIState.world_position into the body transform each
## frame.
##
## Composition equations (off-tree):
##   connector_to_visual = part_to_visual[parent_id] * parent_socket.transform
##                         * connector_root.transform.affine_inverse()
##   child_to_visual     = connector_to_visual * connector_socket.transform
##                         * child_root.transform.affine_inverse()
##
## Rest semantics:
##   - part rests are each part node's immediate-parent-local `.transform`
##     (visual-local for the core, mount-local for children)
##   - mount rests are visual-root-local `.transform`
##   - The separate visual-root-local `part_to_visual` map is bookkeeping for
##     collision placement and is never written to a mount-parented child's
##     `.transform`.

var _recipe_document: Dictionary = {}
var _part_nodes: Dictionary = {}
var _socket_nodes: Dictionary = {}
var _attachment_mounts: Dictionary = {}
var _part_to_visual: Dictionary = {}
var _connector_to_visual: Dictionary = {}
var _part_assembly_rest: Dictionary = {}
var _attachment_assembly_rest: Dictionary = {}
var _runtime_node_count_value: int = 0
var _triangle_budget_value: int = 0
var _is_built: bool = false

## Returns the registered part root for the given instance ID, or null when
## the ID is unknown.
func part(instance_id: String) -> Node3D:
	if not _is_built or not _part_nodes.has(instance_id):
		return null
	return _part_nodes[instance_id]

## Returns the registered socket Node3D for the given part instance and
## short socket name (e.g. `root_0`, `limb_0`), or null when unknown.
func socket(instance_id: String, socket_name: String) -> Node3D:
	if not _is_built:
		return null
	var key: String = "%s|%s" % [instance_id, socket_name]
	if not _socket_nodes.has(key):
		return null
	return _socket_nodes[key]

## Returns the attachment mount Node3D for the given instance ID, or null.
func attachment_mount(instance_id: String) -> Node3D:
	if not _is_built or not _attachment_mounts.has(instance_id):
		return null
	return _attachment_mounts[instance_id]

## Returns a defensive deep copy of the validated recipe document. Caller
## mutations of the returned value never affect the visual.
func recipe_document() -> Dictionary:
	return _recipe_document.duplicate(true)

## Returns a copy of the part node's immediate-parent-local Transform3D, or
## null when the ID is unknown.
func part_rest_transform(instance_id: String) -> Variant:
	if not _is_built or not _part_assembly_rest.has(instance_id):
		return null
	var rest: Transform3D = _part_assembly_rest[instance_id]
	return Transform3D(rest.basis, rest.origin)

## Returns a copy of the mount's visual-root-local Transform3D, or null.
func attachment_rest_transform(instance_id: String) -> Variant:
	if not _is_built or not _attachment_assembly_rest.has(instance_id):
		return null
	var rest: Transform3D = _attachment_assembly_rest[instance_id]
	return Transform3D(rest.basis, rest.origin)

## Returns the total number of nodes in the visual's subtree (root included).
func runtime_node_count() -> int:
	return _runtime_node_count_value

## Returns the catalog triangle budget total across all part occurrences.
func triangle_budget() -> int:
	return _triangle_budget_value

## Internal: stores a registered part root and its socket nodes.
func _register_part(instance_id: String, part_root: Node3D, socket_names: PackedStringArray) -> void:
	_part_nodes[instance_id] = part_root
	for socket_name in socket_names:
		var child_index: int = -1
		for index in range(part_root.get_child_count()):
			var child: Node = part_root.get_child(index)
			if child is Node3D and String(child.name) == socket_name:
				child_index = index
				break
		if child_index < 0:
			continue
		var short_name: String = socket_name.substr("socket_".length())
		var key: String = "%s|%s" % [instance_id, short_name]
		_socket_nodes[key] = part_root.get_child(child_index)

## Internal: stores an attachment mount under its instance_id.
func _register_mount(instance_id: String, mount: Node3D) -> void:
	_attachment_mounts[instance_id] = mount

## Internal: stores the visual-root-local `part_to_visual` composition value.
func _set_part_to_visual(instance_id: String, transform: Transform3D) -> void:
	_part_to_visual[instance_id] = transform

## Internal: stores the visual-root-local connector composition value.
func _set_connector_to_visual(instance_id: String, transform: Transform3D) -> void:
	_connector_to_visual[instance_id] = transform

## Internal: stores the part rest (immediate-parent-local).
func _set_part_rest(instance_id: String, transform: Transform3D) -> void:
	_part_assembly_rest[instance_id] = transform

## Internal: stores the mount rest (visual-root-local).
func _set_attachment_rest(instance_id: String, transform: Transform3D) -> void:
	_attachment_assembly_rest[instance_id] = transform

## Internal: returns the visual-root-local `part_to_visual` composition.
func _get_part_to_visual(instance_id: String) -> Transform3D:
	return _part_to_visual.get(instance_id, Transform3D.IDENTITY)

## Internal: returns the visual-root-local connector composition.
func _get_connector_to_visual(instance_id: String) -> Transform3D:
	return _connector_to_visual.get(instance_id, Transform3D.IDENTITY)

## Internal: stores the validated recipe document.
func _set_recipe_document(document: Dictionary) -> void:
	_recipe_document = document.duplicate(true)

## Internal: stores the runtime accounting values.
func _set_accounting(node_count: int, triangle_total: int) -> void:
	_runtime_node_count_value = node_count
	_triangle_budget_value = triangle_total
	_is_built = true