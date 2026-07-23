extends SceneTree

## Ship-mod open/install/uninstall UI SFX ids exist in seam + router and route.
## Marker: SHIP MOD AUDIO PASS seam=true router=true route=true

const AudioEventSeamScript := preload("res://scripts/audio/audio_event_seam.gd")
const SfxEventRouterScript := preload("res://scripts/systems/sfx_event_router.gd")


func _initialize() -> void:
	var ids: Array[StringName] = [
		AudioEventSeamScript.UI_SHIP_MOD_OPEN,
		AudioEventSeamScript.UI_SHIP_MOD_INSTALL,
		AudioEventSeamScript.UI_SHIP_MOD_UNINSTALL,
	]
	var router = SfxEventRouterScript.new()
	router.configure({})
	for sn in ids:
		var key: String = String(sn)
		if key.is_empty():
			_fail("empty seam constant"); return
		if not SfxEventRouterScript.EVENT_CATALOG.has(key):
			_fail("router missing %s" % key); return
		if router.route(sn, false) == null:
			_fail("not routable %s" % key); return
	print("SHIP MOD AUDIO PASS seam=true router=true route=true")
	quit(0)


func _fail(msg: String) -> void:
	print("SHIP MOD AUDIO FAIL: %s" % msg)
	quit(1)
