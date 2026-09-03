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
var _gait_controller: Variant = null
var _gait_controller_script: GDScript = null

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

## Returns whether the visual has been assembled by the assembler.
func is_built() -> bool:
	return _is_built

## Configures a gait controller for the assembled visual. The visual
## dynamically loads the controller script (no const preload) to avoid a
## dependency cycle with the gait controller. On failure, the previously
## installed controller (if any) is freed, the new candidate is freed, and
## the visual stays in exact assembly rest.
func configure_gait(parts: Variant, recipe: Variant, seed: int) -> bool:
	# Reset prior controller: free any installed, then attempt the candidate.
	if _gait_controller != null and is_instance_valid(_gait_controller):
		_gait_controller = null
	var script: GDScript = _load_gait_controller_script()
	if script == null:
		return false
	var candidate: Variant = script.new()
	if candidate == null:
		return false
	if not (candidate is Object) or not (candidate as Object).has_method("configure"):
		# Not a valid controller; let RefCounted fall out of scope.
		return false
	var configured: bool = false
	if _is_built and parts != null and recipe != null:
		# Defensive guards against malformed inputs.
		if parts is Object and (parts as Object).get_script() != null:
			var configured_call: Variant = (candidate as Object).call("configure", self, parts, recipe, seed)
			if typeof(configured_call) == TYPE_BOOL:
				configured = configured_call
	if not configured:
		# Candidate already a RefCounted — leaving it for GC is fine. Make
		# sure we did not partially wire anything in.
		return false
	_gait_controller = candidate
	return true

## Advances the gait controller by `delta` given the world-space velocity
## and AI state string. No-op when the visual has no configured controller.
func step_gait(delta: float, velocity: Variant, ai_state: String) -> void:
	if _gait_controller == null or not is_instance_valid(_gait_controller):
		return
	if not (_gait_controller as Object).has_method("step"):
		return
	(_gait_controller as Object).call("step", delta, velocity, ai_state)
	for instance_id in _driven_ids():
		var derived_value: Variant = (_gait_controller as Object).call("derived_mount_transform", instance_id)
		if derived_value is Transform3D:
			var mount: Node3D = attachment_mount(instance_id)
			if mount != null and is_instance_valid(mount):
				mount.transform = derived_value

## Returns the active gait controller (RefCounted) or null. Borrowed
## reference; caller must not free.
func gait_controller() -> Variant:
	return _gait_controller

## Returns the currently configured gait driven IDs (lex-sorted) or empty
## when no controller is active.
func _driven_ids() -> PackedStringArray:
	if _gait_controller == null or not is_instance_valid(_gait_controller):
		return PackedStringArray()
	if not (_gait_controller as Object).has_method("driven_ids"):
		return PackedStringArray()
	var value: Variant = (_gait_controller as Object).call("driven_ids")
	if value is PackedStringArray:
		return value
	if value is Array:
		var result: PackedStringArray = PackedStringArray()
		for s in value:
			result.append(String(s))
		return result
	return PackedStringArray()

## Internal: dynamically load the gait controller script to avoid the
## visual → controller dependency cycle. Cached on first successful load.
func _load_gait_controller_script() -> GDScript:
	if _gait_controller_script != null and is_instance_valid(_gait_controller_script):
		return _gait_controller_script
	var candidate: Variant = load("res://scripts/threats/biomass_gait_controller.gd")
	if candidate is GDScript:
		_gait_controller_script = candidate
		return candidate
	return null

## Internal: stores a registered part root and its socket nodes.
func _register_part(instance_id: String, part_root: Node3D, socket_names: PackedStringArray) -> void:
	_part_nodes[instance_id] = part_root
	for socket_name in socket_names:
		var matches: Array[Node3D] = []
		_collect_named_node3d(part_root, socket_name, matches)
		if matches.size() != 1:
			continue
		var short_name: String = socket_name.substr("socket_".length())
		var key: String = "%s|%s" % [instance_id, short_name]
		_socket_nodes[key] = matches[0]

func _collect_named_node3d(node: Node, target_name: String, matches: Array[Node3D]) -> void:
	if node is Node3D and String(node.name) == target_name:
		matches.append(node as Node3D)
	for child in node.get_children():
		_collect_named_node3d(child, target_name, matches)

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

## Internal: restore the immutable assembly pose. Mounts are restored before
## their child parts so parent-local part transforms are never double-applied.
func _reset_to_assembly_rest() -> void:
	for instance_id in _attachment_assembly_rest.keys():
		var mount_value: Variant = _attachment_mounts.get(instance_id, null)
		if mount_value is Node3D and is_instance_valid(mount_value):
			(mount_value as Node3D).transform = _attachment_assembly_rest[instance_id]
	for instance_id in _part_assembly_rest.keys():
		var part_value: Variant = _part_nodes.get(instance_id, null)
		if part_value is Node3D and is_instance_valid(part_value):
			(part_value as Node3D).transform = _part_assembly_rest[instance_id]

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