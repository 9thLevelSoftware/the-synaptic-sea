extends SceneTree
const MenuStateScript := preload("res://scripts/systems/menu_state.gd")
func _init() -> void:
	var state = MenuStateScript.new()
	var catalog: Dictionary = {
		"menus": [
			{"id": "main_menu", "title": "Main", "items": [{"id": "start", "label": "Start", "enabled": true, "kind": "command"}, {"id": "continue", "label": "Continue", "enabled": false, "kind": "command"}]},
			{"id": "settings_menu", "title": "Settings", "items": [{"id": "text_scale", "label": "Text Scale", "enabled": true, "kind": "slider"}, {"id": "back", "label": "Back", "enabled": true, "kind": "command"}]}
		]
	}
	assert(state.configure(catalog))
	assert(state.open_menu("main_menu"))
	assert(state.get_current_menu() == "main_menu")
	state.set_item_enabled("main_menu", "continue", true)
	assert(state.open_menu("settings_menu"))
	assert(state.navigate(0, 1) == 1)
	assert(state.confirm() == "back")
	assert(state.cancel())
	print("MENU STATE PASS menus=2 navigation=true enable_toggle=true")
	quit()
