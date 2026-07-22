extends RefCounted
class_name FireSuppressionState

const SimKeysScript := preload("res://scripts/systems/sim_keys.gd")

## Authoritative, compartment-keyed, persist-until-extinguished fire model (ADR-0041).
## Fire is a SYMPTOM of unrepaired system damage: a compartment ignites only when its
## mapped system is damaged AND it has oxygen, and re-ignites until repaired or vented.
## Pure RefCounted; the coordinator renders passable fire-zone nodes from active_fires.
## apply_summary() restores dynamic state (active_fires, spread/ignition/cascade progress,
## suppressant) and arc_compartment; it assumes configure() has already established the
## structural tunables (compartments, adjacency, rates).

const DEFAULT_SUPPRESSANT_UNITS: float = 100.0
const DEFAULT_SUPPRESSION_RATE: float = 25.0
const DEFAULT_POWER_THRESHOLD: float = 0.5
const DEFAULT_SPREAD_RATE: float = 0.15
const DEFAULT_IGNITION_RATE: float = 0.2
const DEFAULT_CASCADE_RATE: float = 0.5
const DEFAULT_ARC_COMPARTMENT: String = "engineering"
const MIN_INTENSITY: float = 0.1
const MAX_INTENSITY: float = 10.0
# Powered suppression removes this fraction of intensity per second (rate * factor).
# Effective powered-suppression rate is suppression_rate_per_second * SUPPRESSION_INTENSITY_FACTOR
# intensity/sec (~1.0/s at defaults: 25.0 * 0.04), so the scaling is explicit, not a silent surprise.
const SUPPRESSION_INTENSITY_FACTOR: float = 0.04
const SUPPRESSANT_DRAIN_PER_SECOND: float = 0.5

var compartments: Array[String] = []
var active_fires: Dictionary = {}              # compartment_id -> intensity (float)
var suppressant_units: float = DEFAULT_SUPPRESSANT_UNITS
var suppression_rate_per_second: float = DEFAULT_SUPPRESSION_RATE
var power_threshold: float = DEFAULT_POWER_THRESHOLD
var adjacency: Dictionary = {}                 # compartment_id -> Array[String]
var spread_rate_per_second: float = DEFAULT_SPREAD_RATE
var ignition_rate_per_second: float = DEFAULT_IGNITION_RATE
var cascade_rate_per_second: float = DEFAULT_CASCADE_RATE
var arc_compartment: String = DEFAULT_ARC_COMPARTMENT

var spread_progress: Dictionary = {}           # compartment_id -> float accumulator
var ignition_progress: Dictionary = {}         # compartment_id -> float accumulator
var cascade_progress: float = 0.0
# Fire B2: deliberate vents (player-opened vacuum without full hull rupture)
# and door-gated spread (closed bulkhead links block adjacency).
var vented_compartments: Dictionary = {}       # compartment_id -> true
var closed_links: Dictionary = {}              # "a|b" sorted key -> true

func configure(config: Dictionary) -> void:
	compartments.clear()
	for entry in config.get("compartments", []):
		compartments.append(str(entry))
	active_fires.clear()
	spread_progress.clear()
	ignition_progress.clear()
	cascade_progress = 0.0
	vented_compartments.clear()
	closed_links.clear()
	var closed_v: Variant = config.get("closed_links", [])
	if closed_v is Array:
		for pair in (closed_v as Array):
			if pair is Array and (pair as Array).size() >= 2:
				set_link_closed(str(pair[0]), str(pair[1]), true)
	var vented_v: Variant = config.get("vented_compartments", [])
	if vented_v is Array:
		for cid in (vented_v as Array):
			set_vented(str(cid), true)
	suppressant_units = maxf(0.0, float(config.get("suppressant_units", DEFAULT_SUPPRESSANT_UNITS)))
	suppression_rate_per_second = maxf(0.1, float(config.get("suppression_rate_per_second", DEFAULT_SUPPRESSION_RATE)))
	power_threshold = clampf(float(config.get("power_threshold", DEFAULT_POWER_THRESHOLD)), 0.05, 1.0)
	spread_rate_per_second = maxf(0.0, float(config.get("spread_rate_per_second", DEFAULT_SPREAD_RATE)))
	ignition_rate_per_second = maxf(0.0, float(config.get("ignition_rate_per_second", DEFAULT_IGNITION_RATE)))
	cascade_rate_per_second = maxf(0.0, float(config.get("cascade_rate_per_second", DEFAULT_CASCADE_RATE)))
	arc_compartment = str(config.get("arc_compartment", DEFAULT_ARC_COMPARTMENT))
	adjacency.clear()
	var adj_variant: Variant = config.get("adjacency", {})
	if typeof(adj_variant) == TYPE_DICTIONARY:
		for cid in (adj_variant as Dictionary):
			var neighbours: Array[String] = []
			var list_variant: Variant = (adj_variant as Dictionary)[cid]
			if typeof(list_variant) == TYPE_ARRAY:
				for n in (list_variant as Array):
					neighbours.append(str(n))
			adjacency[str(cid)] = neighbours

func ignite(compartment_id: String, intensity: float = 1.0) -> bool:
	if compartment_id.is_empty():
		return false
	active_fires[compartment_id] = clampf(float(active_fires.get(compartment_id, 0.0)) + intensity, MIN_INTENSITY, MAX_INTENSITY)
	return true

func extinguish(compartment_id: String) -> bool:
	if not active_fires.has(compartment_id):
		return false
	active_fires.erase(compartment_id)
	spread_progress.erase(compartment_id)
	# Clear stale spread accumulators around the now-extinguished fire, but only for
	# neighbours that no longer have ANY burning adjacent source — otherwise we would
	# wrongly reset progress still being fed by another active fire (Gemini PR #42).
	for adj in _adjacent(compartment_id):
		if not _has_burning_neighbour(adj):
			spread_progress.erase(adj)
	return true

func is_burning(compartment_id: String) -> bool:
	return active_fires.has(compartment_id)

func get_burning_compartments() -> Array:
	return active_fires.keys()

func get_intensity(compartment_id: String) -> float:
	return float(active_fires.get(compartment_id, 0.0))

func get_active_fire_count() -> int:
	return active_fires.size()

## Sum of active fire intensities (Fire B2: drives oxygen consumption).
func get_total_intensity() -> float:
	var total: float = 0.0
	for cid in active_fires:
		total += float(active_fires[cid])
	return total

## Fire B2: deliberate vent — vacuum the compartment without requiring a hull
## rupture event. Extinguishes fire immediately via the oxygen-loss path next tick
## (and synchronously here). Returns true if state changed.
func set_vented(compartment_id: String, vented: bool = true) -> bool:
	if compartment_id.is_empty():
		return false
	if vented:
		if vented_compartments.has(compartment_id):
			return false
		vented_compartments[compartment_id] = true
		if active_fires.has(compartment_id):
			extinguish(compartment_id)
		return true
	if not vented_compartments.has(compartment_id):
		return false
	vented_compartments.erase(compartment_id)
	return true

func is_vented(compartment_id: String) -> bool:
	return vented_compartments.has(compartment_id)

func deliberate_vent(compartment_id: String) -> bool:
	return set_vented(compartment_id, true)

## Fire B2: door/bulkhead gating. Closed links block spread in both directions.
func set_link_closed(a: String, b: String, closed: bool = true) -> void:
	if a.is_empty() or b.is_empty() or a == b:
		return
	var key: String = _link_key(a, b)
	if closed:
		closed_links[key] = true
	else:
		closed_links.erase(key)

func is_link_closed(a: String, b: String) -> bool:
	return closed_links.has(_link_key(a, b))

func _link_key(a: String, b: String) -> String:
	return a + "|" + b if a < b else b + "|" + a

func tick(delta: float, context: Dictionary) -> bool:
	if delta <= 0.0:
		return false
	var changed: bool = false
	var breached: Dictionary = _to_set(context.get(SimKeysScript.BREACHED_COMPARTMENTS, []))
	var damaged: Dictionary = _to_set(context.get(SimKeysScript.DAMAGED_COMPARTMENTS, []))
	var ship_oxygen: bool = bool(context.get(SimKeysScript.SHIP_OXYGEN_PRESENT, true))
	var powered_ratio: float = float(context.get(SimKeysScript.POWERED_RATIO, 0.0))
	var arc_arcing: bool = bool(context.get(SimKeysScript.ARC_ARCING, false))
	# Optional per-tick closed-link override (merges onto model closed_links).
	var ctx_closed: Dictionary = _to_set(context.get(SimKeysScript.CLOSED_LINKS, []))

	# 1. Vent / oxygen-loss extinguish (breach OR deliberate vent).
	for cid in active_fires.keys():
		if not _has_oxygen(cid, ship_oxygen, breached):
			extinguish(cid)
			changed = true

	# 2. Powered auto-suppression.
	if powered_ratio >= power_threshold and suppressant_units > 0.0 and not active_fires.is_empty():
		for cid in active_fires.keys():
			var reduced: float = float(active_fires[cid]) - suppression_rate_per_second * SUPPRESSION_INTENSITY_FACTOR * delta
			suppressant_units = maxf(0.0, suppressant_units - SUPPRESSANT_DRAIN_PER_SECOND * delta)
			if reduced <= 0.0:
				extinguish(cid)
			else:
				active_fires[cid] = reduced
			changed = true

	# 3. Spread to oxygenated, non-burning adjacent compartments (door-gated).
	var spread_ignites: Array = []
	for cid in active_fires.keys():
		var intensity: float = float(active_fires[cid])
		for adj in _adjacent(cid):
			if active_fires.has(adj) or not _has_oxygen(adj, ship_oxygen, breached) \
					or is_link_closed(str(cid), str(adj)) or ctx_closed.has(_link_key(str(cid), str(adj))):
				spread_progress.erase(adj)
				continue
			var p: float = float(spread_progress.get(adj, 0.0)) + spread_rate_per_second * delta * intensity
			if p >= 1.0:
				spread_ignites.append(adj)
				spread_progress.erase(adj)
			else:
				spread_progress[adj] = p
	for adj in spread_ignites:
		if not active_fires.has(adj):
			active_fires[adj] = 1.0
			changed = true

	# 4. Ignition from unrepaired damage (re-ignites until repaired/vented).
	for cid in compartments:
		var ignitable: bool = damaged.has(cid) and _has_oxygen(cid, ship_oxygen, breached) and not active_fires.has(cid)
		if ignitable:
			var p2: float = float(ignition_progress.get(cid, 0.0)) + ignition_rate_per_second * delta
			if p2 >= 1.0:
				active_fires[cid] = 1.0
				ignition_progress.erase(cid)
				changed = true
			else:
				ignition_progress[cid] = p2
		elif ignition_progress.has(cid):
			ignition_progress.erase(cid)

	# 5. Arc cascade.
	if arc_arcing and not active_fires.has(arc_compartment) and _has_oxygen(arc_compartment, ship_oxygen, breached):
		cascade_progress += cascade_rate_per_second * delta
		if cascade_progress >= 1.0:
			active_fires[arc_compartment] = 1.0
			cascade_progress = 0.0
			changed = true
	else:
		cascade_progress = 0.0

	return changed

func get_summary() -> Dictionary:
	return {
		"compartments": compartments.duplicate(),
		"active_fires": active_fires.duplicate(true),
		"suppressant_units": suppressant_units,
		"suppression_rate_per_second": suppression_rate_per_second,
		"power_threshold": power_threshold,
		"adjacency": adjacency.duplicate(true),
		"spread_rate_per_second": spread_rate_per_second,
		"ignition_rate_per_second": ignition_rate_per_second,
		"cascade_rate_per_second": cascade_rate_per_second,
		"arc_compartment": arc_compartment,
		"spread_progress": spread_progress.duplicate(true),
		"ignition_progress": ignition_progress.duplicate(true),
		"cascade_progress": cascade_progress,
		"vented_compartments": vented_compartments.keys(),
		"closed_links": closed_links.keys(),
	}

func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	var changed: bool = false
	var fires: Variant = summary.get("active_fires", null)
	if typeof(fires) == TYPE_DICTIONARY and (fires as Dictionary) != active_fires:
		active_fires = (fires as Dictionary).duplicate(true)
		changed = true
	var sp: Variant = summary.get("spread_progress", null)
	if typeof(sp) == TYPE_DICTIONARY and (sp as Dictionary) != spread_progress:
		spread_progress = (sp as Dictionary).duplicate(true)
		changed = true
	var ip: Variant = summary.get("ignition_progress", null)
	if typeof(ip) == TYPE_DICTIONARY and (ip as Dictionary) != ignition_progress:
		ignition_progress = (ip as Dictionary).duplicate(true)
		changed = true
	var new_suppressant: float = float(summary.get("suppressant_units", suppressant_units))
	if absf(new_suppressant - suppressant_units) > 0.001:
		suppressant_units = new_suppressant
		changed = true
	var new_cascade: float = float(summary.get("cascade_progress", cascade_progress))
	if absf(new_cascade - cascade_progress) > 0.001:
		cascade_progress = new_cascade
		changed = true
	# Tunables (round-trip but rarely change at runtime).
	if summary.has("arc_compartment") and str(summary["arc_compartment"]) != arc_compartment:
		arc_compartment = str(summary["arc_compartment"]); changed = true
	# Round-trip spread topology + rate tunables (previously dropped — a restored-from-
	# scratch model could not spread). Home reconfigures from tuning before applying, but
	# per-ship derelict fire restores straight from its ShipInstance summary.
	var comps: Variant = summary.get("compartments", null)
	if typeof(comps) == TYPE_ARRAY:
		var new_comps: Array[String] = []
		for c in (comps as Array):
			new_comps.append(str(c))
		if new_comps != compartments:
			compartments = new_comps
			changed = true
	var adj: Variant = summary.get("adjacency", null)
	if typeof(adj) == TYPE_DICTIONARY:
		var new_adj: Dictionary = {}
		for cid in (adj as Dictionary):
			var neighbours: Array[String] = []
			var lst: Variant = (adj as Dictionary)[cid]
			if typeof(lst) == TYPE_ARRAY:
				for n in (lst as Array):
					neighbours.append(str(n))
			new_adj[str(cid)] = neighbours
		if new_adj != adjacency:
			adjacency = new_adj
			changed = true
	if summary.has("suppression_rate_per_second"):
		var new_supp_rate: float = maxf(0.1, float(summary["suppression_rate_per_second"]))
		if absf(new_supp_rate - suppression_rate_per_second) > 0.001:
			suppression_rate_per_second = new_supp_rate
			changed = true
	if summary.has("power_threshold"):
		var new_threshold: float = clampf(float(summary["power_threshold"]), 0.05, 1.0)
		if absf(new_threshold - power_threshold) > 0.001:
			power_threshold = new_threshold
			changed = true
	if summary.has("spread_rate_per_second"):
		var new_spread_rate: float = maxf(0.0, float(summary["spread_rate_per_second"]))
		if absf(new_spread_rate - spread_rate_per_second) > 0.001:
			spread_rate_per_second = new_spread_rate
			changed = true
	if summary.has("ignition_rate_per_second"):
		var new_ignition_rate: float = maxf(0.0, float(summary["ignition_rate_per_second"]))
		if absf(new_ignition_rate - ignition_rate_per_second) > 0.001:
			ignition_rate_per_second = new_ignition_rate
			changed = true
	if summary.has("cascade_rate_per_second"):
		var new_cascade_rate: float = maxf(0.0, float(summary["cascade_rate_per_second"]))
		if absf(new_cascade_rate - cascade_rate_per_second) > 0.001:
			cascade_rate_per_second = new_cascade_rate
			changed = true
	# Fire B2: round-trip deliberate vents + model-level closed bulkhead links.
	var vented_raw: Variant = summary.get("vented_compartments", null)
	if typeof(vented_raw) == TYPE_ARRAY:
		var new_vented: Dictionary = {}
		for cid in (vented_raw as Array):
			var c: String = str(cid)
			if not c.is_empty():
				new_vented[c] = true
		if new_vented != vented_compartments:
			vented_compartments = new_vented
			changed = true
	var closed_raw: Variant = summary.get("closed_links", null)
	if typeof(closed_raw) == TYPE_ARRAY:
		var new_closed: Dictionary = {}
		for key in (closed_raw as Array):
			var k: String = str(key)
			if not k.is_empty():
				new_closed[k] = true
		if new_closed != closed_links:
			closed_links = new_closed
			changed = true
	return changed

func get_status_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("Fire Suppression fires=%d suppressant=%.1f" % [get_active_fire_count(), suppressant_units])
	for cid in active_fires.keys():
		lines.append("Fire %s intensity=%.2f" % [str(cid), float(active_fires[cid])])
	return lines

func _adjacent(compartment_id: String) -> Array:
	var v: Variant = adjacency.get(compartment_id, [])
	return v if typeof(v) == TYPE_ARRAY else []

## True if any compartment adjacent to `compartment_id` is currently burning. Used to
## decide whether a spread accumulator toward `compartment_id` still has a live source.
func _has_burning_neighbour(compartment_id: String) -> bool:
	for other in _adjacent(compartment_id):
		if active_fires.has(other):
			return true
	return false

func _has_oxygen(compartment_id: String, ship_oxygen: bool, breached: Dictionary) -> bool:
	# Fire B2: deliberate vents count as vacuum for ignition/spread/extinguish.
	return ship_oxygen and not breached.has(compartment_id) and not vented_compartments.has(compartment_id)

func _to_set(list_variant: Variant) -> Dictionary:
	var out: Dictionary = {}
	if typeof(list_variant) == TYPE_ARRAY:
		for entry in (list_variant as Array):
			out[str(entry)] = true
	return out
