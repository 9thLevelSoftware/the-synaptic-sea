extends SceneTree

## SFX_REPAIR_COMPLETE is seam+router catalogued for repair finish path.
## Marker: REPAIR COMPLETE SFX PASS seam=true router=true

const AudioEventSeamScript := preload("res://scripts/audio/audio_event_seam.gd")
const SfxEventRouterScript := preload("res://scripts/systems/sfx_event_router.gd")


func _initialize() -> void:
	var eid: String = String(AudioEventSeamScript.SFX_REPAIR_COMPLETE)
	if not SfxEventRouterScript.EVENT_CATALOG.has(eid):
		_fail("router"); return
	var router = SfxEventRouterScript.new()
	router.configure({})
	if router.route(AudioEventSeamScript.SFX_REPAIR_COMPLETE, false) == null:
		_fail("route"); return
	print("REPAIR COMPLETE SFX PASS seam=true router=true")
	quit(0)


func _fail(msg: String) -> void:
	print("REPAIR COMPLETE SFX FAIL: %s" % msg)
	quit(1)
