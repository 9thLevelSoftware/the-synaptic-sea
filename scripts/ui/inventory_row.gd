extends PanelContainer
class_name InventoryRow

## One selectable / draggable / right-clickable inventory row. Thin: every mouse event
## forwards to the owning InventoryPanel's coordinator callbacks. Constructed via the
## load()-self-reference factory so it resolves under --headless --script.

const ItemDefsScript := preload("res://scripts/systems/item_defs.gd")
const SWATCH := {
	"part": Color(0.55, 0.70, 0.95),
	"supply": Color(0.60, 0.90, 0.60),
	"tool": Color(0.95, 0.80, 0.40),
}
const SEL_BG := Color(0.18, 0.40, 0.55, 0.85)

var panel                       # InventoryPanel
var pane: String = ""
var index: int = -1
var item_id: String = ""
var _defs: Dictionary = {}
var _selected: bool = false

static func create(p_panel, p_pane: String, p_index: int, p_item_id: String, p_defs: Dictionary):
	assert(p_panel != null, "InventoryRow.create: panel dependency must not be null")
	var script: GDScript = load("res://scripts/ui/inventory_row.gd")
	var r = script.new()
	r.panel = p_panel
	r.pane = p_pane
	r.index = p_index
	r.item_id = p_item_id
	r._defs = p_defs
	return r

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var h := HBoxContainer.new()
	var sw := ColorRect.new()
	sw.custom_minimum_size = Vector2(14, 14)
	sw.color = SWATCH.get(ItemDefsScript.category(_defs, item_id), Color(0.5, 0.5, 0.5))
	h.add_child(sw)
	var lbl := Label.new()
	var qty: int = int(panel.pane_quantity(pane, item_id)) if is_instance_valid(panel) else 0
	lbl.text = "%s  x%d" % [ItemDefsScript.display_name(_defs, item_id), qty]
	h.add_child(lbl)
	add_child(h)
	_apply_style()

func set_selected(v: bool) -> void:
	_selected = v
	_apply_style()

func _apply_style() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = SEL_BG if _selected else Color(0, 0, 0, 0)
	sb.set_corner_radius_all(4)
	add_theme_stylebox_override("panel", sb)

func _gui_input(event: InputEvent) -> void:
	if not is_instance_valid(panel):
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			panel.row_clicked(pane, index, mb.ctrl_pressed, mb.shift_pressed)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			panel.row_context(pane, index, mb.global_position)

func _get_drag_data(_at_position: Vector2) -> Variant:
	if not is_instance_valid(panel):
		return null
	var data = panel.row_drag_payload(pane, index)
	if data == null:
		return null
	var preview := Label.new()
	preview.text = "%d item(s)" % ((data as Dictionary)["ids"] as Array).size()
	set_drag_preview(preview)
	return data

# A row is also a drop target for its own pane (drop on a row == drop on the pane).
func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return is_instance_valid(panel) and panel.zone_can_accept(pane, data)

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if not is_instance_valid(panel):
		return
	panel.zone_drop(pane, data)
