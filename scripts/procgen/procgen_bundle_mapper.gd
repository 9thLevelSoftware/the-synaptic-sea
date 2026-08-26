extends RefCounted
class_name ProcgenBundleMapper

var last_error: String = ""

## Mechanical port of structural::export::to_layout_json plus a deterministic
## projection of authoritative SiteIR mission consequences into the existing
## loader documents. The mapper never selects encounters, loot, gates, or
## objectives; it only translates already validated Rust records.
func map_to_loader_documents(bundle: Dictionary) -> Dictionary:
	last_error = ""
	var site: Dictionary = bundle.get("site_ir", {})
	var gameplay_ir: Dictionary = bundle.get("gameplay_ir", {})
	var presentation: Dictionary = bundle.get("presentation_ir", {})
	var request: Dictionary = bundle.get("request", {})
	var request_site: Variant = request.get("site", null)
	var ship: Variant = site.get("ship", null)
	var gameplay: Variant = gameplay_ir.get("legacy_slice", null)
	if str(site.get("schema_version", "")) != "site-ir-2" \
			or str(gameplay_ir.get("schema_version", "")) != "gameplay-ir-3" \
			or str(presentation.get("schema_version", "")) != "presentation-ir-2" \
			or str(request.get("schema_version", "")) != "procgen-request-2" \
			or not request_site is Dictionary \
			or not ship is Dictionary or not gameplay is Dictionary \
			or not site.get("mission_graph", null) is Dictionary \
			or not site.get("navigation", null) is Dictionary \
			or not site.get("functional_props", null) is Array \
			or not site.get("spatial_annotations", null) is Dictionary:
		last_error = "migration_documents_missing"
		return {}
	var kit_id: String = str((request_site as Dictionary).get("kit_id", ""))
	if kit_id.is_empty():
		last_error = "presentation_kit_missing"
		return {}
	var presentation_index: Dictionary = _presentation_index(presentation)
	if presentation_index.is_empty():
		return {}
	var source_items: Dictionary = _source_items(gameplay_ir, presentation_index)
	if source_items.is_empty() and not (gameplay_ir.get("items", []) as Array).is_empty():
		return {}
	var layout: Dictionary = _layout(ship as Dictionary, kit_id, request)
	if layout.is_empty(): return {}
	var names: Dictionary = _room_names(ship as Dictionary)
	if not _apply_site_blocked_links(layout, site, names, (ship as Dictionary).get("plan", {})):
		return {}
	var runtime_gameplay: Dictionary = _site_gameplay_slice(gameplay as Dictionary, site, ship as Dictionary, names)
	if runtime_gameplay.is_empty(): return {}
	if not _apply_authoritative_gameplay(layout, runtime_gameplay, gameplay_ir, names, source_items, presentation_index):
		return {}
	layout["presentation_assembly"] = presentation.duplicate(true)
	return {
		"layout": layout,
		"kit_id": kit_id,
		"gameplay_slice": runtime_gameplay,
		"site_ir": site.duplicate(true),
		"gameplay_ir": gameplay_ir.duplicate(true),
		"presentation_ir": presentation.duplicate(true),
	}


func _presentation_index(presentation: Dictionary) -> Dictionary:
	var instructions: Variant = presentation.get("instructions", null)
	if not instructions is Array:
		last_error = "presentation_instruction_mapping"
		return {}
	var index: Dictionary = {}
	for instruction_value in instructions:
		if not instruction_value is Dictionary:
			last_error = "presentation_instruction_mapping"
			return {}
		var instruction: Dictionary = instruction_value
		var subject_id: String = str(instruction.get("subject_id", ""))
		var asset_ids: Variant = instruction.get("asset_ids", null)
		var binding_ids: Variant = instruction.get("adapter_binding_ids", null)
		if subject_id.is_empty() or index.has(subject_id) \
				or not asset_ids is Array or (asset_ids as Array).is_empty() \
				or not binding_ids is Array or (binding_ids as Array).is_empty():
			last_error = "presentation_instruction_mapping"
			return {}
		index[subject_id] = instruction.duplicate(true)
	# These two subjects are required by the current presentation contract even
	# when the generated gameplay happens to contain no rewards or spawns.
	if not index.has("environment:ambient") or not index.has("ship:structural"):
		last_error = "presentation_instruction_mapping"
		return {}
	return index


func _source_items(gameplay_ir: Dictionary, presentation_index: Dictionary) -> Dictionary:
	var items_value: Variant = gameplay_ir.get("items", null)
	var drops_value: Variant = gameplay_ir.get("drops", null)
	if not items_value is Array or not drops_value is Array:
		last_error = "generated_item_mapping"
		return {}
	var items: Dictionary = {}
	for item_value in items_value:
		if not item_value is Dictionary:
			last_error = "generated_item_mapping"
			return {}
		var item: Dictionary = item_value
		var item_id: String = str(item.get("id", ""))
		var subject_id: String = "item:%s" % item_id
		if item_id.is_empty() or items.has(item_id) or not presentation_index.has(subject_id):
			last_error = "generated_item_mapping"
			return {}
		items[item_id] = item
	var by_source: Dictionary = {}
	var bound_items: Dictionary = {}
	for drop_value in drops_value:
		if not drop_value is Dictionary:
			last_error = "generated_item_mapping"
			return {}
		var drop: Dictionary = drop_value
		var item_id: String = str(drop.get("item_id", ""))
		var source_id: String = str(drop.get("source_id", ""))
		if item_id.is_empty() or source_id.is_empty() or not items.has(item_id) \
				or bound_items.has(item_id):
			last_error = "generated_item_mapping"
			return {}
		bound_items[item_id] = true
		var instruction: Dictionary = presentation_index["item:%s" % item_id]
		var exact_item: Dictionary = {
			"item_id": item_id,
			"quantity": 1,
			"frequency_bp": int(drop.get("frequency_bp", 0)),
			"blueprint": (items[item_id] as Dictionary).duplicate(true),
			"asset_ids": (instruction.get("asset_ids", []) as Array).duplicate(true),
			"presentation_binding_ids": (instruction.get("adapter_binding_ids", []) as Array).duplicate(true),
		}
		if not by_source.has(source_id):
			by_source[source_id] = []
		(by_source[source_id] as Array).append(exact_item)
	if bound_items.size() != items.size():
		last_error = "generated_item_mapping"
		return {}
	return by_source


func _apply_authoritative_gameplay(
		layout: Dictionary,
		runtime_gameplay: Dictionary,
		gameplay_ir: Dictionary,
		names: Dictionary,
		source_items: Dictionary,
		presentation_index: Dictionary) -> bool:
	var encounter_value: Variant = gameplay_ir.get("encounter", null)
	var blueprints_value: Variant = gameplay_ir.get("creature_blueprints", null)
	var decisions_value: Variant = gameplay_ir.get("decisions", null)
	if not encounter_value is Dictionary or not blueprints_value is Array or not decisions_value is Array:
		last_error = "authoritative_gameplay_mapping"
		return false
	var blueprints: Dictionary = {}
	for blueprint_value in blueprints_value:
		if not blueprint_value is Dictionary:
			last_error = "authoritative_gameplay_mapping"
			return false
		var blueprint_id: String = str((blueprint_value as Dictionary).get("id", ""))
		if blueprint_id.is_empty() or blueprints.has(blueprint_id):
			last_error = "authoritative_gameplay_mapping"
			return false
		blueprints[blueprint_id] = blueprint_value
	var known_sources: Dictionary = {}
	var markers: Array = []
	var spawns_value: Variant = (encounter_value as Dictionary).get("spawns", null)
	if not spawns_value is Array:
		last_error = "encounter_mapping"
		return false
	for spawn_value in spawns_value:
		if not spawn_value is Dictionary:
			last_error = "encounter_mapping"
			return false
		var spawn: Dictionary = spawn_value
		var spawn_id: String = str(spawn.get("spawn_id", ""))
		var blueprint_id: String = str(spawn.get("blueprint_id", ""))
		var reward_source_id: String = str(spawn.get("reward_source_id", ""))
		var room_id: int = int(spawn.get("room", -1))
		var cell: Variant = spawn.get("cell", null)
		var subject_id: String = "creature:%s" % blueprint_id
		if spawn_id.is_empty() or blueprint_id.is_empty() or reward_source_id.is_empty() \
				or known_sources.has(reward_source_id) or not blueprints.has(blueprint_id) \
				or not names.has(room_id) or not cell is Dictionary \
				or not presentation_index.has(subject_id):
			last_error = "encounter_mapping"
			return false
		known_sources[reward_source_id] = true
		var instruction: Dictionary = presentation_index[subject_id]
		markers.append({
			"id": spawn_id,
			"spawn_id": spawn_id,
			"decision_id": str(spawn.get("decision_id", "")),
			"room_id": str(names[room_id]),
			"deck": _coord(cell, "deck"),
			"cell": _cell2(cell),
			"local_position": _position(cell),
			"encounter_kind": blueprint_id,
			"blueprint_id": blueprint_id,
			"creature_blueprint": (blueprints[blueprint_id] as Dictionary).duplicate(true),
			"faction_id": str(spawn.get("faction_id", "")),
			"threat_role": str(spawn.get("threat_role", "")),
			"ability_id": str(spawn.get("ability_id", "")),
			"reward_source_id": reward_source_id,
			"threat_cost": int(spawn.get("threat_cost", 0)),
			"performance_cost": int(spawn.get("performance_cost", 0)),
			"reward_value": int(spawn.get("reward_value", 0)),
			"count": 1,
			"asset_ids": (instruction.get("asset_ids", []) as Array).duplicate(true),
			"presentation_binding_ids": (instruction.get("adapter_binding_ids", []) as Array).duplicate(true),
			"generated_items": (source_items.get(reward_source_id, []) as Array).duplicate(true),
		})
	layout["encounters"] = markers
	var containers_value: Variant = runtime_gameplay.get("loot_containers", null)
	if not containers_value is Array:
		last_error = "generated_item_source_mapping"
		return false
	for container_value in containers_value:
		if not container_value is Dictionary:
			last_error = "generated_item_source_mapping"
			return false
		var container: Dictionary = container_value
		var source_id: String = str(container.get("id", ""))
		if source_id.is_empty() or known_sources.has(source_id):
			last_error = "generated_item_source_mapping"
			return false
		known_sources[source_id] = true
		container["generated_items"] = (source_items.get(source_id, []) as Array).duplicate(true)
	for source_id in source_items:
		if not known_sources.has(source_id):
			last_error = "generated_item_source_mapping"
			return false
	runtime_gameplay["creature_blueprints"] = (blueprints_value as Array).duplicate(true)
	runtime_gameplay["generated_item_blueprints"] = (gameplay_ir.get("items", []) as Array).duplicate(true)
	runtime_gameplay["gameplay_decisions"] = (decisions_value as Array).duplicate(true)
	runtime_gameplay["encounter_composition_id"] = str((encounter_value as Dictionary).get("composition_id", ""))
	return true

func _room_names(ship: Dictionary) -> Dictionary:
	var names: Dictionary = {}
	for room_value in (ship.get("topology", {}) as Dictionary).get("rooms", []):
		if not room_value is Dictionary: continue
		var room: Dictionary = room_value
		var room_id: int = int(room.get("id", -1))
		names[room_id] = "%s_%02d" % [_role_name(room.get("role", room.get("room_role", "room"))), room_id]
	return names

func _apply_site_blocked_links(layout: Dictionary, site: Dictionary, names: Dictionary, plan: Dictionary) -> bool:
	var navigation: Dictionary = site.get("navigation", {})
	var edge_index: Dictionary = {}
	for edge_value in navigation.get("edges", []):
		if edge_value is Dictionary: edge_index[str((edge_value as Dictionary).get("id", ""))] = edge_value
	var blocked: Array = []
	for gate_value in (site.get("mission_graph", {}) as Dictionary).get("gates", []):
		if not gate_value is Dictionary:
			last_error = "site_gate_mapping"
			return false
		var gate: Dictionary = gate_value
		var edge_id: String = str(gate.get("navigation_edge", ""))
		if not edge_index.has(edge_id):
			last_error = "site_gate_mapping"
			return false
		var edge: Dictionary = edge_index[edge_id]
		var reference: String = str(edge.get("structural_ref", ""))
		var structural: Dictionary = plan.get("edges", {}).get(reference, {})
		blocked.append({
			"id": str(gate.get("id", "")),
			"from_room": str(names.get(int(edge.get("from_room", -1)), "")),
			"to_room": str(names.get(int(edge.get("to_room", -1)), "")),
			"from_cell": _cell3(edge.get("from_cell", {})),
			"to_cell": _cell3(edge.get("to_cell", {})),
			"module_id": str(structural.get("module_id", "")),
			"reason": str(gate.get("kind", "")),
		})
		for portal_value in layout.get("portals", []):
			if portal_value is Dictionary and str((portal_value as Dictionary).get("edge_key", "")) == reference:
				(portal_value as Dictionary)["state"] = "LOCKED"
	layout["blocked_links"] = blocked
	return true

func _site_gameplay_slice(legacy: Dictionary, site: Dictionary, ship: Dictionary, names: Dictionary) -> Dictionary:
	var mission: Dictionary = site.get("mission_graph", {})
	var node_index: Dictionary = {}
	for node_value in mission.get("nodes", []):
		if node_value is Dictionary: node_index[str((node_value as Dictionary).get("id", ""))] = node_value
	var prop_index: Dictionary = {}
	for prop_value in site.get("functional_props", []):
		if prop_value is Dictionary: prop_index[str((prop_value as Dictionary).get("mission_node_id", ""))] = prop_value
	var roles: Dictionary = {}
	for room_value in (ship.get("topology", {}) as Dictionary).get("rooms", []):
		if room_value is Dictionary:
			roles[int((room_value as Dictionary).get("id", -1))] = _role_name((room_value as Dictionary).get("role", "room"))
	var objectives: Array = []
	var sequence: int = 1
	for node_value in mission.get("nodes", []):
		if not node_value is Dictionary: continue
		var node: Dictionary = node_value
		if str(node.get("kind", "")) == "start": continue
		var node_id: String = str(node.get("id", ""))
		if not prop_index.has(node_id):
			last_error = "site_prop_mapping"
			return {}
		var prop: Dictionary = prop_index[node_id]
		var prop_kind: String = str(prop.get("kind", ""))
		var objective_type: String = {
			"key_pickup": "recover_supplies",
			"repair_panel": "restore_systems",
			"objective_console": "download_logs",
			"extraction_console": "extract_site",
		}.get(prop_kind, "")
		var room_id: int = int(node.get("room", -1))
		if objective_type.is_empty() or not names.has(room_id):
			last_error = "site_objective_mapping"
			return {}
		objectives.append({
			"id": node_id,
			"sequence": sequence,
			"type": objective_type,
			"kind": "single",
			"room_id": str(names[room_id]),
			"room_role": str(roles.get(room_id, "room")),
			"semantic": prop_kind,
			"cell": _cell3(prop.get("anchor", {})),
			"approach_cell": _cell3(prop.get("approach", {})),
			"approach_distance_cells": 1,
			"interactable": true,
		})
		sequence += 1
	if objectives.is_empty():
		last_error = "site_objective_mapping"
		return {}
	var start_node: Dictionary = node_index.get(str(mission.get("start_node", "")), {})
	var extraction_node: Dictionary = node_index.get(str(mission.get("extraction_node", "")), {})
	if start_node.is_empty() or extraction_node.is_empty():
		last_error = "site_objective_mapping"
		return {}
	var result: Dictionary = legacy.duplicate(true)
	result["start_room"] = str(names.get(int(start_node.get("room", -1)), ""))
	result["goal_room"] = str(names.get(int(extraction_node.get("room", -1)), ""))
	result["objectives"] = objectives
	return result

func _layout(ship: Dictionary, kit_id: String, request: Dictionary) -> Dictionary:
	var topology: Dictionary = ship.get("topology", {})
	var plan: Dictionary = ship.get("plan", {})
	var vertical_cells: Dictionary = {}
	for vertical_v in topology.get("verticals", []):
		if vertical_v is Dictionary:
			vertical_cells[_cell_key((vertical_v as Dictionary).get("from_cell", {}))] = true
			vertical_cells[_cell_key((vertical_v as Dictionary).get("to_cell", {}))] = true
	var rooms: Array = []
	var names: Dictionary = {}
	for room_v in topology.get("rooms", []):
		if not room_v is Dictionary: continue
		var room: Dictionary = room_v
		var rid: int = int(room.get("id", rooms.size()))
		var role: String = _role_name(room.get("role", room.get("room_role", "room")))
		var name: String = "%s_%02d" % [role, rid]
		names[rid] = name
		var cells: Array = []
		for c in room.get("cells", []): cells.append(_cell2(c))
		var placements: Array = []
		for c in room.get("cells", []):
			var key: String = _cell_key(c)
			var occ: Dictionary = plan.get("occupancy", {}).get(key, {})
			if not occ.is_empty(): placements.append({"name": "floor_cell_x%s_z%s" % [str(_coord(c,"x")), str(_coord(c,"y"))], "module": str(occ.get("module_id", "")), "world_position": _position(c)})
		var zones: Dictionary = _interior_zones(room, plan, vertical_cells)
		rooms.append({"id": name, "room_role": role, "deck": int(room.get("deck", 0)), "cells": cells, "footprint": _footprint(cells), "structural_placements": placements, "reserved_cells": zones.get("reserved_cells", []), "wall_slots": zones.get("wall_slots", []), "center_slots": zones.get("center_slots", []), "interior_zones": zones})
	var room_links: Array = []
	var portals: Array = []
	for portal_v in topology.get("portals", []):
		if not portal_v is Dictionary: continue
		var p: Dictionary = portal_v
		if bool(p.get("exterior", false)) or int(p.get("to_room", -1)) in [-1, 0]: continue
		var from_name: String = names.get(int(p.get("from_room", -1)), "")
		var to_name: String = names.get(int(p.get("to_room", -1)), "")
		var id: String = "%s_to_%s" % [from_name, to_name]
		var from_cell: Variant = p.get("from_cell", {})
		var to_cell: Variant = p.get("to_cell", {})
		var direction: String = _direction(from_cell, to_cell)
		var edge_key: String = _edge_key(from_cell, direction)
		var rec: Dictionary = {"id": id, "from_room": from_name, "to_room": to_name, "from_cell": _cell2(from_cell), "to_cell": _cell2(to_cell), "state": str(p.get("state", "OPEN")).to_upper(), "module_id": str(plan.get("edges", {}).get(edge_key, {}).get("module_id", "")), "edge_key": edge_key, "deck": _coord(from_cell, "deck"), "direction": direction, "opposite_direction": _opposite(direction), "required": true}
		portals.append(rec)
		room_links.append({"id": id, "from_room": from_name, "to_room": to_name, "from_cell": _cell3(from_cell), "to_cell": _cell3(to_cell), "module_id": str(plan.get("edges", {}).get(edge_key, {}).get("module_id", ""))})
	var critical: Array = []
	for rid_v in ship.get("critical_path", []): critical.append(names.get(int(rid_v), str(rid_v)))
	var occupancy: Dictionary = {}
	for key in plan.get("occupancy", {}).keys():
		var occ: Dictionary = plan.occupancy[key]
		occupancy[str(key)] = {"cell_key": str(key), "deck": int(occ.get("cell", {}).get("deck", occ.get("deck", 0))), "cell": _cell2(occ.get("cell", {})), "room_id": names.get(int(occ.get("room_id", -1)), ""), "room_ids": [names.get(int(occ.get("room_id", -1)), "")], "position": occ.get("position", _position(occ.get("cell", {}))), "module_id": str(occ.get("module_id", "")), "variant": _name(occ.get("variant", "intact")), "decal": occ.get("decal", null)}
	var edges: Dictionary = {}
	for edge_key in plan.get("edges", {}).keys():
		var edge: Dictionary = plan.edges[edge_key]
		edges[str(edge_key)] = _edge(edge, names, false)
	var placements: Array = []
	for edge_v in plan.get("placements", []):
		if edge_v is Dictionary: placements.append(_edge(edge_v, names, true))
	var floor_placements: Array = []
	for floor_v in plan.get("floor_placements", []):
		if floor_v is Dictionary: floor_placements.append(_floor(floor_v, names))
	var ceiling_placements: Array = []
	for ceiling_v in plan.get("ceiling_placements", []):
		if ceiling_v is Dictionary: ceiling_placements.append(_floor(ceiling_v, names))
	var socket_bindings: Array = []
	for binding_v in plan.get("socket_bindings", []):
		if binding_v is Dictionary: socket_bindings.append((binding_v as Dictionary).duplicate(true))
	var structural: Dictionary = {"occupancy": occupancy, "edges": edges, "placements": placements, "floor_placements": floor_placements, "ceiling_placements": ceiling_placements, "socket_bindings": socket_bindings, "errors": plan.get("errors", [])}
	var vertical_connections: Array = []
	for vertical_v in topology.get("verticals", []):
		if vertical_v is Dictionary:
			var vertical: Dictionary = vertical_v
			vertical_connections.append({"id": "%s_to_%s" % [names.get(int(vertical.get("from_room", -1)), ""), names.get(int(vertical.get("to_room", -1)), "")], "type": "ladder", "module_id": "", "from_room": names.get(int(vertical.get("from_room", -1)), ""), "to_room": names.get(int(vertical.get("to_room", -1)), ""), "from_cell": _cell3(vertical.get("from_cell", {})), "to_cell": _cell3(vertical.get("to_cell", {}))})
	return {"schema_version": "1.2.0", "document_kind": "ship_layout", "program_id": "worldgen-%s-%d" % [str(ship.get("archetype_id", "")), int(ship.get("seed", 0))], "generator": {"name": "worldgen", "generator_version": int(ship.get("generator_version", 2)), "seed": int(ship.get("seed", 0)), "archetype_id": str(ship.get("archetype_id", "")), "template_id": str(ship.get("template_id", "")), "intactness_bp": int(ship.get("intactness", 0)), "cause_of_loss": str(ship.get("cause_of_loss", "Unknown")), "fractured": bool(ship.get("fractured", false))}, "cell_size": 4.0, "kit_id": kit_id, "biome_id": "", "difficulty_id": str(request.get("difficulty_id", "standard")), "hazard_source": "runtime", "rooms": rooms, "portals": portals, "room_links": room_links, "vertical_connections": vertical_connections, "critical_path": critical, "prototype": {"start_room": names.get(int(ship.get("entry_room", -1)), ""), "goal_room": names.get(int(ship.get("goal_room", -1)), "")}, "landmarks": [], "encounters": [], "blocked_links": [], "fire_zones": [], "arc_zones": [], "breach_zones": [], "structural_plan": structural}

func _coord(value: Variant, axis: String) -> int:
	if value is Dictionary: return int((value as Dictionary).get(axis, 0))
	return 0

func _cell2(value: Variant) -> Array: return [_coord(value, "x"), _coord(value, "y")]
func _cell3(value: Variant) -> Array: return [_coord(value, "x"), _coord(value, "y"), _coord(value, "deck")]
func _position(value: Variant) -> Array: return [float(_coord(value, "x")) * 4.0, float(_coord(value, "deck")) * 4.0, float(_coord(value, "y")) * 4.0]
func _cell_key(value: Variant) -> String: return "%d|%d|%d" % [_coord(value, "deck"), _coord(value, "x"), _coord(value, "y")]

func _edge_key(cell: Variant, direction: String) -> String:
	var deck: int = _coord(cell, "deck")
	var x: int = _coord(cell, "x")
	var y: int = _coord(cell, "y")
	match direction:
		"north": return "%d|h|%d|%d" % [deck, y - 1, x]
		"south": return "%d|h|%d|%d" % [deck, y, x]
		"east": return "%d|v|%d|%d" % [deck, y, x]
		"west": return "%d|v|%d|%d" % [deck, y, x - 1]
	return ""

func _interior_zones(room: Dictionary, plan: Dictionary, vertical_cells: Dictionary) -> Dictionary:
	var zones: Dictionary = {"reserved_cells": [], "wall_slots": [], "center_slots": []}
	var edges: Dictionary = plan.get("edges", {})
	for cell_v in room.get("cells", []):
		var has_wall: bool = false
		var has_door: bool = false
		for direction in ["north", "east", "south", "west"]:
			var edge: Variant = edges.get(_edge_key(cell_v, direction), null)
			if not edge is Dictionary:
				continue
			var kind: String = str((edge as Dictionary).get("kind", ""))
			if kind == "Solid": has_wall = true
			elif kind in ["Door", "Locked", "Hatch"]: has_door = true
		var cell: Array = _cell2(cell_v)
		if has_door or vertical_cells.has(_cell_key(cell_v)):
			(zones.reserved_cells as Array).append(cell)
		elif has_wall:
			(zones.wall_slots as Array).append(cell)
		else:
			(zones.center_slots as Array).append(cell)
	return zones
func _footprint(cells: Array) -> Array:
	if cells.is_empty(): return [0, 0]
	var xs: Array[int] = []; var ys: Array[int] = []
	for c in cells: xs.append(int(c[0])); ys.append(int(c[1]))
	return [xs.max() - xs.min() + 1, ys.max() - ys.min() + 1]
func _name(value: Variant) -> String:
	var text: String = str(value)
	return text.to_lower() if text != "" else "unknown"

func _role_name(value: Variant) -> String:
	var text: String = str(value)
	var known: Dictionary = {"Airlock":"airlock", "Dock":"dock", "Corridor":"corridor", "MainSpine":"main_spine", "Hub":"hub", "Ramp":"ramp", "Elevator":"elevator", "Bridge":"bridge", "Engineering":"engineering", "Reactor":"reactor", "LifeSupport":"life_support", "Maintenance":"maintenance", "Cargo":"cargo", "Hangar":"hangar", "Storage":"storage", "Armory":"armory", "Security":"security", "Medical":"medical", "CrewQuarters":"crew_quarters", "MessHall":"mess_hall", "Compartment":"compartment"}
	return str(known.get(text, text.to_snake_case()))

func _direction(from_cell: Variant, to_cell: Variant) -> String:
	var dx: int = _coord(to_cell, "x") - _coord(from_cell, "x")
	var dy: int = _coord(to_cell, "y") - _coord(from_cell, "y")
	if dx > 0: return "east"
	if dx < 0: return "west"
	if dy > 0: return "south"
	return "north"

func _opposite(direction: String) -> String:
	return {"east": "west", "west": "east", "north": "south", "south": "north"}.get(direction, "")

func _floor(value: Dictionary, names: Dictionary) -> Dictionary:
	var cell: Dictionary = value.get("cell", {})
	return {"id": str(value.get("id", "")), "placement_id": str(value.get("id", "")), "module_id": str(value.get("module_id", "")), "position": value.get("position", _position(cell)), "yaw_degrees": float(value.get("yaw_degrees", 0)), "deck": _coord(cell, "deck"), "cell": _cell2(cell), "cell_key": str(value.get("cell_key", _cell_key(cell))), "room_id": names.get(int(value.get("room_id", -1)), ""), "room_ids": [names.get(int(value.get("room_id", -1)), "")], "variant": _name(value.get("variant", "intact")), "socket_bindings": []}

func _edge(value: Dictionary, names: Dictionary, with_placement_id: bool) -> Dictionary:
	var cell: Dictionary = value.get("cell", {})
	var rooms: Array = value.get("room_ids", [])
	var owner: int = int(rooms[0]) if rooms.size() > 0 else int(value.get("owner_room", -1))
	var other: int = int(rooms[1]) if rooms.size() > 1 else int(value.get("other_room", -1))
	var key: String = str(value.get("edge_key", value.get("key", "")))
	var edge_kind: String = str(value.get("kind", "SOLID")).to_upper()
	var source_cells: Array = []
	for source_v in value.get("source_cells", []): source_cells.append(_cell3(source_v))
	var direction: String = _name(value.get("direction", ""))
	var result: Dictionary = {"id": "edge:%s" % key, "key": key, "edge_key": key, "deck": _coord(cell, "deck"), "cell": _cell2(cell), "direction": direction, "opposite_direction": _opposite(direction), "source_cells": source_cells, "room_ids": [names.get(owner, ""), names.get(other, "")], "owner_room": names.get(owner, ""), "other_room": names.get(other, ""), "kind": edge_kind, "state": edge_kind, "module_id": str(value.get("module_id", "")), "variant": _name(value.get("variant", "intact")), "position": value.get("position", _position(cell)), "yaw_degrees": float(value.get("yaw_degrees", 0)), "portal": bool(value.get("portal", false)), "exterior": bool(value.get("exterior", false)), "placement_required": bool(value.get("wrapper_required", false)), "wrapper_required": bool(value.get("wrapper_required", false)), "socket_bindings": []}
	if with_placement_id: result["placement_id"] = "edge:%s" % key
	return result
