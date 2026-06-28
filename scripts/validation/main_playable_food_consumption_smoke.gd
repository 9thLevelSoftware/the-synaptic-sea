extends SceneTree

## REQ-FC food-loop closure proof: eating a food item through the LIVE consumable path
## actually restores the player's hunger/thirst on vitals_state.
##
## Before this wiring, food items (category "food", carrying hunger_restore/thirst_restore
## but no `effects` array) were a no-op when eaten — consumable_state only dispatched a
## `definition.effects[]` array. Now the food/drink branch applies the food's restores to
## the live vitals/sanity via FoodState. This closes the survival food loop with the
## production that already works (the kitchen crafting station produces cooked_meal).
##
## Pass marker:
##   MAIN PLAYABLE FOOD CONSUMPTION PASS hunger_restored=true thirst_restored=true reachable=true

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
	if playable.vitals_state == null or playable.inventory_state == null:
		_fail("vitals or inventory missing")
		return

	# cooked_meal is the live kitchen-crafting output (recipe_definitions.json) and a
	# category=food item (item_definitions.json: hunger_restore=25, thirst_restore=8).
	playable.inventory_state.add_item("cooked_meal", 1)

	# Drop hunger/thirst well below max so the restore is observable and unclamped.
	playable.vitals_state.hunger = 20.0
	playable.vitals_state.thirst = 20.0
	var hunger_before: float = playable.vitals_state.hunger
	var thirst_before: float = playable.vitals_state.thirst

	# Eat through the REAL consumable path (coordinator -> consumable_state.use_item).
	var result: Dictionary = playable.use_inventory_item_for_validation("cooked_meal")
	if not bool(result.get("ok", false)):
		_fail("eating cooked_meal failed: %s" % str(result))
		return

	# The item was consumed from inventory.
	if int(playable.inventory_state.get_quantity("cooked_meal")) != 0:
		_fail("cooked_meal not removed from inventory after eating")
		return

	# The loop closed: hunger and thirst actually rose on the live vitals model.
	var hunger_after: float = playable.vitals_state.hunger
	var thirst_after: float = playable.vitals_state.thirst
	if hunger_after <= hunger_before:
		_fail("hunger did not rise (before=%.1f after=%.1f) — eat->vitals loop still broken" % [hunger_before, hunger_after])
		return
	if thirst_after <= thirst_before:
		_fail("thirst did not rise (before=%.1f after=%.1f)" % [thirst_before, thirst_after])
		return

	# Codex PR #43: acquiring food via a live acquisition path (here the loot-grant
	# handler) must register it with the spoilage tracker, so the eat-time stale/rotten
	# multiplier actually applies in real play (not just in pre-seeded saves/tests).
	if playable.spoilage_state == null:
		_fail("spoilage_state missing")
		return
	if playable.spoilage_state.has_food("cooked_meal"):
		# Ensure we're proving the acquisition path, not a pre-existing entry.
		playable.spoilage_state.remove_food("cooked_meal")
	playable._on_loot_container_searched("smoke_food_container", [{"item_id": "cooked_meal", "quantity": 1}])
	if not playable.spoilage_state.has_food("cooked_meal"):
		_fail("acquired food was not registered with spoilage_state (eat-time spoilage inert)")
		return

	finished = true
	print("MAIN PLAYABLE FOOD CONSUMPTION PASS hunger_restored=true thirst_restored=true spoilage_tracked=true reachable=true hunger=%.1f->%.1f thirst=%.1f->%.1f" % [
		hunger_before, hunger_after, thirst_before, thirst_after])
	_cleanup_and_quit(0)

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
	push_error("MAIN PLAYABLE FOOD CONSUMPTION FAIL reason=%s" % reason)
	_cleanup_and_quit(1)

func _cleanup_and_quit(code: int) -> void:
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
