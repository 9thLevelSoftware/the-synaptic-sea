extends SceneTree

## Asserts the live dead_fleet biome points at threat_drone_swarm and that
## EncounterInjector actually emits drone_swarm markers from that table
## (reads layout["encounters"], not a phantom field).
##
## Marker: ENCOUNTER TABLE DEAD FLEET PASS table=threat_drone_swarm kinds=drone_swarm markers=N

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

	# Table-covered roles for threat_drone_swarm: engineering, reactor, armory,
	# bay, hangar, engine_bay. Non-critical rooms only (injector skips critical_path).
	var rooms: Array = [
		{"id": "crit_a", "room_role": "corridor", "deck": 0, "cells": [Vector2i(0, 0)]},
		{"id": "crit_b", "room_role": "corridor", "deck": 0, "cells": [Vector2i(1, 0)]},
		{"id": "eng_room", "room_role": "engineering", "deck": 0, "cells": [Vector2i(2, 0), Vector2i(3, 0)]},
		{"id": "rx_room", "room_role": "reactor", "deck": 0, "cells": [Vector2i(4, 0), Vector2i(5, 0)]},
		{"id": "bay_room", "room_role": "bay", "deck": 0, "cells": [Vector2i(6, 0)]},
		{"id": "hangar_room", "room_role": "hangar", "deck": 0, "cells": [Vector2i(7, 0)]},
	]
	var layout_template: Dictionary = {
		"schema_version": "1.2.0",
		"document_kind": "ship_layout",
		"cell_size": 4.0,
		"rooms": rooms,
		"room_links": [],
		"critical_path": ["crit_a", "crit_b"],
	}
	var biome = BiomeProfileScript.from_dict({
		"id": "dead_fleet",
		"encounter_table_id": table_id,
		"encounter_density_modifier": 3.0,
	})
	# deep_dive density helps saturate room rolls (combined clamps at 3.0).
	var diff = DifficultyProfileScript.from_dict({
		"id": "deep_dive",
		"encounter_density_modifier": 2.5,
	})
	var injector = EncounterInjectorScript.new()

	# Sample seeds until we see at least one drone_swarm marker (determinism-safe).
	var saw_drone: bool = false
	var marker_count: int = 0
	var last_encounters: Array = []
	for probe_seed in range(1, 201):
		var layout: Dictionary = layout_template.duplicate(true)
		injector.inject(layout, biome, diff, probe_seed)
		var encounters: Array = layout.get("encounters", [])
		if typeof(encounters) != TYPE_ARRAY:
			_fail("inject did not write layout.encounters array")
			return
		last_encounters = encounters
		marker_count = encounters.size()
		for m in encounters:
			if typeof(m) != TYPE_DICTIONARY:
				continue
			if str(m.get("encounter_kind", "")) == "drone_swarm":
				saw_drone = true
				# Table id must be stamped live on markers.
				if str(m.get("encounter_table_id", "")) != table_id:
					_fail("marker encounter_table_id=%s expected %s" % [str(m.get("encounter_table_id", "")), table_id])
					return
				break
		if saw_drone:
			break

	if not saw_drone:
		_fail("200 seeds never produced drone_swarm from threat_drone_swarm (last markers=%d)" % last_encounters.size())
		return

	print("ENCOUNTER TABLE DEAD FLEET PASS table=threat_drone_swarm kinds=drone_swarm markers=%d" % marker_count)
	quit()

func _fail(reason: String) -> void:
	push_error("ENCOUNTER TABLE DEAD FLEET FAIL reason=%s" % reason)
	quit(1)
