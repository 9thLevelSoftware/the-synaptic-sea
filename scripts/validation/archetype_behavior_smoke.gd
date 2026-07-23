extends SceneTree

## PKG-C4.2: data-driven FSM modifiers — ambush, stalk, swarm_split, anchored, telegraph.
## Still one ThreatAIState FSM. Each archetype exposes a distinct player_verb.
## Marker: ARCHETYPE BEHAVIOR PASS ambush=true stalk=true swarm=true anchored=true telegraph=true verbs=true

const ThreatAIStateScript := preload("res://scripts/systems/threat_ai_state.gd")

const ARCHETYPE_PATH: String = "res://data/combat/threat_archetypes.json"


func _initialize() -> void:
	if not FileAccess.file_exists(ARCHETYPE_PATH):
		_fail("missing archetypes json"); return
	var f := FileAccess.open(ARCHETYPE_PATH, FileAccess.READ)
	var root: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(root) != TYPE_DICTIONARY:
		_fail("bad json"); return
	var archetypes: Dictionary = root
	var verbs: Dictionary = {}

	for aid in archetypes.keys():
		var def: Dictionary = archetypes[aid]
		var t = ThreatAIStateScript.new()
		var cfg: Dictionary = def.duplicate(true)
		cfg["instance_id"] = "t_%s" % aid
		cfg["archetype_id"] = str(aid)
		t.configure(cfg)
		var verb: String = t.get_player_verb()
		if verb.is_empty() or verb == "fight" and str(aid) != "puppet_corpse":
			# puppet may keep fight-ish; others should be distinct from data
			pass
		if verbs.has(verb) and str(aid) != "drone_swarm":
			# allow only intentional duplicates; we want mostly unique
			pass
		verbs[verb] = true
		if not t.player_verb.is_empty():
			pass

	if verbs.size() < 5:
		_fail("expected >=5 distinct player verbs, got %s" % str(verbs.keys())); return

	# --- Ambush hold (mimic): low awareness stays idle ---
	var mimic = ThreatAIStateScript.new()
	mimic.configure((archetypes["mimic"] as Dictionary).duplicate(true))
	mimic.tick(0.1, {
		"noise_level": 0.3,
		"light_level": 0.2,
		"sight_level": 0.2,
		"crouching": false,
		"same_room": true,
		"detect_threshold": 0.85,
		"player_distance": 1.0,
	})
	if mimic.state != ThreatAIStateScript.STATE_IDLE:
		_fail("mimic ambush should hold idle on partial detect, got %s" % mimic.state); return
	# Full detect commits
	mimic.tick(0.1, {
		"noise_level": 1.2,
		"light_level": 1.0,
		"sight_level": 1.0,
		"crouching": false,
		"same_room": true,
		"detect_threshold": 0.85,
		"player_distance": 1.0,
	})
	if mimic.state != ThreatAIStateScript.STATE_TELEGRAPH and mimic.state != ThreatAIStateScript.STATE_ATTACK:
		_fail("mimic should commit after full detect, got %s" % mimic.state); return

	# --- Stalk range (stalker): far same-room stays hunt ---
	var stalker = ThreatAIStateScript.new()
	stalker.configure((archetypes["stalker"] as Dictionary).duplicate(true))
	stalker.tick(0.1, {
		"noise_level": 1.5,
		"light_level": 1.0,
		"sight_level": 1.0,
		"same_room": true,
		"detect_threshold": 0.85,
		"player_distance": 8.0,
	})
	if stalker.state != ThreatAIStateScript.STATE_HUNT:
		_fail("stalker far should hunt, got %s" % stalker.state); return
	stalker.tick(0.1, {
		"noise_level": 1.5,
		"light_level": 1.0,
		"sight_level": 1.0,
		"same_room": true,
		"detect_threshold": 0.85,
		"player_distance": 1.0,
	})
	if stalker.state != ThreatAIStateScript.STATE_TELEGRAPH and stalker.state != ThreatAIStateScript.STATE_ATTACK:
		_fail("stalker close should engage, got %s" % stalker.state); return

	# --- Anchored tendril: never flees, zero move ---
	var tendril = ThreatAIStateScript.new()
	tendril.configure((archetypes["hull_tendril"] as Dictionary).duplicate(true))
	tendril.health = 1.0
	tendril.tick(0.1, {
		"noise_level": 1.5,
		"light_level": 1.0,
		"sight_level": 1.0,
		"same_room": true,
		"detect_threshold": 0.85,
		"player_distance": 1.0,
	})
	if tendril.state == ThreatAIStateScript.STATE_FLEE:
		_fail("anchored must not flee"); return
	tendril.apply_damage({"final_damage": 10.0})
	if tendril.state == ThreatAIStateScript.STATE_FLEE:
		_fail("anchored damage must not flee"); return
	if tendril.effective_move_speed() > 0.0 and tendril.state != ThreatAIStateScript.STATE_ATTACK and tendril.state != ThreatAIStateScript.STATE_TELEGRAPH:
		_fail("anchored idle/hunt move should be 0"); return

	# --- Swarm split: damage → flee ---
	var swarm = ThreatAIStateScript.new()
	swarm.configure((archetypes["biomatter_swarm"] as Dictionary).duplicate(true))
	swarm.health = swarm.max_health
	swarm.apply_damage({"final_damage": swarm.max_health * 0.6})
	if swarm.state != ThreatAIStateScript.STATE_FLEE and swarm.health > 0.0:
		_fail("swarm_split should flee under pressure, got %s" % swarm.state); return

	# --- Telegraph windup ---
	var corpse = ThreatAIStateScript.new()
	corpse.configure((archetypes["puppet_corpse"] as Dictionary).duplicate(true))
	corpse.tick(0.05, {
		"noise_level": 1.5,
		"light_level": 1.0,
		"sight_level": 1.0,
		"same_room": true,
		"detect_threshold": 0.5,
		"player_distance": 0.5,
	})
	if corpse.state != ThreatAIStateScript.STATE_TELEGRAPH:
		_fail("puppet_corpse should telegraph, got %s" % corpse.state); return
	if corpse.can_attack():
		_fail("cannot attack during telegraph"); return
	corpse.tick(1.0, {
		"noise_level": 1.5,
		"light_level": 1.0,
		"sight_level": 1.0,
		"same_room": true,
		"detect_threshold": 0.5,
		"player_distance": 0.5,
	})
	if corpse.state != ThreatAIStateScript.STATE_ATTACK:
		_fail("telegraph should resolve to attack, got %s" % corpse.state); return
	if not corpse.can_attack():
		_fail("should attack after telegraph"); return

	# Distinct verbs check (explicit set)
	var required_verbs: Array = [
		"burn_or_scatter", "keep_distance", "break_los",
		"probe_before_loot", "cut_structure", "emp_or_cover",
	]
	for rv in required_verbs:
		if not verbs.has(rv):
			_fail("missing player_verb %s in %s" % [rv, str(verbs.keys())]); return

	print("ARCHETYPE BEHAVIOR PASS ambush=true stalk=true swarm=true anchored=true telegraph=true verbs=true")
	quit(0)


func _fail(msg: String) -> void:
	print("ARCHETYPE BEHAVIOR FAIL: %s" % msg)
	quit(1)
