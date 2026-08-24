class_name DerelictEntity
extends Node2D
## Placeholder entity: colored marker keyed by kind/proto, holds the live
## mutable state (locked/open/inventory) that persistence diffs address by
## entity_id. The real game replaces the visuals via the scene registry in
## ShipInstantiator while keeping the same state contract.

signal state_changed(entity: DerelictEntity)

var data: Dictionary = {}   # the raw entity dict from the generator
var entity_id: int = 0
var kind: String = ""
var proto: String = ""
var inventory: Array = []   # [{item_id, qty}, ...]

const KIND_COLORS := {
	"container": Color(0.92, 0.72, 0.25),
	"terminal": Color(0.25, 0.80, 0.88),
	"furniture": Color(0.55, 0.43, 0.32),
	"debris": Color(0.5, 0.5, 0.52),
	"body": Color(0.78, 0.22, 0.22),
	"item_pile": Color(0.95, 0.95, 0.5),
}

func setup(p_data: Dictionary) -> void:
	data = p_data
	entity_id = int(data["id"])
	kind = data["kind"]
	proto = data["proto"]
	inventory = []
	var inv: PackedInt32Array = data.get("inventory", PackedInt32Array())
	for i in range(0, inv.size(), 2):
		inventory.append({"item_id": inv[i], "qty": inv[i + 1]})
	position = IsoMath.grid_to_screen(int(data["x"]), int(data["y"]))
	queue_redraw()

func is_open() -> bool:
	return bool(data.get("open", false))

func is_locked() -> bool:
	return bool(data.get("locked", false))

func set_open(v: bool) -> void:
	data["open"] = v
	queue_redraw()
	state_changed.emit(self)

func set_locked(v: bool) -> void:
	data["locked"] = v
	queue_redraw()
	state_changed.emit(self)

func take_all_loot() -> Array:
	var taken := inventory
	inventory = []
	queue_redraw()
	state_changed.emit(self)
	return taken

func _draw() -> void:
	var col: Color = KIND_COLORS.get(kind, Color.MAGENTA)
	match kind:
		"container":
			# Small iso box; open containers render hollow, looted dimmed.
			var s := 10.0
			var pts := PackedVector2Array([
				Vector2(0, -s * 0.5), Vector2(s, 0), Vector2(0, s * 0.5), Vector2(-s, 0)
			])
			if inventory.is_empty():
				col = col.darkened(0.5)
			draw_colored_polygon(pts, col)
			var up := Vector2(0, -8)
			draw_colored_polygon(PackedVector2Array([
				Vector2(-s, 0), Vector2(0, s * 0.5), Vector2(0, s * 0.5) + up, Vector2(-s, 0) + up
			]), col.darkened(0.25))
			draw_colored_polygon(PackedVector2Array([
				Vector2(0, s * 0.5), Vector2(s, 0), Vector2(s, 0) + up, Vector2(0, s * 0.5) + up
			]), col.darkened(0.4))
			if is_locked():
				draw_circle(Vector2(0, -6), 2.5, Color(0.85, 0.2, 0.2))
		"body":
			draw_ellipse_ish(col)
		"terminal":
			draw_rect(Rect2(-5, -12, 10, 12), col)
			draw_rect(Rect2(-3, -10, 6, 6), Color(0.05, 0.15, 0.18))
		"debris":
			var pts2 := PackedVector2Array([
				Vector2(-8, 2), Vector2(-2, -5), Vector2(6, -2), Vector2(8, 4), Vector2(0, 6)
			])
			draw_colored_polygon(pts2, col)
		_:
			if proto == "ladder":
				draw_rect(Rect2(-6, -18, 3, 18), Color(0.9, 0.9, 0.95))
				draw_rect(Rect2(3, -18, 3, 18), Color(0.9, 0.9, 0.95))
				for i in 4:
					draw_rect(Rect2(-6, -16 + i * 5, 12, 2), Color(0.8, 0.8, 0.85))
			else:
				var s2 := 8.0
				draw_colored_polygon(PackedVector2Array([
					Vector2(0, -s2 * 0.6), Vector2(s2, 0), Vector2(0, s2 * 0.6), Vector2(-s2, 0)
				]), col)

func draw_ellipse_ish(col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 12:
		var a := TAU * i / 12.0
		pts.append(Vector2(cos(a) * 11.0, sin(a) * 5.0))
	draw_colored_polygon(pts, col)
