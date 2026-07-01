extends SceneTree

## Domain 5 Task 1: the temperature_delta dispatcher branch is now live via the
## heatpack effect. Configure a cold body temperature, dispatch heatpack, assert
## the temperature rose by the effect amount.
## Marker: THERMAL CONSUMABLE PASS temp_before=<f> temp_after=<f> temp_shifted=true

const EffectDispatcherScript := preload("res://scripts/systems/effect_dispatcher.gd")
const BodyTempScript := preload("res://scripts/systems/body_temperature_state.gd")

func _initialize() -> void:
	var dispatcher = EffectDispatcherScript.new()
	dispatcher.configure({})
	var temp = BodyTempScript.new()
	temp.configure({"temperature": 12.0})  # cold zone, below safe_min 18
	var before: float = temp.get_summary()["temperature"]
	var result: Dictionary = dispatcher.dispatch_effect("heatpack", {"body_temperature_state": temp})
	var after: float = temp.get_summary()["temperature"]
	if not bool(result.get("ok", false)):
		push_error("THERMAL CONSUMABLE FAIL reason=dispatch_%s" % str(result.get("reason", "?")))
		quit(1); return
	if abs((after - before) - 8.0) >= 0.001:
		push_error("THERMAL CONSUMABLE FAIL reason=wrong_shift before=%.3f after=%.3f expected_shift=8.0" % [before, after])
		quit(1); return
	print("THERMAL CONSUMABLE PASS temp_before=%.3f temp_after=%.3f temp_shifted=true" % [before, after])
	quit(0)
