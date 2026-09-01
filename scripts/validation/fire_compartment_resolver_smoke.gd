extends SceneTree

const Resolver := preload("res://scripts/procgen/fire_compartment_resolver.gd")


func _initialize() -> void:
	var layouts: Array = [{"rooms": [
		{"id": "reactor_01", "room_role": "reactor"},
		{"id": "storage_01", "role": "storage"},
	]}]
	var checks := [
		Resolver.from_token("bridge") == "bridge",
		Resolver.from_token("cockpit") == "bridge",
		Resolver.from_token("engine_bay") == "engineering",
		Resolver.from_token("unknown") == "",
		Resolver.from_room_id("reactor_01", layouts) == "engineering",
		Resolver.from_room_id("storage_01", layouts) == "cargo",
		Resolver.from_zone({"to_room": "storage_01", "from_room": "reactor_01"}, layouts) == "cargo",
		Resolver.from_zone({"compartment_id": "bridge", "to_room": "storage_01"}, layouts) == "bridge",
		Resolver.from_zone({"to_room": "unknown"}, layouts) == "",
	]
	if false in checks:
		push_error("FIRE COMPARTMENT RESOLVER FAIL checks=%s" % str(checks))
		quit(1)
		return
	print("FIRE COMPARTMENT RESOLVER PASS canonical=true aliases=true rooms=true precedence=true unknown=true")
	quit(0)
