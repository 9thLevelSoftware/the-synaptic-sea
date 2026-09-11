extends RefCounted

## Shared JSON writer for the Unity parity fixture exporter.
##
## Every fixture is written with Godot's default JSON formatting
## (`JSON.stringify(value, "\t")`: sort_keys=true, full_precision=false),
## after `canonical()` has turned engine value types (Vector2i, Vector3, ...)
## into plain arrays. Godot's default writer keeps only ~15 significant
## digits for floats, so when that default text would not round-trip every
## float exactly, a `<name>.fullprec.json` companion is also written with
## `full_precision=true` (shortest round-trip representation).

var out_dir: String = ""
var files: Array[String] = []
var errors: Array[String] = []


func _init(p_out_dir: String) -> void:
	out_dir = p_out_dir


func abs_path(rel_path: String) -> String:
	return out_dir.path_join(rel_path)


func ensure_dir(rel_dir: String) -> bool:
	var path: String = abs_path(rel_dir)
	if DirAccess.dir_exists_absolute(path):
		return true
	var err: int = DirAccess.make_dir_recursive_absolute(path)
	if err != OK:
		errors.append("cannot create directory %s (err %d)" % [path, err])
		return false
	return true


## Writes canonical(value) as tab-indented default-precision JSON. Returns
## true on success. Adds a .fullprec.json companion when the default text is
## lossy (or when force_fullprec is set).
func write_json(rel_path: String, value: Variant, force_fullprec: bool = false) -> bool:
	var canonical_value: Variant = canonical(value)
	var bad_type: String = find_non_json_type(canonical_value, "$")
	if not bad_type.is_empty():
		errors.append("%s contains a non-JSON value at %s" % [rel_path, bad_type])
		return false
	var text: String = JSON.stringify(canonical_value, "\t")
	if not write_text(rel_path, text):
		return false
	if force_fullprec or is_default_json_lossy(canonical_value):
		var full_text: String = JSON.stringify(canonical_value, "\t", true, true)
		var full_rel: String = rel_path.get_basename() + ".fullprec.json"
		if not write_text(full_rel, full_text):
			return false
	return true


## Writes text byte-for-byte (UTF-8, no trailing newline added).
func write_text(rel_path: String, text: String) -> bool:
	var path: String = abs_path(rel_path)
	if not ensure_dir(rel_path.get_base_dir()):
		return false
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		errors.append("cannot open %s for writing (err %d)" % [path, FileAccess.get_open_error()])
		return false
	file.store_string(text)
	file.close()
	_track(rel_path)
	return true


func copy_file_abs(source_abs: String, rel_path: String) -> bool:
	if not ensure_dir(rel_path.get_base_dir()):
		return false
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(source_abs)
	if bytes.is_empty() and FileAccess.get_open_error() != OK:
		errors.append("cannot read %s" % source_abs)
		return false
	var file: FileAccess = FileAccess.open(abs_path(rel_path), FileAccess.WRITE)
	if file == null:
		errors.append("cannot write %s" % abs_path(rel_path))
		return false
	file.store_buffer(bytes)
	file.close()
	_track(rel_path)
	return true


func _track(rel_path: String) -> void:
	var normalized: String = rel_path.replace("\\", "/")
	if not files.has(normalized):
		files.append(normalized)


## True when JSON.stringify's default (15 significant digit) float output
## would not parse back to exactly the same values as the full-precision text.
func is_default_json_lossy(value: Variant) -> bool:
	var default_parsed: Variant = JSON.parse_string(JSON.stringify(value))
	var full_parsed: Variant = JSON.parse_string(JSON.stringify(value, "", true, true))
	return not deep_equal(default_parsed, full_parsed)


## Deterministic JSON-safe form: engine vectors -> arrays, packed arrays ->
## arrays, StringName -> String, Dictionary keys -> String (sorted).
func canonical(value: Variant) -> Variant:
	match typeof(value):
		TYPE_VECTOR2I:
			var v2i: Vector2i = value
			return [int(v2i.x), int(v2i.y)]
		TYPE_VECTOR2:
			var v2: Vector2 = value
			return [float(v2.x), float(v2.y)]
		TYPE_VECTOR3:
			var v3: Vector3 = value
			return [float(v3.x), float(v3.y), float(v3.z)]
		TYPE_VECTOR3I:
			var v3i: Vector3i = value
			return [int(v3i.x), int(v3i.y), int(v3i.z)]
		TYPE_STRING_NAME:
			return str(value)
		TYPE_DICTIONARY:
			var source: Dictionary = value
			var keys: Array[String] = []
			var by_key: Dictionary = {}
			for key_variant in source.keys():
				var key: String = str(key_variant)
				keys.append(key)
				by_key[key] = source[key_variant]
			keys.sort()
			var ordered: Dictionary = {}
			for key in keys:
				ordered[key] = canonical(by_key[key])
			return ordered
		TYPE_ARRAY, TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY:
			var out: Array = []
			for item in value:
				out.append(canonical(item))
			return out
	return value


## Returns a JSON-path of the first value that is not plain JSON data, or "".
func find_non_json_type(value: Variant, path: String) -> String:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return ""
		TYPE_ARRAY:
			var index: int = 0
			for item in value:
				var found: String = find_non_json_type(item, "%s[%d]" % [path, index])
				if not found.is_empty():
					return found
				index += 1
			return ""
		TYPE_DICTIONARY:
			for key in (value as Dictionary).keys():
				var found: String = find_non_json_type(value[key], "%s.%s" % [path, str(key)])
				if not found.is_empty():
					return found
			return ""
	return "%s (%s)" % [path, type_string(typeof(value))]


## Structural equality that treats int/float with the same numeric value as
## equal (JSON.parse_string returns every number as float).
func deep_equal(a: Variant, b: Variant) -> bool:
	var ta: int = typeof(a)
	var tb: int = typeof(b)
	var a_num: bool = ta == TYPE_INT or ta == TYPE_FLOAT
	var b_num: bool = tb == TYPE_INT or tb == TYPE_FLOAT
	if a_num and b_num:
		return float(a) == float(b)
	if ta != tb:
		return false
	if ta == TYPE_ARRAY:
		var aa: Array = a
		var ba: Array = b
		if aa.size() != ba.size():
			return false
		for i in range(aa.size()):
			if not deep_equal(aa[i], ba[i]):
				return false
		return true
	if ta == TYPE_DICTIONARY:
		var ad: Dictionary = a
		var bd: Dictionary = b
		if ad.size() != bd.size():
			return false
		for key in ad.keys():
			if not bd.has(key):
				return false
			if not deep_equal(ad[key], bd[key]):
				return false
		return true
	return a == b


## Returns up to `limit` JSON paths where two parsed documents differ.
func diff_paths(a: Variant, b: Variant, path: String, out: Array, limit: int = 40) -> void:
	if out.size() >= limit:
		return
	var ta: int = typeof(a)
	var tb: int = typeof(b)
	var a_num: bool = ta == TYPE_INT or ta == TYPE_FLOAT
	var b_num: bool = tb == TYPE_INT or tb == TYPE_FLOAT
	if a_num and b_num:
		if float(a) != float(b):
			out.append("%s: %s != %s" % [path, str(a), str(b)])
		return
	if ta != tb:
		out.append("%s: type %s != %s" % [path, type_string(ta), type_string(tb)])
		return
	if ta == TYPE_ARRAY:
		var aa: Array = a
		var ba: Array = b
		if aa.size() != ba.size():
			out.append("%s: array size %d != %d" % [path, aa.size(), ba.size()])
		for i in range(mini(aa.size(), ba.size())):
			diff_paths(aa[i], ba[i], "%s[%d]" % [path, i], out, limit)
		return
	if ta == TYPE_DICTIONARY:
		var ad: Dictionary = a
		var bd: Dictionary = b
		var keys: Array = ad.keys()
		for key in bd.keys():
			if not keys.has(key):
				keys.append(key)
		keys.sort()
		for key in keys:
			if not ad.has(key):
				out.append("%s.%s: missing on left" % [path, str(key)])
			elif not bd.has(key):
				out.append("%s.%s: missing on right" % [path, str(key)])
			else:
				diff_paths(ad[key], bd[key], "%s.%s" % [path, str(key)], out, limit)
			if out.size() >= limit:
				return
		return
	if a != b:
		out.append("%s: %s != %s" % [path, str(a), str(b)])
