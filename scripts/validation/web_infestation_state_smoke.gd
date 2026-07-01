extends SceneTree

## Domain 4 Task 1: WebInfestationState pure model.
## - Attached: coverage grows over time and tick() returns hull damage > 0.
## - Cut free: coverage recedes.
## - get_summary/apply_summary round-trip; apply_summary rejects a wrong hazard_kind.
## Marker: WEB INFESTATION PASS grows=true recedes=true damage_live=true save_roundtrip=true reject=true

const WebInfestationStateScript := preload("res://scripts/systems/web_infestation_state.gd")

func _initialize() -> void:
	var grows := _test_grows_and_damages()
	var recedes := _test_recedes_when_cut()
	var roundtrip := _test_save_roundtrip()
	var reject := _test_reject_bad_kind()
	if grows and recedes and roundtrip and reject:
		print("WEB INFESTATION PASS grows=true recedes=true damage_live=true save_roundtrip=true reject=true")
		quit(0)
	else:
		push_error("WEB INFESTATION FAIL grows=%s recedes=%s roundtrip=%s reject=%s" % [str(grows), str(recedes), str(roundtrip), str(reject)])
		quit(1)

func _test_grows_and_damages() -> bool:
	var w = WebInfestationStateScript.new()
	w.configure({})  # defaults: attached_to_web = true, seed_coverage = 0.0
	var dmg: float = 0.0
	for i in range(50):
		dmg += w.tick(1.0, false)
	return w.coverage > 0.5 and dmg > 0.0

func _test_recedes_when_cut() -> bool:
	var w = WebInfestationStateScript.new()
	w.configure({"seed_coverage": 0.8})
	w.cut_free()
	var before: float = w.coverage
	for i in range(5):
		w.tick(1.0, false)
	return (not w.attached_to_web) and w.coverage < before

func _test_save_roundtrip() -> bool:
	var w = WebInfestationStateScript.new()
	w.configure({"seed_coverage": 0.42})
	w.cut_free()
	var summary: Dictionary = w.get_summary()
	var w2 = WebInfestationStateScript.new()
	w2.configure({})
	var ok: bool = w2.apply_summary(summary)
	return ok and absf(w2.coverage - 0.42) < 0.001 and w2.attached_to_web == false

func _test_reject_bad_kind() -> bool:
	var w = WebInfestationStateScript.new()
	w.configure({})
	return w.apply_summary({"hazard_kind": "not_web", "coverage": 0.9}) == false
