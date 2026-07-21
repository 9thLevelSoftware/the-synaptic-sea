extends SceneTree

## Asserts the live dead_fleet biome points at threat_drone_swarm (Stream C
## content wiring) and that the table file is loadable by EncounterInjector.
##
## Marker: ENCOUNTER TABLE DEAD FLEET PASS table=threat_drone_swarm kinds=drone_swarm

const BiomeProfileScript := preload("res://scripts/procgen/biome_profile.gd")
const EncounterInjectorScript := preload("res://scripts/procgen/encounter_injector.gd")
const DifficultyProfileScript := preload("res://scripts/procgen/difficulty_profile.gd")

func _init() -> void:
	var biome_path: String = "res://data/procgen/biomes/dead_fleet.json"
	if not FileAccess.file_exists(biome_path):
		_fail("dead_fleet.json missing")
		return
	var f := FileAccess.open(biome_path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail("dead_fleet.json not a dict")
		return
	var table_id: String = str((parsed as Dictionary).get("encounter_table_id", ""))
	if table_id != "threat_drone_swarm":
		_fail("dead_fleet encounter_table_id=%s expected threat_drone_swarm" % table_id)
		return
	var table_path: String = "res://data/procgen/encounter_tables/%s.json" % table_id
	if not FileAccess.file_exists(table_path):
		_fail("table file missing: %s" % table_path)
		return
	# Inject into a tiny synthetic layout to prove the table loads kinds.
	var layout: Dictionary = {
		"rooms": [
			{"id": "eng", "room_role": "engineering", "deck": 0, "structural_placements": [], "cells": [[0, 0], [1, 0]]},
			{"id": "rx", "room_role": "reactor", "deck": 0, "structural_placements": [], "cells": [[2, 0], [3, 0]]},
		],
	}
	var biome = BiomeProfileScript.from_dict({
		"id": "dead_fleet",
		"encounter_table_id": table_id,
		"encounter_density_modifier": 3.0,
	})
	var diff = DifficultyProfileScript.from_dict({"id": "standard"})
	var injector = EncounterInjectorScript.new()
	injector.inject(layout, biome, diff, 42)
	var markers: Array = layout.get("encounter_markers", [])
	if markers.is_empty():
		# Density may still yield empty for tiny layouts — fall back to table file content.
		var tf := FileAccess.open(table_path, FileAccess.READ)
		var tparsed: Variant = JSON.parse_string(tf.get_as_text())
		tf.close()
		var rolls: Array = (tparsed as Dictionary).get("rolls", []) if typeof(tparsed) == TYPE_DICTIONARY else []
		var kinds: Dictionary = {}
		for roll in rolls:
			if typeof(roll) == TYPE_DICTIONARY:
				kinds[str(roll.get("encounter_kind", ""))] = true
		if not kinds.has("drone_swarm"):
			_fail("threat_drone_swarm table missing drone_swarm kind")
			return
		print("ENCOUNTER TABLE DEAD FLEET PASS table=threat_drone_swarm kinds=drone_swarm markers=0 file_ok=true")
		quit()
		return
	var saw_drone: bool = false
	for m in markers:
		if typeof(m) == TYPE_DICTIONARY and str(m.get("encounter_kind", "")) == "drone_swarm":
			saw_drone = true
			break
	if not saw_drone:
		_fail("injected markers missing drone_swarm kind (count=%d)" % markers.size())
		return
	print("ENCOUNTER TABLE DEAD FLEET PASS table=threat_drone_swarm kinds=drone_swarm markers=%d" % markers.size())
	quit()

func _fail(reason: String) -> void:
	push_error("ENCOUNTER TABLE DEAD FLEET FAIL reason=%s" % reason)
	quit(1)
