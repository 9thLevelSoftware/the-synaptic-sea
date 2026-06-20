extends Node3D
class_name ProcgenDebugRunner

signal objective_reached(objective_id: String, sequence: int, objective_type: String, room_id: String)
signal run_completed(objective_count: int, interaction_count: int, frame_count: int, final_distance: float)
signal run_failed(reason: String)

const WALK_SPEED: float = 4.5
const DEFAULT_TIMEOUT_FRAMES: int = 9000
const TARGET_DISTANCE: float = 0.8

var marker: MeshInstance3D
var agent: NavigationAgent3D
var objective_specs: Array = []
var objective_volumes: Array = []
var start_position: Vector3 = Vector3.ZERO
var goal_position: Vector3 = Vector3.ZERO
var timeout_frames: int = DEFAULT_TIMEOUT_FRAMES
var frame_count: int = 0
var interaction_count: int = 0
var current_objective_index: int = 0
var finished: bool = false
var active_target_position: Vector3 = Vector3.INF
var walk_speed: float = WALK_SPEED


func _ready() -> void:
	_ensure_support_nodes()
	set_physics_process(true)


func start_run(start: Vector3, objectives: Array, volumes: Array, goal: Vector3, timeout := DEFAULT_TIMEOUT_FRAMES) -> void:
	_ensure_support_nodes()
	objective_specs = objectives.duplicate(true)
	objective_volumes = volumes
	start_position = start
	goal_position = goal
	timeout_frames = int(timeout)
	frame_count = 0
	interaction_count = 0
	current_objective_index = 0
	finished = false
	active_target_position = Vector3.INF
	global_position = start_position
	position = start_position
	_sync_marker()
	_connect_objective_volumes()
	_set_agent_target(_current_target_position())


func _physics_process(delta: float) -> void:
	if finished:
		return

	frame_count += 1
	if frame_count < 2:
		return

	if agent == null:
		_fail("no-agent")
		return

	var target_position: Vector3 = _current_target_position()
	if target_position == Vector3.INF:
		_fail("no-target")
		return

	_set_agent_target(target_position)
	_advance_toward_target(delta)

	var current_distance: float = global_position.distance_to(target_position)
	if current_objective_index < objective_specs.size():
		var objective_variant: Variant = objective_specs[current_objective_index]
		if typeof(objective_variant) != TYPE_DICTIONARY:
			_fail("objective-not-a-dictionary")
			return
		var objective: Dictionary = objective_variant
		var radius: float = float(objective.get("radius", 1.5))
		if current_distance <= radius:
			var objective_volume: Node = _objective_volume_for_index(current_objective_index)
			if objective_volume != null:
				objective_volume.complete()
			else:
				_on_objective_completed(
					str(objective.get("id", "<objective>")),
					int(objective.get("sequence", current_objective_index + 1)),
					str(objective.get("type", "unknown")),
					str(objective.get("room_id", "<room>"))
				)
			current_objective_index += 1
			active_target_position = Vector3.INF
			if current_objective_index < objective_specs.size():
				_set_agent_target(_current_target_position())
			else:
				_set_agent_target(goal_position)
			return
	else:
		if current_distance <= TARGET_DISTANCE:
			finished = true
			emit_signal("run_completed", current_objective_index, interaction_count, frame_count, current_distance)
			return

	if frame_count >= timeout_frames:
		_fail("timeout")


func _ensure_support_nodes() -> void:
	if marker == null:
		marker = MeshInstance3D.new()
		marker.name = "RunnerMarker"
		var capsule_mesh: CapsuleMesh = CapsuleMesh.new()
		capsule_mesh.radius = 0.35
		capsule_mesh.height = 1.4
		marker.mesh = capsule_mesh
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.albedo_color = Color(0.95, 0.68, 0.15, 1.0)
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		marker.material_override = material
		marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		marker.position = Vector3(0.0, 0.9, 0.0)
		add_child(marker)

	if agent == null:
		agent = NavigationAgent3D.new()
		agent.name = "NavigationAgent3D"
		agent.path_desired_distance = 0.35
		agent.target_desired_distance = TARGET_DISTANCE
		add_child(agent)


func _sync_marker() -> void:
	if marker != null:
		marker.position = Vector3(0.0, 0.9, 0.0)


func _connect_objective_volumes() -> void:
	for volume_variant in objective_volumes:
		if not volume_variant.has_signal("objective_completed"):
			continue
		var volume: Node = volume_variant
		if not volume.objective_completed.is_connected(_on_objective_completed):
			volume.objective_completed.connect(_on_objective_completed)


func _current_target_position() -> Vector3:
	if current_objective_index < objective_specs.size():
		var objective_variant: Variant = objective_specs[current_objective_index]
		if typeof(objective_variant) == TYPE_DICTIONARY:
			var objective: Dictionary = objective_variant
			var position_variant: Variant = objective.get("position", Vector3.INF)
			if typeof(position_variant) == TYPE_VECTOR3:
				return position_variant
	return goal_position


func _objective_volume_for_index(index: int) -> Node:
	if index < 0 or index >= objective_volumes.size():
		return null
	return objective_volumes[index]


func _set_agent_target(target_position: Vector3) -> void:
	if active_target_position == target_position:
		return
	active_target_position = target_position
	agent.target_position = target_position


func _advance_toward_target(delta: float) -> void:
	var next_position: Vector3 = agent.get_next_path_position()
	var step: Vector3 = next_position - global_position
	if step.length_squared() > 0.000001:
		global_position = global_position.move_toward(next_position, walk_speed * delta)


func _on_objective_completed(objective_id: String, sequence: int, objective_type: String, room_id: String) -> void:
	interaction_count += 1
	emit_signal("objective_reached", objective_id, sequence, objective_type, room_id)


func _fail(reason: String) -> void:
	if finished:
		return
	finished = true
	push_error("RUNTIME GAMEPLAY DEMO FAIL frames=%d interactions=%d objective_index=%d distance=%.3f reason=%s" % [frame_count, interaction_count, current_objective_index, global_position.distance_to(_current_target_position()), reason])
	emit_signal("run_failed", reason)
