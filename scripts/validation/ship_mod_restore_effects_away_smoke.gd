extends SceneTree

## After run-snapshot restore, ship-mod re-applies linked sub restore + station tiers.
## Marker: SHIP MOD RESTORE EFFECTS AWAY PASS restore=true tier=true system=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 240

var main_node: Node
var playable
var frame_count: int = 0
var finished: bool = false


func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	get_root().add_child(main_node)
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	if finished:
		return
	frame_count += 1
	if playable == null:
		playable = _find_playable(main_node)
	if playable == null or not playable.playable_started:
		if frame_count > TIMEOUT_FRAMES:
			_fail("playable not ready")
		return
	_validate()


func _validate() -> void:
	finished = true
	playable.away_from_start = true
	playable.inventory_state.add_item("reactor_console", 1)
	if not playable.open_ship_modification_panel_for_validation():
		_fail("open"); return
	var panel = playable.ship_modification_panel
	panel.set_inventory(playable._inventory_qty_dict_for_work())
	if not panel.install_from_inventory(playable.component_catalog):
		_fail("install"); return
	var sum: Dictionary = playable.ship_modification_state.get_summary()
	if int(sum.get("installed", []).size() if sum.get("installed") is Array else 0) < 1:
		_fail("no installed in summary"); return
	# Damage linked sub, clear station tier, re-apply via restore path.
	var sub = playable.ship_systems_manager.systems["power"].get_subcomponent("power_distribution")
	sub.health = 0.1
	var st = playable.crafting_state.get_or_create_station("fabricator")
	st.tier = 0
	st.level = 0
	# Simulate load: apply_summary then reapply effects.
	playable.ship_modification_state.apply_summary(sum)
	playable._reapply_ship_mod_runtime_effects()
	if float(sub.health) < 0.54:
		_fail("system not restored got %s" % str(sub.health)); return
	var tier: int = int(st.effective_tier()) if st.has_method("effective_tier") else int(st.tier)
	if tier < 2:
		_fail("tier not restored got %d" % tier); return
	if playable != null and not bool(playable.away_from_start):
		_fail("away cleared"); return
	print("SHIP MOD RESTORE EFFECTS AWAY PASS away=true restore=true tier=true system=true")
	quit(0)


func _find_playable(n: Node):
	if n is PlayableGeneratedShip:
		return n
	for c in n.get_children():
		var f = _find_playable(c)
		if f != null:
			return f
	return null


func _fail(msg: String) -> void:
	print("SHIP MOD RESTORE EFFECTS AWAY FAIL: %s" % msg)
	finished = true
	quit(1)
