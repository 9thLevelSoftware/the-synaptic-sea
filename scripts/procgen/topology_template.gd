extends RefCounted
class_name TopologyTemplate

# Data class representing a ship topology template. Templates define the
# macro shape of a ship as named zones connected by a topology graph.
# Each zone has a role pool, room count range, position hints, and deck
# assignment. Templates are loaded from JSON and consumed by the
# RoomAssigner and CellLayoutEngine.

var id: String = ""
var description: String = ""
var zones: Array[Dictionary] = []
var connections: Array[Dictionary] = []
var deck_config: Dictionary = {}


static func from_dict(data: Dictionary) -> RefCounted:
	var script: GDScript = load("res://scripts/procgen/topology_template.gd")
	var template: RefCounted = script.new()
	template.id = str(data.get("id", ""))
	template.description = str(data.get("description", ""))

	var raw_zones: Variant = data.get("zones", [])
	if raw_zones is Array:
		for zone_variant in raw_zones:
			if not (zone_variant is Dictionary):
				continue
			var zone: Dictionary = zone_variant
			var parsed_zone: Dictionary = {
				"id": str(zone.get("id", "")),
				"role_pool": [],
				"count": zone.get("count", 1),
				"position_hint": str(zone.get("position_hint", "center")),
				"deck": int(zone.get("deck", 0)),
				"layout": str(zone.get("layout", "single")),
				"attach_to": str(zone.get("attach_to", "")),
			}
			var raw_pool: Variant = zone.get("role_pool", [])
			if raw_pool is Array:
				var pool: Array[String] = []
				for entry in raw_pool:
					pool.append(str(entry))
				parsed_zone["role_pool"] = pool
			template.zones.append(parsed_zone)

	var raw_connections: Variant = data.get("connections", [])
	if raw_connections is Array:
		for conn_variant in raw_connections:
			if not (conn_variant is Dictionary):
				continue
			var conn: Dictionary = conn_variant
			template.connections.append({
				"from": str(conn.get("from", "")),
				"to": str(conn.get("to", "")),
				"distribution": str(conn.get("distribution", "adjacent")),
			})

	var raw_deck: Variant = data.get("deck_config", {})
	if raw_deck is Dictionary:
		template.deck_config = {
			"max_decks": int(raw_deck.get("max_decks", 1)),
			"vertical_transition_probability": float(raw_deck.get("vertical_transition_probability", 0.0)),
		}

	return template


func get_zone(zone_id: String) -> Dictionary:
	for zone in zones:
		if str(zone.get("id", "")) == zone_id:
			return zone
	return {}


func get_zones_attached_to(parent_zone_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for zone in zones:
		if str(zone.get("attach_to", "")) == parent_zone_id:
			result.append(zone)
	return result
