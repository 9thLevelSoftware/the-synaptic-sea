extends SceneTree

## M7-A loop proof (live scene): a pre-damaged hull + unpowered life support fouls the
## hub's ambient atmosphere, which drains the player's health WHILE ABOARD; the drain does
## NOT apply while away on a derelict; restoring power halts it.
##
## Pass marker:
##   MAIN PLAYABLE LIFE SUPPORT VITALS PASS aboard_drain=true away_safe=true recover=true reachable=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 360

var main_node: Node
var playable: PlayableGeneratedShip
var frame_count: int = 0
var finished: bool = false

func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	if main_node == null:
		_fail("could not instantiate main scene")
		return
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
	if playable.vitals_state == null or playable.life_support_expanded_state == null or playable.hull_integrity_state == null:
		_fail("vitals / life_support / hull missing")
		return

	# Clear any spawned encounters so combat damage does not contaminate the
	# pure atmosphere→vitals measurement below. Fallback encounters are always
	# spawned at load time; they are not part of this test's concern.
	if playable.threat_manager != null:
		playable.threat_manager.threats.clear()

	# Aboard the hub, cut power to life support and foul the atmosphere via a real breach.
	playable.away_from_start = false
	playable.set_manual_power_route_for_validation("life_support", 0.0)
	playable.force_hull_breach_for_validation("cargo", 0.7)
	playable.life_support_expanded_state.oxygen_percent = 10.0
	playable.life_support_expanded_state.co2_percent = 60.0
	if playable.life_support_expanded_state.get_health_drain_per_second() <= 0.0:
		_fail("fouled atmosphere should report a health drain")
		return

	# Drive the LIVE coordinator vitals tick for a span; health must drop while aboard.
	playable.vitals_state.health = 90.0
	var aboard_before: float = playable.vitals_state.health
	_pump_vitals(2.0)
	var aboard_after: float = playable.vitals_state.health
	if aboard_after >= aboard_before:
		_fail("health should drop from fouled atmosphere while aboard (%.2f -> %.2f)" % [aboard_before, aboard_after])
		return

	# Away on a derelict: the hub atmosphere must NOT bite.
	playable.away_from_start = true
	playable.vitals_state.health = 90.0
	var away_before: float = playable.vitals_state.health
	_pump_vitals(2.0)
	var away_after: float = playable.vitals_state.health
	if away_after < away_before - 0.001:
		_fail("hub atmosphere should not drain health while away (%.2f -> %.2f)" % [away_before, away_after])
		return

	# Restore power + a clean atmosphere aboard: drain halts.
	playable.away_from_start = false
	playable.set_manual_power_route_for_validation("life_support", 100.0)
	playable.life_support_expanded_state.oxygen_percent = 100.0
	playable.life_support_expanded_state.co2_percent = 2.0
	playable.vitals_state.health = 90.0
	var recover_before: float = playable.vitals_state.health
	_pump_vitals(1.0)
	var recover_after: float = playable.vitals_state.health
	if recover_after < recover_before - 0.001:
		_fail("health should not drop with restored power + clean atmosphere (%.2f -> %.2f)" % [recover_before, recover_after])
		return

	# Seal the pre-damaged cargo breach through a live BreachSealPoint -> breach clears.
	playable.away_from_start = false
	if int(playable.inventory_state.get_quantity("hull_sealant")) < 1:
		playable.inventory_state.add_item("hull_sealant", 1)
	var seal_points: Array = playable.get_breach_seal_points_for_validation()
	if seal_points.is_empty():
		_fail("expected at least one breach seal point for the pre-damaged hull")
		return
	var sp = seal_points[0]
	playable.teleport_player_to_breach_seal_point_for_validation(sp)
	sp.set_validation_player_in_range(playable.player)
	if not sp.try_start(playable.player):
		_fail("breach seal channel should start")
		return
	sp.advance_channel(10.0)
	if playable.hull_integrity_state.get_breach_count() != 0:
		_fail("hull breach should be sealed (count=%d)" % playable.hull_integrity_state.get_breach_count())
		return

	finished = true
	print("MAIN PLAYABLE LIFE SUPPORT VITALS PASS aboard_drain=true away_safe=true recover=true seal_loop=true reachable=true aboard=%.2f->%.2f" % [aboard_before, aboard_after])
	_cleanup_and_quit(0)

# Pumps the coordinator's own _process for `seconds` of simulated time at a fixed step,
# so the live vitals/atmosphere tick path (not the model in isolation) does the work.
func _pump_vitals(seconds: float) -> void:
	var step: float = 1.0 / 30.0
	var elapsed: float = 0.0
	while elapsed < seconds:
		playable._process(step)
		elapsed += step

func _find_playable(node: Node) -> PlayableGeneratedShip:
	if node is PlayableGeneratedShip:
		return node as PlayableGeneratedShip
	for child in node.get_children():
		var found: PlayableGeneratedShip = _find_playable(child)
		if found != null:
			return found
	return null

func _fail(reason: String) -> void:
	if finished:
		return
	finished = true
	push_error("MAIN PLAYABLE LIFE SUPPORT VITALS FAIL reason=%s" % reason)
	_cleanup_and_quit(1)

func _cleanup_and_quit(code: int) -> void:
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
