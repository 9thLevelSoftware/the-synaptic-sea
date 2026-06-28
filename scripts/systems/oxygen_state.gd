extends RefCounted
class_name OxygenState

## Runtime model for the Gate 1 hazard pressure loop.
## This model never reaches into the scene tree. PlayableGeneratedShip owns
## the breach-zone scene node and applies scene consequences from this summary.
##
## Tunables (DEFAULT_* constants) are the values used by the Gate 1 slice.
## They are exposed via get_summary() so smokes can assert the exact tuning
## in use.
##
## Per ADR-0005 this model:
## - Implements the HazardStateContract (configure / tick / get_summary /
##   apply_summary / is_passability_blocked / get_status_lines).
## - Does NOT use PhaseTimer: oxygen is a resource-drain model with no
##   discrete phase cycle, so it intentionally does not inherit timer
##   concepts from ElectricalArcState (the lone timer hazard).
## - The HazardStateContract's `tick(delta_seconds, context)` uniform
##   boundary is preserved by reading `player_in_breach_zone` from the
##   `context` dictionary (per ADR-0005 the `context` argument is loose-
##   typed on purpose so each hazard can pull the keys it cares about).

const DEFAULT_MAX_OXYGEN: float = 100.0
const DEFAULT_DRAIN_RATE: float = 6.0
const DEFAULT_REGEN_RATE: float = 3.5
const DEFAULT_RECOVERY_THRESHOLD: float = 30.0
const DEFAULT_SAFE_THRESHOLD: float = 35.0
const HAZARD_KIND: String = "oxygen"

var breach_zone_ids: Array = []
var max_oxygen: float = DEFAULT_MAX_OXYGEN
var drain_rate: float = DEFAULT_DRAIN_RATE
var regen_rate: float = DEFAULT_REGEN_RATE
var recovery_threshold: float = DEFAULT_RECOVERY_THRESHOLD
var safe_threshold: float = DEFAULT_SAFE_THRESHOLD

var oxygen: float = DEFAULT_MAX_OXYGEN
var breach_open: bool = true
var breach_sealed: bool = false
var passability_blocked: bool = false
var last_player_in_breach_zone: bool = false
# Inventory/tool summary cache populated by apply_inventory_summary(...).
# Per REQ-007: carrying the portable oxygen pump halves the drain rate
# while the player is in an unsealed breach zone. The OxygenState model
# reads this summary before each tick to compute the effective drain
# multiplier; it does not own the InventoryState itself.
var _inventory_summary: Dictionary = {}
# Equipment summary cache populated by apply_equipment_summary(...). The worn
# suit's oxygen-drain multiplier stacks multiplicatively with the inventory
# (tool) multiplier; like the inventory summary it is recomputed live each
# frame by the coordinator and is intentionally not restored by apply_summary.
var _equipment_summary: Dictionary = {}
var effective_drain_rate: float = DEFAULT_DRAIN_RATE

# configure(config: Dictionary) -> void
# - Per ADR-0005 HazardStateContract: receives the loader's zone array
#   and tuning values as a dictionary so the model can unpack the fields
#   it needs. Recognized keys:
#     - "zone_ids": Array[String] (breach-zone ids whose drain applies)
#     - "max_oxygen": float
#     - "drain_rate": float
#     - "regen_rate": float
#     - "recovery_threshold": float (oxygen level below which the
#       corridor becomes impassable until sealed)
#     - "safe_threshold": float (oxygen level at which the HUD stops
#       warning "LOW")
#   Unknown keys are ignored for forward compatibility. Missing keys
#   fall back to the existing value, except for the zone array which
#   defaults to empty when not supplied.
# - Resets oxygen to max, opens the breach if zone_ids is non-empty, and
#   clears the sealed state so a fresh configure behaves like a clean
#   state transition. Passability is recomputed from the new state.
func configure(config: Dictionary) -> void:
	breach_zone_ids.clear()
	if config != null and config.has("zone_ids"):
		var zone_ids_variant: Variant = config["zone_ids"]
		if typeof(zone_ids_variant) == TYPE_ARRAY:
			for zone_id_variant in (zone_ids_variant as Array):
				var zone_id: String = str(zone_id_variant)
				if zone_id.is_empty():
					continue
				breach_zone_ids.append(zone_id)
	if config != null and config.has("max_oxygen"):
		max_oxygen = maxf(0.0, float(config["max_oxygen"]))
	if config != null and config.has("drain_rate"):
		drain_rate = maxf(0.0, float(config["drain_rate"]))
	if config != null and config.has("regen_rate"):
		regen_rate = maxf(0.0, float(config["regen_rate"]))
	if config != null and config.has("recovery_threshold"):
		recovery_threshold = clampf(float(config["recovery_threshold"]), 0.0, max_oxygen)
	if config != null and config.has("safe_threshold"):
		safe_threshold = clampf(float(config["safe_threshold"]), recovery_threshold, max_oxygen)
	oxygen = max_oxygen
	breach_open = breach_zone_ids.size() > 0
	breach_sealed = false
	passability_blocked = false
	last_player_in_breach_zone = false
	_inventory_summary = {}
	_equipment_summary = {}
	effective_drain_rate = drain_rate
	_recompute_passability_blocked()

# tick(delta_seconds: float, context: Dictionary = {}) -> bool
# - Per ADR-0005 HazardStateContract uniform boundary. The optional
#   `context` dictionary is the seam oxygen uses to read per-frame
#   player context: context["player_in_breach_zone"] (bool) drives the
#   drain/regen gate, and any other keys are ignored. The legacy
#   positional bool form was kept for direct callers (e.g. the
#   validation smoke force_runtime_oxygen_to_zero_for_validation
#   seam); passing a bool as the second argument is treated as
#   `player_in_breach_zone` for backward compatibility with the
#   pre-ADR-0005 call sites that pre-date the contract.
# - Returns true when oxygen / passability / breach state changed.
func tick(delta_seconds: float, context = null) -> bool:
	var player_in_breach_zone: bool = false
	if context is bool:
		# Legacy positional form: tick(delta, bool). Preserved so the
		# validation seam and any pre-ADR call sites keep working.
		player_in_breach_zone = context
	elif context != null and typeof(context) == TYPE_DICTIONARY and context.has("player_in_breach_zone"):
		player_in_breach_zone = bool(context["player_in_breach_zone"])
	last_player_in_breach_zone = player_in_breach_zone
	if delta_seconds <= 0.0:
		effective_drain_rate = drain_rate * _compute_drain_multiplier()
		return false
	var changed: bool = false
	if breach_open and not breach_sealed and player_in_breach_zone:
		var multiplier: float = _compute_drain_multiplier()
		effective_drain_rate = drain_rate * multiplier
		var drained: float = effective_drain_rate * delta_seconds
		if drained > 0.0:
			oxygen = maxf(0.0, oxygen - drained)
			changed = true
	else:
		effective_drain_rate = drain_rate * _compute_drain_multiplier()
		if not player_in_breach_zone and oxygen < max_oxygen:
			var regenerated: float = regen_rate * delta_seconds
			if regenerated > 0.0:
				oxygen = minf(max_oxygen, oxygen + regenerated)
				changed = true
	_recompute_passability_blocked()
	return changed

# REQ-007: while the player carries the portable_oxygen_pump AND the breach
# is open and not yet sealed, the drain rate is multiplied by 0.5. Outside
# any of those conditions the multiplier is 1.0 (no change vs Gate 1).
#
# The carrier-driven 0.5/1.0 selection lives on InventoryState (the single
# source of truth added in the parent task). OxygenState only enforces
# hazard-side gates: a sealed or closed breach forces 1.0 because the
# drain itself is suppressed by `breach_open and not breach_sealed` in
# tick(); keeping the multiplier at 1.0 there avoids masking inventory
# state from the summary consumer.
#
# Phase 7 sub-project B: the worn equipment's oxygen-drain multiplier
# (EquipmentState.get_oxygen_drain_multiplier()) stacks multiplicatively
# with the inventory multiplier, both gated to 1.0 when sealed/closed.
func _compute_drain_multiplier() -> float:
	if breach_sealed or not breach_open:
		return 1.0
	return _summary_drain_mult(_inventory_summary) * _summary_drain_mult(_equipment_summary)

# Reads a numeric "drain_multiplier" from a source summary (inventory or
# equipment), defaulting to the neutral 1.0 when absent or non-numeric.
func _summary_drain_mult(summary: Dictionary) -> float:
	var value: Variant = summary.get("drain_multiplier", 1.0)
	if value is float or value is int:
		return float(value)
	return 1.0

# Public seam: the scene coordinator calls this before each tick so the
# inventory state is current when the drain multiplier is evaluated.
func apply_inventory_summary(summary: Dictionary) -> void:
	_inventory_summary = summary.duplicate(true)

# Public seam: the scene coordinator calls this before each tick so the worn
# equipment's oxygen-drain multiplier (EquipmentState.get_oxygen_drain_multiplier())
# is current when the drain multiplier is evaluated. Stacks multiplicatively with
# the inventory (tool) multiplier; both are gated to 1.0 when the breach is
# sealed/closed by _compute_drain_multiplier().
func apply_equipment_summary(summary: Dictionary) -> void:
	_equipment_summary = summary.duplicate(true)

func seal_breach(_zone_id: String) -> bool:
	if not breach_open:
		return false
	if breach_sealed:
		return false
	breach_open = false
	breach_sealed = true
	# Sealing flips the passability semantic: even if oxygen is still at
	# zero, the corridor becomes safe and collision must disable.
	_recompute_passability_blocked()
	return true

func apply_ship_systems_summary(summary: Dictionary) -> bool:
	# Per docs/game/features/hazards.md, completing objective 2
	# (main_power_restored) seals the breach. Other ship-system events are
	# ignored here; this keeps the hazard parallel to route-control state.
	if not bool(summary.get("main_power_restored", false)):
		return false
	if breach_sealed:
		return false
	breach_open = false
	breach_sealed = true
	# Sealing flips the passability semantic: even if oxygen is still at
	# zero, the corridor becomes safe and collision must disable. Re-run
	# passability so downstream scene code sees the post-seal state without
	# waiting for the next tick.
	_recompute_passability_blocked()
	return true

func is_passability_blocked() -> bool:
	return passability_blocked

func is_player_in_breach_zone() -> bool:
	return last_player_in_breach_zone

# get_summary() -> Dictionary
# - Required by the ADR-0005 contract: must include `hazard_kind`
#   ("oxygen") and `passability_blocked` (bool). The remaining keys
#   are model-specific and preserve the existing Gate 1 / REQ-007
#   shape so existing saves and consumers keep working.
func get_summary() -> Dictionary:
	return {
		"hazard_kind": HAZARD_KIND,
		"oxygen": oxygen,
		"max_oxygen": max_oxygen,
		"drain_rate": drain_rate,
		"effective_drain_rate": effective_drain_rate,
		"drain_multiplier": _compute_drain_multiplier(),
		"equipment_drain_multiplier": _summary_drain_mult(_equipment_summary),
		"regen_rate": regen_rate,
		"recovery_threshold": recovery_threshold,
		"safe_threshold": safe_threshold,
		"breach_open": breach_open,
		"breach_sealed": breach_sealed,
		"passability_blocked": passability_blocked,
		"player_in_breach_zone": last_player_in_breach_zone,
		"breach_zone_ids": breach_zone_ids.duplicate(),
	}

func get_status_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	if oxygen <= 0.001:
		lines.append("Oxygen: 0 BREACH BLOCKED")
	elif oxygen <= recovery_threshold + 0.001:
		lines.append("Oxygen: %d LOW" % int(round(oxygen)))
	elif oxygen <= safe_threshold + 0.001:
		lines.append("Oxygen: %d" % int(round(oxygen)))
	else:
		lines.append("Oxygen: %d" % int(round(oxygen)))
	if breach_sealed:
		lines.append("Breach: SEALED")
	elif breach_open:
		lines.append("Breach: OPEN")
	else:
		lines.append("Breach: CLOSED")
	return lines

func _recompute_passability_blocked() -> void:
	if oxygen <= recovery_threshold + 0.001 and not breach_sealed:
		passability_blocked = true
	else:
		passability_blocked = false

# apply_summary(summary: Dictionary) -> bool
# - Per ADR-0005 HazardStateContract uniform boundary: returns false if
#   the kind does not match (a fire or electrical-arc summary cannot
#   restore an OxygenState). Returns false on null/empty input.
#   Returns true if any field changed.
# - The inventory summary is intentionally not re-applied here (the
#   live coordinator keeps the inventory state in sync each frame; the
#   snapshot's inventory_summary drives the drain multiplier
#   indirectly through the inventory model). Unknown keys are
#   ignored for forward compatibility.
func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	if str(summary.get("hazard_kind", "")) != HAZARD_KIND:
		return false
	var changed: bool = false
	var new_oxygen: float = float(summary.get("oxygen", oxygen))
	if absf(new_oxygen - oxygen) > 0.001:
		oxygen = clampf(new_oxygen, 0.0, max_oxygen)
		changed = true
	var new_max: float = float(summary.get("max_oxygen", max_oxygen))
	if absf(new_max - max_oxygen) > 0.001:
		max_oxygen = maxf(0.0, new_max)
		changed = true
	var new_drain: float = float(summary.get("drain_rate", drain_rate))
	if absf(new_drain - drain_rate) > 0.001:
		drain_rate = maxf(0.0, new_drain)
		changed = true
	var new_regen: float = float(summary.get("regen_rate", regen_rate))
	if absf(new_regen - regen_rate) > 0.001:
		regen_rate = maxf(0.0, new_regen)
		changed = true
	var new_recovery: float = float(summary.get("recovery_threshold", recovery_threshold))
	if absf(new_recovery - recovery_threshold) > 0.001:
		recovery_threshold = clampf(new_recovery, 0.0, max_oxygen)
		changed = true
	var new_safe: float = float(summary.get("safe_threshold", safe_threshold))
	if absf(new_safe - safe_threshold) > 0.001:
		safe_threshold = clampf(new_safe, recovery_threshold, max_oxygen)
		changed = true
	var new_breach_open: bool = bool(summary.get("breach_open", breach_open))
	if new_breach_open != breach_open:
		breach_open = new_breach_open
		changed = true
	var new_breach_sealed: bool = bool(summary.get("breach_sealed", breach_sealed))
	if new_breach_sealed != breach_sealed:
		breach_sealed = new_breach_sealed
		changed = true
	var new_player_in: bool = bool(summary.get("player_in_breach_zone", last_player_in_breach_zone))
	if new_player_in != last_player_in_breach_zone:
		last_player_in_breach_zone = new_player_in
		changed = true
	var new_zone_ids_variant: Variant = summary.get("breach_zone_ids", breach_zone_ids)
	if typeof(new_zone_ids_variant) == TYPE_ARRAY and (new_zone_ids_variant as Array) != breach_zone_ids:
		breach_zone_ids = []
		for zone_id in (new_zone_ids_variant as Array):
			breach_zone_ids.append(str(zone_id))
		changed = true
	_recompute_passability_blocked()
	return changed
