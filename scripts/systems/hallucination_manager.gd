extends Node3D
class_name HallucinationManager

## Scene driver for sanity hallucinations. Renders the HallucinationDirector's active
## events. THIS TASK: the phantom-threat channel only (HUD/ambient/FX added in Task 5).
## Phantoms are this node's OWN children, never in ThreatManager — real combat math is
## untouched. Phantoms deal no damage; they dissipate on attack or melee proximity.

const ThreatPlaceholderRendererScript := preload("res://scripts/tools/threat_placeholder_renderer.gd")

var director  # HallucinationDirector
var melee_range: float = 1.2
var _phantom_nodes: Dictionary = {}   # event_id (int) -> Node3D
const PHANTOM_ARCHETYPE := "stalker"  # neutral phantom look; deterministic, no real id leak

func configure(p_director) -> void:
	director = p_director

func render(delta: float, player_position: Vector3) -> void:
	if director == null:
		clear_all()
		return
	var events: Array = director.get_active_events("phantom")
	var live_ids: Dictionary = {}
	for e in events:
		var id: int = int(e["id"])
		live_ids[id] = true
		if not _phantom_nodes.has(id):
			var pos: Vector3 = e["position"]
			var node := ThreatPlaceholderRendererScript.build_placeholder(PHANTOM_ARCHETYPE, ["phantom"], pos)
			node.name = "Phantom_%d" % id
			node.set_meta("is_phantom", true)
			add_child(node)
			_phantom_nodes[id] = node
	# Free phantom nodes whose event expired.
	for id in _phantom_nodes.keys():
		if not live_ids.has(id):
			_free_phantom(id)
	# Dissipate phantoms the player has walked into.
	for id in _phantom_nodes.keys():
		var n = _phantom_nodes[id]
		if is_instance_valid(n) and (n as Node3D).global_position.distance_to(player_position) <= melee_range:
			_free_phantom(id)

## Vanish the nearest phantom within attack_range; returns whether one was dissipated.
func dissipate_phantom_in_range(player_position: Vector3, attack_range: float = 1.6) -> bool:
	var best_id: int = -1
	var best_d: float = attack_range
	for id in _phantom_nodes.keys():
		var n = _phantom_nodes[id]
		if not is_instance_valid(n):
			continue
		var d: float = (n as Node3D).global_position.distance_to(player_position)
		if d <= best_d:
			best_d = d
			best_id = id
	if best_id >= 0:
		_free_phantom(best_id)
		return true
	return false

func phantom_count() -> int:
	var n: int = 0
	for id in _phantom_nodes.keys():
		if is_instance_valid(_phantom_nodes[id]):
			n += 1
	return n

func clear_all() -> void:
	for id in _phantom_nodes.keys():
		_free_phantom(id)
	_phantom_nodes.clear()

func _free_phantom(id: int) -> void:
	var n = _phantom_nodes.get(id, null)
	if n != null and is_instance_valid(n):
		if n.get_parent() != null:
			n.get_parent().remove_child(n)
		n.queue_free()
	_phantom_nodes.erase(id)
