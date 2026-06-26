extends SceneTree

func _initialize() -> void:
	var script := load("res://scripts/systems/unique_item_state.gd")
	if script == null:
		_fail("could not load unique_item_state.gd")
		return
	var state = script.new()
	state.configure()
	if not state.can_claim("captains_black_box", "seed:a"):
		_fail("fresh state should allow first claim")
		return
	if not state.claim("captains_black_box", "seed:a", "captains_black_box"):
		_fail("claim should succeed")
		return
	if state.can_claim("captains_black_box", "seed:a"):
		_fail("claimed unique should not be claimable again")
		return
	if state.claim("captains_black_box", "seed:a", "captains_black_box"):
		_fail("duplicate claim should fail")
		return
	if not state.record_codex_unlock("sargasso_reliquary"):
		_fail("new codex unlock should record")
		return
	if state.record_codex_unlock("sargasso_reliquary"):
		_fail("duplicate codex unlock should fail")
		return
	var summary: Dictionary = state.get_summary()
	var clone = script.new()
	clone.configure(summary)
	if not clone.is_claimed("captains_black_box"):
		_fail("summary round-trip lost claimed unique")
		return
	if not clone.is_seed_claimed("seed:a"):
		_fail("summary round-trip lost claimed seed")
		return
	if not clone.unlocked_codex_entry_ids.has("captains_black_box"):
		_fail("claim should persist codex unlock")
		return
	if not clone.unlocked_codex_entry_ids.has("sargasso_reliquary"):
		_fail("recorded codex unlock missing after round-trip")
		return
	print("UNIQUE ITEM STATE PASS claimed=%d codex=%d" % [clone.claimed_unique_ids.size(), clone.unlocked_codex_entry_ids.size()])
	quit(0)

func _fail(reason: String) -> void:
	push_error("UNIQUE ITEM STATE FAIL reason=%s" % reason)
	quit(1)
