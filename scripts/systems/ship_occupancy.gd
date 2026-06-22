extends RefCounted
class_name ShipOccupancy

## Pure spatial-containment resolver: returns the ShipInstance whose world-space
## interior AABB contains the player. Entry ORDER is priority — list the host
## (home) ship first so a dock-seam overlap deterministically resolves to it.

static func resolve(player_pos: Vector3, entries: Array) -> Variant:
	for entry in entries:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var aabb = entry.get("aabb", null)
		if aabb == null or typeof(aabb) != TYPE_AABB:
			continue
		# AABB.has_point is half-open on the max face; grow a hair so a player
		# exactly on a shared seam still counts as inside.
		if (aabb as AABB).grow(0.001).has_point(player_pos):
			return entry.get("inst", null)
	return null
