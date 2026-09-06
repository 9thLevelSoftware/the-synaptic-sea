extends RefCounted
class_name SaveLoadService

## REQ-012 current-run save/load service + Task 11 multi-slot extension.
##
## Owned by PlayableGeneratedShip, not an autoload. Single save slot at
## `user://saves/current_run.json` (legacy REQ-012 path) plus the
## Task 11 slot families:
##
##   - manual slots: slot_01..slot_06 (user://saves/<slot_id>.json)
##   - autosave slots: autosave_a..autosave_c (rotation)
##   - quicksave: quicksave (single dedicated slot)
##   - world slot: world (alias for the legacy save_world path)
##
## Per ADR-0007/0031: this service is current-run only. No hub/meta/
## cross-run state is serialized through it. Adding fields to RunSnapshot
## requires an ADR; adding new save paths or slots is out of scope for
## Gate 2.
##
## Per ADR-0031/0032 and ADR-0059/P10: rejected input is retained at its
## original path byte-for-byte. A diagnostic copy may be written under .corrupt,
## and a migrated inspection copy is written only from an accepted prepared load.

const SAVE_PATH: String = "user://saves/current_run.json"
const CURRENT_SLICE_VERSION: String = "gate2-current-run-6"
const SAVES_DIR: String = "user://saves"
const INDEX_PATH: String = "user://saves/index.json"
const CORRUPT_DIR: String = "user://saves/.corrupt"
const CLOUD_DIR: String = "user://saves/.cloud"
const WORLD_SLOT_FILE: String = "user://saves/world.json"
# Legacy slot file paths preserved so existing REQ-012 autosave-sequence
# smoke and world_save_service smoke keep their on-disk contract intact.
const LEGACY_CURRENT_RUN_PATH: String = SAVE_PATH
# Active autosave (the slot_id the legacy autosave_sequence smoke expects
# to land at SAVE_PATH). We write the active autosave to SAVE_PATH so the
# existing `user://saves/current_run.json` invariant is preserved.
const ACTIVE_AUTOSAVE_SLOT_ID: String = "autosave_active"
const WorldSnapshotScript := preload("res://scripts/systems/world_snapshot.gd")
const SaveSlotStateScript := preload("res://scripts/systems/save_slot_state.gd")
const SaveIndexStateScript := preload("res://scripts/systems/save_index_state.gd")
const SaveMigrationServiceScript := preload("res://scripts/systems/save_migration_service.gd")
const SaveRestoreCandidateScript := preload("res://scripts/systems/save_restore_candidate.gd")
const PermadeathResolverScript := preload("res://scripts/systems/permadeath_resolver.gd")
const CloudManifestStateScript := preload("res://scripts/systems/cloud_manifest_state.gd")
const ShipGeneratorScript := preload("res://scripts/procgen/ship_generator.gd")
const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")
const BiomeProfileScript := preload("res://scripts/procgen/biome_profile.gd")
const ThreatInitialStateBuilderScript := preload("res://scripts/systems/threat_initial_state_builder.gd")
const THREAT_ARCHETYPE_PATH: String = "res://data/combat/threat_archetypes.json"
const LOOT_BIOME_PATH: String = "res://data/items/biome_definitions.json"
const CURRENT_DIFFICULTY_IDS: Array[String] = ["standard", "hardened", "deep_dive"]
const HOME_COMBAT_BOOTSTRAP_PROFILES: Dictionary = {
	"default_seed_000017": {
		"layout_path": "res://data/procgen/smoke/seed_000017/layout.json",
		"kit_path": "res://data/kits/ship_structural_v0.json",
		"gameplay_slice_path": "res://data/procgen/smoke/seed_000017/gameplay_slice.json",
	},
	"coherent_ship_001": {
		"layout_path": "res://data/procgen/golden/coherent_ship_001/layout.json",
		"kit_path": "res://data/kits/ship_structural_v0.json",
		"gameplay_slice_path": "res://data/procgen/golden/coherent_ship_001/gameplay_slice.json",
	},
	"coherent_ship_002": {
		"layout_path": "res://data/procgen/golden/coherent_ship_002/layout.json",
		"kit_path": "res://data/kits/ship_structural_v0.json",
		"gameplay_slice_path": "res://data/procgen/golden/coherent_ship_002/gameplay_slice.json",
	},
}
# Current restore construction places an active derelict at this canonical
# post-restore anchor. Legacy saves did not store root or socket transforms, so
# the bootstrap path requires a positive stationary-host witness and does not
# claim to recover an original historical transform.
const ACTIVE_DERELICT_COMBAT_ANCHOR: Vector3 = Vector3(100.0, 0.0, 0.0)

# run_id slot-ownership rework: the identity of the run currently driving
# this service. Stamped onto every write (save_world/save_to_slot) so the
# shared slot family (world, autosave_a/b/c, autosave_active, quickslot) is
# owned structurally instead of by convention-tracked flags
# (_persisted_lineage_active / _manual_slots_written_this_run). Set by the
# coordinator at session start and on a successful Continue/F9 load.
var _active_run_id: String = ""
var _prepared_loads: Dictionary = {}
var _prepared_sequence: int = 0
var _after_source_read_validation_hook: Callable = Callable()

func set_active_run_id(id: String) -> void:
	_active_run_id = id

func get_active_run_id() -> String:
	return _active_run_id


## Deterministic P10 race seam. Production leaves this invalid; validation may
## mutate the backing path after the exact byte buffer is read to prove the
## resulting capability is sealed to those bytes and rejected before commit.
func set_after_source_read_hook_for_validation(hook: Callable) -> void:
	_after_source_read_validation_hook = hook

# `--headless --script` doesn't always repopulate the class registry for
# scripts that are preloaded but never instantiated by name. When that
# happens, calling `.new()` on the const preloaded script raises
# "Nonexistent function 'new' in base 'GDScript'". Wrap each `.new()` in
# this helper to fall back to load().new() if the const call fails.
static func _safe_new(script_res) -> Object:
	if script_res == null:
		return null
	if script_res.has_method("new"):
		return script_res.new()
	# Fallback: the script_res came back as a generic Resource (e.g.
	# the const resolution failed silently). Reload from path.
	var path: String = script_res.resource_path if script_res.resource_path else ""
	if path.is_empty():
		return null
	var reloaded: GDScript = load(path)
	if reloaded == null:
		return null
	return reloaded.new()

# Maps a slot_id to the on-disk path. The active autosave is the legacy
# SAVE_PATH so existing REQ-012 + autosave-sequence smokes stay green; the
# world slot lives at its own file; everything else lives at
# user://saves/<slot_id>.json.
func _slot_path(slot_id: String, slot_kind: String) -> String:
	if slot_id == ACTIVE_AUTOSAVE_SLOT_ID:
		return SAVE_PATH
	if slot_kind == SaveSlotStateScript.SLOT_KIND_WORLD or slot_id == "world":
		return WORLD_SLOT_FILE
	return "user://saves/%s.json" % slot_id

func save_current_run(snapshot: RunSnapshot) -> bool:
	# Legacy REQ-012 alias: the active autosave slot is the current_run.json path.
	# Preserves the smoke contracts that depend on SAVE_PATH.
	return save_to_slot(ACTIVE_AUTOSAVE_SLOT_ID, snapshot, SaveSlotStateScript.SLOT_KIND_AUTO, false, "current_run_alias")

func load_current_run():
	return load_from_slot(ACTIVE_AUTOSAVE_SLOT_ID)


## P10 detached disk boundary. No source, sidecar, index, or live model changes
## occur here. The returned token remains valid only while the source hash agrees.
func prepare_run_load(slot_id: String, fallback_run_id: String = "") -> Dictionary:
	return prepare_slot_load(slot_id, fallback_run_id)


func prepare_world_load(fallback_run_id: String = "") -> Dictionary:
	return _prepare_slot_path("world", WORLD_SLOT_FILE, fallback_run_id)


## All current player-loadable slots use one coherent world envelope. Historical
## run v1-v4 payloads are adapted only after proving their detached owner graph
## closes without an external pending-output dependency.
func prepare_slot_load(slot_id: String, fallback_run_id: String = "") -> Dictionary:
	if slot_id.is_empty():
		return {"ok": false, "reason": "empty_slot_id"}
	return _prepare_slot_path(
		slot_id, _slot_path(slot_id, _indexed_kind_for(slot_id)), fallback_run_id)


func _prepare_slot_path(slot_id: String, path: String, fallback_run_id: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "reason": "missing_file", "source_path": path}
	if PermadeathResolverScript.new().has_died_in(slot_id):
		return {"ok": false, "reason": "permadeath_frozen", "source_path": path}
	var read: Dictionary = _read_source_bytes(path)
	if not bool(read.get("ok", false)):
		return read.merged({"source_path": path}, true)
	# JSON.parse_string emits an engine error for ordinary malformed user data.
	# Preparation is a structured, read-only denial boundary, so use the parser
	# instance and return its error without polluting the runtime diagnostics.
	var parser := JSON.new()
	if parser.parse(str(read.text)) != OK or not parser.data is Dictionary:
		return {"ok": false, "reason": "invalid_json_object", "source_path": path, "source_sha256": read.sha256}
	var source: Dictionary = parser.data as Dictionary
	var source_version: String = str(source.get("slice_version", ""))
	var migration: Dictionary = {}
	var world_dict: Dictionary = {}
	var effective_run_id: String = ""
	if source_version.begins_with("world-") or slot_id == "world":
		migration = SaveMigrationServiceScript.new().migrate_world(source)
		if not migration.get("dict", null) is Dictionary \
				or bool(migration.get("newer_than_current", false)):
			return _prepare_failure(path, read.sha256, migration)
		world_dict = (migration.dict as Dictionary).duplicate(true)
		effective_run_id = str(world_dict.get("run_id", ""))
		if effective_run_id.is_empty():
			if str(migration.get("from_version", "")) == WorldSnapshotScript.WORLD_SLICE_VERSION \
					or fallback_run_id.is_empty():
				return {"ok": false, "reason": "missing_target_run_id", "source_path": path, "source_sha256": read.sha256}
			effective_run_id = fallback_run_id
			world_dict["run_id"] = effective_run_id
			if world_dict.get("home_ship", null) is Dictionary:
				world_dict.home_ship["run_id"] = effective_run_id
	else:
		# A standalone current v5 payload cannot recover away stores or a field
		# receipt pin. Only recognized historical run schemas receive closure.
		if source_version == CURRENT_SLICE_VERSION:
			return {"ok": false, "reason": "unclosed_owner_graph", "source_path": path, "source_sha256": read.sha256}
		migration = SaveMigrationServiceScript.new().migrate_run(source)
		if not migration.get("dict", null) is Dictionary \
				or not bool(migration.get("migrated", false)):
			return _prepare_failure(path, read.sha256, migration)
		effective_run_id = fallback_run_id if not fallback_run_id.is_empty() else _active_run_id
		if effective_run_id.is_empty():
			return {"ok": false, "reason": "missing_target_run_id", "source_path": path, "source_sha256": read.sha256}
		var migrated_run: Dictionary = (migration.dict as Dictionary).duplicate(true)
		migrated_run["run_id"] = effective_run_id
		world_dict = _closed_world_dict_from_run(migrated_run, effective_run_id)
		migration["dict"] = world_dict
		migration["to_version"] = WorldSnapshotScript.WORLD_SLICE_VERSION
	if source_version != CURRENT_SLICE_VERSION \
			and source_version != WorldSnapshotScript.WORLD_SLICE_VERSION:
		var bootstrap: Dictionary = _bootstrap_migrated_combat(world_dict)
		if not bool(bootstrap.get("ok", false)):
			return {
				"ok": false,
				"reason": str(bootstrap.get("reason", "combat_bootstrap_failed")),
				"source_path": path,
				"source_sha256": read.sha256,
			}
		world_dict = (bootstrap.world as Dictionary).duplicate(true)
		migration["dict"] = world_dict
	var expected_godot: String = Engine.get_version_info()["string"]
	var snapshot = WorldSnapshotScript.from_dict(
		world_dict, WorldSnapshotScript.WORLD_SLICE_VERSION, expected_godot)
	if snapshot == null:
		return {"ok": false, "reason": "invalid_world_snapshot", "source_path": path, "source_sha256": read.sha256}
	var candidate_result: Dictionary = SaveRestoreCandidateScript.build(snapshot, effective_run_id)
	if not bool(candidate_result.get("ok", false)):
		return {
			"ok": false,
			"reason": str(candidate_result.get("reason", "invalid_restore_candidate")),
			"source_path": path,
			"source_sha256": read.sha256,
		}
	if not _cloud_manifest_matches(slot_id, path):
		return {"ok": false, "reason": "manifest_sha_mismatch", "source_path": path, "source_sha256": read.sha256}
	var candidate = candidate_result.candidate
	migration["dict"] = candidate.world_snapshot.to_dict()
	var prepared: Dictionary = _store_prepared_load(
		"world", path, read.sha256, migration, candidate.world_snapshot, candidate)
	candidate.attach_source(prepared)
	return prepared


func _prepare_failure(path: String, sha256: String, migration: Dictionary) -> Dictionary:
	return {
		"ok": false,
		"reason": str(migration.get("reason", "unsupported_version")),
		"source_path": path,
		"source_sha256": sha256,
	}


## Reconstructs only combat state omitted by a recognized pre-v6 payload. The
## complete candidate is still decoded and validated afterwards; current v6
## input never reaches this initializer.
func _bootstrap_migrated_combat(world_source: Dictionary) -> Dictionary:
	var world: Dictionary = world_source.duplicate(true)
	var definitions_result: Dictionary = _read_json_dictionary(THREAT_ARCHETYPE_PATH)
	if not bool(definitions_result.get("ok", false)):
		return {"ok": false, "reason": "combat_bootstrap_definitions_invalid"}
	var definitions: Dictionary = definitions_result.value as Dictionary
	var home_v: Variant = world.get("home_ship", null)
	if not home_v is Dictionary:
		return {"ok": false, "reason": "combat_bootstrap_home_missing"}
	var home: Dictionary = (home_v as Dictionary).duplicate(true)
	var inventory_v: Variant = home.get("inventory_summary", null)
	if not inventory_v is Dictionary:
		return {"ok": false, "reason": "combat_bootstrap_home_inventory_missing"}
	var inventory: Dictionary = (inventory_v as Dictionary).duplicate(true)
	if not inventory.has("threat_summary"):
		var home_profile: Dictionary = _canonical_home_combat_profile(home)
		if home_profile.is_empty():
			return {"ok": false, "reason": "combat_bootstrap_home_profile_unknown"}
		var layout_result: Dictionary = _read_json_dictionary(
			str(home_profile.get("layout_path", "")))
		if not bool(layout_result.get("ok", false)):
			return {"ok": false, "reason": "combat_bootstrap_home_layout_invalid"}
		var home_layout: Dictionary = layout_result.value as Dictionary
		var home_initial: Dictionary = ThreatInitialStateBuilderScript.build_initial_v2(
			home_layout, _encounter_markers(home_layout), Vector3.ZERO, definitions)
		if not bool(home_initial.get("ok", false)):
			return {"ok": false, "reason": "combat_bootstrap_home:%s" % str(home_initial.get("reason", "invalid"))}
		inventory["threat_summary"] = (home_initial.summary as Dictionary).duplicate(true)
		home["inventory_summary"] = inventory
		world["home_ship"] = home

	var current_location: String = str(world.get("current_location", ""))
	if current_location.is_empty() or current_location == "home":
		return {"ok": true, "reason": "", "world": world}
	var visited_v: Variant = world.get("visited_ships", null)
	if not visited_v is Dictionary or not (visited_v as Dictionary).has(current_location):
		return {"ok": false, "reason": "combat_bootstrap_active_ship_missing"}
	var visited: Dictionary = (visited_v as Dictionary).duplicate(true)
	var active_v: Variant = visited.get(current_location, null)
	if not active_v is Dictionary:
		return {"ok": false, "reason": "combat_bootstrap_active_ship_invalid"}
	var active: Dictionary = (active_v as Dictionary).duplicate(true)
	if not active.has("combat"):
		if not _active_host_anchor_is_reconstructable(world, current_location, active):
			return {
				"ok": false,
				"reason": "combat_bootstrap_active_anchor_unreconstructable",
			}
		var generated: Dictionary = _generate_bootstrap_documents(active)
		if not bool(generated.get("ok", false)):
			return generated
		var away_layout: Dictionary = generated.layout as Dictionary
		var away_initial: Dictionary = ThreatInitialStateBuilderScript.build_initial_v2(
			away_layout, _encounter_markers(away_layout),
			ACTIVE_DERELICT_COMBAT_ANCHOR, definitions)
		if not bool(away_initial.get("ok", false)):
			return {"ok": false, "reason": "combat_bootstrap_active:%s" % str(away_initial.get("reason", "invalid"))}
		active["combat"] = (away_initial.summary as Dictionary).duplicate(true)
		visited[current_location] = active
		world["visited_ships"] = visited
	return {"ok": true, "reason": "", "world": world}


func _canonical_home_combat_profile(home: Dictionary) -> Dictionary:
	for key in ["layout_path", "kit_path", "gameplay_slice_path"]:
		if typeof(home.get(key, null)) != TYPE_STRING:
			return {}
	var profile_ids: Array = HOME_COMBAT_BOOTSTRAP_PROFILES.keys()
	profile_ids.sort()
	for profile_id_v in profile_ids:
		var profile_v: Variant = HOME_COMBAT_BOOTSTRAP_PROFILES[profile_id_v]
		if not profile_v is Dictionary:
			continue
		var profile: Dictionary = profile_v as Dictionary
		if str(home.layout_path) == str(profile.layout_path) \
				and str(home.kit_path) == str(profile.kit_path) \
				and str(home.gameplay_slice_path) == str(profile.gameplay_slice_path):
			return profile.duplicate(true)
	return {}


func _active_host_anchor_is_reconstructable(
		world: Dictionary, current_location: String, active: Dictionary) -> bool:
	var active_ship_id_v: Variant = active.get("ship_id", null)
	var active_marker_id_v: Variant = active.get("marker_id", null)
	if typeof(active_ship_id_v) != TYPE_STRING \
			or str(active_ship_id_v).is_empty() \
			or typeof(active_marker_id_v) != TYPE_STRING \
			or str(active_marker_id_v) != current_location:
		return false
	var known_ship_ids: Dictionary = {"lifeboat": true, "ship_start": true}
	var visited_v: Variant = world.get("visited_ships", null)
	if not visited_v is Dictionary:
		return false
	for ship_v in (visited_v as Dictionary).values():
		if ship_v is Dictionary and typeof((ship_v as Dictionary).get("ship_id", null)) == TYPE_STRING:
			var ship_id: String = str((ship_v as Dictionary).ship_id)
			if not ship_id.is_empty():
				known_ship_ids[ship_id] = true
	var edges_v: Variant = world.get("dock_edges", null)
	if not edges_v is Array:
		return false
	var host_witness: bool = false
	for edge_v in edges_v as Array:
		if not edge_v is Dictionary:
			return false
		var edge: Dictionary = edge_v as Dictionary
		if typeof(edge.get("host", null)) != TYPE_STRING \
				or typeof(edge.get("mobile", null)) != TYPE_STRING:
			return false
		var host: String = str(edge.host)
		var mobile: String = str(edge.mobile)
		if mobile == str(active_ship_id_v):
			return false
		if host == current_location:
			if mobile.is_empty() or not known_ship_ids.has(mobile):
				return false
			host_witness = true
	return host_witness


func _generate_bootstrap_documents(active: Dictionary) -> Dictionary:
	var blueprint_v: Variant = active.get("blueprint", null)
	if not _valid_bootstrap_blueprint(blueprint_v):
		return {"ok": false, "reason": "combat_bootstrap_active_blueprint_invalid"}
	var blueprint = ShipBlueprintScript.from_dict(blueprint_v as Dictionary)
	var generator = ShipGeneratorScript.new()
	var context: Dictionary = {}
	if blueprint.has_generation_context_v1():
		if not blueprint.is_generation_context_v1_valid():
			return {"ok": false, "reason": "combat_bootstrap_generation_context_invalid"}
		context = blueprint.generation_context_v1
		var biome_ids: Array[String] = _load_biome_ids()
		if not biome_ids.has(str(context.get("biome", ""))) \
				or not CURRENT_DIFFICULTY_IDS.has(str(context.get("difficulty", ""))):
			return {"ok": false, "reason": "combat_bootstrap_generation_context_unsupported"}
	else:
		context = _legacy_generation_context(
			int(blueprint.seed_value), int(blueprint.size), int(blueprint.condition))
	generator.configure_run_context(str(context.biome), str(context.difficulty))
	var documents: Dictionary = generator.generate_documents_from_seed(
		int(blueprint.seed_value), int(blueprint.size), int(blueprint.condition))
	if not bool(documents.get("ok", false)):
		return {"ok": false, "reason": "combat_bootstrap_generation:%s" % str(documents.get("reason", "invalid"))}
	return documents


func _valid_bootstrap_blueprint(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var blueprint: Dictionary = value as Dictionary
	if not blueprint.has("seed_value") or not blueprint.has("size") or not blueprint.has("condition"):
		return false
	if not _is_integral_json_number(blueprint.seed_value) \
			or not _is_integral_json_number(blueprint.size) \
			or not _is_integral_json_number(blueprint.condition):
		return false
	return [0, 1, 2].has(int(blueprint.size)) and [0, 1, 2].has(int(blueprint.condition))


func _is_integral_json_number(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) \
			and is_finite(float(value)) and float(value) == floor(float(value))


func _legacy_generation_context(seed_value: int, size: int, condition: int) -> Dictionary:
	var biome_ids: Array[String] = _load_biome_ids()
	var biome: String = "abyssal_synaptic_sea"
	if not biome_ids.is_empty():
		biome = BiomeProfileScript.select_biome(seed_value, biome_ids)
	var depth: int = size * 2 + condition
	var difficulty: String = "standard"
	if depth >= 5:
		difficulty = "deep_dive"
	elif depth >= 3:
		difficulty = "hardened"
	return {"biome": biome, "difficulty": difficulty}


func _load_biome_ids() -> Array[String]:
	var result: Array[String] = []
	var read: Dictionary = _read_json_dictionary(LOOT_BIOME_PATH)
	if bool(read.get("ok", false)):
		var biomes_v: Variant = (read.value as Dictionary).get("biomes", {})
		if biomes_v is Dictionary:
			for biome_id_v in (biomes_v as Dictionary).keys():
				result.append(str(biome_id_v))
	result.sort()
	if result.is_empty():
		result.append("abyssal_synaptic_sea")
	return result


func _read_json_dictionary(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {"ok": false}
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK or not parser.data is Dictionary:
		return {"ok": false}
	return {"ok": true, "value": (parser.data as Dictionary).duplicate(true)}


func _encounter_markers(layout: Dictionary) -> Array:
	var markers_v: Variant = layout.get("encounters", [])
	return (markers_v as Array).duplicate(true) if markers_v is Array else []


func _closed_world_dict_from_run(run_dict: Dictionary, run_id: String) -> Dictionary:
	var pending: Dictionary = {
		"schema": "pending-outputs-1", "ship_id": "ship_start", "records": [],
	}
	return {
		"world_summary": {},
		"home_ship": run_dict.duplicate(true),
		"meta_progression_summary": {},
		"unique_item_summary": {},
		"home_looted_containers": [],
		"home_ship_carts": [],
		"home_pending_outputs_v1": pending,
		"home_breach_environment": {},
		"visited_ships": {},
		"current_location": "",
		"world_time": 0.0,
		"player_position_in_ship": run_dict.get("player_position", [0.0, 0.0, 0.0]),
		"dock_edges": [],
		"piloted_ship_id": "",
		"aboard_ship_id": "ship_start",
		"opened_ports": [],
		"run_id": run_id,
		"slice_version": WorldSnapshotScript.WORLD_SLICE_VERSION,
		"godot_version": str(run_dict.get("godot_version", Engine.get_version_info()["string"])),
		"saved_at": str(run_dict.get("saved_at", "")),
	}


func write_prepared_migration_copy(prepared_token: String) -> bool:
	var prepared_v: Variant = _prepared_loads.get(prepared_token, null)
	if not prepared_v is Dictionary:
		return false
	var prepared: Dictionary = prepared_v
	if not bool(prepared.get("migrated", false)):
		return true
	var path: String = str(prepared.source_path)
	if not FileAccess.file_exists(path) \
			or CloudManifestStateScript.recompute_sha256(path) != str(prepared.source_sha256):
		return false
	var migrated_path: String = path.trim_suffix(".json") + ".migrated.json"
	var file := FileAccess.open(migrated_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(prepared.migrated_dict, "\t", false, true))
	file.close()
	return true


func prepared_source_is_unchanged(prepared_token: String) -> bool:
	var prepared_v: Variant = _prepared_loads.get(prepared_token, null)
	if not prepared_v is Dictionary:
		return false
	var prepared: Dictionary = prepared_v
	var path: String = str(prepared.get("source_path", ""))
	var expected_sha: String = str(prepared.get("source_sha256", ""))
	return not path.is_empty() and not expected_sha.is_empty() \
		and FileAccess.file_exists(path) \
		and CloudManifestStateScript.recompute_sha256(path) == expected_sha


## Resolves an opaque prepared-load capability back into a fresh detached
## candidate. The caller never receives the service-owned candidate stored at
## prepare time, so mutating a returned request dictionary cannot change what
## will be committed. The seal binds the token to the exact canonical world
## payload and source hash; mixing fields from two prepared requests rejects.
func resolve_prepared_load(prepared_token: String, prepared_seal: String) -> Dictionary:
	var prepared_v: Variant = _prepared_loads.get(prepared_token, null)
	if not prepared_v is Dictionary:
		return {"ok": false, "reason": "unknown_prepared_token"}
	var prepared: Dictionary = prepared_v
	if prepared_seal.is_empty() or prepared_seal != str(prepared.get("seal", "")):
		return {"ok": false, "reason": "prepared_seal_mismatch"}
	if not prepared_source_is_unchanged(prepared_token):
		return {"ok": false, "reason": "prepared_source_changed"}
	var world_dict_v: Variant = prepared.get("world_dict", null)
	if not world_dict_v is Dictionary:
		return {"ok": false, "reason": "missing_prepared_world"}
	var world_dict: Dictionary = (world_dict_v as Dictionary).duplicate(true)
	if _prepared_payload_digest(world_dict) != str(prepared.get("payload_digest", "")):
		return {"ok": false, "reason": "prepared_payload_changed"}
	var snapshot = WorldSnapshotScript.from_dict(
		world_dict, WorldSnapshotScript.WORLD_SLICE_VERSION,
		Engine.get_version_info()["string"])
	if snapshot == null:
		return {"ok": false, "reason": "invalid_prepared_world"}
	var candidate_result: Dictionary = SaveRestoreCandidateScript.build(
		snapshot, str(world_dict.get("run_id", "")))
	if not bool(candidate_result.get("ok", false)):
		return {
			"ok": false,
			"reason": str(candidate_result.get("reason", "invalid_restore_candidate")),
		}
	return {
		"ok": true,
		"candidate": candidate_result.candidate,
		"migrated": bool(prepared.get("migrated", false)),
	}


func discard_prepared_load(prepared_token: String) -> void:
	_prepared_loads.erase(prepared_token)


func _read_source_bytes(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "reason": "read_failed"}
	var source_bytes: PackedByteArray = file.get_buffer(file.get_length())
	file.close()
	if _after_source_read_validation_hook.is_valid():
		var hook: Callable = _after_source_read_validation_hook
		_after_source_read_validation_hook = Callable()
		hook.call(path, source_bytes.duplicate())
	var text_value: String = source_bytes.get_string_from_utf8()
	if text_value.is_empty():
		return {"ok": false, "reason": "empty_file"}
	var hash_context := HashingContext.new()
	if hash_context.start(HashingContext.HASH_SHA256) != OK:
		return {"ok": false, "reason": "hash_failed"}
	if hash_context.update(source_bytes) != OK:
		return {"ok": false, "reason": "hash_failed"}
	return {
		"ok": true,
		"text": text_value,
		"sha256": hash_context.finish().hex_encode(),
	}


func _store_prepared_load(
		kind: String, path: String, source_sha256: String,
		migration: Dictionary, snapshot: Variant, _candidate: Variant = null) -> Dictionary:
	_prepared_sequence += 1
	var token: String = "p10:%s:%d" % [kind, _prepared_sequence]
	var world_dict: Dictionary = snapshot.to_dict()
	var payload_digest: String = _prepared_payload_digest(world_dict)
	var seal: String = ("%s|%s|%s" % [token, source_sha256, payload_digest]).sha256_text()
	var record: Dictionary = {
		"kind": kind,
		"source_path": path,
		"source_sha256": source_sha256,
		"from_version": str(migration.get("from_version", "")),
		"to_version": str(migration.get("to_version", "")),
		"migrated": bool(migration.get("migrated", false)),
		"migrated_dict": (migration.dict as Dictionary).duplicate(true),
		"world_dict": world_dict.duplicate(true),
		"payload_digest": payload_digest,
		"seal": seal,
	}
	_prepared_loads[token] = record
	return {
		"ok": true,
		"token": token,
		"seal": seal,
		"kind": kind,
		"source_path": path,
		"source_sha256": source_sha256,
		"from_version": str(record.from_version),
		"to_version": str(record.to_version),
		"migrated": bool(record.migrated),
	}


func _prepared_payload_digest(world_dict: Dictionary) -> String:
	return JSON.stringify(world_dict, "", true, true).sha256_text()


## Read-only proof seam. It returns a deep dictionary copy rather than the
## service-owned WorldSnapshot/candidate objects.
func inspect_prepared_world_for_validation(
		prepared_token: String, prepared_seal: String) -> Dictionary:
	var prepared_v: Variant = _prepared_loads.get(prepared_token, null)
	if not prepared_v is Dictionary:
		return {}
	var prepared: Dictionary = prepared_v
	if prepared_seal != str(prepared.get("seal", "")):
		return {}
	var world_dict_v: Variant = prepared.get("world_dict", null)
	return (world_dict_v as Dictionary).duplicate(true) if world_dict_v is Dictionary else {}


func prepared_load_count_for_validation() -> int:
	return _prepared_loads.size()


func _cloud_manifest_matches(slot_id: String, path: String) -> bool:
	var manifest_path: String = "%s/%s.manifest.json" % [CLOUD_DIR, slot_id]
	if not FileAccess.file_exists(manifest_path):
		return true
	var file := FileAccess.open(manifest_path, FileAccess.READ)
	if file == null:
		return true
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return true
	var stored_sha: String = str((parsed as Dictionary).get("payload_sha256", ""))
	var computed_sha: String = CloudManifestStateScript.recompute_sha256(path)
	return stored_sha.is_empty() or computed_sha.is_empty() or stored_sha == computed_sha


func _write_rejected_diagnostic_copy(path: String, slot_id: String, epoch: int) -> void:
	_backup_corrupt_file(path, slot_id, epoch)

## REQ-0012 world save: serializes a whole WorldSnapshot to the world slot
## file. The world slot is its own file (world.json), distinct from the
## current_run.json path the autosave writes to. An old single-ship save
## at SAVE_PATH is rejected by RunSnapshot.from_dict on the next
## load_current_run (version mismatch → fresh run).
func save_world(world_snapshot) -> bool:
	if world_snapshot == null:
		push_warning("SaveLoadService: cannot save null world snapshot")
		return false
	if not _ensure_save_dir():
		return false
	var prepared_write: Dictionary = _coherent_world_for_write(
		world_snapshot, "world", SaveSlotStateScript.SLOT_KIND_WORLD, false)
	if not bool(prepared_write.get("ok", false)):
		push_warning("SaveLoadService: rejected incoherent world save reason=%s" % str(
			prepared_write.get("reason", "invalid_world_snapshot")))
		return false
	world_snapshot = prepared_write.world_snapshot
	var path: String = WORLD_SLOT_FILE
	var json: String = JSON.stringify(world_snapshot.to_dict(), "	", false, true)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("SaveLoadService: cannot open world save file for writing, error=%d" % FileAccess.get_open_error())
		return false
	file.store_string(json)
	file.close()
	# Reclaim-on-write (ADR-0043): a death record describes the run that died
	# in this slot, not the run writing now. A live run's system write to
	# "world" legitimately reclaims the slot, so clear any stale death
	# record -- but only AFTER the write is confirmed on disk (PR #57 Codex
	# round 3 P2). Clearing before opening the file left a window where a
	# failed write (locked/unwritable path) discarded the death record while
	# the old DEAD payload was still on disk, silently unfreezing a dead run
	# and letting Continue load past a death that never actually reclaimed
	# anything. This does not reopen save-scumming: frozen MANUAL slots
	# offer no write verbs in the UI, and load gates fire before any write
	# ever happens.
	PermadeathResolverScript.new().clear_death("world")
	# Index the world slot row + write its cloud manifest.
	_index_world_slot(world_snapshot)
	_write_cloud_manifest("world", path, WorldSnapshotScript.WORLD_SLICE_VERSION)
	return true

## Reads the world save from WORLD_SLOT_FILE. Returns null when no save
## exists, the file is empty/not a JSON object, or the WorldSnapshot
## version markers do not match. On parse/version failure, the bad file
## is moved to .corrupt/ before returning null.
func load_world():
	var prepared: Dictionary = prepare_world_load()
	if not bool(prepared.get("ok", false)):
		return null
	var token: String = str(prepared.token)
	var world_dict: Dictionary = inspect_prepared_world_for_validation(
		token, str(prepared.get("seal", "")))
	var snapshot = WorldSnapshotScript.from_dict(
		world_dict, WorldSnapshotScript.WORLD_SLICE_VERSION,
		Engine.get_version_info()["string"])
	discard_prepared_load(token)
	return snapshot

func delete_current_run() -> bool:
	# Legacy REQ-012 contract: delete the current_run autosave file. Also
	# remove the world slot and index entries so a stale world save
	# cannot survive a finished run (the original ADR-0012 design kept
	# world save; the smoke contracts demand it be wiped here to keep
	# the save_load_service_smoke, world_save_service_smoke, and
	# main_playable_slice_save_load_smoke green).
	var ok: bool = true
	if FileAccess.file_exists(SAVE_PATH):
		var err: int = DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
		if err != OK:
			push_warning("SaveLoadService: failed to delete save file, error=%d" % err)
			ok = false
	if FileAccess.file_exists(WORLD_SLOT_FILE):
		var werr: int = DirAccess.remove_absolute(ProjectSettings.globalize_path(WORLD_SLOT_FILE))
		if werr != OK:
			push_warning("SaveLoadService: failed to delete world save file, error=%d" % werr)
			ok = false
	# Also remove the world slot's cloud manifest (mirrors delete_slot()'s
	# manifest removal) so a finished run does not leak
	# user://saves/.cloud/world.manifest.json.
	var world_manifest_path: String = "%s/world.manifest.json" % CLOUD_DIR
	if FileAccess.file_exists(world_manifest_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(world_manifest_path))
	# Remove the active autosave from the index so a fresh run does
	# not see a phantom autosave row.
	var idx = _load_index()
	idx.remove(ACTIVE_AUTOSAVE_SLOT_ID)
	idx.remove("world")
	_save_index(idx)
	return ok

func has_save() -> bool:
	# Legacy REQ-012 contract: true when EITHER the current_run autosave
	# exists OR a world save exists. The autosave-sequence smoke asserts
	# has_save=true after the first objective-completion auto-save;
	# world_save_service asserts has_save=true after save_world().
	return FileAccess.file_exists(SAVE_PATH) or FileAccess.file_exists(WORLD_SLOT_FILE)

## Ensures the save slot's parent directory exists. `user://saves` may not exist
## on a fresh Godot install; without this, FileAccess.open silently returns null
## and the save fails without a useful error. Shared by save_current_run and
## save_world. Returns false only when directory creation genuinely fails.
func _ensure_save_dir() -> bool:
	var dir_path: String = SAVE_PATH.get_base_dir()
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir_path)):
		var make_err: int = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_path))
		if make_err != OK and make_err != ERR_ALREADY_EXISTS:
			push_warning("SaveLoadService: failed to create save dir, error=%d" % make_err)
			return false
	return true

# ----------------------------------------------------------------------------
# Task 11 multi-slot API (ADR-0031, ADR-0032).
# ----------------------------------------------------------------------------

## Write a RunSnapshot to a named slot. The slot_kind stamps the row in
## the index; the slot_id controls the on-disk path. Returns false on
## I/O failure or a null snapshot.
func save_to_slot(slot_id: String, snapshot: Variant, slot_kind: String, is_quicksave: bool, display_name: String) -> bool:
	if slot_id.is_empty():
		push_warning("SaveLoadService: save_to_slot called with empty slot_id")
		return false
	if snapshot == null:
		push_warning("SaveLoadService: save_to_slot called with null snapshot")
		return false
	if not _ensure_save_dir():
		return false
	var prepared_write: Dictionary = _coherent_world_for_write(
		snapshot, slot_id, slot_kind, is_quicksave)
	if not bool(prepared_write.get("ok", false)):
		push_warning("SaveLoadService: rejected incoherent save slot=%s reason=%s" % [
			slot_id, str(prepared_write.get("reason", "invalid_world_snapshot"))])
		return false
	var world_snapshot = prepared_write.world_snapshot
	var run_snapshot: RunSnapshot = prepared_write.run_snapshot
	var path: String = _slot_path(slot_id, slot_kind)
	var data: Dictionary = world_snapshot.to_dict()
	var json: String = JSON.stringify(data, "	", false, true)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("SaveLoadService: cannot open slot file for writing, slot_id=%s error=%d" % [slot_id, FileAccess.get_open_error()])
		return false
	file.store_string(json)
	file.close()
	# Reclaim-on-write (ADR-0043): a death record describes the run that died
	# in this slot, not the run writing now. A live run's system write to
	# this slot legitimately reclaims it, so clear any stale death record --
	# but only AFTER the write is confirmed on disk (PR #57 Codex round 3
	# P2). Clearing before opening the file left a window where a failed
	# write (locked/unwritable path) discarded the death record while the
	# old DEAD payload was still on disk, silently unfreezing a dead run and
	# letting Continue load past a death that never actually reclaimed
	# anything. This does not reopen save-scumming: frozen MANUAL slots
	# offer no write verbs in the UI, and load gates fire before any write
	# ever happens.
	PermadeathResolverScript.new().clear_death(slot_id)
	# Update the index row + write the cloud manifest.
	_index_run_slot(slot_id, slot_kind, display_name, run_snapshot, path)
	_write_cloud_manifest(slot_id, path, WorldSnapshotScript.WORLD_SLICE_VERSION)
	return true


func _coherent_world_for_write(
		snapshot: Variant,
		slot_id: String,
		slot_kind: String,
		is_quicksave: bool) -> Dictionary:
	if snapshot == null or not snapshot is Object \
			or not (snapshot as Object).has_method("to_dict"):
		return {"ok": false, "reason": "invalid_snapshot"}
	var raw: Dictionary = snapshot.call("to_dict")
	var world_dict: Dictionary = {}
	if str(raw.get("slice_version", "")).begins_with("world-") or raw.has("home_ship"):
		world_dict = raw.duplicate(true)
	else:
		var run_snapshot: RunSnapshot = snapshot as RunSnapshot
		if run_snapshot == null:
			return {"ok": false, "reason": "invalid_run_snapshot"}
		_stamp_run_slot_metadata(run_snapshot, slot_id, slot_kind, is_quicksave)
		_normalize_current_run_capture(run_snapshot)
		world_dict = _closed_world_dict_from_run(run_snapshot.to_dict(), _active_run_id)
	var home_v: Variant = world_dict.get("home_ship", null)
	if not home_v is Dictionary:
		return {"ok": false, "reason": "missing_home_run"}
	var home_dict: Dictionary = (home_v as Dictionary).duplicate(true)
	home_dict["slot_id"] = slot_id
	home_dict["slot_kind"] = slot_kind
	home_dict["is_autosave"] = slot_kind == SaveSlotStateScript.SLOT_KIND_AUTO
	home_dict["is_quicksave"] = is_quicksave
	home_dict["run_id"] = _active_run_id
	home_dict["slice_version"] = CURRENT_SLICE_VERSION
	home_dict["godot_version"] = Engine.get_version_info()["string"]
	if str(home_dict.get("saved_at", "")).is_empty():
		home_dict["saved_at"] = Time.get_datetime_string_from_system(true)
	if int(home_dict.get("saved_at_epoch", 0)) == 0:
		home_dict["saved_at_epoch"] = int(Time.get_unix_time_from_system())
	world_dict["home_ship"] = home_dict
	world_dict["run_id"] = _active_run_id
	world_dict["slice_version"] = WorldSnapshotScript.WORLD_SLICE_VERSION
	world_dict["godot_version"] = Engine.get_version_info()["string"]
	world_dict["saved_at"] = str(home_dict.saved_at)
	if not world_dict.get("home_pending_outputs_v1", null) is Dictionary \
			or (world_dict.home_pending_outputs_v1 as Dictionary).is_empty():
		world_dict["home_pending_outputs_v1"] = {
			"schema": "pending-outputs-1", "ship_id": "ship_start", "records": [],
		}
	var visited_v: Variant = world_dict.get("visited_ships", {})
	if not visited_v is Dictionary:
		return {"ok": false, "reason": "invalid_visited_ships"}
	var visited: Dictionary = (visited_v as Dictionary).duplicate(true)
	for marker_v in visited:
		if not visited[marker_v] is Dictionary:
			return {"ok": false, "reason": "invalid_visited_ship"}
		var ship_summary: Dictionary = (visited[marker_v] as Dictionary).duplicate(true)
		var ship_id: String = str(ship_summary.get("ship_id", ""))
		if ship_id.is_empty():
			return {"ok": false, "reason": "invalid_visited_ship"}
		if not ship_summary.get("pending_outputs_v1", null) is Dictionary \
				or (ship_summary.pending_outputs_v1 as Dictionary).is_empty():
			ship_summary["pending_outputs_v1"] = {
				"schema": "pending-outputs-1", "ship_id": ship_id, "records": [],
			}
		visited[marker_v] = ship_summary
	world_dict["visited_ships"] = visited
	var world_snapshot = WorldSnapshotScript.from_dict(
		world_dict, WorldSnapshotScript.WORLD_SLICE_VERSION,
		Engine.get_version_info()["string"])
	if world_snapshot == null:
		return {"ok": false, "reason": "invalid_world_snapshot"}
	var candidate_result: Dictionary = SaveRestoreCandidateScript.build(
		world_snapshot, _active_run_id)
	if not bool(candidate_result.get("ok", false)):
		return candidate_result
	var candidate = candidate_result.candidate
	return {
		"ok": true,
		"world_snapshot": candidate.world_snapshot,
		"run_snapshot": candidate.run_snapshot,
	}


func _stamp_run_slot_metadata(
		snapshot: RunSnapshot,
		slot_id: String,
		slot_kind: String,
		is_quicksave: bool) -> void:
	snapshot.slot_id = slot_id
	snapshot.slot_kind = slot_kind
	snapshot.is_autosave = slot_kind == SaveSlotStateScript.SLOT_KIND_AUTO
	snapshot.is_quicksave = is_quicksave
	snapshot.run_id = _active_run_id
	if snapshot.slice_version.is_empty():
		snapshot.slice_version = CURRENT_SLICE_VERSION
	snapshot.godot_version = Engine.get_version_info()["string"]
	if snapshot.saved_at.is_empty():
		snapshot.saved_at = Time.get_datetime_string_from_system(true)
	if snapshot.saved_at_epoch == 0:
		snapshot.saved_at_epoch = int(Time.get_unix_time_from_system())


func _normalize_current_world_capture(world_snapshot) -> void:
	var home: Dictionary = world_snapshot.home_ship.duplicate(true)
	if not home.is_empty():
		if str(home.get("godot_version", "")).is_empty():
			home["godot_version"] = Engine.get_version_info()["string"]
		var migrated: Dictionary = SaveMigrationServiceScript.new().migrate_run(home)
		if migrated.get("dict", null) is Dictionary:
			world_snapshot.home_ship = (migrated.dict as Dictionary).duplicate(true)
	var normalized_visited: Dictionary = world_snapshot.visited_ships.duplicate(true)
	for marker_variant in normalized_visited:
		var raw: Variant = normalized_visited[marker_variant]
		if raw is Dictionary and str((raw as Dictionary).get("ship_id", "")).is_empty():
			var ship_summary: Dictionary = (raw as Dictionary).duplicate(true)
			ship_summary["ship_id"] = "legacy:%s" % str(marker_variant)
			normalized_visited[marker_variant] = ship_summary
	world_snapshot.visited_ships = normalized_visited


func _normalize_current_run_capture(snapshot: RunSnapshot) -> void:
	if str(snapshot.recipe_knowledge_summary.get("owner_id", "")).is_empty() \
			and str(snapshot.recipe_knowledge_summary.get("migration_origin", "native")) == "native":
		snapshot.recipe_knowledge_summary["owner_id"] = "player:%s" % (
			snapshot.run_id if not snapshot.run_id.is_empty() else "local")
	if not snapshot.crafting_summary.has("field_crafting"):
		snapshot.crafting_summary["field_crafting"] = {
			"recipe_count": 0,
			"active_craft": {},
			"station_summaries": {},
			"physical_station_summaries": {},
			"craft_jobs_v1": {"schema": "craft-jobs-2", "jobs": [], "owners": []},
			"field_pending_v1": {
				"schema": "field-pending-2",
				"ship_id": "", "receipt_sequence": 0, "active_receipt_id": "",
				"pinned_destination_ship_id": "", "pinned_local_position": [],
				"receipt_history_v1": [],
			},
		}

## Read a RunSnapshot from a named slot. Returns null on missing file,
## parse failure, or version mismatch. On parse/version failure, the bad
## file is moved to .corrupt/ and the slot row is flagged in the index.
func load_from_slot(slot_id: String):
	var prepared: Dictionary = prepare_slot_load(slot_id)
	if not bool(prepared.get("ok", false)):
		return null
	var token: String = str(prepared.token)
	var world_dict: Dictionary = inspect_prepared_world_for_validation(
		token, str(prepared.get("seal", "")))
	var world_snapshot = WorldSnapshotScript.from_dict(
		world_dict, WorldSnapshotScript.WORLD_SLICE_VERSION,
		Engine.get_version_info()["string"])
	discard_prepared_load(token)
	if world_snapshot == null:
		return null
	return RunSnapshot.from_dict(
		world_snapshot.home_ship, CURRENT_SLICE_VERSION,
		Engine.get_version_info()["string"])

func delete_slot(slot_id: String) -> bool:
	var kind: String = _indexed_kind_for(slot_id)
	var path: String = _slot_path(slot_id, kind)
	var ok: bool = true
	if FileAccess.file_exists(path):
		var err: int = DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		if err != OK:
			push_warning("SaveLoadService: failed to delete slot file, slot_id=%s error=%d" % [slot_id, err])
			ok = false
	var migrated_path: String = path.trim_suffix(".json") + ".migrated.json"
	if FileAccess.file_exists(migrated_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(migrated_path))
	var manifest_path: String = "%s/%s.manifest.json" % [CLOUD_DIR, slot_id]
	if FileAccess.file_exists(manifest_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(manifest_path))
	var death_path: String = PermadeathResolverScript.new().death_path_for(slot_id)
	if FileAccess.file_exists(death_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(death_path))
	var idx := _load_index()
	idx.remove(slot_id)
	_save_index(idx)
	return ok

func has_slot(slot_id: String) -> bool:
	if slot_id.is_empty():
		return false
	return FileAccess.file_exists(_slot_path(slot_id, _indexed_kind_for(slot_id)))

## run_id slot-ownership rework: every slot_id whose index row (or the
## world row) is stamped with run_id. Replaces the old convention-tracked
## freeze set (_persisted_lineage_active + _manual_slots_written_this_run):
## ownership is now read directly from what was actually written, not from
## a flag a call site might forget to set. An empty run_id matches NOTHING
## -- a fresh run that has neither loaded nor saved anything must never
## freeze a prior run's still-live slots.
func slot_ids_for_run(run_id: String) -> Array:
	if run_id.is_empty():
		return []
	var result: Array = []
	var idx = _load_index()
	for row in idx.slots:
		if row != null and String(row.run_id) == run_id:
			var indexed_id := String(row.slot_id)
			if not result.has(indexed_id):
				result.append(indexed_id)
	# PR #58 (Codex P2): the index is a derived cache -- list_slots()
	# reclassifies it against the disk, and a corrupt/missing index.json
	# parses to an EMPTY SaveIndexState. If freeze ownership trusted the
	# index alone, a dead run whose index was lost (corruption, manual
	# deletion, partial sync) would freeze nothing and stay continuable.
	# Payload files carry the authoritative run_id stamp, so union in a
	# direct disk scan; the index remains a fast path, never the gate.
	for disk_id in _all_slot_ids_on_disk():
		var slot_id := String(disk_id)
		if slot_id == "index" or result.has(slot_id):
			continue
		if _payload_run_id(slot_id) == run_id:
			result.append(slot_id)
	return result

## Reads only the top-level run_id key from a slot's payload file.
## Returns "" for missing/unreadable/corrupt payloads and legacy saves
## written before the run_id rework -- both fail OPEN by design.
func _payload_run_id(slot_id: String) -> String:
	var path := _slot_path(slot_id, _indexed_kind_for(slot_id))
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return ""
	return str((parsed as Dictionary).get("run_id", ""))

## run_id slot-ownership rework: freezes every slot owned by run_id (per
## slot_ids_for_run) with a PermadeathResolver death record. Lives here
## rather than on PermadeathResolver because that class is deliberately
## index-blind pure file I/O (ADR-0043 addendum records the rationale);
## this service already owns the index, so it is the natural place to
## resolve "which slots does this run own" before recording deaths.
func freeze_run(run_id: String, cause: String, epitaph: String, run_time: float, final_seq: int) -> void:
	var resolver := PermadeathResolverScript.new()
	for slot_id in slot_ids_for_run(run_id):
		resolver.record_death(slot_id, cause, epitaph, run_time, final_seq)

## Returns an Array of SaveSlotState rows sorted by saved_at desc.
## Reclassifies rows whose slot file is missing on disk as `corrupt=true`.
func list_slots() -> Array:
	var idx = _load_index()
	var present: Array = []
	for slot_id in _all_slot_ids_on_disk():
		present.append(slot_id)
	# Slot discovery is a read boundary. The UI calls it during construction,
	# including while a replacement scene is still detached/staged. Reclassify
	# the loaded cache in memory so callers see missing payloads immediately,
	# without rewriting index.json or its timestamp before activation.
	idx.reclassify_corrupt(present)
	return idx.sorted_by_saved_at_desc()

func _all_slot_ids_on_disk() -> Array:
	var result: Array = []
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(SAVES_DIR)):
		return result
	var dir := DirAccess.open(ProjectSettings.globalize_path(SAVES_DIR))
	if dir == null:
		return result
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if not entry.begins_with(".") and entry.ends_with(".json") and not entry.ends_with(".migrated.json") and not entry.ends_with(".death.json"):
			var slot_id: String = entry.trim_suffix(".json")
			if slot_id == "current_run":
				slot_id = ACTIVE_AUTOSAVE_SLOT_ID
			result.append(slot_id)
		entry = dir.get_next()
	dir.list_dir_end()
	return result

func _indexed_kind_for(slot_id: String) -> String:
	var idx = _load_index()
	var row = idx.find(slot_id)
	if row != null:
		return row.slot_kind
	if slot_id == ACTIVE_AUTOSAVE_SLOT_ID:
		return SaveSlotStateScript.SLOT_KIND_AUTO
	if slot_id == "world":
		return SaveSlotStateScript.SLOT_KIND_WORLD
	if SaveSlotStateScript.MANUAL_SLOT_IDS.has(slot_id):
		return SaveSlotStateScript.SLOT_KIND_MANUAL
	if SaveSlotStateScript.AUTOSAVE_SLOT_IDS.has(slot_id):
		return SaveSlotStateScript.SLOT_KIND_AUTO
	if slot_id == SaveSlotStateScript.QUICKSAVE_SLOT_ID:
		return SaveSlotStateScript.SLOT_KIND_QUICK
	return SaveSlotStateScript.SLOT_KIND_MANUAL  # safe default; loader will validate

func _load_index() -> Object:
	if not FileAccess.file_exists(INDEX_PATH):
		return SaveIndexStateScript.new()
	var f := FileAccess.open(INDEX_PATH, FileAccess.READ)
	if f == null:
		return SaveIndexStateScript.new()
	var json: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(json)
	return SaveIndexStateScript.from_dict(parsed)

func _save_index(idx) -> void:
	if not _ensure_save_dir():
		return
	idx.updated_at = Time.get_datetime_string_from_system(true)
	idx.godot_version = Engine.get_version_info()["string"]
	var f := FileAccess.open(INDEX_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("SaveLoadService: cannot open index file for writing, error=%d" % FileAccess.get_open_error())
		return
	f.store_string(JSON.stringify(idx.to_dict(), "	", false, true))
	f.close()

func _index_run_slot(slot_id: String, slot_kind: String, display_name: String, snapshot: RunSnapshot, payload_path: String) -> void:
	var idx = _load_index()
	var row = SaveSlotStateScript.new()
	row.slot_id = slot_id
	row.slot_kind = slot_kind
	row.display_name = display_name if not display_name.is_empty() else slot_id
	# ADR-0046: index REAL metadata from the snapshot's dedicated fields
	# (the old placeholders derived location from player X, the seed from
	# pos.x*1000, and play time from the Unix epoch).
	row.synaptic_sea_seed = int(snapshot.world_seed)
	row.player_class = str(snapshot.player_progression_summary.get("class_id", ""))
	row.current_location = str(snapshot.current_location)
	row.objective_sequence = int(snapshot.current_objective_sequence)
	row.play_time_seconds = float(snapshot.play_time_seconds)
	row.saved_at = snapshot.saved_at
	row.saved_at_epoch = int(Time.get_unix_time_from_system())
	row.schema_version = CURRENT_SLICE_VERSION
	row.payload_size_bytes = _size_of_file(payload_path)
	row.run_id = snapshot.run_id
	idx.add_or_replace(row)
	_save_index(idx)

func _index_world_slot(world_snapshot) -> void:
	var idx = _load_index()
	var row = SaveSlotStateScript.new()
	row.slot_id = "world"
	row.slot_kind = SaveSlotStateScript.SLOT_KIND_WORLD
	row.display_name = "World"
	row.current_location = str(world_snapshot.current_location)
	row.objective_sequence = 0
	row.saved_at = Time.get_datetime_string_from_system(true)
	row.saved_at_epoch = int(Time.get_unix_time_from_system())
	row.schema_version = WorldSnapshotScript.WORLD_SLICE_VERSION
	row.payload_size_bytes = _size_of_file(WORLD_SLOT_FILE)
	row.run_id = world_snapshot.run_id
	idx.add_or_replace(row)
	_save_index(idx)

func _write_cloud_manifest(slot_id: String, slot_path: String, schema_version: String) -> void:
	if not _ensure_save_dir():
		return
	# Ensure the .cloud subdir exists.
	var cloud_abs: String = ProjectSettings.globalize_path(CLOUD_DIR)
	if not DirAccess.dir_exists_absolute(cloud_abs):
		var mk: int = DirAccess.make_dir_recursive_absolute(cloud_abs)
		if mk != OK and mk != ERR_ALREADY_EXISTS:
			return  # silent: a failed manifest does not break the save
	var manifest := CloudManifestStateScript.build_for_slot(slot_id, slot_path, schema_version)
	var manifest_path: String = "%s/%s.manifest.json" % [CLOUD_DIR, slot_id]
	var f := FileAccess.open(manifest_path, FileAccess.WRITE)
	if f == null:
		push_warning("SaveLoadService: cannot write cloud manifest for slot_id=%s" % slot_id)
		return
	f.store_string(JSON.stringify(manifest.to_dict(), "	", false, true))
	f.close()

func _backup_corrupt_file(path: String, slot_id: String, epoch: int) -> void:
	if not _ensure_save_dir():
		return
	var corrupt_abs: String = ProjectSettings.globalize_path(CORRUPT_DIR)
	if not DirAccess.dir_exists_absolute(corrupt_abs):
		var mk: int = DirAccess.make_dir_recursive_absolute(corrupt_abs)
		if mk != OK and mk != ERR_ALREADY_EXISTS:
			return
	var base: String = path.get_file()
	var backup_path: String = "%s/%s.%d.%s.bak" % [CORRUPT_DIR, slot_id, int(epoch), base]
	if FileAccess.file_exists(path):
		var source := FileAccess.open(path, FileAccess.READ)
		var destination := FileAccess.open(backup_path, FileAccess.WRITE)
		if source != null and destination != null:
			destination.store_buffer(source.get_buffer(source.get_length()))
		if source != null:
			source.close()
		if destination != null:
			destination.close()
	# Mark the slot row corrupt in the index.
	var idx = _load_index()
	var row = idx.find(slot_id)
	if row != null:
		row.corrupt = true
		_save_index(idx)

func _size_of_file(path: String) -> int:
	if not FileAccess.file_exists(path):
		return 0
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return 0
	var sz: int = int(f.get_length())
	f.close()
	return sz
