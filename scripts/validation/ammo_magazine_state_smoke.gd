extends SceneTree

## Domain 5 Task 2: ammo_state is now a per-weapon magazine with a timed reload.
## Asserts spend/empty/begin_reload/tick-completion and summary round-trip.
## Marker: AMMO MAGAZINE STATE PASS spent=true empty=true reloaded=true roundtrip=true

const AmmoStateScript := preload("res://scripts/systems/ammo_state.gd")

func _initialize() -> void:
	var a = AmmoStateScript.new()
	a.configure({"magazines": {"flare_pistol": 1}})
	var spent: bool = a.spend("flare_pistol") and a.loaded("flare_pistol") == 0
	var empty: bool = not a.spend("flare_pistol")  # magazine now empty -> false
	# Reload 2 rounds from a 2-round magazine with 5 in reserve.
	var began: bool = a.begin_reload("flare_pistol", 2, 5) and a.reload_target == 2 and a.is_reloading()
	# tick less than RELOAD_SECONDS: not done
	var mid: Dictionary = a.tick(0.5)
	var not_done: bool = mid.is_empty() and a.is_reloading()
	# tick past completion
	var done: Dictionary = a.tick(2.0)
	var reloaded: bool = began and not_done and done.get("weapon_id", "") == "flare_pistol" \
		and int(done.get("loaded", 0)) == 2 and a.loaded("flare_pistol") == 2 and not a.is_reloading()
	# summary round-trip mid-reload
	var b = AmmoStateScript.new()
	b.configure({"magazines": {"shock_probe": 3}})
	b.begin_reload("shock_probe", 5, 4)
	var c = AmmoStateScript.new()
	c.apply_summary(b.get_summary())
	var roundtrip: bool = c.loaded("shock_probe") == 3 and c.is_reloading() and c.reload_target == b.reload_target
	if spent and empty and reloaded and roundtrip:
		print("AMMO MAGAZINE STATE PASS spent=true empty=true reloaded=true roundtrip=true")
		quit(0)
	else:
		push_error("AMMO MAGAZINE STATE FAIL spent=%s empty=%s reloaded=%s roundtrip=%s" % [str(spent), str(empty), str(reloaded), str(roundtrip)])
		quit(1)
