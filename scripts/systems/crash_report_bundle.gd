extends RefCounted
class_name CrashReportBundle

## REQ-RL-007 crash report bundle.
##
## Pure data sink. Captures `{message, context, stack}` entries and
## flushes them to disk as a JSON bundle. Caps at 256 entries FIFO so
## a runaway log never blows up the user data dir.
##
## Disk-only in this package; upload to a telemetry endpoint is a
## deferred integration concern (ADR-0029). The smoke proves the
## round-trip and the cap.

const MAX_BUNDLE_ENTRIES: int = 256

var _entries: Array = []
var _captured_at: String = ""

func capture(message: String, context: Dictionary = {}, stack: Array = []) -> void:
	if _entries.size() >= MAX_BUNDLE_ENTRIES:
		_entries.pop_front()
	_entries.append({
		"message": message,
		"context": context.duplicate(true),
		"stack": stack.duplicate(),
		"captured_at": Time.get_datetime_string_from_system(true),
	})
	_captured_at = Time.get_datetime_string_from_system(true)

func size() -> int:
	return _entries.size()

func get_entries() -> Array:
	return _entries.duplicate()

func clear() -> void:
	_entries.clear()
	_captured_at = ""

func flush(target_path: String) -> bool:
	if target_path.is_empty():
		return false
	var dir_path: String = target_path.get_base_dir()
	if not dir_path.is_empty():
		var global_dir: String = ProjectSettings.globalize_path(dir_path)
		if not DirAccess.dir_exists_absolute(global_dir):
			var make_err: int = DirAccess.make_dir_recursive_absolute(global_dir)
			if make_err != OK and make_err != ERR_ALREADY_EXISTS:
				push_warning("CrashReportBundle: failed to create crash dir, error=%d" % make_err)
				return false
	var file := FileAccess.open(target_path, FileAccess.WRITE)
	if file == null:
		push_warning("CrashReportBundle: cannot open target for writing, error=%d" % FileAccess.get_open_error())
		return false
	var payload: Dictionary = {
		"captured_at": _captured_at,
		"entry_count": _entries.size(),
		"max_entries": MAX_BUNDLE_ENTRIES,
		"entries": _entries.duplicate(true),
	}
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	return true

func load_from_disk(source_path: String) -> bool:
	if not FileAccess.file_exists(source_path):
		return false
	var file := FileAccess.open(source_path, FileAccess.READ)
	if file == null:
		return false
	var json_text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(json_text)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		return false
	var dict: Dictionary = parsed
	_captured_at = str(dict.get("captured_at", ""))
	var entries_variant: Variant = dict.get("entries", [])
	if typeof(entries_variant) != TYPE_ARRAY:
		return false
	_entries.clear()
	for entry in (entries_variant as Array):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		_entries.append(entry)
	# Trim down to MAX_BUNDLE_ENTRIES in case the on-disk bundle had more
	# (e.g. produced by a future build with a higher cap).
	while _entries.size() > MAX_BUNDLE_ENTRIES:
		_entries.pop_front()
	return true

func get_summary() -> Dictionary:
	return {
		"entry_count": _entries.size(),
		"max_entries": MAX_BUNDLE_ENTRIES,
		"captured_at": _captured_at,
	}