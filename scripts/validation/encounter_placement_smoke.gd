extends SceneTree

# encounter_placement_smoke — REQ-PG-007 / RISK-011 follow-up.
#
# The audit found that EncounterInjector read `room.cells`, a key that exists
# only in hand-built test fixtures — serialized layouts (LayoutSerializer,
# golden ships, the full ShipLayoutGenerator path) carry floor cells as
# `structural_placements` with world_position = cell * cell_size. Every real
# marker therefore fell back to cell [0, 0]. Downstream, ThreatManager ignored
# the cell entirely and clustered every threat on a 4 u circle around the ship
# anchor. Net effect: encounter placement was fiction end-to-end.
#
# This smoke drives the REAL pipeline (ShipLayoutGenerator with biome +
# difficulty -> serialized rooms -> EncounterInjector -> ThreatManager) and
# asserts:
#   1. markers_exist   — a high-density biome/difficulty combination yields
#                        >= 2 markers on a generated layout.
#   2. cells_real      — every marker's `cell` is one of its room's actual
#                        floor cells (derived from structural_placements /
#                        cell_size), and every marker carries a
#                        `local_position` matching a floor placement of its
#                        room. No [0,0] fallback fiction.
#   3. spawns_in_rooms — ThreatManager spawns each threat at
#                        anchor + local_position (not on the legacy anchor
#                        circle), so threats stand in their rolled rooms.
#
# Pass marker: ENCOUNTER PLACEMENT PASS markers=<n> cells_real=true spawns_in_rooms=true distinct_positions=true

const ShipLayoutGeneratorScript := preload("res://scripts/procgen/ship_layout_generator.gd")
const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")
const ThreatManagerScript := preload("res://scripts/systems/threat_manager.gd")

const SEEDS: Array = [314, 999, 42, 7, 123]
const ANCHOR: Vector3 = Vector3(100.0, 0.0, 50.0)
const EPS: float = 0.01

var _ran: bool = false
var tm: Node = null

func _initialize() -> void:
	# ThreatManager loads its archetype JSONs in _ready, which does not fire
	# until the first processed frame in --script mode — defer validation.
	process_frame.connect(_on_first_frame)

func _on_first_frame() -> void:
	if _ran:
		return
	_ran = true
	_run_validation()

func _run_validation() -> void:
	# --- Generate a real layout with markers (deterministic seed scan) ------
	var layout: Dictionary = {}
	var markers: Array = []
	for seed_value in SEEDS:
		var generator: RefCounted = ShipLayoutGeneratorScript.new()
		var bp: RefCounted = ShipBlueprintScript.new(
			ShipBlueprintScript.Size.MEDIUM, ShipBlueprintScript.Condition.PRISTINE, int(seed_value))
		var candidate: Dictionary = generator.generate_with_options(bp, {}, "breach_field", "deep_dive")
		var enc: Variant = candidate.get("encounters", [])
		if enc is Array and (enc as Array).size() >= 2:
			layout = candidate
			markers = enc
			break
	if markers.is_empty():
		_fail("no seed in %s produced >=2 encounter markers at breach_field/deep_dive density" % str(SEEDS))
		return

	# --- Criterion 2: marker cells are real room floor cells ----------------
	var cell_size: float = float(layout.get("cell_size", 4.0))
	var rooms_by_id: Dictionary = {}
	for room in layout.get("rooms", []):
		if room is Dictionary:
			rooms_by_id[str((room as Dictionary).get("id", ""))] = room
	for marker_variant in markers:
		var marker: Dictionary = marker_variant
		var rid: String = str(marker.get("room_id", ""))
		if not rooms_by_id.has(rid):
			_fail("marker %s references unknown room %s" % [str(marker.get("id")), rid])
			return
		var room: Dictionary = rooms_by_id[rid]
		var floor_cells: Dictionary = {}
		var floor_positions: Array = []
		for p in room.get("structural_placements", []):
			if p is Dictionary and str((p as Dictionary).get("name", "")).begins_with("floor_cell"):
				var wp: Variant = (p as Dictionary).get("world_position", null)
				if wp is Array and (wp as Array).size() >= 3:
					floor_cells["%d,%d" % [int(roundf(float(wp[0]) / cell_size)), int(roundf(float(wp[2]) / cell_size))]] = true
					floor_positions.append(wp)
		if floor_cells.is_empty():
			_fail("room %s has no floor placements to derive cells from" % rid)
			return
		var cell: Variant = marker.get("cell", null)
		if not (cell is Array) or (cell as Array).size() < 2:
			_fail("marker %s has no usable cell" % str(marker.get("id")))
			return
		var cell_key: String = "%d,%d" % [int((cell as Array)[0]), int((cell as Array)[1])]
		if not floor_cells.has(cell_key):
			_fail("marker %s cell %s is not a floor cell of room %s (floor cells: %s)" % [str(marker.get("id")), cell_key, rid, str(floor_cells.keys())])
			return
		var lp: Variant = marker.get("local_position", null)
		if not (lp is Array) or (lp as Array).size() < 3:
			_fail("marker %s missing local_position" % str(marker.get("id")))
			return
		var lp_matches: bool = false
		for wp in floor_positions:
			if absf(float(wp[0]) - float(lp[0])) < EPS and absf(float(wp[2]) - float(lp[2])) < EPS:
				lp_matches = true
				break
		if not lp_matches:
			_fail("marker %s local_position %s matches no floor placement of room %s" % [str(marker.get("id")), str(lp), rid])
			return
	var cells_real: bool = true

	# --- Criterion 3: ThreatManager spawns at anchor + local_position -------
	tm = ThreatManagerScript.new()
	get_root().add_child(tm)
	tm.configure_for_layout(layout, markers, ANCHOR)
	if tm.threats.is_empty():
		_fail("ThreatManager spawned no threats from %d markers" % markers.size())
		return
	var marker_lp: Dictionary = {}
	for marker_variant in markers:
		var marker: Dictionary = marker_variant
		marker_lp[str(marker.get("id", ""))] = marker.get("local_position")
	var positions_seen: Dictionary = {}
	for threat in tm.threats:
		# instance_id = "<marker_id>_<i>"; strip the trailing per-count index.
		var iid: String = String(threat.instance_id)
		var marker_id: String = iid.substr(0, iid.rfind("_"))
		if not marker_lp.has(marker_id):
			_fail("threat %s does not map back to a marker" % iid)
			return
		var lp: Array = marker_lp[marker_id]
		var expected: Vector3 = ANCHOR + Vector3(float(lp[0]), float(lp[1]), float(lp[2]))
		var actual: Vector3 = Vector3(float(threat.world_position[0]), float(threat.world_position[1]), float(threat.world_position[2]))
		if actual.distance_to(expected) > 1.5:
			_fail("threat %s spawned at %s, expected near %s (anchor+local_position)" % [iid, str(actual), str(expected)])
			return
		positions_seen["%.1f,%.1f" % [actual.x, actual.z]] = true
	var distinct: bool = positions_seen.size() >= 2
	if not distinct:
		_fail("all %d threats share one position — anchor-cluster regression" % tm.threats.size())
		return

	print("ENCOUNTER PLACEMENT PASS markers=%d cells_real=%s spawns_in_rooms=true distinct_positions=%s" % [
		markers.size(), str(cells_real).to_lower(), str(distinct).to_lower()])
	tm.queue_free()
	quit(0)

func _fail(reason: String) -> void:
	push_error("ENCOUNTER PLACEMENT FAIL reason=%s" % reason)
	if is_instance_valid(tm):
		tm.queue_free()
	quit(1)
