extends SceneTree

## Gate 6 production save identity smoke.
##
## Boots PlayableGeneratedShip through the production bundle seam, captures a
## current-run snapshot, and proves that save/load carries the exact request
## and semantic hash rather than legacy generated-document paths.

const PlayableGeneratedShipScript := preload("res://scripts/procgen/playable_generated_ship.gd")
const RunSnapshotScript := preload("res://scripts/systems/run_snapshot.gd")
const SaveLoadServiceScript := preload("res://scripts/systems/save_load_service.gd")
const ShipGeneratorScript := preload("res://scripts/procgen/ship_generator.gd")
const TitleMainScript := preload("res://scripts/title_main.gd")

const SEED: int = 73
const SIZE: int = 1
const CONDITION: int = 2
const TIMEOUT_FRAMES: int = 900

var playable: Node = null
var frames: int = 0
var finished: bool = false


func _initialize() -> void:
	playable = PlayableGeneratedShipScript.new()
	playable.configure_procgen_start(SEED, SIZE, CONDITION)
	get_root().add_child(playable)
	process_frame.connect(_on_process_frame)


func _on_process_frame() -> void:
	if finished:
		return
	frames += 1
	if frames > TIMEOUT_FRAMES:
		_fail("production boot timed out")
		return
	if not playable.playable_started:
		return
	_run_checks()


func _run_checks() -> void:
	var snapshot: RunSnapshot = playable._build_run_snapshot()
	if snapshot == null:
		_fail("run snapshot missing")
		return
	if snapshot.slice_version != SaveLoadServiceScript.CURRENT_SLICE_VERSION:
		_fail("slice version=%s" % snapshot.slice_version)
		return
	if snapshot.procgen_request.is_empty() or snapshot.procgen_semantic_hash.is_empty():
		_fail("production request/hash missing")
		return
	if not snapshot.layout_path.is_empty() or not snapshot.kit_path.is_empty() \
			or not snapshot.gameplay_slice_path.is_empty():
		_fail("legacy paths present in production snapshot")
		return

	var encoded: Dictionary = snapshot.to_dict()
	var decoded: Variant = JSON.parse_string(JSON.stringify(encoded))
	if not decoded is Dictionary:
		_fail("snapshot JSON round-trip malformed")
		return
	var restored: RunSnapshot = RunSnapshotScript.from_dict(
		decoded,
		SaveLoadServiceScript.CURRENT_SLICE_VERSION,
		Engine.get_version_info()["string"])
	if restored == null or restored.procgen_request != snapshot.procgen_request \
			or restored.procgen_semantic_hash != snapshot.procgen_semantic_hash:
		_fail("snapshot round-trip changed request/hash")
		return
	var malformed_request: Dictionary = (decoded as Dictionary).duplicate(true)
	malformed_request["procgen_request"] = "not-a-request"
	if RunSnapshotScript.from_dict(
			malformed_request,
			SaveLoadServiceScript.CURRENT_SLICE_VERSION,
			Engine.get_version_info()["string"]) != null:
		_fail("non-dictionary procgen request accepted")
		return
	var missing_hash: Dictionary = (decoded as Dictionary).duplicate(true)
	missing_hash["procgen_semantic_hash"] = ""
	if RunSnapshotScript.from_dict(
			missing_hash,
			SaveLoadServiceScript.CURRENT_SLICE_VERSION,
			Engine.get_version_info()["string"]) != null:
		_fail("procgen request/hash half-pair accepted")
		return
	var malformed_hash: Dictionary = (decoded as Dictionary).duplicate(true)
	malformed_hash["procgen_semantic_hash"] = "G".repeat(64)
	if RunSnapshotScript.from_dict(
			malformed_hash,
			SaveLoadServiceScript.CURRENT_SLICE_VERSION,
			Engine.get_version_info()["string"]) != null:
		_fail("malformed semantic hash accepted")
		return

	var generator: RefCounted = ShipGeneratorScript.new()
	var replay: Dictionary = generator.generate_documents_from_request(
		snapshot.procgen_request, snapshot.procgen_semantic_hash)
	if replay.is_empty() or str(replay.get("semantic_hash", "")) != snapshot.procgen_semantic_hash:
		_fail("exact request replay failed: %s" % generator.last_error)
		return
	var rejected: Dictionary = generator.generate_documents_from_request(
		snapshot.procgen_request, "0".repeat(snapshot.procgen_semantic_hash.length()))
	if not rejected.is_empty() or generator.last_error != "semantic_hash_mismatch":
		_fail("wrong expected hash did not fail closed: %s" % generator.last_error)
		return
	var old_version_request: Dictionary = snapshot.procgen_request.duplicate(true)
	old_version_request["generator_version"] = int(old_version_request.generator_version) - 1
	if not generator.generate_documents_from_request(old_version_request).is_empty() \
			or generator.last_error != "new_world_required_generator_version":
		_fail("generator-version mismatch did not require new world: %s" % generator.last_error)
		return
	var old_content_request: Dictionary = snapshot.procgen_request.duplicate(true)
	old_content_request["content_manifest_hash"] = "f".repeat(64)
	if not generator.generate_documents_from_request(old_content_request).is_empty() \
			or generator.last_error != "new_world_required_content_manifest":
		_fail("content mismatch did not require new world: %s" % generator.last_error)
		return
	var title: Node = TitleMainScript.new()
	var prompt: String = title._display_boot_error(generator.last_error)
	title.free()
	if not prompt.contains("Start a new world") \
			or not prompt.contains("profile and settings are preserved"):
		_fail("new-world prompt is unclear")
		return
	var legacy_world: RefCounted = playable._build_world_snapshot()
	var legacy_home: Dictionary = legacy_world.home_ship.duplicate(true)
	legacy_home["procgen_request"] = {}
	legacy_home["procgen_semantic_hash"] = ""
	legacy_world.home_ship = legacy_home
	if playable._apply_world_snapshot(legacy_world) \
			or playable.last_failure_reason != "new_world_required_legacy_generator":
		_fail("legacy production world did not fail closed: %s" % playable.last_failure_reason)
		return
	var legacy_run: RunSnapshot = RunSnapshotScript.new()
	legacy_run.layout_path = "res://data/procgen/smoke/seed_000017/layout.json"
	legacy_run.kit_path = "res://data/kits/ship_structural_v0.json"
	legacy_run.gameplay_slice_path = \
		"res://data/procgen/smoke/seed_000017/gameplay_slice.json"
	playable.last_failure_reason = ""
	if playable._apply_run_snapshot(legacy_run) \
			or playable.last_failure_reason != "new_world_required_legacy_generator":
		_fail("legacy production run slot did not fail closed: %s" % playable.last_failure_reason)
		return

	finished = true
	print("PROCGEN GATE6 SAVE REPLAY PASS version=%s request=true hash=true paths_empty=true roundtrip=true replay=true mismatch_rejected=true new_world_required=true prompt=true clean_break=true" % snapshot.slice_version)
	_cleanup_and_quit(0)


func _fail(reason: String) -> void:
	if finished:
		return
	finished = true
	push_error("PROCGEN GATE6 SAVE REPLAY FAIL reason=%s" % reason)
	_cleanup_and_quit(1)


func _cleanup_and_quit(code: int) -> void:
	if playable != null and is_instance_valid(playable):
		playable.queue_free()
	call_deferred("_do_quit", code)


func _do_quit(code: int) -> void:
	quit(code)
