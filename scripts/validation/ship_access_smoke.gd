extends SceneTree

## Pure-model smoke for ShipAccessState: claim/grant/revoke/has_access semantics,
## owner cannot be revoked, and summary round-trip.

const ShipAccessStateScript := preload("res://scripts/systems/ship_access_state.gd")
const ShipInstanceScript := preload("res://scripts/systems/ship_instance.gd")
const ShipSystemsManagerScript := preload("res://scripts/systems/ship_systems_manager.gd")

func _init() -> void:
	var a = ShipAccessStateScript.create()
	assert(a.owner_id == "", "fresh access has no owner")
	assert(not a.has_access("player_local"), "no access before claim")

	# claim sets owner + grants access; idempotent for same owner; rejects new owner.
	assert(a.claim("player_local") == true, "first claim succeeds")
	assert(a.owner_id == "player_local", "owner recorded")
	assert(a.has_access("player_local"), "owner has access")
	assert(a.claim("player_local") == true, "re-claim by owner is idempotent true")
	assert(a.claim("player_2") == false, "claim by non-owner of owned ship fails")
	assert(a.owner_id == "player_local", "owner unchanged after failed claim")

	# grant/revoke for additional players; owner cannot be revoked.
	a.grant("player_2")
	assert(a.has_access("player_2"), "granted player has access")
	a.revoke("player_2")
	assert(not a.has_access("player_2"), "revoked player loses access")
	a.revoke("player_local")
	assert(a.has_access("player_local"), "owner cannot be revoked")

	# summary round-trip.
	a.grant("player_3")
	var summary: Dictionary = a.get_summary()
	var b = ShipAccessStateScript.create()
	assert(b.apply_summary(summary) == true, "apply_summary accepts valid dict")
	assert(b.owner_id == "player_local", "owner round-trips")
	assert(b.has_access("player_3"), "granted access round-trips")
	assert(b.apply_summary("not a dict") == false, "apply_summary rejects non-dict")

	# ShipInstance owns a ShipAccessState that round-trips through its summary.
	var inst = ShipInstanceScript.create("ship_test", "cell:cell:1", null, null, null)
	assert(inst.get_access().owner_id == "", "fresh ship unowned")
	inst.get_access().claim("player_local")
	var inst_summary: Dictionary = inst.get_summary()
	assert(inst_summary.has("access"), "ship summary carries access")
	var inst2 = ShipInstanceScript.create("ship_test", "cell:cell:1", null, null, null)
	inst2.apply_summary(inst_summary)
	assert(inst2.get_access().owner_id == "player_local", "ship access round-trips")

	# is_working_vessel reads the ship's own propulsion operational status.
	assert(inst.is_working_vessel() == false, "no systems manager -> not working")
	var mgr = ShipSystemsManagerScript.new()
	mgr.configure(mgr.load_definitions(), 0, 0)   # condition 0 = pristine -> all operational
	var working_inst = ShipInstanceScript.create("ship_ok", "cell:cell:2", null, mgr, null)
	assert(working_inst.is_working_vessel() == true, "operational propulsion -> working vessel")

	print("SHIP ACCESS SMOKE PASS owner=%s access=%d ship_owner=%s" % [b.owner_id, b.access_ids.size(), inst2.get_access().owner_id])
	quit()
