extends SceneTree

## PKG-C3.1a: typed wounds pure model — bleed, infection, fracture/arm work-speed mult, treat.
## Marker: WOUND STATE PASS kinds=true bleed=true infection=true work_speed=true treat=true round_trip=true

const WoundStateScript := preload("res://scripts/systems/wound_state.gd")
const WorkActionStateScript := preload("res://scripts/systems/work_action_state.gd")
const WorkActionCatalogScript := preload("res://scripts/systems/work_action_catalog.gd")


func _initialize() -> void:
	var ws = WoundStateScript.new()
	ws.configure({})
	if ws.wound_count() != 0:
		_fail("empty start"); return

	# Reject invalid kind
	if not ws.apply_wound({"kind": "magic", "severity": 0.5}).is_empty():
		_fail("invalid kind should reject"); return

	var lac: String = ws.apply_wound({
		"kind": WoundStateScript.KIND_LACERATION,
		"body_part": WoundStateScript.BODY_TORSO,
		"severity": 0.6,
	})
	if lac.is_empty():
		_fail("laceration apply"); return
	var bleed_lac: float = ws.total_bleed_rate()
	if bleed_lac < 0.1:
		_fail("laceration should bleed, got %s" % str(bleed_lac)); return

	var burn: String = ws.apply_wound({
		"kind": WoundStateScript.KIND_BURN,
		"body_part": WoundStateScript.BODY_TORSO,
		"severity": 0.7,
	})
	if burn.is_empty():
		_fail("burn apply"); return
	var peak_inf: float = ws.peak_infection_chance()
	if peak_inf < 0.3:
		_fail("burn should raise infection chance, got %s" % str(peak_inf)); return

	var puncture: String = ws.apply_wound({
		"kind": WoundStateScript.KIND_PUNCTURE,
		"body_part": WoundStateScript.BODY_ARM,
		"severity": 0.5,
	})
	if puncture.is_empty():
		_fail("puncture"); return

	# Arm fracture taxes work speed hard
	var frac: String = ws.apply_wound({
		"kind": WoundStateScript.KIND_FRACTURE,
		"body_part": WoundStateScript.BODY_ARM,
		"severity": 0.8,
	})
	if frac.is_empty():
		_fail("fracture"); return
	var work_mult: float = ws.work_speed_multiplier()
	if work_mult > 0.55:
		_fail("arm fracture should slow work substantially, got %s" % str(work_mult)); return
	if work_mult < 0.05:
		_fail("work mult floor"); return

	# Leg fracture slows move
	ws.apply_wound({
		"kind": WoundStateScript.KIND_FRACTURE,
		"body_part": WoundStateScript.BODY_LEG,
		"severity": 0.6,
	})
	if ws.movement_speed_multiplier() >= 0.95:
		_fail("leg fracture should slow move"); return

	# Thirst up with bleed
	if ws.thirst_drain_multiplier() <= 1.0:
		_fail("bleed should raise thirst mult"); return

	# WorkAction consumes work_speed_mult from wounds
	var cat = WorkActionCatalogScript.new()
	if not cat.load_default():
		_fail("wa catalog"); return
	var work = WorkActionStateScript.new()
	work.configure_action("cut_wall", cat.get_action("cut_wall"))
	work.start("wall_x", {
		"tool_class": "welding_lance",
		"skill_id": "salvage",
		"skill_level": 0,
		"inventory": {},
	})
	work.tick(2.0, {"work_speed_mult": work_mult})
	var slow_progress: float = work.progress
	work.reset()
	work.configure_action("cut_wall", cat.get_action("cut_wall"))
	work.start("wall_y", {
		"tool_class": "welding_lance",
		"skill_id": "salvage",
		"skill_level": 0,
		"inventory": {},
	})
	work.tick(2.0, {"work_speed_mult": 1.0})
	if slow_progress >= work.progress - 0.001:
		_fail("wound work_speed_mult should slow WorkAction progress (%s vs %s)" % [str(slow_progress), str(work.progress)])
		return

	# Bandage reduces bleed
	var before_bleed: float = ws.total_bleed_rate()
	if not ws.bandage(lac):
		_fail("bandage"); return
	if ws.total_bleed_rate() >= before_bleed:
		_fail("bandage should reduce total bleed"); return

	# Treat clears infection on that wound
	if not ws.treat(burn):
		_fail("treat burn"); return
	var burn_e: Dictionary = ws.get_wound(burn)
	if not bool(burn_e.get("treated", false)):
		_fail("treated flag"); return
	if float(burn_e.get("infection_chance", 1.0)) > 0.001:
		_fail("treat should clear infection chance"); return

	# tick ages
	ws.tick(10.0)
	var aged: Dictionary = ws.get_wound(lac)
	if float(aged.get("age_seconds", 0.0)) < 9.0:
		_fail("age tick"); return

	# suggest_from_damage
	var sug: Dictionary = WoundStateScript.suggest_from_damage(20.0, "burn", WoundStateScript.BODY_TORSO)
	if str(sug.get("kind", "")) != WoundStateScript.KIND_BURN:
		_fail("suggest burn"); return
	if float(sug.get("severity", 0.0)) <= 0.0:
		_fail("suggest severity"); return

	# round-trip
	var snap: Dictionary = ws.get_summary()
	var ws2 = WoundStateScript.new()
	if not ws2.apply_summary(snap):
		_fail("apply_summary"); return
	if ws2.wound_count() != ws.wound_count():
		_fail("round-trip count"); return
	if absf(ws2.work_speed_multiplier() - ws.work_speed_multiplier()) > 0.001:
		_fail("round-trip work mult"); return

	var lines: PackedStringArray = ws.get_status_lines()
	if lines.is_empty():
		_fail("status lines"); return

	print("WOUND STATE PASS kinds=true bleed=true infection=true work_speed=true treat=true round_trip=true")
	quit(0)


func _fail(msg: String) -> void:
	print("WOUND STATE FAIL: %s" % msg)
	quit(1)
