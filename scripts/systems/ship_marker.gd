extends RefCounted
class_name ShipMarker

## Lightweight pre-generation descriptor of a ship in Sargasso space. Pure data;
## the actual ship is materialized on demand from seed_value via ShipGenerator.

var marker_id: String = ""
var position: Vector3 = Vector3.ZERO   # y is always 0 (planar Sargasso grid)
var size_class: int = 0                # ShipBlueprint.Size
var condition: int = 1                 # ShipBlueprint.Condition
var ship_type: String = ""
var seed_value: int = 0

func to_dict() -> Dictionary:
	return {
		"marker_id": marker_id,
		"position": [position.x, position.y, position.z],
		"size_class": size_class,
		"condition": condition,
		"ship_type": ship_type,
		"seed_value": seed_value,
	}

static func from_dict(d: Dictionary):
	var m = load("res://scripts/systems/ship_marker.gd").new()
	m.marker_id = str(d.get("marker_id", ""))
	var p: Variant = d.get("position", [0.0, 0.0, 0.0])
	if typeof(p) == TYPE_ARRAY and (p as Array).size() >= 3:
		m.position = Vector3(float(p[0]), float(p[1]), float(p[2]))
	m.size_class = int(d.get("size_class", 0))
	m.condition = int(d.get("condition", 1))
	m.ship_type = str(d.get("ship_type", ""))
	m.seed_value = int(d.get("seed_value", 0))
	return m
