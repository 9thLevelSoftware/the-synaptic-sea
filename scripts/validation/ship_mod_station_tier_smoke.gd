extends SceneTree

## Ship-mod install with station_tier_bonus raises fabricator tier; uninstall drops it.
## Marker: SHIP MOD STATION TIER PASS install=true tier=true uninstall=true

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
	if playable.crafting_state == null:
		_fail("no crafting_state"); return
	var st0 = playable.crafting_state.get_or_create_station("fabricator")
	var tier_before: int = int(st0.effective_tier()) if st0.has_method("effective_tier") else int(st0.tier)
	playable.inventory_state.add_item("reactor_console", 1)
	if not playable.open_ship_modification_panel_for_validation():
		_fail("open"); return
	var panel = playable.ship_modification_panel
	panel.set_inventory(playable._inventory_qty_dict_for_work())
	if not panel.install_from_inventory(playable.component_catalog):
		_fail("install status=%s" % "\n".join(panel.get_status_lines())); return
	var st1 = playable.crafting_state.get_station("fabricator")
	if st1 == null:
		_fail("no fabricator station"); return
	var tier_after: int = int(st1.effective_tier()) if st1.has_method("effective_tier") else int(st1.tier)
	if tier_after < 2:
		_fail("expected fabricator tier>=2 from reactor_console got %d (before=%d)" % [tier_after, tier_before]); return
	panel.refresh()
	if not panel.uninstall_selected():
		_fail("uninstall"); return
	var st2 = playable.crafting_state.get_station("fabricator")
	var tier_final: int = int(st2.effective_tier()) if st2.has_method("effective_tier") else int(st2.tier)
	if tier_final >= tier_after:
		# After uninstall, tier should drop unless other placed bonuses remain.
		# reactor_console was the only ship-mod bonus; allow placement bonuses to keep some tier.
		if tier_final > 0 and playable.component_placement_state != null:
			var has_other: bool = false
			for e in playable.component_placement_state.placed:
				if typeof(e) != TYPE_DICTIONARY:
					continue
				var def: Dictionary = playable.component_catalog.get_component(str((e as Dictionary).get("component_id", "")))
				if int(def.get("station_tier_bonus", 0)) > 0 and str(def.get("station_affinity", "")) in ["fabricator", "any", ""]:
					has_other = true
					break
			if not has_other and tier_final >= 2:
				_fail("tier did not drop after uninstall got %d" % tier_final); return
		elif tier_final >= 2:
			_fail("tier did not drop after uninstall got %d" % tier_final); return
	print("SHIP MOD STATION TIER PASS install=true tier=true uninstall=true")
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
	print("SHIP MOD STATION TIER FAIL: %s" % msg)
	finished = true
	quit(1)
