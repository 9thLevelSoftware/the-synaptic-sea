extends SceneTree

## Live playable ship-mod rejects installs that exceed power budget.
## Marker: SHIP MOD POWER BUDGET SCENE PASS fill=true reject=true inventory=true

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
	if not playable.open_ship_modification_panel_for_validation():
		_fail("open"); return
	var panel = playable.ship_modification_panel
	# Expand candidate slots so we can fill budget.
	panel.candidate_slots = PackedStringArray()
	for i in range(20):
		panel.candidate_slots.append("hub_slot_%d" % i)
	# Heavy power components: machinery_block draws 12
	playable.inventory_state.add_item("machinery_block", 20)
	var installed: int = 0
	var rejected: bool = false
	for _i in range(20):
		panel.set_inventory(playable._inventory_qty_dict_for_work())
		var ok: bool = panel.install_from_inventory(
			playable.component_catalog,
			PackedStringArray(["machinery_block"])
		)
		if ok:
			installed += 1
		else:
			rejected = true
			break
	if installed < 1:
		_fail("expected at least one install"); return
	if not rejected:
		_fail("expected power_budget reject after fill installed=%d draw=%s supply=%s" % [
			installed,
			str(playable.ship_modification_state.total_power_draw()),
			str(playable.ship_modification_state.power_supply),
		]); return
	# Rejected install should leave inventory stack for the blocked item.
	if playable.inventory_state.get_quantity("machinery_block") < 1:
		_fail("inventory should retain item on reject"); return
	print("SHIP MOD POWER BUDGET SCENE PASS fill=true reject=true inventory=true")
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
	print("SHIP MOD POWER BUDGET SCENE FAIL: %s" % msg)
	finished = true
	quit(1)
