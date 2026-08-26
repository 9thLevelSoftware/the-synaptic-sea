extends RefCounted
class_name ProcgenCanonicalJson

## Rust semantic_hash's mechanical projection, without passing numbers through
## Godot's Variant parser (which would erase 40.0 versus 40).
var last_error: String = ""
var _source: String = ""
var _index: int = 0

func canonicalize(raw: String) -> String:
	last_error = ""
	_source = raw
	_index = 0
	var value: Variant = _parse_value()
	if value == null:
		return ""
	_skip_ws()
	if _index != _source.length():
		return _fail("trailing input")
	if not _is_object(value):
		return _fail("lifecycle root must be an object")
	var bundle: Variant = _object_get(value, "bundle")
	if bundle == null or not _is_object(bundle):
		return _fail("lifecycle bundle must be an object")
	var projection: Array = []
	for key in ["version", "request", "world_ir", "site_ir", "gameplay_ir"]:
		var child: Variant = _object_get(bundle, key)
		if child == null:
			return _fail("bundle missing %s" % key)
		if key == "request":
			if not _is_object(child):
				return _fail("bundle request must be an object")
			child = _without_key(child, "presentation")
		projection.append([key, child])
	return _serialize_object(projection)

func semantic_hash(raw: String) -> String:
	var canonical: String = canonicalize(raw)
	if canonical.is_empty():
		return ""
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(canonical.to_utf8_buffer())
	return context.finish().hex_encode()

func _fail(message: String) -> String:
	last_error = message + " at byte %d" % _index
	return ""

func _skip_ws() -> void:
	while _index < _source.length() and _source[_index] in [" ", "\t", "\r", "\n"]:
		_index += 1

func _parse_value() -> Variant:
	_skip_ws()
	if _index >= _source.length():
		_fail("unexpected end")
		return null
	var c: String = _source[_index]
	if c == "{": return _parse_object()
	if c == "[": return _parse_array()
	if c == "\"": return _parse_string()
	if c == "-" or c.is_valid_int() and c >= "0" and c <= "9": return _parse_number()
	for literal in ["true", "false", "null"]:
		if _source.substr(_index, literal.length()) == literal:
			_index += literal.length()
			return {"t": literal}
	_fail("invalid token")
	return null

func _parse_object() -> Variant:
	_index += 1
	var entries: Array = []
	var seen: Dictionary = {}
	_skip_ws()
	if _take("}"): return {"t": "o", "v": entries}
	while true:
		_skip_ws()
		if _index >= _source.length() or _source[_index] != "\"":
			_fail("object key must be a string")
			return null
		var key_value: Variant = _parse_string()
		if key_value == null: return null
		var key: String = key_value["v"]
		if seen.has(key):
			_fail("duplicate object key")
			return null
		seen[key] = true
		_skip_ws()
		if not _take(":"):
			_fail("expected colon")
			return null
		var child: Variant = _parse_value()
		if child == null: return null
		entries.append([key, child])
		_skip_ws()
		if _take("}"): break
		if not _take(","):
			_fail("expected comma")
			return null
	return {"t": "o", "v": entries}

func _parse_array() -> Variant:
	_index += 1
	var values: Array = []
	_skip_ws()
	if _take("]"): return {"t": "a", "v": values}
	while true:
		var child: Variant = _parse_value()
		if child == null: return null
		values.append(child)
		_skip_ws()
		if _take("]"): break
		if not _take(","):
			_fail("expected comma")
			return null
	return {"t": "a", "v": values}

func _parse_string() -> Variant:
	var start: int = _index
	_index += 1
	while _index < _source.length():
		var c: String = _source[_index]
		if c == "\\":
			_index += 2
			continue
		if c == "\"":
			_index += 1
			var token: String = _source.substr(start, _index - start)
			var decoded: Variant = JSON.parse_string(token)
			if decoded == null and token != "\"null\"":
				_fail("invalid string")
				return null
			return {"t": "s", "v": str(decoded)}
		if c.unicode_at(0) < 32:
			_fail("control character in string")
			return null
		_index += 1
	_fail("unterminated string")
	return null

func _parse_number() -> Variant:
	var start: int = _index
	if _take("-") and _index >= _source.length():
		_fail("invalid number")
		return null
	if _index < _source.length() and _source[_index] == "0":
		_index += 1
	else:
		if _index >= _source.length() or not _source[_index].is_valid_int():
			_fail("invalid number")
			return null
		while _index < _source.length() and _source[_index].is_valid_int(): _index += 1
	if _index < _source.length() and _source[_index] == ".":
		_index += 1
		var fraction_start: int = _index
		while _index < _source.length() and _source[_index].is_valid_int(): _index += 1
		if fraction_start == _index: return _fail("invalid fraction") as Variant
	if _index < _source.length() and (_source[_index] == "e" or _source[_index] == "E"):
		_index += 1
		if _index < _source.length() and (_source[_index] == "+" or _source[_index] == "-"): _index += 1
		var exponent_start: int = _index
		while _index < _source.length() and _source[_index].is_valid_int(): _index += 1
		if exponent_start == _index: return _fail("invalid exponent") as Variant
	if _index < _source.length() and (_source[_index] == "." or _source[_index] == "e" or _source[_index] == "E"):
		_fail("invalid number")
		return null
	if _index < _source.length() and (_source[_index].is_valid_int() or _source[_index] == "_"):
		_fail("invalid number")
		return null
	return {"t": "n", "v": _source.substr(start, _index - start)}

func _take(token: String) -> bool:
	if _source.substr(_index, token.length()) == token:
		_index += token.length()
		return true
	return false

func _is_object(value: Variant) -> bool: return value is Dictionary and value.get("t", "") == "o"
func _object_get(value: Variant, key: String) -> Variant:
	for entry in value["v"]:
		if entry[0] == key: return entry[1]
	return null
func _without_key(value: Variant, unwanted: String) -> Variant:
	var entries: Array = []
	for entry in value["v"]:
		if entry[0] != unwanted: entries.append(entry)
	return {"t": "o", "v": entries}

func _serialize_object(entries: Array) -> String:
	var sorted: Array = entries.duplicate()
	sorted.sort_custom(func(a: Array, b: Array) -> bool: return String(a[0]) < String(b[0]))
	var parts: Array[String] = []
	for entry in sorted: parts.append(JSON.stringify(entry[0]) + ":" + _serialize(entry[1]))
	return "{" + ",".join(parts) + "}"

func _serialize(value: Variant) -> String:
	var tag: String = value["t"]
	if tag == "o":
		var entries: Array = value["v"].duplicate()
		entries.sort_custom(func(a: Array, b: Array) -> bool: return String(a[0]) < String(b[0]))
		var parts: Array[String] = []
		for entry in entries: parts.append(JSON.stringify(entry[0]) + ":" + _serialize(entry[1]))
		return "{" + ",".join(parts) + "}"
	if tag == "a":
		var values: Array[String] = []
		for child in value["v"]: values.append(_serialize(child))
		return "[" + ",".join(values) + "]"
	if tag == "s": return JSON.stringify(value["v"])
	if tag == "n": return value["v"]
	return tag
