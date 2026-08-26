class_name DerelictDebugViewer
extends Node2D
## Debug/regeneration viewer and test scene: seed entry, archetype pick,
## intactness slider, deck switching, room-graph/damage overlays, plus a
## walkable grid player (WASD, F interact, E/Q decks).

var site: DerelictSite
var player: GridPlayer
var camera: Camera2D
var overlay: Node2D
var info_label: Label
var msg_label: Label
var seed_spin: SpinBox
var arch_option: OptionButton
var intact_slider: HSlider
var intact_check: CheckBox
var overlay_check: CheckBox
var deck_label: Label

var _dragging := false

func _ready() -> void:
	site = DerelictSite.new()
	site.name = "Site"
	add_child(site)
	site.ship_ready.connect(_on_ship_ready)

	camera = Camera2D.new()
	camera.zoom = Vector2(0.6, 0.6)
	add_child(camera)
	camera.make_current()

	overlay = OverlayDraw.new()
	overlay.viewer = self
	overlay.z_index = 100
	add_child(overlay)

	_build_ui()
	_regenerate()

func _build_ui() -> void:
	var ui := CanvasLayer.new()
	add_child(ui)
	var panel := PanelContainer.new()
	panel.position = Vector2(8, 8)
	ui.add_child(panel)
	var v := VBoxContainer.new()
	panel.add_child(v)

	var h1 := HBoxContainer.new()
	v.add_child(h1)
	h1.add_child(_label("Seed"))
	seed_spin = SpinBox.new()
	seed_spin.max_value = 1_000_000_000
	seed_spin.value = 12
	h1.add_child(seed_spin)
	var rand_btn := Button.new()
	rand_btn.text = "🎲"
	rand_btn.pressed.connect(func() -> void:
		seed_spin.value = randi() % 1_000_000
		_regenerate())
	h1.add_child(rand_btn)

	var h2 := HBoxContainer.new()
	v.add_child(h2)
	h2.add_child(_label("Class"))
	arch_option = OptionButton.new()
	for a in ["shuttle", "corvette", "freighter", "frigate"]:
		arch_option.add_item(a)
	arch_option.select(3)
	h2.add_child(arch_option)

	var h3 := HBoxContainer.new()
	v.add_child(h3)
	intact_check = CheckBox.new()
	intact_check.text = "Intactness"
	intact_check.button_pressed = true
	h3.add_child(intact_check)
	intact_slider = HSlider.new()
	intact_slider.min_value = 0
	intact_slider.max_value = 10000
	intact_slider.value = 3000
	intact_slider.custom_minimum_size.x = 160
	h3.add_child(intact_slider)

	var regen := Button.new()
	regen.text = "Regenerate (R)"
	regen.pressed.connect(_regenerate)
	v.add_child(regen)

	var h4 := HBoxContainer.new()
	v.add_child(h4)
	var down := Button.new()
	down.text = "Deck -"
	down.pressed.connect(func() -> void: _switch_deck(-1))
	h4.add_child(down)
	deck_label = _label("0")
	h4.add_child(deck_label)
	var up := Button.new()
	up.text = "Deck +"
	up.pressed.connect(func() -> void: _switch_deck(1))
	h4.add_child(up)

	overlay_check = CheckBox.new()
	overlay_check.text = "Room graph overlay"
	overlay_check.toggled.connect(func(_v: bool) -> void: overlay.queue_redraw())
	v.add_child(overlay_check)

	info_label = _label("")
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_label.custom_minimum_size.x = 260
	v.add_child(info_label)

	msg_label = _label("")
	msg_label.modulate = Color(1.0, 0.9, 0.5)
	v.add_child(msg_label)

	v.add_child(_label("WASD move · F interact · E/Q decks\nMMB drag pan · wheel zoom"))

func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l

func _regenerate() -> void:
	site.world_seed = int(seed_spin.value)
	site.world_x = 0
	site.world_y = 0
	site.archetype_id = arch_option.get_item_text(arch_option.selected)
	var intact := -1
	if intact_check.button_pressed:
		intact = int(intact_slider.value)
	site.discover(intact)

func _on_ship_ready(ship_node: DerelictShipNode) -> void:
	if player:
		player.queue_free()
	player = GridPlayer.new()
	player.attach(ship_node)
	player.message.connect(func(t: String) -> void: msg_label.text = t)
	player.deck_changed.connect(func(d: int) -> void:
		deck_label.text = str(d)
		overlay.queue_redraw())
	var ship := ship_node.ship
	var frac := "  FRACTURED" if ship["fractured"] else ""
	info_label.text = "%s  seed %d\nintactness %.2f  cause: %s%s\n%d rooms, %d entities, %d decks" % [
		ship["archetype_id"], ship["seed"], ship["intactness"] / 10000.0,
		ship["cause_of_loss"], frac, ship["rooms"].size(), ship["entities"].size(),
		ship["decks"].size()]
	deck_label.text = "0"
	# Center camera on the ship.
	var deck0: Dictionary = ship["decks"][0]
	camera.position = IsoMath.grid_to_screen(int(deck0["width"]) / 2, int(deck0["height"]) / 2)
	overlay.queue_redraw()

func _switch_deck(dir: int) -> void:
	if site.ship_node == null:
		return
	var d: int = clampi(site.ship_node.active_deck + dir, 0, site.ship_node.deck_count() - 1)
	site.ship_node.set_active_deck(d)
	if player:
		player.deck = d
	deck_label.text = str(d)
	overlay.queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_R:
		_regenerate()
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera.zoom *= 1.1
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.zoom /= 1.1
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		camera.position -= event.relative / camera.zoom.x


class OverlayDraw:
	extends Node2D
	var viewer: DerelictDebugViewer

	func _draw() -> void:
		if not viewer.overlay_check.button_pressed or viewer.site.ship_node == null:
			return
		var ship: Dictionary = viewer.site.ship_node.ship
		var active: int = viewer.site.ship_node.active_deck
		var centers := {}
		for room in ship["rooms"]:
			var cx := (int(room["min_x"]) + int(room["max_x"])) / 2.0
			var cy := (int(room["min_y"]) + int(room["max_y"])) / 2.0
			centers[int(room["id"])] = IsoMath.grid_to_screen(int(cx), int(cy))
			if int(room["deck"]) == active:
				var col := Color(1, 0.3, 0.3, 0.9) if room["depressurized"] else Color(0.4, 1, 0.6, 0.9)
				draw_circle(centers[int(room["id"])], 5.0, col)
		for edge in ship["edges"]:
			var a: int = edge["a"]
			var b: int = edge["b"]
			if centers.has(a) and centers.has(b):
				var col2 := Color(1, 0.5, 1, 0.8) if edge["kind"] == "shaft" else Color(0.5, 0.9, 1, 0.5)
				draw_line(centers[a], centers[b], col2, 2.0)
		for ev in ship["damage_events"]:
			if int(ev["deck"]) != active:
				continue
			var p := IsoMath.grid_to_screen(int(ev["x"]), int(ev["y"]))
			draw_arc(p, ev["radius"] * IsoMath.TILE_W * 0.5, 0, TAU, 32, Color(1, 0.4, 0.1, 0.8), 2.0)
