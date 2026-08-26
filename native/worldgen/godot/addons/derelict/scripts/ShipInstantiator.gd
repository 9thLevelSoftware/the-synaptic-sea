class_name DerelictShipNode
extends Node2D
## Instantiates a generated ship Dictionary into TileMapLayers + entities.
## One DeckRoot per deck; only the active deck is fully visible (deck below
## dimmed as cutaway). Entity spawning is budgeted across frames so frigate-
## scale ships never hitch the main thread.

signal entity_mutated(entity: DerelictEntity)
signal build_finished

const SPAWN_BUDGET_PER_FRAME := 50
## WallEdge enum values from the generator.
const EDGE_NONE := 0
const EDGE_DOORWAY := 3
const EDGE_BREACHED := 4

var ship: Dictionary = {}
var deck_roots: Array[Node2D] = []
var wall_layers: Array[WallLayer] = []
var entities_by_id: Dictionary = {}       # id -> DerelictEntity
var doors_by_id: Dictionary = {}          # id -> door entity dict (live state)
var active_deck: int = 0

var _spawn_queue: Array = []
var _tileset: TileSet

func build(p_ship: Dictionary) -> void:
	ship = p_ship
	_clear()
	_tileset = PlaceholderTiles.build_tileset()
	var decks: Array = ship["decks"]
	# Doors keep live state in a shared dict so WallLayer can render them.
	for e in ship["entities"]:
		if e["kind"] == "door":
			doors_by_id[int(e["id"])] = e
	for d in decks.size():
		var deck: Dictionary = decks[d]
		var root := Node2D.new()
		root.name = "Deck%d" % d
		add_child(root)
		deck_roots.append(root)

		var floor_layer := TileMapLayer.new()
		floor_layer.name = "Floor"
		floor_layer.tile_set = _tileset
		root.add_child(floor_layer)
		var decal_layer := TileMapLayer.new()
		decal_layer.name = "Decals"
		decal_layer.tile_set = _tileset
		root.add_child(decal_layer)

		var w: int = deck["width"]
		var h: int = deck["height"]
		var floor_ids: PackedInt32Array = deck["floor"]
		var decals: PackedInt32Array = deck["decal"]
		for y in h:
			for x in w:
				var i := y * w + x
				var f := floor_ids[i]
				if f != 0:
					floor_layer.set_cell(Vector2i(x, y), 0, Vector2i(f, 0))
				if decals[i] != 0:
					decal_layer.set_cell(Vector2i(x, y), 1, Vector2i(decals[i], 0))

		var ents := Node2D.new()
		ents.name = "Entities"
		ents.y_sort_enabled = true
		root.add_child(ents)

		var walls := WallLayer.new()
		walls.name = "Walls"
		root.add_child(walls)
		walls.setup(deck, doors_by_id)
		wall_layers.append(walls)

	# Queue non-door entities for budgeted spawning.
	for e in ship["entities"]:
		if e["kind"] != "door":
			_spawn_queue.append(e)
	set_active_deck(0)
	set_process(true)

func _process(_delta: float) -> void:
	if _spawn_queue.is_empty():
		set_process(false)
		build_finished.emit()
		return
	var n: int = mini(SPAWN_BUDGET_PER_FRAME, _spawn_queue.size())
	for i in n:
		_spawn_entity(_spawn_queue.pop_back())

func _spawn_entity(e: Dictionary) -> void:
	var node := DerelictEntity.new()
	node.setup(e)
	node.state_changed.connect(func(ent: DerelictEntity) -> void: entity_mutated.emit(ent))
	var deck_i: int = e["deck"]
	deck_roots[deck_i].get_node("Entities").add_child(node)
	entities_by_id[int(e["id"])] = node

func _clear() -> void:
	for c in get_children():
		c.queue_free()
	deck_roots.clear()
	wall_layers.clear()
	entities_by_id.clear()
	doors_by_id.clear()
	_spawn_queue.clear()

func set_active_deck(d: int) -> void:
	active_deck = clampi(d, 0, deck_roots.size() - 1)
	for i in deck_roots.size():
		var root := deck_roots[i]
		if i == active_deck:
			root.visible = true
			root.modulate = Color.WHITE
		elif i == active_deck - 1:
			# Cutaway: deck below shows dimmed.
			root.visible = true
			root.modulate = Color(0.45, 0.45, 0.5)
		else:
			root.visible = false

func deck_count() -> int:
	return deck_roots.size()

# --- Grid queries (player movement / interaction) --------------------------

func _deck(d: int) -> Dictionary:
	return ship["decks"][d]

func floor_at(d: int, x: int, y: int) -> int:
	var deck := _deck(d)
	var w: int = deck["width"]
	if x < 0 or y < 0 or x >= w or y >= int(deck["height"]):
		return 0
	return deck["floor"][y * w + x]

## Wall edge crossed when stepping from (x,y) to the 4-neighbor (nx,ny).
func edge_between(d: int, x: int, y: int, nx: int, ny: int) -> int:
	var deck := _deck(d)
	var w: int = deck["width"]
	var h: int = deck["height"]
	var get_n := func(tx: int, ty: int) -> int:
		if tx < 0 or ty < 0 or tx >= w or ty >= h:
			return EDGE_NONE
		return deck["wall_north"][ty * w + tx]
	var get_w := func(tx: int, ty: int) -> int:
		if tx < 0 or ty < 0 or tx >= w or ty >= h:
			return EDGE_NONE
		return deck["wall_west"][ty * w + tx]
	if ny == y - 1:
		return get_n.call(x, y)
	if ny == y + 1:
		return get_n.call(x, y + 1)
	if nx == x - 1:
		return get_w.call(x, y)
	if nx == x + 1:
		return get_w.call(x + 1, y)
	return EDGE_NONE

func door_at_edge(d: int, x: int, y: int, nx: int, ny: int) -> DerelictEntity:
	# Doors sit on the north edge (rotation 0) or west edge (rotation 1) of
	# their tile; a step across that edge hits the door.
	var tile_x: int
	var tile_y: int
	var rot: int
	if ny == y - 1:
		tile_x = x; tile_y = y; rot = 0
	elif ny == y + 1:
		tile_x = x; tile_y = y + 1; rot = 0
	elif nx == x - 1:
		tile_x = x; tile_y = y; rot = 1
	elif nx == x + 1:
		tile_x = x + 1; tile_y = y; rot = 1
	else:
		return null
	for id in doors_by_id:
		var door: Dictionary = doors_by_id[id]
		if door["deck"] == d and door["x"] == tile_x and door["y"] == tile_y and door["rotation"] == rot:
			return _door_entity(id)
	return null

func _door_entity(id: int) -> DerelictEntity:
	# Doors are not spawned as nodes (walls render them); wrap the dict in a
	# transient accessor so interaction code has one API.
	if entities_by_id.has(id):
		return entities_by_id[id]
	var node := DerelictEntity.new()
	node.setup(doors_by_id[id])
	node.data = doors_by_id[id]  # share, don't copy: WallLayer reads this
	node.state_changed.connect(func(ent: DerelictEntity) -> void:
		entity_mutated.emit(ent)
		for wl in wall_layers:
			wl.queue_redraw())
	entities_by_id[id] = node
	deck_roots[int(doors_by_id[id]["deck"])].get_node("Entities").add_child(node)
	node.visible = false  # rendered by WallLayer, node exists for state only
	return node

## True if a player can step between adjacent tiles (walkable floor, and the
## edge is passable: no wall, an open door, or a breach).
func can_step(d: int, x: int, y: int, nx: int, ny: int) -> bool:
	if floor_at(d, nx, ny) == 0:
		return false
	var edge := edge_between(d, x, y, nx, ny)
	if edge == EDGE_NONE or edge == EDGE_BREACHED:
		return true
	if edge == EDGE_DOORWAY:
		var door := door_at_edge(d, x, y, nx, ny)
		return door == null or door.is_open()
	return false

func ladder_at(d: int, x: int, y: int) -> bool:
	for id in entities_by_id:
		var e: DerelictEntity = entities_by_id[id]
		if e.proto == "ladder" and int(e.data["deck"]) == d \
			and int(e.data["x"]) == x and int(e.data["y"]) == y:
			return true
	return false
