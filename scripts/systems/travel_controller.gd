extends RefCounted
class_name TravelController

## Validates and executes a jump to a marker, materializing the ship via the
## procgen pipeline. Pure coordinator — takes the world, a ShipGenerator, and
## operational status as inputs; mutates the world only on success.

## systems_ops: { "propulsion": bool }. radius: current scanner reach.
## Returns { success: bool, reason: String, ship: Node3D|null }.
func attempt_travel(marker, systems_ops: Dictionary, world, generator, radius: float) -> Dictionary:
	if marker == null:
		return {"success": false, "reason": "null_marker", "ship": null}
	var in_range: bool = false
	for m in world.markers_in_range(radius):
		if m.marker_id == marker.marker_id:
			in_range = true
			break
	if not in_range:
		return {"success": false, "reason": "out_of_range", "ship": null}
	if not bool(systems_ops.get("propulsion", false)):
		return {"success": false, "reason": "propulsion_offline", "ship": null}
	var ship = generator.generate_from_seed(marker.seed_value, marker.size_class, marker.condition)
	if ship == null:
		return {"success": false, "reason": "generation_failed", "ship": null}
	world.set_player_position(marker.position)
	world.mark_generated(marker.marker_id)
	return {"success": true, "reason": "ok", "ship": ship}
