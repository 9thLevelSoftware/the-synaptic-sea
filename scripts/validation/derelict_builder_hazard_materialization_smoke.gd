extends SceneTree

const PreviewScript := preload("res://scripts/procgen/derelict_builder_preview.gd")


func _initialize() -> void:
	var preview = PreviewScript.new()
	var authored := [{"id": "fire_01"}, {"id": "breach_01"}]
	if not preview._hazard_array_matches(authored, [{"id": "fire_01"}, {"id": "breach_01"}]):
		_fail("matching authored and materialized hazard IDs were rejected")
	if preview._hazard_array_matches(authored, []):
		_fail("dropped authored hazards were accepted as empty")
	if preview._hazard_array_matches(authored, [{"id": "fire_01"}, {"id": "other"}]):
		_fail("wrong materialized hazard ID was accepted")
	print("DERELICT BUILDER HAZARD MATERIALIZATION PASS")
	quit(0)


func _fail(message: String) -> void:
	push_error("DERELICT BUILDER HAZARD MATERIALIZATION FAIL %s" % message)
	quit(1)
