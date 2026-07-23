extends SceneTree

## PKG-D5.4: extended template catalog + zone/branch/wreck mutators.
## Marker: TEMPLATES WRECK MUTATOR PASS catalog=true load=true zone=true branch=true wreck=true

const TemplateSelectorScript := preload("res://scripts/procgen/template_selector.gd")
const TopologyTemplateScript := preload("res://scripts/procgen/topology_template.gd")
const LayoutMutatorScript := preload("res://scripts/procgen/layout_mutator.gd")
const ModuleIntegrityMapScript := preload("res://scripts/systems/module_integrity_map.gd")
const ModuleIntegrityStateScript := preload("res://scripts/systems/module_integrity_state.gd")

const NEW_TEMPLATES: Array[String] = ["ring", "radial", "double_spine", "hangar_wing", "vault"]


func _initialize() -> void:
	var sel = TemplateSelectorScript.new()
	var extended: Array = sel.available_templates(false, true)
	if extended.size() < 12:
		_fail("extended pool expected >=12, got %d" % extended.size()); return
	var disk_n: int = sel.catalog_size_on_disk()
	if disk_n < 12:
		_fail("on-disk templates expected >=12, got %d" % disk_n); return

	# All new templates load
	for tid in NEW_TEMPLATES:
		if not extended.has(tid):
			_fail("missing template id in pool: %s" % tid); return
		var t = sel._load_template(tid)
		if t == null:
			_fail("load failed: %s" % tid); return
		if str(t.get("id")) != tid:
			_fail("id mismatch %s" % tid); return
		if t.zones.is_empty() or t.connections.is_empty():
			_fail("%s empty zones/connections" % tid); return
		# entry zone present
		var has_entry: bool = false
		for z in t.zones:
			if str(z.get("id", "")) == "entry":
				has_entry = true
		if not has_entry:
			_fail("%s missing entry" % tid); return

	# Zone mutator is seeded and may drop lateral clusters
	var radial = sel._load_template("radial")
	var zones_before: int = radial.zones.size()
	var zm: int = LayoutMutatorScript.apply_zone_mutators(radial, 42)
	# deterministic re-run
	var radial2 = sel._load_template("radial")
	var zm2: int = LayoutMutatorScript.apply_zone_mutators(radial2, 42)
	if zm != zm2 or radial.zones.size() != radial2.zones.size():
		_fail("zone mutator not deterministic"); return
	if radial.zones.size() > zones_before:
		_fail("zone mutator should not grow zones"); return

	# Branch mutator blocks some links
	var layout: Dictionary = {
		"critical_path": ["airlock", "corridor"],
		"room_links": [
			{"id": "l1", "from_room": "airlock", "to_room": "corridor", "module_id": "doorway_frame_open_1x1"},
			{"id": "l2", "from_room": "corridor", "to_room": "cargo", "module_id": "doorway_frame_open_1x1"},
			{"id": "l3", "from_room": "corridor", "to_room": "med", "module_id": "doorway_frame_open_1x1"},
			{"id": "l4", "from_room": "cargo", "to_room": "storage", "module_id": "doorway_frame_open_1x1"},
			{"id": "l5", "from_room": "med", "to_room": "crew", "module_id": "doorway_frame_open_1x1"},
		],
		"blocked_links": [],
	}
	var blocks: int = LayoutMutatorScript.apply_branch_mutators(layout, 7)
	if blocks < 1:
		_fail("branch mutator should block at least one link"); return
	# critical hop protected
	var still_open: bool = false
	for L in layout["room_links"]:
		if str(L.get("from_room", "")) == "airlock" and str(L.get("to_room", "")) == "corridor":
			still_open = true
	if not still_open:
		_fail("critical_path first hop must stay open"); return

	# Wreck mutator damages walls
	var wreck_layout: Dictionary = {
		"rooms": [
			{
				"id": "eng",
				"structural_placements": [
					{"module_id": "wall_straight_1x1"},
					{"module_id": "wall_straight_1x1"},
					{"module_id": "wall_outer_corner"},
					{"module_id": "floor_1x1"},
					{"module_id": "wall_straight_1x1"},
					{"module_id": "doorway_frame_open_1x1"},
				],
			},
			{
				"id": "cor",
				"structural_placements": [
					{"module_id": "wall_straight_1x1"},
					{"module_id": "wall_straight_1x1"},
					{"module_id": "wall_straight_1x1"},
					{"module_id": "floor_1x1"},
				],
			},
		],
	}
	var map = ModuleIntegrityMapScript.new()
	var wreck_n: int = LayoutMutatorScript.apply_wreck_mutator(wreck_layout, 99, map, 0.9)
	if wreck_n < 2:
		_fail("wreck should damage multiple structural modules, got %d" % wreck_n); return
	if not bool(wreck_layout.get("wreck_applied", false)):
		_fail("wreck_applied flag"); return
	var md: Array = wreck_layout.get("module_damage", [])
	if md.size() != wreck_n:
		_fail("module_damage size"); return
	# At least one module not intact
	var any_damaged: bool = false
	for row in md:
		var mid: String = str(row.get("module_id", ""))
		var st: String = map.get_state(mid)
		if st != ModuleIntegrityStateScript.STATE_INTACT:
			any_damaged = true
			break
	if not any_damaged:
		_fail("integrity map should show non-intact modules"); return

	# Deterministic wreck
	var map_b = ModuleIntegrityMapScript.new()
	var layout_b: Dictionary = wreck_layout.duplicate(true)
	layout_b.erase("module_damage")
	layout_b.erase("wreck_applied")
	# rebuild clean placements
	layout_b = {
		"rooms": wreck_layout["rooms"],
	}
	var wreck_n2: int = LayoutMutatorScript.apply_wreck_mutator(layout_b, 99, map_b, 0.9)
	if wreck_n2 != wreck_n:
		_fail("wreck determinism count"); return

	print("TEMPLATES WRECK MUTATOR PASS catalog=true load=true zone=true branch=true wreck=true")
	quit(0)


func _fail(msg: String) -> void:
	print("TEMPLATES WRECK MUTATOR FAIL: %s" % msg)
	quit(1)
