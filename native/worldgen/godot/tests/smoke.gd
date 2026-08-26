extends SceneTree
## Headless smoke test:
##   godot --headless --path godot -s tests/smoke.gd
## Exercises sync + async generation, ship instantiation (budgeted spawning),
## grid queries, and the persistence diff round-trip.

var _frames := 0
var ship_node: DerelictShipNode
var generator: RefCounted
var async_id := 0
var phase := "sync"

func _initialize() -> void:
	print("SMOKE: start")
	generator = ClassDB.instantiate("DerelictGenerator")
	assert(generator != null, "DerelictGenerator class missing (extension not loaded?)")

	# --- Sync generation ---
	var ship: Dictionary = generator.generate(12, {"archetype_id": "frigate", "intactness_override": 600})
	assert(not ship.has("error"), "generation error: %s" % ship.get("error"))
	assert(ship["decks"].size() >= 2, "frigate should be multi-deck")
	assert(ship["fractured"] == true, "seed 12 @ 600bp should fracture")
	print("SMOKE: sync gen ok — %d rooms, %d entities, fractured=%s" % [
		ship["rooms"].size(), ship["entities"].size(), ship["fractured"]])

	# Determinism through the bridge.
	var ship2: Dictionary = generator.generate(12, {"archetype_id": "frigate", "intactness_override": 600})
	assert(ship["entities"].size() == ship2["entities"].size(), "non-deterministic entity count")
	assert(ship["decks"][0]["floor"] == ship2["decks"][0]["floor"], "non-deterministic floor layer")
	print("SMOKE: bridge determinism ok")

	# --- Instantiate ---
	ship_node = DerelictShipNode.new()
	root.add_child(ship_node)
	ship_node.build(ship)

	# --- Async request ---
	async_id = generator.generate_async(77, {"archetype_id": "corvette"})

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames > 600:
		push_error("SMOKE: timeout")
		quit(1)
		return true

	if phase == "sync":
		if ship_node._spawn_queue.is_empty():
			var n: int = ship_node.entities_by_id.size()
			assert(n > 100, "expected >100 spawned entities, got %d" % n)
			print("SMOKE: instantiation ok — %d entity nodes over %d frames" % [n, _frames])
			_test_queries()
			_test_persistence()
			phase = "async"
		return false

	if phase == "async":
		var result: Variant = generator.poll_async(async_id)
		if result == null:
			return false
		assert(not (result as Dictionary).has("error"))
		print("SMOKE: async gen ok (frame %d)" % _frames)
		print("SMOKE: ALL PASS")
		quit(0)
		return true
	return false

func _test_queries() -> void:
	# Deck switching + a few grid queries must not error.
	ship_node.set_active_deck(1)
	ship_node.set_active_deck(0)
	var deck0: Dictionary = ship_node.ship["decks"][0]
	var w: int = deck0["width"]
	var found_step := false
	for i in deck0["floor"].size():
		if deck0["floor"][i] != 0:
			var x: int = i % w
			var y: int = i / w
			if ship_node.can_step(0, x, y, x + 1, y):
				found_step = true
				break
	assert(found_step, "no walkable step found on deck 0")
	print("SMOKE: grid queries ok")

func _test_persistence() -> void:
	var p := ShipPersistence.new("smoke_test_site", 12, 1, {"archetype_id": "frigate"})
	# Mutate a real container.
	var container: DerelictEntity = null
	for id in ship_node.entities_by_id:
		var e: DerelictEntity = ship_node.entities_by_id[id]
		if e.kind == "container" and not e.inventory.is_empty():
			container = e
			break
	assert(container != null, "no lootable container found")
	var looted_id := container.entity_id
	container.take_all_loot()
	p.record(container)
	p.save()

	var p2 := ShipPersistence.load_for("smoke_test_site")
	assert(p2 != null, "persistence load failed")
	assert(p2.container_inventory.has(looted_id), "diff lost container mutation")
	assert(p2.container_inventory[looted_id].is_empty(), "looted container should be empty")
	# Re-apply onto the ship (simulates load-after-restart).
	container.inventory = [{"item_id": 1, "qty": 5}]  # pretend regenerated full
	p2.apply(ship_node)
	assert(container.inventory.is_empty(), "apply() did not restore looted state")
	DirAccess.remove_absolute("user://derelicts/smoke_test_site.json")
	print("SMOKE: persistence round-trip ok")
