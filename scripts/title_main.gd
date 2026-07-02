extends Node

## ADR-0043 title screen bootstrap. project.godot run/main_scene points
## here; scripts/main.gd / scenes/main.tscn stay byte-identical so every
## existing main-scene smoke (which preloads res://scenes/main.tscn
## directly) is unaffected. This node instantiates scenes/main.tscn
## itself, lazily, only on New Game / Continue.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const MenuStateScript := preload("res://scripts/systems/menu_state.gd")
const MenuPanelScript := preload("res://scripts/ui/menu_panel.gd")
const SaveLoadServiceScript := preload("res://scripts/systems/save_load_service.gd")
const PermadeathResolverScript := preload("res://scripts/systems/permadeath_resolver.gd")
const TitleSaveQueryScript := preload("res://scripts/systems/title_save_query.gd")

var menu_state
var menu_panel
var main_node: Node = null
var playable_instance: PlayableGeneratedShip = null
var _save_load_service = null
var _resolver = null

func _ready() -> void:
	_save_load_service = SaveLoadServiceScript.new()
	_resolver = PermadeathResolverScript.new()
	_build_title_ui()

func _build_title_ui() -> void:
	menu_state = MenuStateScript.new()
	var catalog: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui/menu_definitions.json"))
	if typeof(catalog) != TYPE_DICTIONARY or not menu_state.configure(catalog as Dictionary):
		push_error("TitleMain: failed to configure MenuState from menu_definitions.json")
		return
	menu_panel = MenuPanelScript.new()
	menu_panel.name = "TitleMenuPanel"
	add_child(menu_panel)
	menu_state.menu_changed.connect(_on_menu_changed)
	menu_state.focus_changed.connect(_on_focus_changed)
	_refresh_continue_enabled()
	menu_state.open_menu("main_menu")
	_refresh_panel()

func _refresh_continue_enabled() -> void:
	var available: bool = TitleSaveQueryScript.is_continue_available(_save_load_service, _resolver)
	menu_state.set_item_enabled("main_menu", "continue", available)

func _unhandled_input(event: InputEvent) -> void:
	if main_node != null:
		return  # gameplay owns input once it exists
	if event.is_action_pressed("ui_down"):
		menu_state.navigate(0, 1)
		_refresh_panel()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		menu_state.navigate(0, -1)
		_refresh_panel()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_confirm()
		get_viewport().set_input_as_handled()

func _confirm() -> void:
	var item_id: String = menu_state.confirm()
	if item_id.is_empty():
		return
	match item_id:
		"start": _on_title_start()
		"continue": _on_title_continue()
		"settings": pass  # out of scope for this domain's title screen (spec 3.1)
		"quit": _on_title_quit()

func _on_title_start() -> void:
	_instantiate_gameplay(false)

func _on_title_continue() -> void:
	_instantiate_gameplay(true)

func _instantiate_gameplay(should_load: bool) -> void:
	main_node = MAIN_SCENE.instantiate()
	add_child(main_node)
	if menu_panel != null:
		menu_panel.visible = false
	_poll_for_playable_started(should_load)

func _poll_for_playable_started(should_load: bool) -> void:
	if main_node == null:
		return
	playable_instance = main_node.playable_instance
	if playable_instance == null or not playable_instance.playable_started:
		call_deferred("_poll_for_playable_started", should_load)
		return
	if not playable_instance.return_to_title_requested.is_connected(_on_gameplay_return_to_title):
		playable_instance.return_to_title_requested.connect(_on_gameplay_return_to_title)
	if should_load:
		playable_instance.request_load()

func _on_title_quit() -> void:
	get_tree().quit()

func _on_gameplay_return_to_title() -> void:
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	main_node = null
	playable_instance = null
	if menu_panel != null and is_instance_valid(menu_panel):
		menu_panel.queue_free()
	menu_panel = null
	_build_title_ui()

func _on_menu_changed(_new_menu_id: String, _previous_menu_id: String) -> void:
	_refresh_panel()

func _on_focus_changed(_new_index: int) -> void:
	_refresh_panel()

func _refresh_panel() -> void:
	if menu_panel == null or menu_state == null:
		return
	var current_menu: String = menu_state.get_current_menu()
	if current_menu.is_empty():
		menu_panel.visible = false
		return
	menu_panel.visible = true
	var lines := PackedStringArray()
	var items: Array = menu_state.get_items(current_menu)
	for index in range(items.size()):
		var item: Dictionary = items[index]
		var item_id: String = str(item.get("id", ""))
		var label_text: String = str(item.get("label", item_id))
		var prefix: String = "> " if index == menu_state.get_focus_index() else "  "
		var enabled_suffix: String = "" if menu_state.is_item_enabled(current_menu, item_id) else " (disabled)"
		lines.append(prefix + label_text + enabled_suffix)
	menu_panel.set_content("The Synaptic Sea", lines)
