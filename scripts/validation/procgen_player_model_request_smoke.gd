extends SceneTree

const ConsumerScript := preload("res://scripts/procgen/procgen_bundle_consumer.gd")

func _init() -> void:
	var consumer: RefCounted = ConsumerScript.new()
	var canonical: Array = [
		{"kind": "combat_mastery", "value_bp": 1000},
		{"kind": "damage_pressure", "value_bp": 2000},
		{"kind": "resource_pressure", "value_bp": 3000},
		{"kind": "objective_pace", "value_bp": 4000},
	]
	_assert(not consumer.build_request(42, 0, 1, {}, "standard", "", "site:signals", 0, 0, canonical).is_empty(), "canonical")
	_assert(not consumer.build_request(42, 0, 1, {}, "standard", "", "site:baseline", 0, 0, []).is_empty(), "baseline")

	var reordered: Array = canonical.duplicate(true)
	var first: Variant = reordered[0]
	reordered[0] = reordered[1]
	reordered[1] = first
	_assert_rejected(consumer, reordered, "reordered")
	var duplicate: Array = canonical.duplicate(true)
	duplicate[1].kind = "combat_mastery"
	_assert_rejected(consumer, duplicate, "duplicate")
	var out_of_bounds: Array = canonical.duplicate(true)
	out_of_bounds[0].value_bp = 10001
	_assert_rejected(consumer, out_of_bounds, "bounds")
	var unknown: Array = canonical.duplicate(true)
	unknown[0].kind = "account_history"
	_assert_rejected(consumer, unknown, "unknown")
	print("PROCGEN PLAYER MODEL REQUEST PASS canonical=true baseline=true fail_closed=true")
	quit(0)

func _assert_rejected(consumer: RefCounted, signals: Array, label: String) -> void:
	var result: Dictionary = consumer.build_request(
		42, 0, 1, {}, "standard", "", "site:%s" % label, 0, 0, signals)
	_assert(result.is_empty() and consumer.last_error == "request_player_model", label)

func _assert(condition: bool, label: String) -> void:
	if condition:
		return
	push_error("PROCGEN PLAYER MODEL REQUEST FAIL:%s" % label)
	quit(1)
