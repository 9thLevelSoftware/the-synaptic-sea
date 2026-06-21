extends "res://scripts/systems/ship_system.gd"
class_name LifeSupportSystem

## The one system with a model-level time effect: it owns an OxygenState and
## drains it while Life Support is not operational. Reuses the existing
## OxygenState drain semantics by mapping "life support offline" onto the
## oxygen model's "player_in_breach_zone" gate.

const OxygenStateScript := preload("res://scripts/systems/oxygen_state.gd")

var oxygen_state: OxygenStateScript

func _init(p_system_id: String = "life_support", p_dependency_ids: Array[String] = []) -> void:
	super(p_system_id, p_dependency_ids)
	oxygen_state = OxygenStateScript.new()
	# Configure with a single zone so breach_open == true and the model is in
	# its drainable state; we never seal it. Drain/regen is then gated purely
	# by the operational flag we pass into tick().
	oxygen_state.configure({"zone_ids": ["life_support"]})

func get_oxygen_state() -> OxygenStateScript:
	return oxygen_state

## Offline -> oxygen drains (player_in_breach_zone == true). Operational ->
## oxygen regenerates per the OxygenState model.
func advance(delta: float, operational: bool) -> void:
	oxygen_state.tick(delta, {"player_in_breach_zone": not operational})

func get_summary() -> Dictionary:
	var base: Dictionary = super.get_summary()
	base["oxygen"] = oxygen_state.get_summary()
	return base

func apply_summary(summary: Dictionary) -> bool:
	var changed: bool = super.apply_summary(summary)
	var oxy_variant: Variant = summary.get("oxygen", null)
	if typeof(oxy_variant) == TYPE_DICTIONARY:
		if oxygen_state.apply_summary(oxy_variant):
			changed = true
	return changed
