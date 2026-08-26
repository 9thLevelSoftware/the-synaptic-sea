extends SceneTree

const ThreatManagerScript: GDScript = preload("res://scripts/systems/threat_manager.gd")

func _initialize() -> void:
	var failures: Array[String] = []
	var manager = ThreatManagerScript.new()
	manager._ready()
	var kills: Array[Dictionary] = []
	manager.threat_killed.connect(func(record: Dictionary) -> void: kills.append(record.duplicate(true)))
	var authoritative: Dictionary = {
		"id": "spawn:rust:01",
		"room_id": "bridge",
		"cell": [2, 3],
		"local_position": [8.0, 0.0, 12.0],
		"encounter_kind": "creature_brute",
		"count": 1,
		"blueprint_id": "creature_brute",
		"creature_blueprint": {
			"id":"creature_brute", "ability_id":"ability_bash", "threat_role":"tank",
		},
		"spawn_id": "spawn:rust:01",
		"faction_id": "faction:salvage",
		"threat_role": "tank",
		"ability_id": "ability_bash",
		"reward_source_id": "reward:rust:01",
		"generated_items": [{
			"item_id": "item:plate_scrap", "quantity": 1,
			"blueprint": {"id":"item:plate_scrap"},
		}],
		"asset_ids": ["asset:primitive:creature_brute"],
		"presentation_binding_ids": ["binding:threat:brute"],
	}
	manager.configure_for_layout({}, [authoritative], Vector3.ZERO)
	if manager.threats.size() != 1:
		_fail("authoritative spawn count=%d" % manager.threats.size()); return
	var threat = manager.threats[0]
	for key in ["spawn_id", "blueprint_id", "faction_id", "threat_role", "ability_id", "reward_source_id"]:
		_expect(str(threat.get_summary().get(key, "")) == str(authoritative[key]), failures, "retained %s" % key)
	_expect(threat.generated_items == authoritative["generated_items"], failures, "retained generated_items")
	_expect(threat.creature_blueprint == authoritative["creature_blueprint"], failures, "retained creature blueprint")
	_expect(threat.asset_ids == authoritative["asset_ids"], failures, "retained asset ids")
	_expect(threat.presentation_binding_ids == authoritative["presentation_binding_ids"], failures, "retained presentation bindings")
	threat.apply_damage({"amount": 999.0})
	manager._sweep_dead_threats()
	_expect(kills.size() == 1, failures, "authoritative kill emitted")
	if kills.size() == 1:
		for key in ["spawn_id", "blueprint_id", "faction_id", "threat_role", "ability_id", "reward_source_id"]:
			_expect(str(kills[0].get(key, "")) == str(authoritative[key]), failures, "kill %s" % key)
		_expect(kills[0].get("generated_items", []) == authoritative["generated_items"], failures, "kill generated_items")
		_expect(kills[0].get("creature_blueprint", {}) == authoritative["creature_blueprint"], failures, "kill creature blueprint")
		_expect(kills[0].get("asset_ids", []) == authoritative["asset_ids"], failures, "kill asset ids")
		_expect(kills[0].get("presentation_binding_ids", []) == authoritative["presentation_binding_ids"], failures, "kill presentation bindings")

	manager.configure_for_layout({}, [{"id": "malformed", "blueprint_id": "creature_drone", "spawn_id": ""}], Vector3.ZERO)
	_expect(manager.threats.is_empty(), failures, "malformed provider fails closed")
	manager.configure_for_layout({}, [{"id": "legacy", "encounter_kind": "stalker", "room_id": "legacy_room"}], Vector3.ZERO)
	_expect(manager.threats.size() == 1 and manager.threats[0].spawn_id.is_empty(), failures, "legacy marker compatible")

	manager.free()
	if failures.is_empty():
		print("PROCGEN AUTHORITATIVE THREAT RUNTIME PASS retained=true kill_record=true malformed_fail_closed=true legacy_compatible=true")
		quit(0)
	else:
		push_error("PROCGEN AUTHORITATIVE THREAT RUNTIME FAIL reasons=%s" % str(failures))
		quit(1)

func _expect(condition: bool, failures: Array[String], label: String) -> void:
	if not condition:
		failures.append(label)

func _fail(reason: String) -> void:
	push_error("PROCGEN AUTHORITATIVE THREAT RUNTIME FAIL reason=%s" % reason)
	quit(1)
