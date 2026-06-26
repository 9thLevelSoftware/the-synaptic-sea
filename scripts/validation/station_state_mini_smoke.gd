extends SceneTree

const StationStateScript := preload("res://scripts/systems/station_state.gd")

func _initialize() -> void:
	var station = StationStateScript.new()
	station.configure({"station_kind": "fabricator", "level": 1, "powered": true})
	print("STATION MINI PASS kind=%s" % station.station_kind)
	quit()
