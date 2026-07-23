extends RefCounted
class_name WoundState

## PKG-C3.1a: typed wounds pure model (laceration/burn/fracture/puncture).
## Tracks severity, bleed, infection risk, treatment, and WorkAction work-speed mult.
## Never touches the scene tree. Scene/coordinator apply multipliers into vitals tick
## and WorkActionState context (work_speed_mult).

const KIND_LACERATION: String = "laceration"
const KIND_BURN: String = "burn"
const KIND_FRACTURE: String = "fracture"
const KIND_PUNCTURE: String = "puncture"

const BODY_TORSO: String = "torso"
const BODY_ARM: String = "arm"
const BODY_LEG: String = "leg"
const BODY_HEAD: String = "head"

const VALID_KINDS: Array[String] = [KIND_LACERATION, KIND_BURN, KIND_FRACTURE, KIND_PUNCTURE]
const VALID_BODY: Array[String] = [BODY_TORSO, BODY_ARM, BODY_LEG, BODY_HEAD]

## wounds: Array of {
##   wound_id, kind, body_part, severity (0..1), bleed_rate, infection_chance,
##   treated (bool), bandaged (bool), age_seconds
## }
var wounds: Array = []
var _next_id: int = 1


func configure(config: Dictionary = {}) -> void:
	wounds.clear()
	_next_id = 1
	var raw: Variant = config.get("wounds", [])
	if raw is Array:
		for entry in raw:
			if entry is Dictionary:
				_ingest_wound(entry as Dictionary)


func clear() -> void:
	wounds.clear()
	_next_id = 1


func wound_count() -> int:
	return wounds.size()


func active_count() -> int:
	var n: int = 0
	for w in wounds:
		if typeof(w) != TYPE_DICTIONARY:
			continue
		if float((w as Dictionary).get("severity", 0.0)) > 0.001:
			n += 1
	return n


## Apply a wound from a damage event. Returns wound_id or empty on reject.
## event keys: kind, body_part, severity (0..1), optional source_id
func apply_wound(event: Dictionary) -> String:
	var kind: String = str(event.get("kind", KIND_LACERATION))
	if not VALID_KINDS.has(kind):
		return ""
	var body: String = str(event.get("body_part", BODY_TORSO))
	if not VALID_BODY.has(body):
		body = BODY_TORSO
	var severity: float = clampf(float(event.get("severity", 0.3)), 0.05, 1.0)
	var wound_id: String = str(event.get("wound_id", ""))
	if wound_id.is_empty():
		wound_id = "w%d" % _next_id
		_next_id += 1
	var bleed: float = _base_bleed(kind, severity)
	var infection: float = _base_infection(kind, severity)
	var entry: Dictionary = {
		"wound_id": wound_id,
		"kind": kind,
		"body_part": body,
		"severity": severity,
		"bleed_rate": bleed,
		"infection_chance": infection,
		"treated": false,
		"bandaged": false,
		"age_seconds": 0.0,
		"source_id": str(event.get("source_id", "")),
	}
	wounds.append(entry)
	return wound_id


func _ingest_wound(entry: Dictionary) -> void:
	var kind: String = str(entry.get("kind", KIND_LACERATION))
	if not VALID_KINDS.has(kind):
		return
	var wound_id: String = str(entry.get("wound_id", ""))
	if wound_id.is_empty():
		wound_id = "w%d" % _next_id
		_next_id += 1
	else:
		var num: int = int(wound_id.trim_prefix("w"))
		if num >= _next_id:
			_next_id = num + 1
	var severity: float = clampf(float(entry.get("severity", 0.3)), 0.0, 1.0)
	wounds.append({
		"wound_id": wound_id,
		"kind": kind,
		"body_part": str(entry.get("body_part", BODY_TORSO)),
		"severity": severity,
		"bleed_rate": float(entry.get("bleed_rate", _base_bleed(kind, severity))),
		"infection_chance": float(entry.get("infection_chance", _base_infection(kind, severity))),
		"treated": bool(entry.get("treated", false)),
		"bandaged": bool(entry.get("bandaged", false)),
		"age_seconds": float(entry.get("age_seconds", 0.0)),
		"source_id": str(entry.get("source_id", "")),
	})


func _base_bleed(kind: String, severity: float) -> float:
	match kind:
		KIND_LACERATION:
			return severity * 0.35
		KIND_PUNCTURE:
			return severity * 0.45
		KIND_BURN:
			return severity * 0.08
		KIND_FRACTURE:
			return severity * 0.05
		_:
			return severity * 0.2


func _base_infection(kind: String, severity: float) -> float:
	match kind:
		KIND_BURN:
			return clampf(severity * 0.55, 0.0, 0.95)
		KIND_PUNCTURE:
			return clampf(severity * 0.40, 0.0, 0.90)
		KIND_LACERATION:
			return clampf(severity * 0.25, 0.0, 0.80)
		KIND_FRACTURE:
			return clampf(severity * 0.10, 0.0, 0.50)
		_:
			return clampf(severity * 0.2, 0.0, 0.7)


func get_wound(wound_id: String) -> Dictionary:
	for w in wounds:
		if typeof(w) != TYPE_DICTIONARY:
			continue
		if str((w as Dictionary).get("wound_id", "")) == wound_id:
			return (w as Dictionary).duplicate(true)
	return {}


## Total bleed rate across untreated/unbandaged wounds (health/sec contribution for vitals).
func total_bleed_rate() -> float:
	var total: float = 0.0
	for w in wounds:
		if typeof(w) != TYPE_DICTIONARY:
			continue
		var e: Dictionary = w
		if float(e.get("severity", 0.0)) <= 0.001:
			continue
		var rate: float = float(e.get("bleed_rate", 0.0))
		if bool(e.get("bandaged", false)):
			rate *= 0.25
		if bool(e.get("treated", false)):
			rate *= 0.1
		total += rate
	return total


## Peak infection chance among open wounds (for SLOW infection rolls later).
func peak_infection_chance() -> float:
	var peak: float = 0.0
	for w in wounds:
		if typeof(w) != TYPE_DICTIONARY:
			continue
		var e: Dictionary = w
		if bool(e.get("treated", false)):
			continue
		if float(e.get("severity", 0.0)) <= 0.001:
			continue
		peak = maxf(peak, float(e.get("infection_chance", 0.0)))
	return peak


## Fracture / arm injury slows work (WorkActionState context work_speed_mult).
func work_speed_multiplier() -> float:
	var mult: float = 1.0
	for w in wounds:
		if typeof(w) != TYPE_DICTIONARY:
			continue
		var e: Dictionary = w
		var sev: float = float(e.get("severity", 0.0))
		if sev <= 0.001:
			continue
		var kind: String = str(e.get("kind", ""))
		var body: String = str(e.get("body_part", ""))
		if kind == KIND_FRACTURE:
			# Fractures always tax work speed; arm fractures hit harder.
			var tax: float = 0.15 + sev * 0.35
			if body == BODY_ARM:
				tax = 0.25 + sev * 0.50
			mult *= clampf(1.0 - tax, 0.15, 1.0)
		elif body == BODY_ARM and (kind == KIND_LACERATION or kind == KIND_PUNCTURE):
			mult *= clampf(1.0 - sev * 0.20, 0.4, 1.0)
	return clampf(mult, 0.05, 1.0)


## Movement speed mult for leg/torso fractures (API for coordinator).
func movement_speed_multiplier() -> float:
	var mult: float = 1.0
	for w in wounds:
		if typeof(w) != TYPE_DICTIONARY:
			continue
		var e: Dictionary = w
		var sev: float = float(e.get("severity", 0.0))
		if sev <= 0.001:
			continue
		if str(e.get("kind", "")) == KIND_FRACTURE and str(e.get("body_part", "")) == BODY_LEG:
			mult *= clampf(1.0 - (0.20 + sev * 0.40), 0.2, 1.0)
	return clampf(mult, 0.1, 1.0)


## Thirst drain mult — open bleeding wounds raise thirst (C3.1b will curve this).
func thirst_drain_multiplier() -> float:
	var bleed: float = total_bleed_rate()
	return 1.0 + clampf(bleed * 0.8, 0.0, 1.5)


## Bandage reduces bleed immediately. Returns false if wound missing.
func bandage(wound_id: String) -> bool:
	for i in range(wounds.size()):
		if typeof(wounds[i]) != TYPE_DICTIONARY:
			continue
		var e: Dictionary = wounds[i]
		if str(e.get("wound_id", "")) != wound_id:
			continue
		e["bandaged"] = true
		e["bleed_rate"] = float(e.get("bleed_rate", 0.0)) * 0.4
		wounds[i] = e
		return true
	return false


## Full treatment (medicine) clears infection risk and marks treated; reduces severity.
func treat(wound_id: String, severity_reduce: float = 0.35) -> bool:
	for i in range(wounds.size()):
		if typeof(wounds[i]) != TYPE_DICTIONARY:
			continue
		var e: Dictionary = wounds[i]
		if str(e.get("wound_id", "")) != wound_id:
			continue
		e["treated"] = true
		e["bandaged"] = true
		e["infection_chance"] = 0.0
		e["severity"] = maxf(0.0, float(e.get("severity", 0.0)) - maxf(0.0, severity_reduce))
		e["bleed_rate"] = _base_bleed(str(e.get("kind", "")), float(e.get("severity", 0.0))) * 0.15
		wounds[i] = e
		return true
	return false


## Age wounds; untreated severity can creep infection_chance slightly.
func tick(delta_seconds: float) -> void:
	if delta_seconds <= 0.0:
		return
	for i in range(wounds.size()):
		if typeof(wounds[i]) != TYPE_DICTIONARY:
			continue
		var e: Dictionary = wounds[i]
		e["age_seconds"] = float(e.get("age_seconds", 0.0)) + delta_seconds
		if not bool(e.get("treated", false)) and float(e.get("severity", 0.0)) > 0.0:
			var inf: float = float(e.get("infection_chance", 0.0))
			e["infection_chance"] = clampf(inf + delta_seconds * 0.002 * float(e.get("severity", 0.0)), 0.0, 0.98)
		wounds[i] = e


## Optional: convert damage pipeline result into a wound event suggestion.
static func suggest_from_damage(final_damage: float, damage_type: String = "", body_part: String = BODY_TORSO) -> Dictionary:
	if final_damage < 2.0:
		return {}
	var kind: String = KIND_LACERATION
	match damage_type:
		"burn", "fire", "heat":
			kind = KIND_BURN
		"blunt", "crush", "impact":
			kind = KIND_FRACTURE
		"pierce", "bullet", "stab":
			kind = KIND_PUNCTURE
		_:
			kind = KIND_LACERATION
	var severity: float = clampf(final_damage / 40.0, 0.1, 1.0)
	return {
		"kind": kind,
		"body_part": body_part if not body_part.is_empty() else BODY_TORSO,
		"severity": severity,
	}


func get_summary() -> Dictionary:
	return {
		"schema": "wound_state_v1",
		"next_id": _next_id,
		"count": wounds.size(),
		"wounds": wounds.duplicate(true),
		"bleed_rate": total_bleed_rate(),
		"work_speed_mult": work_speed_multiplier(),
		"move_speed_mult": movement_speed_multiplier(),
		"thirst_mult": thirst_drain_multiplier(),
	}


func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	wounds.clear()
	_next_id = maxi(1, int(summary.get("next_id", 1)))
	var raw: Variant = summary.get("wounds", [])
	if raw is Array:
		for entry in raw:
			if entry is Dictionary:
				wounds.append((entry as Dictionary).duplicate(true))
	return true


func get_status_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	if wounds.is_empty():
		lines.append("Wounds: none")
		return lines
	lines.append("Wounds: %d bleed=%.2f work×%.2f" % [active_count(), total_bleed_rate(), work_speed_multiplier()])
	for w in wounds:
		if typeof(w) != TYPE_DICTIONARY:
			continue
		var e: Dictionary = w
		if float(e.get("severity", 0.0)) <= 0.001:
			continue
		var flags: String = ""
		if bool(e.get("treated", false)):
			flags += "T"
		if bool(e.get("bandaged", false)):
			flags += "B"
		if flags.is_empty():
			flags = "-"
		lines.append("  %s %s@%s sev=%.2f [%s]" % [
			str(e.get("wound_id", "")),
			str(e.get("kind", "")),
			str(e.get("body_part", "")),
			float(e.get("severity", 0.0)),
			flags,
		])
	return lines
