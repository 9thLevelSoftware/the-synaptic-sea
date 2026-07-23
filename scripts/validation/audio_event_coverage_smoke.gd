extends SceneTree

## PKG-D10: every pillar work verb + new UI/combat events exist in seam + router catalog.
## Marker: AUDIO EVENT COVERAGE PASS verbs=true seam=true router=true work_driver=true

const AudioEventSeamScript := preload("res://scripts/audio/audio_event_seam.gd")
const SfxEventRouterScript := preload("res://scripts/systems/sfx_event_router.gd")
const WorkActionCatalogScript := preload("res://scripts/systems/work_action_catalog.gd")
const WorkActionDriverScript := preload("res://scripts/systems/work_action_driver.gd")
const ModuleIntegrityMapScript := preload("res://scripts/systems/module_integrity_map.gd")


func _initialize() -> void:
	var router = SfxEventRouterScript.new()
	router.configure({})

	# Seam constants registered in router
	var missing_seam: Array = []
	for eid in AudioEventSeamScript.ALL_SFX_IDS:
		var key: String = String(eid)
		if not SfxEventRouterScript.EVENT_CATALOG.has(key):
			missing_seam.append(key)
	for eid2 in AudioEventSeamScript.ALL_UI_IDS:
		var key2: String = String(eid2)
		if not SfxEventRouterScript.EVENT_CATALOG.has(key2):
			missing_seam.append(key2)
	if not missing_seam.is_empty():
		_fail("router missing seam ids: %s" % str(missing_seam)); return

	# Every work verb in catalog maps to a catalogued event (avoid cooldown flakes).
	var cat = WorkActionCatalogScript.new()
	if not cat.load_default():
		_fail("work catalog"); return
	var verbs_checked: int = 0
	var seen_events: Dictionary = {}
	for aid in cat.action_ids():
		var def: Dictionary = cat.get_action(str(aid))
		var verb: String = str(def.get("verb", ""))
		if verb.is_empty():
			continue
		var sn: StringName = AudioEventSeamScript.sfx_for_work_verb(verb)
		var key: String = String(sn)
		if not SfxEventRouterScript.EVENT_CATALOG.has(key):
			_fail("verb %s event %s missing from router catalog" % [verb, key]); return
		if not seen_events.has(key):
			var routed: Variant = router.route(sn, false)
			if routed == null:
				_fail("verb %s event %s not routable" % [verb, key]); return
			seen_events[key] = true
		verbs_checked += 1
	if verbs_checked < 8:
		_fail("expected many verbs, got %d" % verbs_checked); return

	# WorkActionDriver stamps audio_event on complete
	var driver = WorkActionDriverScript.new()
	driver.configure({})
	var map = ModuleIntegrityMapScript.new()
	map.ensure_module("r/wall", "wall_straight_1x1", {}, "r")
	driver.start_action("cut_wall", "r/wall", {
		"tool_class": "welding_lance",
		"skill_id": "salvage",
		"skill_level": 0,
		"inventory": {},
	})
	driver.tick(20.0, {})
	var inv: Dictionary = {}
	var res: Dictionary = driver.complete(map, inv)
	if not bool(res.get("ok", false)):
		_fail("cut complete"); return
	var ae: String = str(res.get("audio_event", ""))
	if ae != String(AudioEventSeamScript.SFX_WORK_CUT):
		_fail("expected cut sfx, got %s" % ae); return
	# Fresh router (avoids cooldown from earlier catalog probes).
	var router2 = SfxEventRouterScript.new()
	router2.configure({})
	var bus: String = driver.emit_completion_sfx(router2)
	if bus.is_empty():
		_fail("emit_completion_sfx should route"); return

	# Explicit new UI/combat events route
	for need in [
		AudioEventSeamScript.SFX_COMBAT_THREAT_ALERT,
		AudioEventSeamScript.SFX_WOUND_BANDAGE,
		AudioEventSeamScript.UI_CHART_ROUTE,
		AudioEventSeamScript.SFX_SANITY_PHANTOM,
	]:
		if router.route(need, false) == null:
			_fail("missing route for %s" % String(need)); return

	print("AUDIO EVENT COVERAGE PASS verbs=true seam=true router=true work_driver=true")
	quit(0)


func _fail(msg: String) -> void:
	print("AUDIO EVENT COVERAGE FAIL: %s" % msg)
	quit(1)
