extends SceneTree

## Phase 2a: per-ship hull + web models on ShipInstance.
## Asserts:
##   1. hull_roundtrip: configure/damage hull; summary round-trips to a fresh instance.
##   2. web_roundtrip: coverage + cut_free survive save/load.
##   3. web_attached_delegates: is_web_attached() delegates to the web model.
## Marker: SHIP INSTANCE MODELS PASS hull_roundtrip=true web_roundtrip=true web_attached_delegates=true

const ShipInstanceScript := preload("res://scripts/systems/ship_instance.gd")
const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")
const ShipSystemsManagerScript := preload("res://scripts/systems/ship_systems_manager.gd")

func _initialize() -> void:
	var bp = ShipBlueprintScript.new(ShipBlueprintScript.Size.SMALL, ShipBlueprintScript.Condition.DAMAGED, 4242)
	var mgr = ShipSystemsManagerScript.new()
	mgr.configure(mgr.load_definitions(), bp.condition, bp.seed_value)

	# --- 1. hull_roundtrip ---
	var inst = ShipInstanceScript.create("ship_hull_test", "0:0:0", bp, mgr, null)
	inst.get_hull().configure({"compartments": [{"compartment_id": "bridge", "health": 1.0}]})
	inst.get_hull().damage_compartment("bridge", 0.6, true)

	if not inst.has_hull():
		_fail("has_hull() should be true after configure")
		return

	var integ_before: float = inst.get_hull().average_integrity()
	var breach_before: int = inst.get_hull().get_breach_count()

	var summary: Dictionary = inst.get_summary()
	if not summary.has("hull"):
		_fail("get_summary() missing 'hull' key when hull has compartments")
		return

	var restored = ShipInstanceScript.create("", "", null, null, null)
	if not restored.apply_summary(summary):
		_fail("apply_summary returned false for hull-bearing summary")
		return

	if not restored.has_hull():
		_fail("restored instance has_hull() returned false")
		return

	var hull_roundtrip: bool = (
		absf(restored.get_hull().average_integrity() - integ_before) < 0.001
		and restored.get_hull().get_breach_count() > 0
		and breach_before > 0
	)
	if not hull_roundtrip:
		_fail("hull_roundtrip failed: integ=%.3f breach=%d" % [
			restored.get_hull().average_integrity(),
			restored.get_hull().get_breach_count()
		])
		return

	# --- 2. web_roundtrip ---
	var inst2 = ShipInstanceScript.create("ship_web_test", "0:0:1", bp, mgr, null)
	inst2.get_web().coverage = 0.42
	inst2.get_web().cut_free()

	var summary2: Dictionary = inst2.get_summary()
	if not summary2.has("web"):
		_fail("get_summary() missing 'web' key when web has coverage > 0 and cut free")
		return

	var restored2 = ShipInstanceScript.create("", "", null, null, null)
	if not restored2.apply_summary(summary2):
		_fail("apply_summary returned false for web-bearing summary")
		return

	var web_roundtrip: bool = (
		absf(restored2.get_web().coverage - 0.42) < 0.001
		and not restored2.is_web_attached()
	)
	if not web_roundtrip:
		_fail("web_roundtrip failed: coverage=%.3f attached=%s" % [
			restored2.get_web().coverage, str(restored2.is_web_attached())
		])
		return

	# --- 3. web_attached_delegates ---
	var inst3 = ShipInstanceScript.create("ship_delegate_test", "0:0:2", null, null, null)
	var default_attached: bool = inst3.is_web_attached()
	inst3.get_web().cut_free()
	var after_cut: bool = inst3.is_web_attached()

	var web_attached_delegates: bool = default_attached == true and after_cut == false
	if not web_attached_delegates:
		_fail("web_attached_delegates failed: default=%s after_cut=%s" % [
			str(default_attached), str(after_cut)
		])
		return

	print("SHIP INSTANCE MODELS PASS hull_roundtrip=true web_roundtrip=true web_attached_delegates=true")
	quit(0)

func _fail(reason: String) -> void:
	push_error("SHIP INSTANCE MODELS FAIL reason=%s" % reason)
	quit(1)
