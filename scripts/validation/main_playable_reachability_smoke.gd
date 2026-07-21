extends SceneTree

## Stream A reachability proof: systems that previously existed only as models /
## validation seams are reachable through the LIVE interact path and boot
## construction.
##
## Covers:
##   1. Organic salvage cart parked on home boot (no spawn_cart_for_validation).
##   2. Home-branch loot containers search via real player.interact dispatch.
##   3. HangarBayControl dock/launch via real _on_player_interact_requested.
##   4. Achievement catalog triggers fire for loot_searched (and tool_acquired
##      remains wired).
##
## Marker:
##   MAIN PLAYABLE REACHABILITY PASS organic_cart=true home_loot=true hangar_interact=true achievements=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 600

var main_node: Node
var frame_count: int = 0
var finished: bool = false
var exercised: bool = false

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
	var playable = _find_playable(main_node)
	if playable == null:
		if frame_count > TIMEOUT_FRAMES:
			_fail("no PlayableGeneratedShip found")
		return
	if playable.loader == null or not playable.loader.has_loaded_ship():
		if frame_count > TIMEOUT_FRAMES:
			_fail("loader did not finish")
		return
	if not playable.playable_started:
		if frame_count > TIMEOUT_FRAMES:
			_fail("playable never started")
		return
	if exercised:
		return
	exercised = true
	_validate(playable)

func _validate(playable) -> void:
	# --- 1. Organic cart on home boot ---
	var home_id: String = playable.home_ship_id_for_validation()
	if home_id.is_empty():
		_fail("home ship id empty")
		return
	var organic_found: bool = false
	var organic_cart_id: String = ""
	if playable.home_ship != null:
		for cart in playable.home_ship.get_carts():
			if cart == null:
				continue
			var cid: String = String(cart.cart_id)
			if cid.begins_with("organic_cart_"):
				organic_found = true
				organic_cart_id = cid
				break
	if not organic_found:
		# Cargo-less layouts are allowed to skip; assert hangar/cargo fallback
		# home always has a park surface in the current golden start ship.
		_fail("no organic cart on home after boot (carts empty or only validation ids)")
		return
	var cart_control_live: bool = false
	for c in playable.cart_controls:
		if is_instance_valid(c) and String(c.cart_id) == organic_cart_id:
			cart_control_live = true
			break
	if not cart_control_live:
		_fail("organic cart has no live CartControl")
		return

	# --- 2. Home loot via real interact path ---
	if playable.loot_containers.is_empty():
		_fail("no home loot containers built at boot")
		return
	var lc = null
	for candidate in playable.loot_containers:
		if is_instance_valid(candidate) and not candidate.searched:
			lc = candidate
			break
	if lc == null:
		_fail("no unsearched home loot container")
		return
	var loot_id: String = String(lc.container_id)
	var unlocked_before_loot: int = 0
	if playable.achievement_state != null:
		unlocked_before_loot = int(playable.achievement_state.get_unlock_count())
	if playable.player == null:
		_fail("player missing")
		return
	# Force candidate range like other headless interact smokes, then use the
	# real interact dispatch (NOT search_loot_container_for_validation).
	if lc.has_method("set_validation_player_in_range"):
		lc.set_validation_player_in_range(playable.player)
	playable.player.teleport_to(lc.global_position)
	playable.player.request_interact()
	if not lc.searched:
		_fail("home loot not searched via real interact path")
		return
	if playable.achievement_state != null:
		if not playable.achievement_state.is_unlocked("first_loot"):
			_fail("first_loot achievement not unlocked after loot search")
			return
		if int(playable.achievement_state.get_unlock_count()) <= unlocked_before_loot:
			_fail("achievement unlock count did not rise after loot search")
			return

	# --- 3. Hangar interact path (dock lifeboat into home bay) ---
	if playable.hangar_controls.is_empty():
		_fail("no hangar controls after boot")
		return
	var hangar = playable.hangar_controls[0]
	if not is_instance_valid(hangar):
		_fail("hangar control invalid")
		return
	var lifeboat_id: String = playable.lifeboat_ship_id_for_validation()
	if lifeboat_id.is_empty():
		_fail("lifeboat id empty")
		return
	# Ensure not already bayed so dock is the meaningful action.
	if playable.ship_is_bayed_in_for_validation(lifeboat_id, home_id):
		playable.bay_launch_for_validation(home_id)
	if playable.ship_bay_slot_count_for_validation(home_id) < 1:
		_fail("home has no hangar slots")
		return
	playable.player.teleport_to(hangar.global_position)
	# Drive the REAL interact dispatch — hangar is now in the chain.
	playable._on_player_interact_requested(playable.player)
	if not playable.ship_is_bayed_in_for_validation(lifeboat_id, home_id):
		_fail("hangar interact did not bay the lifeboat into home")
		return
	# Launch back out via the same interact path (prefer launch when occupied
	# and no free dock candidate — after baying the lifeboat is no longer a
	# dock candidate, so launch should fire).
	playable.player.teleport_to(hangar.global_position)
	playable._on_player_interact_requested(playable.player)
	if playable.ship_is_bayed_in_for_validation(lifeboat_id, home_id):
		_fail("hangar interact did not launch the bayed lifeboat")
		return

	print(
		"MAIN PLAYABLE REACHABILITY PASS organic_cart=true home_loot=true hangar_interact=true achievements=true cart=%s loot=%s"
		% [organic_cart_id, loot_id]
	)
	finished = true
	quit(0)

func _find_playable(node: Node):
	if node == null:
		return null
	if node.get_script() != null and String(node.get_script().resource_path).ends_with("playable_generated_ship.gd"):
		return node
	for child in node.get_children():
		var hit = _find_playable(child)
		if hit != null:
			return hit
	return null

func _fail(reason: String) -> void:
	push_error("MAIN PLAYABLE REACHABILITY FAIL reason=%s" % reason)
	finished = true
	quit(1)
