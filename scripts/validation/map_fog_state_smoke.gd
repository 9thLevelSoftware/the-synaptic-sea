extends SceneTree
const MapFogStateScript := preload("res://scripts/systems/map_fog_state.gd")
func _init() -> void:
	var state = MapFogStateScript.new()
	assert(state.configure_for_rooms({"rooms": ["a", "b", "c"], "neighbours": {"a": ["b"], "b": ["a", "c"], "c": ["b"]}}))
	assert(state.track("a"))
	assert(state.is_discovered("a"))
	assert(state.reveal("b"))
	assert(state.is_revealed("b"))
	assert(state.get_tracked_room_id() == "a")
	print("MAP FOG STATE PASS rooms=3 discovered=%d revealed=%d" % [state.get_discovered_count(), state.get_revealed_count()])
	quit()
