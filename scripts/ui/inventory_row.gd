extends PanelContainer
class_name InventoryRow

## One selectable / draggable / right-clickable inventory row. Thin: every mouse event
## forwards to the owning InventoryPanel's coordinator callbacks. Constructed via the
## load()-self-reference factory so it resolves under --headless --script.

const ItemDefsScript := preload("res://scripts/systems/item_defs.gd")
const RarityTierScript := preload("res://scripts/systems/rarity_tier.gd")
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
var lot_id: String = ""
var lot_quantity: int = 0
var _defs: Dictionary = {}
var _selected: bool = false

static func create(p_panel, p_pane: String, p_index: int, p_item_id: String, p_defs: Dictionary, p_lot_id: String = "", p_lot_quantity: int = 0):
	assert(p_panel != null, "InventoryRow.create: panel dependency must not be null")
	var script: GDScript = load("res://scripts/ui/inventory_row.gd")
	var r = script.new()
	r.panel = p_panel
	r.pane = p_pane
	r.index = p_index
	r.item_id = p_item_id
	r.lot_id = p_lot_id
	r.lot_quantity = p_lot_quantity
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
	var qty: int = lot_quantity if not lot_id.is_empty() else (int(panel.pane_quantity(pane, item_id)) if is_instance_valid(panel) else 0)
	var quality_text: String = ""
	if not lot_id.is_empty() and is_instance_valid(panel):
		quality_text = "  [%s]" % lot_id
		var inv = panel._inv_for_pane(pane) if panel.has_method("_inv_for_pane") else null
		if inv != null and inv.has_method("get_lot_summary"):
			for lot_v in (inv.get_lot_summary().get("lots", []) as Array):
				if lot_v is Dictionary and str((lot_v as Dictionary).get("lot_id", "")) == lot_id:
					quality_text = "  %s  [%s]" % [str((lot_v as Dictionary).get("quality_tier", "standard")).capitalize(), lot_id]
					break
	lbl.text = "%s  x%d%s" % [ItemDefsScript.display_name(_defs, item_id), qty, quality_text]
	h.add_child(lbl)
	add_child(h)
	_apply_style()

func set_selected(v: bool) -> void:
	_selected = v
	_apply_style()

func _apply_style() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = SEL_BG if _selected else Color(0, 0, 0, 0)
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.border_color = RarityTierScript.color(ItemDefsScript.rarity(_defs, item_id))
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
	var data = panel.row_lot_drag_payload(pane, item_id, lot_id, qty_for_drag()) if not lot_id.is_empty() else panel.row_drag_payload(pane, index)
	if data == null:
		return null
	var preview := Label.new()
	preview.text = "%d item(s)" % ((data as Dictionary)["ids"] as Array).size()
	set_drag_preview(preview)
	return data

func qty_for_drag() -> int:
	return lot_quantity if lot_quantity > 0 else (int(panel.pane_quantity(pane, item_id)) if is_instance_valid(panel) else 0)

# A row is also a drop target for its own pane (drop on a row == drop on the pane).
func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return is_instance_valid(panel) and panel.zone_can_accept(pane, data)

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if not is_instance_valid(panel):
		return
	panel.zone_drop(pane, data)
