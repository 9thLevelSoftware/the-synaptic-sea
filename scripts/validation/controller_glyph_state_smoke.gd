extends SceneTree
const ControllerGlyphStateScript := preload("res://scripts/systems/controller_glyph_state.gd")
func _init() -> void:
	var state = ControllerGlyphStateScript.new()
	var glyphs: Dictionary = {"version": "controller-glyphs-1", "default_scheme": "auto", "fallback_scheme": "keyboard", "actions": [{"action": "interact", "schemes": {"keyboard": "[E]", "gamepad_xbox": "[A]", "gamepad_ps": "[Cross]"}}]}
	assert(state.configure(glyphs, {"interact": [69]}))
	assert(state.glyph_for("interact", "keyboard") == "[E]")
	assert(state.resolve_scheme("keyboard") == "keyboard")
	print("CONTROLLER GLYPH STATE PASS schemes=3 action=interact glyph=%s" % state.glyph_for("interact", "keyboard"))
	quit()
