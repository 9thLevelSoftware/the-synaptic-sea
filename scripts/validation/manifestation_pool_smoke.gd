extends SceneTree

## PKG-C3.3: manifestation pool schema + narrative force triggers.
## Marker: MANIFESTATION POOL PASS schema=true kinds=true force_room=true force_log=true no_code_entry=true

const ManifestationPoolScript := preload("res://scripts/systems/manifestation_pool.gd")
const HallucinationDirectorScript := preload("res://scripts/systems/hallucination_director.gd")
const SimKeysScript := preload("res://scripts/systems/sim_keys.gd")


func _initialize() -> void:
	var pool = ManifestationPoolScript.new()
	if not pool.load_default():
		_fail("pool load_default"); return
	if pool.schema != "manifestation_pool_v1":
		_fail("schema id"); return
	if pool.kind_count() < 4:
		_fail("expected whisper kind + legacy kinds, got %d" % pool.kind_count()); return
	if pool.entry_count() < 8:
		_fail("expected rich entry pool, got %d" % pool.entry_count()); return
	if not pool.has_kind("whisper"):
		_fail("whisper kind missing — schema growth without code path"); return
	if not pool.has_entry("ambient_static_hiss"):
		_fail("missing ambient entry"); return
	if not pool.has_entry("narrative_bridge_mirror"):
		_fail("missing force_only narrative entry"); return

	# Weighted pick never returns force_only
	for i in range(20):
		var pick: String = pool.pick_entry_id("phantom", 3, 1000 + i * 17)
		if pick == "narrative_bridge_mirror":
			_fail("force_only entry leaked into random pick"); return

	# Room / log hooks
	var room_ids: Array = pool.force_entries_for_room("bridge")
	if room_ids.is_empty() or not room_ids.has("narrative_bridge_mirror"):
		_fail("bridge room trigger"); return
	var log_ids: Array = pool.force_entries_for_audio_log("log_captain_last")
	if log_ids.is_empty() or not log_ids.has("narrative_log_confession"):
		_fail("audio log trigger"); return

	# Director uses pool + force_trigger
	var dir = HallucinationDirectorScript.new()
	dir.configure({"seed": 7, "load_pool": true})
	if dir.pool == null:
		_fail("director should load pool"); return
	var eid: int = dir.force_trigger("narrative_bridge_mirror", Vector3(1, 0, 2))
	if eid < 0:
		_fail("force_trigger failed"); return
	var active: Array = dir.get_active_events()
	if active.is_empty():
		_fail("forced event missing"); return
	var ev: Dictionary = active[0]
	if str(ev.get("entry_id", "")) != "narrative_bridge_mirror":
		_fail("entry_id not stored"); return
	if str(ev.get("caption", "")).is_empty():
		_fail("caption required"); return
	if not bool(ev.get("forced", false)):
		_fail("forced flag"); return

	var n_room: int = dir.force_room_triggers("reactor", Vector3.ZERO)
	if n_room < 1:
		_fail("force_room_triggers"); return
	var n_log: int = dir.force_audio_log_triggers("log_sanity_seed", Vector3(0, 1, 0))
	if n_log < 1:
		_fail("force_audio_log_triggers"); return

	# Scheduled tick still works with expanded kinds (whisper)
	dir.configure({"seed": 3, "load_pool": true})
	var anchors: Array = [Vector3(0, 0, 0), Vector3(4, 0, 0)]
	for _i in range(40):
		dir.tick(0.5, {
			SimKeysScript.SANITY: 20.0,
			SimKeysScript.IN_SAFE_ZONE: false,
			SimKeysScript.ANCHOR_POSITIONS: anchors,
		})
	if dir.get_active_events().is_empty():
		_fail("scheduled manifestations should appear at tier 2"); return
	# Events may carry entry_id from pool
	var any_entry: bool = false
	for e2 in dir.get_active_events():
		if not str(e2.get("entry_id", "")).is_empty():
			any_entry = true
			break
	if not any_entry:
		_fail("pool-backed entries should appear on schedule"); return

	# Safe zone clears forced + scheduled
	dir.tick(0.1, {
		SimKeysScript.SANITY: 10.0,
		SimKeysScript.IN_SAFE_ZONE: true,
		SimKeysScript.ANCHOR_POSITIONS: anchors,
	})
	if not dir.get_active_events().is_empty():
		_fail("safe zone should clear events"); return

	# Adding a new entry only needs data — simulate in-memory append contract
	pool.entries["data_only_new"] = {
		"kind": "whisper",
		"min_tier": 1,
		"weight": 5,
		"caption": "New schema entry without code.",
		"audio_event": "sfx.sanity.whisper",
	}
	if pool.pick_entry_id("whisper", 2, 42).is_empty():
		_fail("new data entry should be pickable"); return

	print("MANIFESTATION POOL PASS schema=true kinds=true force_room=true force_log=true no_code_entry=true")
	quit(0)


func _fail(msg: String) -> void:
	print("MANIFESTATION POOL FAIL: %s" % msg)
	quit(1)
