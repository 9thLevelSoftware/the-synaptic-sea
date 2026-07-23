extends SceneTree

## PKG-D7: every catalog skill has live effect consumers; work/craft/heal multipliers scale.
## Marker: SKILL EFFECTS PASS audit=true work=true craft=true heal=true travel=true class_kit=true

const SkillEffectsResolverScript := preload("res://scripts/systems/skill_effects_resolver.gd")
const PlayerProgressionStateScript := preload("res://scripts/systems/player_progression_state.gd")
const WorkActionCatalogScript := preload("res://scripts/systems/work_action_catalog.gd")
const WorkActionStateScript := preload("res://scripts/systems/work_action_state.gd")


func _initialize() -> void:
	var res = SkillEffectsResolverScript.new()
	if not res.load_default():
		_fail("load skill_effects.json"); return
	if res.effect_count() < 22:
		_fail("expected >=22 skill effects, got %d" % res.effect_count()); return

	var audit: Dictionary = res.audit_catalog_coverage()
	if not bool(audit.get("ok", false)):
		_fail("audit failed missing=%s emit_only=%s covered=%s" % [
			str(audit.get("missing", [])),
			str(audit.get("emit_only", [])),
			str(audit.get("covered", 0)),
		])
		return
	if int(audit.get("catalog_count", 0)) < 22:
		_fail("catalog_count"); return

	# Progression mock: high repair/scavenging/welding
	var catalog: Dictionary = PlayerProgressionStateScript.load_skills_catalog()
	var prog = PlayerProgressionStateScript.new()
	prog.configure(null, catalog, {})
	for sid in ["repair", "scavenging", "welding", "fabrication", "first_aid", "piloting", "cooking"]:
		if prog.skills.has(sid):
			prog.skills[sid] = 5

	var slow_ctx: Dictionary = res.build_work_context(prog, "weld", "welding", "")
	if float(slow_ctx.get("work_speed_mult", 1.0)) <= 1.05:
		_fail("welding L5 should raise work_speed, got %s" % str(slow_ctx.get("work_speed_mult", 1.0))); return

	# WorkAction tick respects work_speed_mult from skill effects
	var cat = WorkActionCatalogScript.new()
	if not cat.load_default():
		_fail("work catalog"); return
	var work = WorkActionStateScript.new()
	work.configure_action("weld_patch", cat.get_action("weld_patch"))
	var inv: Dictionary = {"hull_plate": 1}
	if not work.start("wall", {
		"tool_class": "welding_lance",
		"skill_id": "repair",
		"skill_level": 5,
		"inventory": inv,
	}):
		_fail("weld start"); return
	var mult: float = float(slow_ctx.get("work_speed_mult", 1.0))
	work.tick(1.0, {"work_speed_mult": mult})
	var progressed: float = work.progress
	work.reset()
	work.configure_action("weld_patch", cat.get_action("weld_patch"))
	work.start("wall2", {
		"tool_class": "welding_lance", "skill_id": "repair", "skill_level": 0, "inventory": inv,
	})
	work.tick(1.0, {"work_speed_mult": 1.0})
	if progressed <= work.progress + 0.001:
		_fail("higher work_speed_mult should advance more (%s vs %s)" % [str(progressed), str(work.progress)])
		return

	# Craft quality / salvage / heal / travel
	var q0: float = res.craft_quality_bonus(null, "fabrication", "")
	var q5: float = res.craft_quality_bonus(prog, "fabrication", "engineer")
	if q5 <= q0:
		_fail("craft quality should scale with skill + class kit"); return
	var applied: float = res.apply_craft_quality(0.5, prog, "fabrication", "engineer")
	if applied <= 0.5:
		_fail("apply_craft_quality"); return

	var salvage: float = res.salvage_yield_multiplier(prog, "scout")
	if salvage <= 1.0:
		_fail("salvage yield"); return

	var heal: float = res.heal_multiplier(prog, "medic")
	if heal <= 1.0:
		_fail("heal mult"); return

	var fuel_m: float = res.travel_fuel_multiplier(prog)
	if fuel_m >= 1.0:
		_fail("piloting should reduce fuel cost mult"); return

	var food_m: float = res.travel_food_multiplier(prog)
	# resource_management at 0 by default in our seed — set it
	prog.skills["resource_management"] = 4
	food_m = res.travel_food_multiplier(prog)
	if food_m >= 1.0:
		_fail("resource_management should reduce food mult"); return

	var repair_f: float = res.repair_duration_factor(prog)
	if repair_f <= 1.0:
		_fail("repair duration factor"); return

	var scan: float = res.scan_detail_bonus(prog, "scout")
	if scan <= 0.0:
		_fail("scan detail"); return

	# Every skill has consumers
	for sid in catalog.keys():
		if res.consumers_for(str(sid)).is_empty():
			_fail("emit-only skill %s" % sid); return

	# Class kit engineer flat work speed
	var eng: float = res.work_speed_multiplier(prog, "weld", "welding", "engineer")
	var no_kit: float = res.work_speed_multiplier(prog, "weld", "welding", "")
	if eng <= no_kit:
		_fail("engineer kit should add work_speed_flat"); return

	print("SKILL EFFECTS PASS audit=true work=true craft=true heal=true travel=true class_kit=true")
	quit(0)


func _fail(msg: String) -> void:
	print("SKILL EFFECTS FAIL: %s" % msg)
	quit(1)
