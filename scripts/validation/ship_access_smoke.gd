extends SceneTree

## Pure-model smoke for ShipAccessState: claim/grant/revoke/has_access semantics,
## owner cannot be revoked, and summary round-trip.

const ShipAccessStateScript := preload("res://scripts/systems/ship_access_state.gd")

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

	print("SHIP ACCESS SMOKE PASS owner=%s access=%d" % [b.owner_id, b.access_ids.size()])
	quit()
