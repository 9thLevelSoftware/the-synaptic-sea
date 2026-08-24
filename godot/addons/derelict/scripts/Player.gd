class_name GridPlayer
extends Node2D
## Minimal grid-walking test player: WASD to step tile-by-tile, F to
## interact (open/toggle doors when bumping, loot adjacent containers),
## E/Q to climb ladders between decks. Movement respects walls, doors, and
## breaches through the ship node's grid queries.

signal deck_changed(deck: int)
signal message(text: String)

var ship_node: DerelictShipNode
var gx: int = 0
var gy: int = 0
var deck: int = 0
var _move_cooldown := 0.0

const MOVE_REPEAT := 0.14

func attach(p_ship: DerelictShipNode) -> void:
	ship_node = p_ship
	deck = 0
	# Spawn on the first airlock's tile, else first walkable tile.
	var spawn := _find_spawn()
	gx = spawn.x
	gy = spawn.y
	_sync_position()

func _find_spawn() -> Vector2i:
	for room in ship_node.ship["rooms"]:
		if room["kind"] == "airlock" and room["deck"] == 0:
			return Vector2i(int((room["min_x"] + room["max_x"]) / 2.0),
				int((room["min_y"] + room["max_y"]) / 2.0))
	var deck0: Dictionary = ship_node.ship["decks"][0]
	var w: int = deck0["width"]
	for i in deck0["floor"].size():
		if deck0["floor"][i] != 0:
			return Vector2i(i % w, i / w)
	return Vector2i.ZERO

func _process(delta: float) -> void:
	if ship_node == null:
		return
	_move_cooldown -= delta
	if _move_cooldown > 0.0:
		return
	var step := Vector2i.ZERO
	if Input.is_action_pressed("move_up"):
		step = Vector2i(0, -1)
	elif Input.is_action_pressed("move_down"):
		step = Vector2i(0, 1)
	elif Input.is_action_pressed("move_left"):
		step = Vector2i(-1, 0)
	elif Input.is_action_pressed("move_right"):
		step = Vector2i(1, 0)
	if step != Vector2i.ZERO:
		_try_step(step)
		_move_cooldown = MOVE_REPEAT

func _unhandled_input(event: InputEvent) -> void:
	if ship_node == null:
		return
	if event.is_action_pressed("interact"):
		_interact()
	elif event.is_action_pressed("deck_up"):
		_climb(1)
	elif event.is_action_pressed("deck_down"):
		_climb(-1)

func _try_step(step: Vector2i) -> void:
	var nx := gx + step.x
	var ny := gy + step.y
	if ship_node.can_step(deck, gx, gy, nx, ny):
		gx = nx
		gy = ny
		_sync_position()
		return
	# Bump a closed door: open it if unlocked.
	var door := ship_node.door_at_edge(deck, gx, gy, nx, ny)
	if door and not door.is_open():
		if door.is_locked():
			message.emit("Door is locked.")
		else:
			door.set_open(true)
			message.emit("Door opened.")

func _interact() -> void:
	# Loot any container on or adjacent to the player's tile.
	for id in ship_node.entities_by_id:
		var e: DerelictEntity = ship_node.entities_by_id[id]
		if e.kind != "container" or int(e.data["deck"]) != deck:
			continue
		var ex := int(e.data["x"])
		var ey := int(e.data["y"])
		if absi(ex - gx) + absi(ey - gy) <= 1:
			if e.is_locked():
				message.emit("Container locked.")
				return
			var loot := e.take_all_loot()
			if loot.is_empty():
				message.emit("Empty.")
			else:
				var names: Array[String] = []
				for stack in loot:
					names.append("%dx item#%d" % [stack["qty"], stack["item_id"]])
				message.emit("Looted: " + ", ".join(names))
			return
	message.emit("Nothing to interact with.")

func _climb(dir: int) -> void:
	var target := deck + dir
	if target < 0 or target >= ship_node.deck_count():
		return
	if ship_node.ladder_at(deck, gx, gy) and ship_node.ladder_at(target, gx, gy):
		deck = target
		ship_node.set_active_deck(deck)
		_sync_position()
		deck_changed.emit(deck)
		message.emit("Deck %d" % deck)
	else:
		message.emit("No ladder here.")

func _sync_position() -> void:
	position = IsoMath.grid_to_screen(gx, gy)
	# Keep the player on the active deck's entity layer for y-sorting.
	var parent := ship_node.deck_roots[deck].get_node("Entities")
	if get_parent() != parent:
		if get_parent():
			get_parent().remove_child(self)
		parent.add_child(self)

func _draw() -> void:
	draw_circle(Vector2(0, -8), 7.0, Color(0.3, 0.9, 1.0))
	draw_circle(Vector2(0, -8), 4.0, Color(0.1, 0.4, 0.6))
