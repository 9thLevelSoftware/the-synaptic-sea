extends SceneTree

const StoreScript := preload("res://scripts/procgen/seed_lab/procgen_promotion_store.gd")
const PREFIX := "PROCGEN PROMOTION STORE"

func _init() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/procgen/corpora/procgen_regression_v1.json"))
	if not parsed is Dictionary or not parsed.get("entries", null) is Array:
		_fail("corpus")
		return
	var candidate: Dictionary = {}
	for entry: Variant in parsed.entries:
		if entry is Dictionary and str((entry as Dictionary).get("classification", "")) == "approved_candidate":
			candidate = (entry as Dictionary).duplicate(true)
			break
	if candidate.is_empty():
		_fail("approved_fixture")
		return
	candidate.erase("approval_ref")
	var unique: String = _sha256("%d" % Time.get_ticks_usec())
	candidate.source_diagnostic.identity_hash = unique
	candidate.source_diagnostic.capture_hash = _sha256("capture:" + unique)
	candidate.candidate_id = _sha256("approved_candidate:" + unique)
	var store: RefCounted = StoreScript.new()
	if not _expect(store.validate(candidate, true), "valid_%s" % store.last_error): return
	var integer_candidate: Dictionary = _integers_from_json(candidate)
	if not _expect(store.validate(integer_candidate), "integer_contract_%s" % store.last_error): return
	var float_candidate: Dictionary = integer_candidate.duplicate(true)
	float_candidate.request.world_seed = float(float_candidate.request.world_seed)
	if not _expect(not store.validate(float_candidate) and store.last_error == "request_integer_types", "float_rejection_%s" % store.last_error): return
	var stale: Dictionary = integer_candidate.duplicate(true)
	stale.provenance.artifact_sha256 = "a".repeat(64)
	if not _expect(not store.validate(stale) and store.last_error == "provenance_stale", "stale_%s" % store.last_error): return
	var private: Dictionary = integer_candidate.duplicate(true)
	private.provenance.notes = "not allowed"
	if not _expect(not store.validate(private), "privacy"): return

	var saved: Dictionary = store.save_pending(integer_candidate)
	if not _expect(bool(saved.get("saved", false)), "save_%s" % store.last_error): return
	var path: String = str(saved.get("path", ""))
	if not _expect(path.begins_with("user://procgen/promotions/") and not path.begins_with("res://"), "path"): return
	var again: Dictionary = store.save_pending(integer_candidate)
	if not _expect(bool(again.get("saved", false)) and bool(again.get("idempotent", false)), "idempotent"): return
	if not _expect(not store.read_pending(str(integer_candidate.candidate_id)).is_empty(), "readback_%s" % store.last_error): return
	var conflicting: Dictionary = integer_candidate.duplicate(true)
	conflicting.provenance.technical_validation_codes = ["bundle_valid"]
	if not _expect(not bool(store.save_pending(conflicting).get("saved", true)) and store.last_error == "conflict", "conflict_%s" % store.last_error): return
	if not _expect(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK, "cleanup"): return
	print(PREFIX + " PASS schema=true privacy=true conflict=true readback=true")
	quit(0)

func _integers_from_json(candidate: Dictionary) -> Dictionary:
	var result: Dictionary = candidate.duplicate(true)
	result.request.world_seed = int(result.request.world_seed)
	result.request.generator_version = int(result.request.generator_version)
	result.request.site.x = int(result.request.site.x)
	result.request.site.y = int(result.request.site.y)
	result.request.site.loot_richness_bp = int(result.request.site.loot_richness_bp)
	if result.request.site.intactness_override_bp != null:
		result.request.site.intactness_override_bp = int(result.request.site.intactness_override_bp)
	result.request.presentation.seed = int(result.request.presentation.seed)
	for signal_value: Variant in result.request.player_model.signals:
		if signal_value is Dictionary: (signal_value as Dictionary).value_bp = int((signal_value as Dictionary).value_bp)
	result.provenance.generator_version = int(result.provenance.generator_version)
	return result

func _sha256(value: String) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(value.to_utf8_buffer())
	return context.finish().hex_encode()

func _expect(condition: bool, marker: String) -> bool:
	if condition: return true
	_fail(marker)
	return false

func _fail(marker: String) -> void:
	print(PREFIX + " FAIL " + marker)
	quit(1)
