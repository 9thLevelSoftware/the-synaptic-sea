extends SceneTree

const FactoryScript := preload("res://scripts/procgen/readability_prop_factory.gd")

var finished: bool = false
var created_nodes: Array[Node3D] = []

func _initialize() -> void:
	var checks: Array[Dictionary] = [
		{"name": "ObjectiveAffordance_01_ObjectiveSupplyCache", "node": FactoryScript.create_objective_prop(1, "recover_supplies"), "kind": "ObjectiveSupplyCache"},
		{"name": "ObjectiveAffordance_02_ObjectiveBreakerPanel", "node": FactoryScript.create_objective_prop(2, "restore_systems"), "kind": "ObjectiveBreakerPanel"},
		{"name": "ObjectiveAffordance_03_ObjectiveMedTerminal", "node": FactoryScript.create_objective_prop(3, "download_logs"), "kind": "ObjectiveMedTerminal"},
		{"name": "ObjectiveAffordance_04_ObjectiveReactorConsole", "node": FactoryScript.create_objective_prop(4, "stabilize_reactor"), "kind": "ObjectiveReactorConsole"},
		{"name": "BlockedAffordance_01_BlockedBiomatter", "node": FactoryScript.create_blocked_biomatter(), "kind": "BlockedBiomatter"},
		{"name": "VerticalAffordance_01_RampCue", "node": FactoryScript.create_ramp_cue(), "kind": "RampCue"},
		{"name": "EntryBeacon", "node": FactoryScript.create_entry_beacon(), "kind": "EntryBeacon"},
		{"name": "DestinationReactorCore", "node": FactoryScript.create_destination_reactor_core(), "kind": "DestinationReactorCore"},
	]
	for check in checks:
		var check_node: Node3D = check["node"]
		if check_node != null and is_instance_valid(check_node):
			created_nodes.append(check_node)
		_validate_prop(check_node, str(check["name"]), str(check["kind"]))
		if finished:
			_free_created_nodes()
			return
	var cue: Node3D = FactoryScript.create_route_cue(1, Vector3.ZERO, Vector3(4.0, 0.0, 0.0))
	if cue != null and is_instance_valid(cue):
		created_nodes.append(cue)
	_validate_prop(cue, "RouteCue_01", "RouteCue")
	if finished:
		_free_created_nodes()
		return
	finished = true
	_free_created_nodes()
	print("READABILITY PROP FACTORY PASS props=9")
	quit(0)

func _free_created_nodes() -> void:
	for node in created_nodes:
		if node != null and is_instance_valid(node):
			node.free()
	created_nodes.clear()

func _validate_prop(node: Node3D, expected_name: String, expected_kind: String) -> void:
	if node == null:
		_fail("node null for %s" % expected_name)
		return
	if node.name != expected_name:
		_fail("name mismatch expected=%s actual=%s" % [expected_name, node.name])
		return
	if str(node.get_meta("readability_kind", "")) != expected_kind:
		_fail("kind mismatch expected=%s actual=%s" % [expected_kind, str(node.get_meta("readability_kind", ""))])
		return
	if node.get_child_count() <= 0:
		_fail("prop has no children name=%s" % node.name)
		return
	# Stricter visual assertion: require at least one MeshInstance3D child.
	# OmniLight3D / Marker3D may exist as optional accents but must NOT
	# satisfy this check on their own.
	var mesh_count: int = 0
	for child in node.get_children():
		if child is MeshInstance3D:
			mesh_count += 1
	if mesh_count <= 0:
		_fail("prop lacks MeshInstance3D child name=%s" % node.name)

func _fail(reason: String) -> void:
	if finished:
		return
	finished = true
	_free_created_nodes()
	push_error("READABILITY PROP FACTORY FAIL reason=%s" % reason)
	quit(1)