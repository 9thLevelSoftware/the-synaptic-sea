extends SceneTree

const MapperScript := preload("res://scripts/procgen/procgen_bundle_mapper.gd")

func _init() -> void:
	var mapper: RefCounted = MapperScript.new()
	var failures: Array[String] = []
	for condition in ["intact", "damaged", "fractured"]:
		var ship: Dictionary = {"generator_version": 2, "seed": 42, "archetype_id": "shuttle", "template_id": "fixture", "intactness": 9500 if condition == "intact" else 6000, "cause_of_loss": "ReactorBreach" if condition != "intact" else "None", "topology": {"rooms": [{"id": 1, "role": "CrewQuarters", "deck": 0, "cells": [{"deck": 0, "x": 0, "y": 0}]}], "portals": [], "verticals": []}, "plan": {"occupancy": {"0|0|0": {"cell": {"deck": 0, "x": 0, "y": 0}, "room_id": 1, "module_id": "floor_1x1", "variant": "Intact"}}, "edges": {}, "placements": [], "floor_placements": [], "ceiling_placements": [], "socket_bindings": [], "errors": []}, "entry_room": 1, "goal_room": 1, "critical_path": [], "fractured": condition == "fractured"}
		var bundle: Dictionary = {"site_ir": {"schema_version": "site-ir-1", "ship": ship}, "gameplay_ir": {"legacy_slice": {"schema_version": "1.1.0", "document_kind": "ship_gameplay_slice", "objectives": []}}, "presentation_ir": {"kit_id": "ship_structural_v0"}, "request": {"difficulty_id": "standard"}}
		var docs: Dictionary = mapper.map_to_loader_documents(bundle)
		if docs.is_empty() or str((docs.layout.rooms[0] as Dictionary).get("room_role", "")) != "crew_quarters": failures.append("role_%s" % condition)
		if str((docs.layout.generator as Dictionary).get("cause_of_loss", "")) != str(ship.cause_of_loss): failures.append("cause_%s" % condition)
		if docs.gameplay_slice.get("document_kind", "") != "ship_gameplay_slice": failures.append("gameplay_%s" % condition)
	if not failures.is_empty():
		for failure in failures: print("TASK5 MAPPER FAIL:%s" % failure)
		quit(1); return
	print("TASK5 MAPPER PASS intact=true damaged=true fractured=true gameplay_verbatim=true")
	quit(0)
