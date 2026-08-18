extends Node2D
class_name TopDownInteractor
## 2D raycast equivalent of the 3D interaction system.
## Handles player interaction with doors, containers, and NPCs in top-down view.

signal interaction_detected(target: Node2D)
signal interaction_cleared()

const INTERACT_RANGE: float = 64.0  # pixels (1.33 tiles at 48px)

var owner_node: Node2D
var _current_target: Node2D = null


func _ready() -> void:
	set_physics_process(true)


func _physics_process(_delta: float) -> void:
	_update_interaction_target()


func set_owner(node: Node2D) -> void:
	owner_node = node


func try_interact() -> Node2D:
	if _current_target != null:
		if _current_target.has_method("on_interact"):
			_current_target.on_interact(owner_node)
		return _current_target
	return null


func get_current_target() -> Node2D:
	return _current_target


func _update_interaction_target() -> void:
	if owner_node == null:
		return
	var space := get_world_2d().direct_space_state
	if space == null:
		return

	var query := PhysicsPointQueryParameters2D.new()
	query.position = owner_node.global_position
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var results := space.intersect_point(query, 32)

	var closest: Node2D = null
	var closest_dist := INTERACT_RANGE
	for hit in results:
		var collider = hit.get("collider")
		if collider == null or collider == owner_node:
			continue
		if collider.has_method("is_interactable") and not collider.is_interactable():
			continue
		var dist: float = owner_node.global_position.distance_to(collider.global_position)
		if dist < closest_dist:
			closest_dist = dist
			closest = collider

	if closest != _current_target:
		_current_target = closest
		if _current_target != null:
			interaction_detected.emit(_current_target)
		else:
			interaction_cleared.emit()
