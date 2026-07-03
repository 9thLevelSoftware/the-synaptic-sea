extends SceneTree

## REQ-UI parse-check smoke.
## Loads every new pure-state / schema class and asserts each one
## instantiates cleanly. Purely a static parse-check; the per-class
## smokes cover the runtime contract.

const MenuStateScript        := preload("res://scripts/systems/menu_state.gd")
const SettingsStateScript    := preload("res://scripts/systems/settings_state.gd")
const TooltipPresenterScript := preload("res://scripts/systems/tooltip_presenter.gd")
const TooltipPayloadScript   := preload("res://scripts/systems/tooltip_payload.gd")
const TutorialStateScript    := preload("res://scripts/systems/tutorial_state.gd")
const ControllerGlyphStateScript := preload("res://scripts/systems/controller_glyph_state.gd")
const WebChartStateScript    := preload("res://scripts/systems/web_chart_state.gd")

const MenuStateSchemaScript        := preload("res://scripts/schemas/menu_state_schema.gd")
const SettingsStateSchemaScript    := preload("res://scripts/schemas/settings_state_schema.gd")
const TooltipSchemaScript          := preload("res://scripts/schemas/tooltip_schema.gd")
const TutorialStateSchemaScript    := preload("res://scripts/schemas/tutorial_state_schema.gd")
const ControllerGlyphSchemaScript  := preload("res://scripts/schemas/controller_glyph_schema.gd")

func _initialize() -> void:
	var classes := [
		MenuStateScript, SettingsStateScript, TooltipPresenterScript,
		TooltipPayloadScript, TutorialStateScript,
		ControllerGlyphStateScript, WebChartStateScript,
		MenuStateSchemaScript, SettingsStateSchemaScript, TooltipSchemaScript,
		TutorialStateSchemaScript,
		ControllerGlyphSchemaScript,
	]
	for cls in classes:
		var instance = cls.new()
		if instance == null:
			_fail("could not instantiate %s" % str(cls))
			return
		instance = null
	print("UI SHELL PARSE PASS classes=%d" % classes.size())
	quit(0)

func _fail(reason: String) -> void:
	push_error("UI SHELL PARSE FAIL reason=%s" % reason)
	quit(1)
