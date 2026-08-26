extends SceneTree

const MapperScript := preload("res://scripts/procgen/procgen_bundle_mapper.gd")

func _init() -> void:
	var mapper: RefCounted = MapperScript.new()
	var failures: Array[String] = []
	for condition in ["intact", "damaged", "fractured"]:
		var ship: Dictionary = {"generator_version": 2, "seed": 42, "archetype_id": "shuttle", "template_id": "fixture", "intactness": 9500 if condition == "intact" else 6000, "cause_of_loss": "ReactorBreach" if condition != "intact" else "None", "topology": {"rooms": [{"id": 1, "role": "CrewQuarters", "deck": 0, "cells": [{"deck": 0, "x": 0, "y": 0}]}], "portals": [], "verticals": []}, "plan": {"occupancy": {"0|0|0": {"cell": {"deck": 0, "x": 0, "y": 0}, "room_id": 1, "module_id": "floor_1x1", "variant": "Intact"}}, "edges": {}, "placements": [], "floor_placements": [], "ceiling_placements": [], "socket_bindings": [], "errors": []}, "entry_room": 1, "goal_room": 1, "critical_path": [], "fractured": condition == "fractured"}
		var cell: Dictionary = {"deck": 0, "x": 0, "y": 0}
		var mission: Dictionary = {
			"schema_version": "site-mission-1", "mission_id": "fixture",
			"start_node": "start", "required_objectives": ["objective:0"],
			"extraction_node": "extraction",
			"nodes": [
				{"id":"start", "kind":"start", "room":1, "cell":cell, "key_id":null, "repair_id":null},
				{"id":"objective:0", "kind":"objective", "room":1, "cell":cell, "key_id":null, "repair_id":null},
				{"id":"extraction", "kind":"extraction", "room":1, "cell":cell, "key_id":null, "repair_id":null},
			],
			"edges": [{"from":"start", "to":"objective:0"}, {"from":"objective:0", "to":"extraction"}],
			"gates": [],
		}
		var site_ir: Dictionary = {
			"schema_version": "site-ir-2", "ship": ship, "mission_graph": mission,
			"navigation": {"schema_version":"site-navigation-1", "nodes":[{"room":1}], "edges":[]},
			"functional_props": [
				{"id":"prop:objective:0", "kind":"objective_console", "room":1, "anchor":cell, "approach":cell, "mission_node_id":"objective:0", "key_id":null, "repair_id":null, "extraction_portal_ref":null},
				{"id":"prop:extraction", "kind":"extraction_console", "room":1, "anchor":cell, "approach":cell, "mission_node_id":"extraction", "key_id":null, "repair_id":null, "extraction_portal_ref":"fixture"},
			],
			"spatial_annotations": {"schema_version":"site-spatial-1", "rooms":[{"room":1, "minimum_clearance":1, "cover_cells":[], "los_pairs":[]}]},
		}
		var container_item: Dictionary = {
			"id": "item:container", "family_id": "tool", "rarity_id": "common",
			"socket_id": "socket_tool", "affixes": [], "stat_budget": 0,
			"economy_value": 25, "visual_tag": "item_tool",
		}
		var reward_item: Dictionary = {
			"id": "item:reward", "family_id": "weapon", "rarity_id": "common",
			"socket_id": "socket_weapon", "affixes": [], "stat_budget": 0,
			"economy_value": 60, "visual_tag": "item_weapon",
		}
		var gameplay_ir: Dictionary = {
			"schema_version": "gameplay-ir-2",
			"legacy_slice": {
				"schema_version": "1.1.0", "document_kind": "ship_gameplay_slice",
				"start_room":"crew_quarters_01", "goal_room":"crew_quarters_01",
				"critical_path":[], "fire_zones":[], "objectives":[],
				"loot_containers":[{
					"id":"container:fixture", "kind":"cargo_crate",
					"room_id":"crew_quarters_01", "approach_cell":[0, 0, 0],
					"loot_table":"worldgen_seeded",
				}],
				"summary":"fixture",
			},
			"creature_blueprints": [{"id":"creature_brute"}],
			"encounter": {
				"schema_version":"encounter-output-2", "composition_id":"composition:fixture",
				"spawns":[{
					"spawn_id":"spawn:fixture", "decision_id":"decision:fixture",
					"reward_source_id":"reward:fixture", "room":1, "cell":cell,
					"blueprint_id":"creature_brute", "faction_id":"faction:derelict",
					"threat_role":"bruiser", "ability_id":"ability:slam",
					"threat_cost":100, "performance_cost":50, "reward_value":60,
				}],
			},
			"items": [container_item, reward_item],
			"drops": [
				{"item_id":"item:container", "source_id":"container:fixture", "frequency_bp":7000},
				{"item_id":"item:reward", "source_id":"reward:fixture", "frequency_bp":3500},
			],
			"decisions": [{"decision_id":"decision:fixture"}],
		}
		var presentation_ir: Dictionary = {
			"schema_version":"presentation-ir-2",
			"instructions":[
				{"subject_id":"environment:ambient", "asset_ids":["ambient:default"], "adapter_binding_ids":["binding:ambient:default"]},
				{"subject_id":"ship:structural", "asset_ids":["ship:default"], "adapter_binding_ids":["binding:ship:default"]},
				{"subject_id":"creature:creature_brute", "asset_ids":["creature:brute"], "adapter_binding_ids":["binding:threat:brute"]},
				{"subject_id":"item:item:container", "asset_ids":["item:tool"], "adapter_binding_ids":["binding:item:tool"]},
				{"subject_id":"item:item:reward", "asset_ids":["item:weapon"], "adapter_binding_ids":["binding:item:weapon"]},
			],
			"decisions":[], "repairs":[], "fallback_subjects":[],
		}
		var bundle: Dictionary = {
			"site_ir": site_ir,
			"gameplay_ir": gameplay_ir,
			"presentation_ir": presentation_ir,
			"request": {
				"schema_version":"procgen-request-2", "difficulty_id":"standard",
				"site":{"kit_id":"ship_structural_v0"},
			},
		}
		var docs: Dictionary = mapper.map_to_loader_documents(bundle)
		if docs.is_empty() or str((docs.layout.rooms[0] as Dictionary).get("room_role", "")) != "crew_quarters": failures.append("role_%s" % condition)
		if str((docs.layout.generator as Dictionary).get("cause_of_loss", "")) != str(ship.cause_of_loss): failures.append("cause_%s" % condition)
		if str(docs.get("kit_id", "")) != "ship_structural_v0" or str(docs.layout.get("kit_id", "")) != "ship_structural_v0": failures.append("request_kit_%s" % condition)
		if docs.gameplay_slice.get("document_kind", "") != "ship_gameplay_slice": failures.append("gameplay_%s" % condition)
		if (docs.gameplay_slice.get("objectives", []) as Array).size() != 2: failures.append("site_objectives_%s" % condition)
		if str((docs.get("site_ir", {}) as Dictionary).get("schema_version", "")) != "site-ir-2": failures.append("site_ir_%s" % condition)
		var encounters: Array = docs.layout.get("encounters", [])
		if encounters.size() != 1 or str((encounters[0] as Dictionary).get("spawn_id", "")) != "spawn:fixture": failures.append("encounter_%s" % condition)
		elif str((encounters[0] as Dictionary).get("encounter_kind", "")) != "creature_brute" \
				or ((encounters[0] as Dictionary).get("generated_items", []) as Array).size() != 1: failures.append("encounter_projection_%s" % condition)
		var containers: Array = docs.gameplay_slice.get("loot_containers", [])
		if containers.size() != 1 or ((containers[0] as Dictionary).get("generated_items", []) as Array).size() != 1: failures.append("container_projection_%s" % condition)
		elif str((((containers[0] as Dictionary).get("generated_items", []) as Array)[0] as Dictionary).get("item_id", "")) != "item:container": failures.append("container_item_%s" % condition)
		if str((docs.layout.get("presentation_assembly", {}) as Dictionary).get("schema_version", "")) != "presentation-ir-2": failures.append("presentation_%s" % condition)
	if not failures.is_empty():
		for failure in failures: print("TASK5 MAPPER FAIL:%s" % failure)
		quit(1); return
	print("TASK5 MAPPER PASS intact=true damaged=true fractured=true site_projection=true")
	quit(0)
