extends SceneTree

## Task 1.5: slice audio content pack coverage.
##
## Every slice-required event/layer id must resolve through AudioManager's
## existing STREAM_CATALOG to a real, decodable, non-empty WAV. This smoke
## deliberately checks the manager catalog rather than creating a second
## audio-event registry.
##
## Marker: AUDIO CONTENT COVERAGE PASS clips=15 catalog=true non_empty=true decoded=true

const AudioManagerScript := preload("res://scripts/audio/audio_manager.gd")

const REQUIRED_STREAM_IDS: Array[StringName] = [
	&"sfx.footstep",
	&"ui.panel.open",
	&"ui.panel.close",
	&"sfx.tool.pickup",
	&"sfx.fire.crackle",
	&"meta.hull.groan",
	&"sfx.combat.hit",
	&"sfx.combat.threat_alert",
	&"sfx.door.open",
	&"sfx.door.close",
	&"sfx.dock.land",
	&"ui.vitals.low",
	&"layer.base",
	&"layer.tension_drone",
	&"layer.critical_pad",
]

func _initialize() -> void:
	var catalog: Dictionary = AudioManagerScript.STREAM_CATALOG
	var failures: Array[String] = []
	var decoded_count: int = 0
	var non_empty_count: int = 0
	for event_id in REQUIRED_STREAM_IDS:
		var key: String = String(event_id)
		if not catalog.has(key):
			failures.append("catalog missing %s" % key)
			continue
		var path: String = String(catalog.get(key, ""))
		if path.is_empty():
			failures.append("catalog path empty for %s" % key)
			continue
		if not FileAccess.file_exists(path):
			failures.append("file missing for %s: %s" % [key, path])
			continue
		var file: FileAccess = FileAccess.open(path, FileAccess.READ)
		if file == null:
			failures.append("file cannot open for %s: %s" % [key, path])
			continue
		var byte_size: int = file.get_length()
		file.close()
		if byte_size <= 44:
			failures.append("file too small for %s: %d bytes" % [key, byte_size])
		else:
			non_empty_count += 1
		var stream: AudioStreamWAV = AudioStreamWAV.load_from_file(path)
		if stream == null:
			failures.append("WAV decode failed for %s: %s" % [key, path])
		else:
			decoded_count += 1

	if not failures.is_empty():
		_fail("; ".join(failures))
		return
	print("AUDIO CONTENT COVERAGE PASS clips=%d catalog=true non_empty=%s decoded=%s" % [
		REQUIRED_STREAM_IDS.size(),
		str(non_empty_count == REQUIRED_STREAM_IDS.size()).to_lower(),
		str(decoded_count == REQUIRED_STREAM_IDS.size()).to_lower(),
	])
	quit(0)

func _fail(reason: String) -> void:
	push_error("AUDIO CONTENT COVERAGE FAIL reason=%s" % reason)
	quit(1)
