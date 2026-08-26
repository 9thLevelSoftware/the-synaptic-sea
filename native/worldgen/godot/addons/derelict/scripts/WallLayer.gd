class_name WallLayer
extends Node2D
## Draws one deck's edge-walls (PZ-style walls-on-edges) as extruded quads.
## Placeholder rendering: a single canvas item drawing every wall keeps node
## count low; the real game can replace this with autotiled wall sprites.

const WALL_H := 24.0
const COLORS := {
	1: Color(0.78, 0.80, 0.86),  # Hull
	2: Color(0.58, 0.60, 0.66),  # Interior
	4: Color(0.85, 0.42, 0.25),  # Breached
}
const DOOR_CLOSED := Color(0.30, 0.75, 0.42)
const DOOR_LOCKED := Color(0.80, 0.25, 0.25)
const DOOR_OPEN := Color(0.30, 0.75, 0.42, 0.35)

var deck_data: Dictionary = {}
## entity_id -> door entity dict (state read live so interactions redraw).
var doors: Dictionary = {}

func setup(p_deck: Dictionary, p_doors: Dictionary) -> void:
	deck_data = p_deck
	doors = p_doors
	queue_redraw()

func _draw() -> void:
	if deck_data.is_empty():
		return
	var w: int = deck_data["width"]
	var h: int = deck_data["height"]
	var wall_n: PackedInt32Array = deck_data["wall_north"]
	var wall_w: PackedInt32Array = deck_data["wall_west"]
	# Draw in grid order (back to front in iso: increasing x+y).
	for y in h:
		for x in w:
			var i := y * w + x
			_draw_edge(x, y, true, wall_n[i])
			_draw_edge(x, y, false, wall_w[i])

func _draw_edge(x: int, y: int, north: bool, kind: int) -> void:
	if kind == 0:
		return
	var c := IsoMath.grid_to_screen(x, y)
	var a: Vector2
	var b: Vector2
	if north:
		a = c + IsoMath.corner_top()
		b = c + IsoMath.corner_right()
	else:
		a = c + IsoMath.corner_left()
		b = c + IsoMath.corner_top()
	if kind == 3:  # Doorway: posts + door leaf from live door state
		_draw_post(a)
		_draw_post(b)
		var door := _door_at(x, y, north)
		if not door.is_empty():
			var col: Color = DOOR_OPEN if door.get("open", false) \
				else (DOOR_LOCKED if door.get("locked", false) else DOOR_CLOSED)
			_draw_quad(a.lerp(b, 0.15), a.lerp(b, 0.85), col)
		return
	var col2: Color = COLORS.get(kind, Color.MAGENTA)
	if kind == 4:  # breached: jagged, drawn shorter
		_draw_quad(a.lerp(b, 0.05), a.lerp(b, 0.55), col2, WALL_H * 0.5)
		_draw_quad(a.lerp(b, 0.7), a.lerp(b, 0.95), col2, WALL_H * 0.3)
	else:
		_draw_quad(a, b, col2)

func _draw_quad(a: Vector2, b: Vector2, col: Color, height: float = WALL_H) -> void:
	var up := Vector2(0, -height)
	draw_colored_polygon(PackedVector2Array([a, b, b + up, a + up]), col)
	# Top edge highlight for readability.
	draw_line(a + up, b + up, col.lightened(0.25), 1.5)

func _draw_post(p: Vector2) -> void:
	var up := Vector2(0, -WALL_H)
	draw_line(p, p + up, Color(0.85, 0.87, 0.9), 3.0)

func _door_at(x: int, y: int, north: bool) -> Dictionary:
	var want_rot := 0 if north else 1
	for id in doors:
		var d: Dictionary = doors[id]
		if d["x"] == x and d["y"] == y and d["rotation"] == want_rot:
			return d
	return {}
