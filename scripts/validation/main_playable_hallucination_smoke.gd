extends SceneTree

## Live-scene proof of the sanity hallucination loop (phantom channel + teeth).
## Marker: MAIN PLAYABLE HALLUCINATION PASS manifest=true phantom_no_damage=true attack_dissipates=true teeth=true clears=true hud=true fx=true reachable=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 360

var main_node: Node
var playable: PlayableGeneratedShip
var frame_count: int = 0
var finished: bool = false

func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	if main_node == null:
		_fail("could not instantiate main scene"); return
	get_root().add_child(main_node)
	process_frame.connect(_on_process_frame)

func _on_process_frame() -> void:
	if finished:
		return
	frame_count += 1
	if playable == null:
		playable = _find_playable(main_node)
	if playable == null or playable.loader == null or not playable.loader.has_loaded_ship() or not playable.playable_started:
		if frame_count > TIMEOUT_FRAMES:
			_fail("playable did not become ready")
		return
	_validate()

func _validate() -> void:
	var director = playable.get_hallucination_director_for_validation()
	var manager = playable.get_hallucination_manager_for_validation()
	if director == null or manager == null:
		_fail("hallucination director/manager missing"); return
	if playable.threat_manager != null:
		playable.threat_manager.threats.clear()

	# Put the player in the sanity field at home: breach open => in_safe == false, so the
	# coordinator's home-path sanity block (which ticks the director) runs. (The away path
	# early-returns before the sanity block by design, so we exercise the home-path field.)
	playable.away_from_start = false
	if playable.oxygen_state != null:
		playable.oxygen_state.breach_open = true
		playable.oxygen_state.breach_sealed = false
	# Crater sanity into tier 3.
	playable.sanity_state.sanity = 8.0

	# Manifest: pump frames until phantoms appear.
	var manifested := false
	for i in range(600):
		playable._process(1.0 / 30.0)
		if manager.phantom_count() > 0:
			manifested = true; break
	if not manifested:
		_fail("no phantom manifested at tier 3"); return

	# Phantom deals NO combat damage: phantoms live on the manager, never in
	# ThreatManager, so with the threat list cleared no combat math can touch the
	# player. Confirm phantoms are present while the threat list stays empty AND
	# health does not take a combat-sized drop over a short window.
	playable.vitals_state.health = 90.0
	var hp_before: float = playable.vitals_state.health
	for i in range(30):
		playable._process(1.0 / 30.0)
	var threats_empty: bool = playable.threat_manager == null or playable.threat_manager.threats.is_empty()
	var phantom_no_damage: bool = manager.phantom_count() > 0 and threats_empty and playable.vitals_state.health > hp_before - 2.0

	# Ensure at least one phantom is live for the attack test.
	if manager.phantom_count() == 0:
		for i in range(600):
			playable._process(1.0 / 30.0)
			if manager.phantom_count() > 0:
				break

	# Attack dissipates a phantom and spends ammo (wasted swing). Equip an ammo
	# weapon, park the player on a phantom, then swing.
	_arm_ammo_weapon()
	_park_player_on_phantom(manager)
	var before_phantoms: int = manager.phantom_count()
	# Domain 5: attack fires from the magazine (AmmoState), not raw inventory.
	var ammo_before: int = playable.ammo_state.loaded("flare_pistol")
	var result: Dictionary = playable._attack_with_equipped_weapon()
	var attack_dissipates: bool = manager.phantom_count() < before_phantoms and bool(result.get("phantom_dissipated", false))
	attack_dissipates = attack_dissipates and playable.ammo_state.loaded("flare_pistol") < ammo_before

	# No-respawn (commit-to-reveal): a dissipated phantom must NOT reappear next frame.
	# Regression guard for the director-event-not-removed bug — without remove_event the
	# manager rebuilds the same phantom from active_events on the very next render().
	var post_attack_count: int = manager.phantom_count()
	for i in range(5):
		playable._process(1.0 / 30.0)
	var no_respawn: bool = manager.phantom_count() <= post_attack_count

	# Teeth: tier 3 drains health over time (sanity_health_drain).
	playable.vitals_state.health = 90.0
	var teeth_before: float = playable.vitals_state.health
	for i in range(60):
		playable._process(1.0 / 30.0)
	var teeth: bool = playable.vitals_state.health < teeth_before

	# Channels: at tier 3, false-HUD lines are present and FX intensity is maxed.
	# Keep the home-path field live (breach open, away_from_start false) so the
	# coordinator's sanity block keeps ticking the director.
	playable.away_from_start = false
	if playable.oxygen_state != null:
		playable.oxygen_state.breach_open = true
		playable.oxygen_state.breach_sealed = false
	playable.sanity_state.sanity = 8.0
	var hud_ok: bool = false
	for i in range(240):
		playable._process(1.0 / 30.0)
		if manager.get_hallucinated_status_lines().size() > 0:
			hud_ok = true
			break
	var fx_ok: bool = director.get_fx_intensity() >= 0.99

	# Derelict path (Codex PR #44): hallucinations + teeth must run on the away/boarded
	# path too — it is the primary field-run context, and that _process branch returns
	# before the home-path sanity block. Away is never a safe zone, so sanity drains and
	# tier-3 health teeth apply even though the away path skips the full survival vitals tick.
	if playable.threat_manager != null:
		playable.threat_manager.threats.clear()
	playable.away_from_start = true
	playable.sanity_state.sanity = 50.0
	var away_sanity_before: float = playable.sanity_state.sanity
	for i in range(30):
		playable._process(1.0 / 30.0)
	var away_sanity_drains: bool = playable.sanity_state.sanity < away_sanity_before
	if playable.threat_manager != null:
		playable.threat_manager.threats.clear()
	playable.sanity_state.sanity = 8.0
	playable.vitals_state.health = 90.0
	for i in range(30):
		playable._process(1.0 / 30.0)
	var away_teeth: bool = playable.vitals_state.health < 90.0
	var away_ticks: bool = away_sanity_drains and away_teeth

	# Clears: restore sanity (tier 0) and seal the breach (safe zone) => everything cleared.
	playable.away_from_start = false
	if playable.oxygen_state != null:
		playable.oxygen_state.breach_open = false
	playable.sanity_state.sanity = 100.0
	for i in range(10):
		playable._process(1.0 / 30.0)
	var clears: bool = manager.phantom_count() == 0

	if manifested and phantom_no_damage and attack_dissipates and no_respawn and teeth and away_ticks and hud_ok and fx_ok and clears:
		print("MAIN PLAYABLE HALLUCINATION PASS manifest=true phantom_no_damage=true attack_dissipates=true no_respawn=true teeth=true away_ticks=true clears=true hud=true fx=true reachable=true")
		finished = true
		_cleanup_and_quit(0)
	else:
		_fail("manifest=%s no_damage=%s attack=%s no_respawn=%s teeth=%s away_ticks=%s hud=%s fx=%s clears=%s" % [manifested, phantom_no_damage, attack_dissipates, no_respawn, teeth, away_ticks, hud_ok, fx_ok, clears])

func _ammo_id() -> String:
	return "flare_round"

func _arm_ammo_weapon() -> void:
	# flare_pistol is a real primary_hand weapon with ammo_item_id == "flare_round"
	# (data/combat/weapon_definitions.json). Domain 5: attack_with_weapon fires from
	# the per-weapon magazine (AmmoState). We pre-seed 2 rounds so the attack can
	# spend one even against a phantom (no real target) — a swing is a wasted action.
	playable.inventory_state.add_item(_ammo_id(), 5)
	playable.ammo_state.configure({"magazines": {"flare_pistol": 2}})
	if playable.equipment_state != null and playable.equipment_state.has_method("equip"):
		playable.equipment_state.equip("flare_pistol")

func _park_player_on_phantom(manager) -> void:
	# Move the player onto a live phantom so the attack-path dissipation reaches it.
	# Done WITHOUT pumping _process so render()'s melee auto-dissipate does not fire first.
	if playable.player == null or not (playable.player is Node3D):
		return
	for id in manager._phantom_nodes.keys():
		var n = manager._phantom_nodes[id]
		if is_instance_valid(n):
			(playable.player as Node3D).global_position = (n as Node3D).global_position
			return

func _find_playable(node: Node) -> PlayableGeneratedShip:
	if node is PlayableGeneratedShip:
		return node as PlayableGeneratedShip
	for child in node.get_children():
		var f = _find_playable(child)
		if f != null:
			return f
	return null

func _fail(reason: String) -> void:
	if finished:
		return
	finished = true
	push_error("MAIN PLAYABLE HALLUCINATION FAIL reason=%s" % reason)
	_cleanup_and_quit(1)

func _cleanup_and_quit(code: int) -> void:
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
