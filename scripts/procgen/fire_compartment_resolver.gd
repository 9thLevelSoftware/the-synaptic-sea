extends RefCounted
class_name FireCompartmentResolver

## Single room-role vocabulary shared by the builder preview and boarded runtime.
const COMPARTMENT_FOR_ROLE := {
	"bridge": "bridge",
	"cockpit": "bridge",
	"engineering": "engineering",
	"reactor": "engineering",
	"engine_bay": "engineering",
	"hydroponics": "hydroponics",
	"cargo": "cargo",
	"storage": "cargo",
}


static func from_token(raw: String) -> String:
	var token := raw.strip_edges()
	if token.is_empty():
		return ""
	if token in COMPARTMENT_FOR_ROLE.values():
		return token
	return str(COMPARTMENT_FOR_ROLE.get(token, ""))


static func from_room_id(room_id: String, layout_sources: Array) -> String:
	var token := room_id.strip_edges()
	if token.is_empty():
		return ""
	for layout_variant in layout_sources:
		if not (layout_variant is Dictionary):
			continue
		var rooms_variant: Variant = (layout_variant as Dictionary).get("rooms", [])
		if not (rooms_variant is Array):
			continue
		for room_variant in rooms_variant:
			if not (room_variant is Dictionary):
				continue
			var room: Dictionary = room_variant
			if str(room.get("id", "")) != token:
				continue
			return from_token(str(room.get("room_role", room.get("role", ""))))
	return ""


static func from_zone(zone: Dictionary, layout_sources: Array) -> String:
	for candidate_key in ["compartment_id", "to_room", "from_room"]:
		var candidate := str(zone.get(candidate_key, ""))
		var mapped := from_token(candidate)
		if mapped.is_empty():
			mapped = from_room_id(candidate, layout_sources)
		if not mapped.is_empty():
			return mapped
	return ""
