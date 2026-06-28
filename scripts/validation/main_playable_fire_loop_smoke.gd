extends SceneTree

## M7-B full loop (live scene): damaged system + oxygen ignites; player takes vitals
## damage; manual extinguish via the REAL interact dispatcher clears it (charge spent);
## still-damaged compartment re-ignites; repairing the system stops re-ignition;
## a powered recharge port refills the extinguisher.
## Pass marker:
##   MAIN PLAYABLE FIRE LOOP PASS ignite=true teeth=true extinguish=true reignite=true repair_stops=true recharge=true reachable=true

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
	if playable.fire_suppression_state == null or playable.get_extinguisher_state() == null:
		_fail("fire model / extinguisher missing"); return
	if playable.threat_manager != null:
		playable.threat_manager.threats.clear()
	playable.away_from_start = false

	# Isolate engineering as the SOLE fire source: the boot ship applies random
	# condition-damage to several systems, which seeds stray fires that would spread
	# back into engineering and make the repair-stops assertion non-deterministic.
	# Heal every system and clear any stray fires first, so re-ignition is attributable
	# only to power's damage below.
	for sid in playable.ship_systems_manager.systems:
		for heal_sub in playable.ship_systems_manager.get_system(sid).subcomponents:
			heal_sub.health = 1.0
	playable.fire_suppression_state.active_fires.clear()
	playable.fire_suppression_state.ignition_progress.clear()
	playable.fire_suppression_state.spread_progress.clear()
	# Neutralize the electrical-arc cascade (REQ-013): the arc hazard can be ARCING at
	# boot and would re-ignite arc_compartment ("engineering") in the fire model's
	# cascade step regardless of repair, masking the damage->ignition relationship this
	# test asserts. Zeroing the cascade rate leaves damage- and spread-driven fire intact.
	playable.fire_suppression_state.cascade_rate_per_second = 0.0

	# Keep suppression UNPOWERED for the manual-fight portion: powered auto-suppression
	# (stations >= power_threshold) would otherwise extinguish engineering before the manual
	# extinguish step, making this test non-deterministic. This also models the real scenario
	# the manual loop exists for — a power failure where the crew must fight fire by hand.
	# (Reclaiming the dead shield power budget gives the grid surplus, so stations now stays
	# pinned at full power unless explicitly routed to 0 here. The recharge sub-test below
	# powers its port directly via set_powered(true), so it is unaffected by this route.)
	playable.set_manual_power_route_for_validation("stations", 0.0)

	# Damage power (engineering's system) so engineering becomes ignitable; ensure oxygen.
	playable.life_support_expanded_state.oxygen_percent = 100.0
	for sub in playable.ship_systems_manager.get_system("power").subcomponents:
		sub.health = 0.1
	# Drive ignition via the model tick.
	var ctx_steps := 0
	while not playable.fire_suppression_state.is_burning("engineering") and ctx_steps < 600:
		playable.fire_suppression_state.tick(0.1, playable._build_fire_context())
		ctx_steps += 1
	if not playable.fire_suppression_state.is_burning("engineering"):
		_fail("damaged+oxygen never ignited engineering"); return
	playable._refresh_fire_zones()

	# Teeth.
	playable.vitals_state.health = 90.0
	var ez = _engineering_zone()
	if ez == null:
		_fail("no engineering fire zone"); return
	if playable.player != null:
		playable.player.global_position = ez.global_position
	for i in range(60):
		playable._process(1.0 / 30.0)
	if playable.vitals_state.health >= 90.0:
		_fail("fire did not drain vitals"); return

	# Manual extinguish via the REAL dispatcher.
	playable.get_extinguisher_state().charge = playable.get_extinguisher_state().max_charge
	if int(playable.inventory_state.get_quantity("fire_extinguisher")) < 1:
		playable.inventory_state.add_item("fire_extinguisher", 1)
	var points: Array = playable.get_fire_suppression_points_for_validation()
	if points.is_empty():
		_fail("no fire suppression point for the burning compartment"); return
	var fp = null
	for p in points:
		if str(p.compartment_id) == "engineering":
			fp = p
	if fp == null:
		_fail("no engineering suppression point"); return
	playable.teleport_player_to_fire_suppression_point_for_validation(fp)
	var charge_before: float = playable.get_extinguisher_state().charge
	playable._on_player_interact_requested(playable.player)
	if not (fp.channeling or fp.extinguished):
		_fail("interact dispatch did not start the extinguish channel (loop unreachable)"); return
	fp.advance_channel(10.0)
	if playable.fire_suppression_state.is_burning("engineering"):
		_fail("manual extinguish did not clear the fire"); return
	if playable.get_extinguisher_state().charge >= charge_before:
		_fail("extinguish should spend charge"); return

	# Re-ignition while still damaged.
	var reignited := false
	for i in range(600):
		playable.fire_suppression_state.tick(0.1, playable._build_fire_context())
		if playable.fire_suppression_state.is_burning("engineering"):
			reignited = true; break
	if not reignited:
		_fail("still-damaged compartment did not re-ignite"); return

	# Repair stops re-ignition.
	playable.fire_suppression_state.extinguish("engineering")
	for sub in playable.ship_systems_manager.get_system("power").subcomponents:
		sub.health = 1.0
	for i in range(200):
		playable.fire_suppression_state.tick(0.1, playable._build_fire_context())
	if playable.fire_suppression_state.is_burning("engineering"):
		_fail("repaired compartment kept re-igniting"); return

	# Recharge port refills when powered.
	var ext = playable.get_extinguisher_state()
	ext.charge = 0.0
	var port = playable.get_extinguisher_recharge_port_for_validation()
	if port == null:
		_fail("no recharge port present"); return
	port.set_powered(true)
	port.set_validation_player_in_range(playable.player)
	if playable.player != null:
		playable.player.global_position = port.global_position
	for i in range(60):
		port._process(1.0 / 30.0)
	if ext.charge <= 0.0:
		_fail("powered recharge port did not refill the extinguisher"); return

	finished = true
	print("MAIN PLAYABLE FIRE LOOP PASS ignite=true teeth=true extinguish=true reignite=true repair_stops=true recharge=true reachable=true")
	_cleanup_and_quit(0)

func _engineering_zone() -> Node3D:
	for zn in playable.get_fire_zone_nodes_for_validation():
		if str(zn.get_meta("fire_compartment_id", "")) == "engineering" and zn is Node3D:
			return zn as Node3D
	return null

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
	push_error("MAIN PLAYABLE FIRE LOOP FAIL reason=%s" % reason)
	_cleanup_and_quit(1)

func _cleanup_and_quit(code: int) -> void:
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
