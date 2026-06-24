extends PanelContainer
class_name InventoryDropZone

## A drop target tagged with a `target` ("self"/"container" pane, or "slot:<slot_id>").
## Forwards drops to the owning InventoryPanel; on an equipment slot, right-click forwards
## to slot_context (Unequip). Constructed via the load()-self-reference factory.

var panel                       # InventoryPanel
var target: String = ""

static func create(p_panel, p_target: String):
	var script: GDScript = load("res://scripts/ui/inventory_drop_zone.gd")
	var z = script.new()
	z.panel = p_panel
	z.target = p_target
	return z

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return panel.zone_can_accept(target, data)

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	panel.zone_drop(target, data)

func _gui_input(event: InputEvent) -> void:
	if not target.begins_with("slot:"):
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			panel.slot_context(target.substr(5), mb.global_position)
