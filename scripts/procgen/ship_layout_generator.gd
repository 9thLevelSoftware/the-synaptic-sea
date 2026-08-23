extends RefCounted
class_name ShipLayoutGenerator

# Top-level orchestrator for the procgen layout pipeline.
# Runs the 5-stage pipeline:
#   TemplateSelector -> RoomAssigner -> CellLayoutEngine ->
#   WallDoorResolver -> LayoutSerializer
# Returns a complete layout.json Dictionary.
#
# Task 12 package extensions:
#   - generate() accepts biome_id / difficulty_id kwargs and forwards
#     them to RoomAssigner (for variant selection) and EncounterInjector
#     (for encounter spawn markers).
#   - generate() optionally accepts a RoomVariantSelector.
#   - generate() returns a layout with schema_version "1.2.0" and a
#     new top-level "encounters" array populated by EncounterInjector.

const TemplateSelectorScript := preload("res://scripts/procgen/template_selector.gd")
const RoomAssignerScript := preload("res://scripts/procgen/room_assigner.gd")
const CellLayoutEngineScript := preload("res://scripts/procgen/cell_layout_engine.gd")
const WallDoorResolverScript := preload("res://scripts/procgen/wall_door_resolver.gd")
const LayoutSerializerScript := preload("res://scripts/procgen/layout_serializer.gd")
const RoomVariantSelectorScript := preload("res://scripts/procgen/room_variant_selector.gd")
const BiomeProfileScript := preload("res://scripts/procgen/biome_profile.gd")
const DifficultyProfileScript := preload("res://scripts/procgen/difficulty_profile.gd")
const EncounterInjectorScript := preload("res://scripts/procgen/encounter_injector.gd")
const StructuralEdgePlanScript := preload("res://scripts/procgen/structural_edge_plan.gd")

var template_selector: RefCounted = TemplateSelectorScript.new()
var room_assigner: RefCounted = RoomAssignerScript.new()
var cell_layout_engine: RefCounted = CellLayoutEngineScript.new()
var wall_door_resolver: RefCounted = WallDoorResolverScript.new()
var layout_serializer: RefCounted = LayoutSerializerScript.new()
var variant_selector: RefCounted = null
var biome_id: String = ""
var difficulty_id: String = ""


func generate(blueprint: RefCounted, archetype: Dictionary = {}) -> Dictionary:
	return generate_with_options(blueprint, archetype, "", "", false)


# Extended entry point. When `biome_id` / `difficulty_id` are
# non-empty, the RoomAssigner is given the variant selector (if
# one is built), and after Stage 5 the EncounterInjector populates
# `layout.encounters`. When the biome / difficulty ids are empty
# strings, the legacy behaviour is preserved exactly.
const MAX_CONNECTIVITY_ATTEMPTS: int = 4

func generate_with_options(
		blueprint: RefCounted,
		archetype: Dictionary = {},
		biome_id: String = "",
		difficulty_id: String = "",
		extended_templates: bool = false) -> Dictionary:
	assert(blueprint != null, "ShipLayoutGenerator: blueprint must not be null")

	self.biome_id = biome_id
	self.difficulty_id = difficulty_id

	var base_seed: int = int(blueprint.seed_value)
	var best_effort: Dictionary = {}
	for attempt in range(MAX_CONNECTIVITY_ATTEMPTS):
		# F2: deterministic seed salt on retry so bad connectivity is not sticky.
		var attempt_seed: int = base_seed if attempt == 0 else int(base_seed ^ (attempt * 0x9E3779B9))
		var candidate: Dictionary = {}
		if attempt > 0:
			# Mutate seed for this attempt only (restore after).
			var saved: int = int(blueprint.seed_value)
			blueprint.seed_value = attempt_seed
			candidate = _generate_once(blueprint, archetype, biome_id, difficulty_id, extended_templates)
			blueprint.seed_value = saved
		else:
			candidate = _generate_once(blueprint, archetype, biome_id, difficulty_id, extended_templates)
		if candidate.is_empty():
			continue
		# Keep best non-empty across attempts (do not lose a usable ship if a
		# later salted attempt returns {}).
		best_effort = candidate
		if _layout_is_connected(candidate):
			return candidate
	# All attempts failed connectivity — still return best effort if non-empty so
	# loaders do not hard-crash; quality gate smoke fails disconnected layouts.
	if not best_effort.is_empty():
		push_warning("ShipLayoutGenerator: layout connectivity soft-fail after %d attempts seed=%d" % [
			MAX_CONNECTIVITY_ATTEMPTS, base_seed])
		return best_effort
	push_error("SHIP LAYOUT GENERATOR FAIL all connectivity attempts empty")
	return {}


func _generate_once(
		blueprint: RefCounted,
		archetype: Dictionary,
		biome_id: String,
		difficulty_id: String,
		extended_templates: bool) -> Dictionary:
	# Stage 1: Select topology template.
	var template: RefCounted
	if extended_templates:
		template = template_selector.select_with_options(
			blueprint, archetype, true, true)
	else:
		template = template_selector.select(blueprint, archetype)
	if template == null:
		push_error("SHIP LAYOUT GENERATOR FAIL template selection returned null")
		return {}

	# Stage 2: Assign rooms to template zones (with variant selector).
	var room_plan: Array[Dictionary]
	if variant_selector == null and not biome_id.is_empty():
		variant_selector = RoomVariantSelectorScript.new()
	if variant_selector != null:
		room_plan = room_assigner.assign_with_selector(
			template, blueprint, archetype, variant_selector, biome_id)
	else:
		room_plan = room_assigner.assign(template, blueprint, archetype)
	if room_plan.is_empty():
		push_error("SHIP LAYOUT GENERATOR FAIL room assignment returned empty")
		return {}

	# Stage 3: Place rooms on 2D grid.
	var cell_grid: Dictionary = cell_layout_engine.layout(room_plan, template, int(blueprint.seed_value))
	if cell_grid.get("rooms", {}).is_empty():
		push_error("SHIP LAYOUT GENERATOR FAIL cell layout returned empty rooms")
		return {}

	# Stage 4: Resolve walls, doors, interior zones.
	var geometry: Dictionary = wall_door_resolver.resolve(cell_grid, room_plan)

	# Stage 5: Serialize to layout.json format.
	var archetype_name: String = str(archetype.get("name", str(archetype.get("template", "default"))))
	var layout: Dictionary = layout_serializer.serialize(
		cell_grid, geometry, room_plan,
		str(template.id), int(blueprint.seed_value), archetype_name)

	# The structural compiler consumes solved logical footprints, not the
	# serializer's legacy visual module lists. Stamp the exact cells selected by
	# CellLayoutEngine onto every room and emit portal intents only for real
	# shared cardinal edges between those cells.
	if not _stamp_explicit_structural_layout(layout, cell_grid):
		# A stale logical adjacency is a malformed solved layout. Do not return a
		# best-effort layout whose portal list no longer describes its footprints.
		push_error("SHIP LAYOUT GENERATOR FAIL invalid adjacency/footprint boundary")
		return {}

	# Stage 6 (optional): Inject encounter markers when biome and/or
	# difficulty are non-empty.
	if not biome_id.is_empty() or not difficulty_id.is_empty():
		var biome_data: Dictionary = _resolve_biome(biome_id)
		var difficulty_data: Dictionary = _resolve_difficulty(difficulty_id)
		var biome = BiomeProfileScript.from_dict(biome_data)
		var difficulty = DifficultyProfileScript.from_dict(difficulty_data)
		var injector: RefCounted = EncounterInjectorScript.new()
		layout = injector.inject(layout, biome, difficulty, int(blueprint.seed_value))

	# Stamp template_id here (not in LayoutSerializer) so golden schema-key
	# coherence stays on serializer output. Hive binds biomatter independent of biome.
	layout["template_id"] = str(template.id)
	# Stamp biome / difficulty / kit_id / hazard authority on the layout.
	if not biome_id.is_empty():
		layout["biome_id"] = biome_id
	if str(template.id) == "hive":
		layout["kit_id"] = "ship_structural_biomatter"
	elif not biome_id.is_empty():
		# E3: biome-biased structural kit preference (loader still uses module ids).
		layout["kit_id"] = _kit_id_for_biome(biome_id)
	elif str(layout.get("kit_id", "")).is_empty():
		layout["kit_id"] = "ship_structural_v0"
	if not difficulty_id.is_empty():
		layout["difficulty_id"] = difficulty_id
	# F4: runtime coordinator owns fire/breach seeding for derelicts; layout arrays
	# remain optional overlays (goldens may still author markers).
	layout["hazard_source"] = "runtime"

	return layout


func _stamp_explicit_structural_layout(layout: Dictionary, cell_grid: Dictionary) -> bool:
	var placed_rooms: Dictionary = cell_grid.get("rooms", {})
	var rooms: Array = layout.get("rooms", [])
	for room_variant in rooms:
		if not (room_variant is Dictionary):
			continue
		var room: Dictionary = room_variant
		var room_id: String = str(room.get("id", ""))
		if room_id.is_empty() or not placed_rooms.has(room_id):
			continue
		var solved: Dictionary = placed_rooms[room_id]
		var cells: Array[Vector2i] = []
		for cell_variant in solved.get("cells", []):
			if cell_variant is Vector2i:
				cells.append(cell_variant)
		var role: String = str(solved.get("role", room.get("room_role", "")))
		var deck: int = int(solved.get("deck", room.get("deck", 0)))
		var footprint: Vector2i = solved.get("footprint", Vector2i.ZERO)
		room["role"] = role
		# Keep room_role for existing gameplay/loader consumers while making the
		# canonical role field explicit for compiler callers.
		room["room_role"] = role
		room["deck"] = deck
		room["cells"] = cells
		room["footprint"] = footprint

	var raw_adjacencies: Array = cell_grid.get("adjacencies", [])
	# Keep the pre-dedup topology available to validation/stress code. The
	# physical portal list below intentionally has one record per shared edge;
	# it must not become the only source from which required intents are derived.
	layout["adjacency_intents"] = _copy_adjacency_intents(raw_adjacencies)
	var portal_result: Dictionary = _build_explicit_portals(raw_adjacencies, placed_rooms)
	if not bool(portal_result.get("ok", false)):
		return false
	layout["portals"] = portal_result.get("portals", [])
	# This filtered graph is useful to consumers that need only physical seams;
	# room_links remains the backwards-compatible logical graph.
	layout["structural_room_links"] = (layout["portals"] as Array).duplicate(true)
	return true


func _build_explicit_portals(adjacencies: Array, placed_rooms: Dictionary) -> Dictionary:
	var portals: Array = []
	var emitted_edges: Dictionary = {}
	var errors: Array[String] = []
	for adjacency_variant in adjacencies:
		if not (adjacency_variant is Dictionary):
			errors.append("adjacency intent is not a Dictionary")
			continue
		var adjacency: Dictionary = adjacency_variant
		var from_room: String = str(adjacency.get("from_room", ""))
		var to_room: String = str(adjacency.get("to_room", ""))
		if from_room.is_empty() or to_room.is_empty():
			errors.append("adjacency intent is missing a room endpoint")
			continue
		if not placed_rooms.has(from_room) or not placed_rooms.has(to_room):
			errors.append("adjacency intent references an unknown room: %s -> %s" % [from_room, to_room])
			continue
		var from_data: Dictionary = placed_rooms[from_room]
		var to_data: Dictionary = placed_rooms[to_room]
		var from_deck: int = int(from_data.get("deck", 0))
		var to_deck: int = int(to_data.get("deck", 0))
		var from_cell_result: Dictionary = _integer_cell(adjacency.get("from_cell", null))
		var to_cell_result: Dictionary = _integer_cell(adjacency.get("to_cell", null))
		if not bool(from_cell_result.get("ok", false)) or not bool(to_cell_result.get("ok", false)):
			errors.append("adjacency intent has invalid integer endpoint cells: %s -> %s" % [from_room, to_room])
			continue
		var from_cell: Vector2i = from_cell_result["cell"]
		var to_cell: Vector2i = to_cell_result["cell"]
		if not _room_contains_cell(from_data, from_cell):
			errors.append("adjacency intent source cell is not in room footprint: %s %s" % [from_room, from_cell])
			continue
		if not _room_contains_cell(to_data, to_cell):
			errors.append("adjacency intent target cell is not in room footprint: %s %s" % [to_room, to_cell])
			continue
		if from_deck != to_deck:
			# A vertical connection has no cardinal shared edge. It remains in
			# vertical_connections; never invent a same-deck portal for it. The
			# endpoint membership checks above still apply to stale vertical links.
			continue
		var direction: String = _direction_between(from_cell, to_cell)
		if direction.is_empty():
			errors.append("adjacency intent endpoints do not share a cardinal boundary: %s -> %s" % [from_room, to_room])
			continue
		var declared_direction: String = str(adjacency.get(
			"direction", adjacency.get("wall", adjacency.get("from_direction", ""))))
		if not declared_direction.is_empty() and declared_direction != direction:
			errors.append(
				"adjacency intent declared boundary %s but endpoints are %s: %s -> %s" % [
					declared_direction, direction, from_room, to_room])
			continue
		var edge_key: String = StructuralEdgePlanScript.edge_key(from_deck, from_cell, direction)
		var declared_edge_key: String = str(adjacency.get("edge_key", ""))
		if not declared_edge_key.is_empty() and declared_edge_key != edge_key:
			errors.append(
				"adjacency intent declared edge %s but endpoints resolve to %s" % [
					declared_edge_key, edge_key])
			continue
		if emitted_edges.has(edge_key):
			continue
		emitted_edges[edge_key] = true
		var intent_type: Variant = "door"
		if adjacency.has("type"):
			intent_type = adjacency["type"]
		elif adjacency.has("portal_type"):
			intent_type = adjacency["portal_type"]
		var required: Variant = true if not adjacency.has("required") else adjacency["required"]
		portals.append({
			"id": "portal:%s" % edge_key,
			"from_room": from_room,
			"to_room": to_room,
			# Keep both accepted intent spellings in the emitted record. This
			# avoids flattening LOCKED/HATCH/etc. to the historical door default.
			"type": intent_type,
			"portal_type": intent_type,
			"required": required,
			"edge_key": edge_key,
			"deck": from_deck,
			"cell": from_cell,
			"direction": direction,
			"opposite_direction": StructuralEdgePlanScript.OPPOSITE[direction],
			"from_cell": from_cell,
			"to_cell": to_cell,
			"source_cells": [from_cell, to_cell],
		})
	return {"ok": errors.is_empty(), "portals": portals, "errors": errors}


func _copy_adjacency_intents(adjacencies: Array) -> Array:
	var intents: Array = []
	for adjacency_variant in adjacencies:
		if not (adjacency_variant is Dictionary):
			intents.append(adjacency_variant)
			continue
		var intent: Dictionary = (adjacency_variant as Dictionary).duplicate(true)
		# CellLayoutEngine's discovered adjacencies predate the explicit intent
		# field. Their absence means required, but an authored false must stay
		# false rather than being replaced by the default.
		if not intent.has("required"):
			intent["required"] = true
		intents.append(intent)
	return intents


func _room_contains_cell(room_data: Dictionary, cell: Vector2i) -> bool:
	var raw_cells: Variant = room_data.get("cells", [])
	if not (raw_cells is Array):
		return false
	for raw_cell in raw_cells:
		var result: Dictionary = _integer_cell(raw_cell)
		if bool(result.get("ok", false)) and result["cell"] == cell:
			return true
	return false


func _integer_cell(raw_cell: Variant) -> Dictionary:
	if raw_cell is Vector2i:
		return {"ok": true, "cell": raw_cell}
	if raw_cell is Array and (raw_cell as Array).size() == 2:
		var values: Array = raw_cell
		if typeof(values[0]) == TYPE_INT and typeof(values[1]) == TYPE_INT:
			return {"ok": true, "cell": Vector2i(int(values[0]), int(values[1]))}
	return {"ok": false, "cell": Vector2i.ZERO}


func _direction_between(from_cell: Vector2i, to_cell: Vector2i) -> String:
	var delta: Vector2i = to_cell - from_cell
	for direction_variant in StructuralEdgePlanScript.DIRECTIONS.keys():
		var direction: String = str(direction_variant)
		if StructuralEdgePlanScript.DIRECTIONS[direction] == delta:
			return direction
	return ""


## Room-link connectivity: every room id must be reachable from prototype.start_room.
func _layout_is_connected(layout: Dictionary) -> bool:
	var rooms_v: Variant = layout.get("rooms", [])
	if not (rooms_v is Array) or (rooms_v as Array).is_empty():
		return false
	var room_ids: Array[String] = []
	for r in (rooms_v as Array):
		if r is Dictionary:
			var rid: String = str((r as Dictionary).get("id", ""))
			if not rid.is_empty():
				room_ids.append(rid)
	if room_ids.is_empty():
		return false
	var start: String = str((layout.get("prototype", {}) as Dictionary).get("start_room", room_ids[0]))
	if start.is_empty():
		start = room_ids[0]
	var adj: Dictionary = {}  # id -> Array[String]
	for rid in room_ids:
		adj[rid] = [] as Array
	var links_v: Variant = layout.get("room_links", [])
	if links_v is Array:
		for link_v in (links_v as Array):
			if not (link_v is Dictionary):
				continue
			var a: String = str((link_v as Dictionary).get("from_room", ""))
			var b: String = str((link_v as Dictionary).get("to_room", ""))
			if a.is_empty() or b.is_empty():
				continue
			if not adj.has(a):
				adj[a] = [] as Array
			if not adj.has(b):
				adj[b] = [] as Array
			(adj[a] as Array).append(b)
			(adj[b] as Array).append(a)
	# BFS
	var seen: Dictionary = {}
	var q: Array = [start]
	seen[start] = true
	while not q.is_empty():
		var cur: String = str(q.pop_front())
		for nxt in adj.get(cur, []):
			var n: String = str(nxt)
			if seen.has(n):
				continue
			seen[n] = true
			q.append(n)
	return seen.size() >= room_ids.size()


func _kit_id_for_biome(biome: String) -> String:
	# Prefer abyssal-biased kit when present; else structural default.
	match biome:
		"abyssal_synaptic_sea":
			return "ship_structural_v0"
		"breach_field":
			return "ship_structural_v0"
		"dead_fleet":
			return "ship_structural_v0"
		_:
			return "ship_structural_v0"


# Resolves a biome dictionary from `biome_id`. When `biome_id` is
# empty, returns a minimal abyssal_synaptic_sea default so the encounter
# injector still runs (but the encounter density stays at 1.0 and
# the resulting encounter list is typically empty for the standard
# difficulty).
func _resolve_biome(biome_id: String) -> Dictionary:
	if biome_id.is_empty():
		return {"id": "abyssal_synaptic_sea"}
	# Try to load the JSON file first; fall back to a built-in
	# default for the three known biomes so the smoke bundle works
	# even without a fully populated data/ tree.
	var rel_path: String = "res://data/procgen/biomes/" + biome_id + ".json"
	if FileAccess.file_exists(rel_path):
		var text: String = FileAccess.get_file_as_string(rel_path)
		var parsed: Variant = JSON.parse_string(text)
		if parsed is Dictionary:
			return parsed
	match biome_id:
		"breach_field":
			return {
				"id": "breach_field",
				"hazard_modifier": 1.4,
				"loot_quality_modifier": 1.1,
				"encounter_density_modifier": 1.3,
				"ambient_intensity": 0.85,
				"encounter_table_id": "biomatter_lurker",
			}
		"dead_fleet":
			return {
				"id": "dead_fleet",
				"hazard_modifier": 1.1,
				"loot_quality_modifier": 1.4,
				"encounter_density_modifier": 0.8,
				"ambient_intensity": 1.1,
				"encounter_table_id": "derelict_pirate",
			}
		_:
			return {
				"id": "abyssal_synaptic_sea",
				"hazard_modifier": 1.0,
				"loot_quality_modifier": 1.0,
				"encounter_density_modifier": 1.0,
				"ambient_intensity": 1.0,
				"encounter_table_id": "biomatter_lurker",
			}


func _resolve_difficulty(difficulty_id: String) -> Dictionary:
	# Tranche 4 (2026-07-06 audit): the id -> dials mapping moved verbatim to
	# DifficultyProfile.resolve_dict() so the settings menu renders the same
	# canonical values this generator consumes (no split-brain).
	return DifficultyProfileScript.resolve_dict(difficulty_id)
