extends RefCounted
class_name ShipGenerator

# Production bridge from the authoritative Rust ProcgenBundle to the existing
# scene loader. The legacy GDScript pipeline remains below only as an explicitly
# named migration oracle until Gate 6 removes it.

const ShipLayoutGeneratorScript := preload("res://scripts/procgen/ship_layout_generator.gd")
const GameplaySliceBuilderScript := preload("res://scripts/procgen/gameplay_slice_builder.gd")
const StructuralEdgeCompilerScript := preload("res://scripts/procgen/structural_edge_compiler.gd")
const StructuralPlanValidatorScript := preload("res://scripts/procgen/structural_plan_validator.gd")
const GeneratedShipLoaderScript := preload("res://scripts/procgen/generated_ship_loader.gd")
const ProcgenManifestValidatorScript := preload("res://scripts/procgen/procgen_manifest_validator.gd")
const BundleConsumerScript := preload("res://scripts/procgen/procgen_bundle_consumer.gd")
const BundleMapperScript := preload("res://scripts/procgen/procgen_bundle_mapper.gd")
const ProcgenRequestCodecScript := preload("res://scripts/procgen/procgen_request_codec.gd")

const USE_WORLDGEN := true
const WORLDGEN_KIT_ID: String = "ship_structural_v0"

var layout_generator: RefCounted = ShipLayoutGeneratorScript.new()
var _worldgen_kit_loaded: bool = false
var _worldgen_kit_doc: Dictionary = {}

# Compatibility-shaped run context. Production forwards only the requested
# difficulty into ProcgenRequest; biome mechanics are Rust-owned and are never
# inferred or stamped here. The migration oracle still consumes both values.
var biome_id: String = ""
var difficulty_id: String = ""
var _wrapper_map_cache: Dictionary = {}
var fallback_policy: RefCounted = null
var last_error: String = ""
var last_outcome: String = "idle"
var migration_oracle_invocations: int = 0
var procgen_site_id: String = ""
var procgen_site_x: int = 0
var procgen_site_y: int = 0
var procgen_player_signals: Array = []
var procgen_presentation_seed: int = -1
var procgen_locale: String = "en-US"

func configure_authored_fallback(fallback_id: String, provider: Callable) -> void:
	fallback_policy = preload("res://scripts/procgen/procgen_fallback_policy.gd").new()
	fallback_policy.configure(fallback_id, provider)

func clear_authored_fallback() -> void:
	fallback_policy = null


# Sets the context applied to the next generation. Production consumes the
# difficulty value; biome_id exists only for migration-oracle compatibility.
func configure_run_context(p_biome_id: String, p_difficulty_id: String) -> void:
	biome_id = p_biome_id
	difficulty_id = p_difficulty_id


# Supplies the coordinate-addressed identity consumed by WorldIR/SiteIR. The
# empty default keeps legacy callers stable while travel/save systems can bind
# a discovered site without relying on generation order.
func configure_procgen_site(
		p_site_id: String,
		p_x: int,
		p_y: int,
		p_player_signals: Array = [],
		p_presentation_seed: int = -1,
		p_locale: String = "en-US") -> void:
	procgen_site_id = p_site_id
	procgen_site_x = p_x
	procgen_site_y = p_y
	procgen_player_signals = p_player_signals.duplicate()
	procgen_presentation_seed = p_presentation_seed
	procgen_locale = p_locale


# Builds the full Node3D tree for the given blueprint.
# `archetype` is forwarded to the layout generator for template
# selection and role weighting.
func generate_migration_oracle(blueprint, archetype: Dictionary = {}) -> Node3D:
	assert(blueprint != null, "ShipGenerator: blueprint must not be null")
	migration_oracle_invocations += 1
	last_error = ""
	last_outcome = "migration_oracle"

	# F5: production travel often passed {}; load derelict archetype defaults so
	# guaranteed_roles / role_weights actually apply.
	if archetype.is_empty() and (not biome_id.is_empty() or not difficulty_id.is_empty()):
		archetype = _default_derelict_archetype()

	var layout: Dictionary = layout_generator.generate_with_options(blueprint, archetype, biome_id, difficulty_id, _extended_for(difficulty_id))
	if layout.is_empty():
		push_error("SHIP GENERATOR FAIL layout generation returned empty")
		return null

	return _load_layout_as_scene(layout)


func _default_derelict_archetype() -> Dictionary:
	var path: String = "res://data/procgen/archetypes/derelict.json"
	if FileAccess.file_exists(path):
		var text: String = FileAccess.get_file_as_string(path)
		var parsed: Variant = JSON.parse_string(text)
		if parsed is Dictionary:
			return (parsed as Dictionary).duplicate(true)
	return {
		"name": "Derelict",
		"guaranteed_roles": ["dock"],
		"max_duplicates": 3,
		"role_weights": {"cargo": 4, "corridor": 3, "bridge": 3, "crew_quarters": 2, "hangar": 2},
	}


# E1: any real difficulty (production travel always sets one) unlocks the
# extended template pool. Empty difficulty keeps the legacy three-template
# contract for unit smokes that call generate() without run context.
func _extended_for(diff_id: String) -> bool:
	return not str(diff_id).is_empty()


func generate_layout_migration_oracle(blueprint, archetype: Dictionary = {}) -> Dictionary:
	assert(blueprint != null, "ShipGenerator: blueprint must not be null")
	migration_oracle_invocations += 1
	last_error = ""
	last_outcome = "migration_oracle"
	return layout_generator.generate(blueprint, archetype)


# Convenience wrapper that builds a ShipBlueprint from seed/size/condition
# and runs generate().
func generate_from_seed(
		seed_value: int,
		size: int = 0,
		condition: int = 1) -> Node3D:
	return _generate_via_worldgen(seed_value, size, condition)


## Runs the authoritative lifecycle once and returns the validated bundle plus
## the exact in-memory documents consumed by Godot. Production callers that do
## not need a Node3D (top-down projection, save replay, combined scenes, tools)
## use this seam instead of rebuilding gameplay or writing temporary JSON.
func generate_documents_from_seed(
		seed_value: int,
		size: int = 0,
		condition: int = 1,
		archetype_override: String = "") -> Dictionary:
	last_error = ""
	last_outcome = "generating"
	var context: Dictionary = _native_context()
	if context.is_empty():
		return {}
	var consumer: RefCounted = BundleConsumerScript.new()
	var requested_difficulty: String = difficulty_id if not difficulty_id.is_empty() else "standard"
	var request: Dictionary = consumer.build_request(
		seed_value,
		size,
		condition,
		context.runtime_manifest,
		requested_difficulty,
		archetype_override,
		procgen_site_id,
		procgen_site_x,
		procgen_site_y,
		procgen_player_signals,
		procgen_presentation_seed,
		procgen_locale,
	)
	if request.is_empty():
		return _documents_fail(str(consumer.last_error), str(consumer.last_error))
	return _generate_documents(request, context, consumer, "")


## Replays an exact persisted request. When an expected semantic hash is
## supplied, regeneration fails closed before scene state is applied if the
## current source/content/adapter produces anything different.
func generate_documents_from_request(
		request: Dictionary,
		expected_semantic_hash: String = "") -> Dictionary:
	last_error = ""
	last_outcome = "generating"
	if request.is_empty():
		return _documents_fail("request_missing", "persisted request missing")
	var normalized_request: Dictionary = ProcgenRequestCodecScript.normalize(request)
	if normalized_request.is_empty():
		return _documents_reject("new_world_required_request_malformed")
	request = normalized_request
	var context: Dictionary = _native_context()
	if context.is_empty():
		return {}
	var incompatibility: String = _persisted_request_incompatibility(request, context)
	if not incompatibility.is_empty():
		return _documents_reject(incompatibility)
	return _generate_documents(
		request.duplicate(true),
		context,
		BundleConsumerScript.new(),
		expected_semantic_hash,
	)


## Read-only compatibility preflight for persisted worlds. This deliberately
## does not generate a bundle or select a fallback.
func persisted_request_incompatibility(request: Dictionary) -> String:
	var normalized_request: Dictionary = ProcgenRequestCodecScript.normalize(request)
	if request.is_empty():
		return "new_world_required_legacy_generator"
	if normalized_request.is_empty():
		return "new_world_required_request_malformed"
	var context: Dictionary = _native_context()
	if context.is_empty():
		return last_error
	return _persisted_request_incompatibility(normalized_request, context)


## Compatibility is checked before native generation or authored fallback.
## A pre-release save from another generator/content/schema version therefore
## cannot be mistaken for an ordinary generation failure or silently replaced.
func _persisted_request_incompatibility(
		request: Dictionary,
		context: Dictionary) -> String:
	var runtime_manifest: Dictionary = context.get("runtime_manifest", {})
	var export_schemas: Dictionary = runtime_manifest.get("export_schemas", {})
	if str(request.get("schema_version", "")) \
			!= str(export_schemas.get("procgen_request", "")):
		return "new_world_required_request_schema"
	var generator_version: Variant = request.get("generator_version", null)
	if typeof(generator_version) == TYPE_BOOL \
			or (typeof(generator_version) != TYPE_INT and typeof(generator_version) != TYPE_FLOAT) \
			or int(generator_version) != int(runtime_manifest.get("generator_version", -1)):
		return "new_world_required_generator_version"
	if str(request.get("content_manifest_hash", "")) \
			!= str(runtime_manifest.get("content_manifest_hash", "")):
		return "new_world_required_content_manifest"
	return ""

func generate(blueprint, archetype: Dictionary = {}) -> Node3D:
	if blueprint == null:
		return _generation_fail("blueprint_missing", "blueprint missing")
	var archetype_override: String = ""
	if not archetype.is_empty():
		if archetype.size() != 1 or not archetype.has("archetype_id") \
				or not archetype.get("archetype_id", null) is String:
			return _generation_fail("unsupported_legacy_archetype", "legacy archetype dictionaries are migration-oracle only")
		archetype_override = str(archetype.archetype_id)
	var seed_value: int = int(blueprint.get("seed_value", blueprint.get("seed", 0))) if blueprint is Dictionary else int(blueprint.seed_value)
	var size: int = int(blueprint.get("size", 0)) if blueprint is Dictionary else int(blueprint.size)
	var condition: int = int(blueprint.get("condition", 1)) if blueprint is Dictionary else int(blueprint.condition)
	return _generate_via_worldgen(seed_value, size, condition, archetype_override)


func _generate_via_worldgen(seed_value: int, size: int, condition: int, archetype_override: String = "") -> Node3D:
	var documents: Dictionary = generate_documents_from_seed(
		seed_value, size, condition, archetype_override)
	if documents.is_empty():
		return null
	return instantiate_documents(documents, true)


func _native_context() -> Dictionary:
	# Missing native support is an explicit failure (legacy wording retained for
	# migration-oracle/source inventory compatibility): native path is required.
	if not USE_WORLDGEN or not ClassDB.class_exists("DerelictGenerator"):
		return _documents_fail("native_adapter_unavailable", "native adapter unavailable")
	var generator: Object = ClassDB.instantiate("DerelictGenerator") as Object
	if generator == null or not generator.has_method("generate_bundle") \
			or not generator.has_method("generator_manifest") \
			or not generator.has_method("capabilities"):
		return _documents_fail("native_bundle_api_unavailable", "native bundle API unavailable")
	var build_manifest: Dictionary = {}
	var runtime_manifest: Dictionary = {}
	var capabilities: Dictionary = {}
	var manifest_variant: Variant = JSON.parse_string(str(generator.generator_manifest()))
	var capabilities_variant: Variant = JSON.parse_string(str(generator.capabilities()))
	if not manifest_variant is Dictionary or not capabilities_variant is Dictionary:
		return _documents_fail("native_context_malformed", "native manifest/capabilities malformed")
	runtime_manifest = manifest_variant
	capabilities = capabilities_variant
	var build_manifest_path: String = _build_manifest_path(runtime_manifest)
	if build_manifest_path.is_empty():
		return _documents_fail("build_manifest_target_unsupported", "no build manifest for runtime target")
	if not FileAccess.file_exists(build_manifest_path):
		return _documents_fail("build_manifest_missing", "external build manifest missing")
	var build_variant: Variant = JSON.parse_string(FileAccess.get_file_as_string(build_manifest_path))
	if not build_variant is Dictionary:
		return _documents_fail("build_manifest_malformed", "external build manifest malformed")
	build_manifest = build_variant
	var manifest_verdict: String = ProcgenManifestValidatorScript.new().validate(build_manifest, generator)
	if manifest_verdict != ProcgenManifestValidatorScript.OK:
		return _documents_fail("build_manifest_%s" % manifest_verdict, "external build manifest: %s" % manifest_verdict)
	return {
		"generator": generator,
		"build_manifest": build_manifest,
		"runtime_manifest": runtime_manifest,
		"capabilities": capabilities,
	}


func _build_manifest_path(runtime_manifest: Dictionary) -> String:
	match str(runtime_manifest.get("target", "")):
		"x86_64-pc-windows-msvc":
			return "res://data/procgen/manifests/build/win64.json"
		"wasm32-unknown-unknown":
			return "res://data/procgen/manifests/build/web.json"
		_:
			return ""


func _generate_documents(
		request: Dictionary,
		context: Dictionary,
		consumer: RefCounted,
		expected_semantic_hash: String) -> Dictionary:
	var generator: Object = context.generator
	var build_manifest: Dictionary = context.build_manifest
	var runtime_manifest: Dictionary = context.runtime_manifest
	var capabilities: Dictionary = context.capabilities
	var lifecycle_json: String = str(generator.generate_bundle(JSON.stringify(request)))
	var lifecycle_failure: String = _lifecycle_failure_code(lifecycle_json)
	var bundle: Dictionary = {}
	if lifecycle_failure.is_empty():
		bundle = consumer.consume(
			lifecycle_json, request, build_manifest, runtime_manifest, capabilities)
	var fallback_selected: bool = false
	if bundle.is_empty():
		var primary_error: String = lifecycle_failure \
			if not lifecycle_failure.is_empty() else str(consumer.last_error)
		if fallback_policy != null:
			bundle = fallback_policy.resolve(request, consumer)
			fallback_selected = not bundle.is_empty()
		if not fallback_selected:
			if fallback_policy != null:
				last_outcome = "fallback_%s" % str(fallback_policy.last_outcome)
				return _documents_fail(str(fallback_policy.last_error), "bundle validation %s; authored fallback %s" % [primary_error, str(fallback_policy.last_error)])
			return _documents_fail(primary_error, "bundle validation: %s" % primary_error)
	var semantic_hash: String = str(bundle.get("semantic_hash", ""))
	if not expected_semantic_hash.is_empty() and semantic_hash != expected_semantic_hash:
		return _documents_reject("semantic_hash_mismatch")
	var mapper: RefCounted = BundleMapperScript.new()
	var mapped: Dictionary = mapper.map_to_loader_documents(bundle)
	if mapped.is_empty():
		return _documents_fail(str(mapper.last_error), "bundle mapping: %s" % str(mapper.last_error))
	var kit_id: String = str(mapped.get("kit_id", ""))
	var kit: Dictionary = _load_worldgen_kit(kit_id)
	if kit.is_empty():
		return _documents_fail(last_error if not last_error.is_empty() else "presentation_kit", "presentation kit rejected: %s" % kit_id)
	last_error = ""
	last_outcome = "fallback_selected" if fallback_selected else "generated"
	return {
		"bundle": bundle.duplicate(true),
		"request": request.duplicate(true),
		"layout": (mapped.layout as Dictionary).duplicate(true),
		"gameplay_slice": (mapped.gameplay_slice as Dictionary).duplicate(true),
		"kit": kit.duplicate(true),
		"semantic_hash": semantic_hash,
		"fallback_selected": fallback_selected,
	}


func _lifecycle_failure_code(lifecycle_json: String) -> String:
	var parsed: Variant = JSON.parse_string(lifecycle_json)
	if not parsed is Dictionary:
		return ""
	var lifecycle: Dictionary = parsed
	if str(lifecycle.get("status", "")) != "failed":
		return ""
	var failure_variant: Variant = lifecycle.get("failure", {})
	if not failure_variant is Dictionary:
		return "lifecycle_failed"
	var code: String = str((failure_variant as Dictionary).get("code", ""))
	return "lifecycle_%s" % (code if not code.is_empty() else "failed")


## Instantiates only already-validated bundle documents. This method performs
## presentation assembly and metadata binding; it never generates mechanics.
func instantiate_documents(
		documents: Dictionary,
		apply_atmosphere: bool = true) -> Node3D:
	for key in ["bundle", "request", "layout", "gameplay_slice", "kit"]:
		if not documents.get(key, null) is Dictionary:
			return _generation_fail("documents_malformed", "bundle documents missing %s" % key)
	var bundle: Dictionary = documents.bundle
	var request: Dictionary = documents.request
	var semantic_hash: String = str(documents.get("semantic_hash", ""))
	if semantic_hash.is_empty() or semantic_hash != str(bundle.get("semantic_hash", "")):
		return _generation_fail("documents_semantic_hash", "bundle document semantic hash mismatch")
	var loader: Node3D = GeneratedShipLoaderScript.new()
	if not loader.load_from_documents(
			(documents.layout as Dictionary).duplicate(true),
			(documents.kit as Dictionary).duplicate(true),
			(documents.gameplay_slice as Dictionary).duplicate(true),
			apply_atmosphere):
		loader.queue_free()
		return _generation_fail("loader_rejected_documents", "loader rejected bundle documents")
	loader.name = "GeneratedShip"
	loader.set_meta("procgen_site_ir", (bundle.get("site_ir", {}) as Dictionary).duplicate(true))
	loader.set_meta("procgen_gameplay_ir", (bundle.get("gameplay_ir", {}) as Dictionary).duplicate(true))
	loader.set_meta("procgen_presentation_ir", (bundle.get("presentation_ir", {}) as Dictionary).duplicate(true))
	loader.set_meta("procgen_request", request.duplicate(true))
	loader.set_meta("procgen_semantic_hash", semantic_hash)
	loader.set_meta("procgen_fallback_selected", bool(documents.get("fallback_selected", false)))
	last_error = ""
	return loader


func _load_worldgen_kit(kit_id: String = WORLDGEN_KIT_ID) -> Dictionary:
	if kit_id != WORLDGEN_KIT_ID:
		last_error = "unsupported_presentation_kit"
		return {}
	if _worldgen_kit_loaded:
		return _worldgen_kit_doc.duplicate(true)
	var kit_path: String = "res://data/kits/%s.json" % kit_id
	if not FileAccess.file_exists(kit_path):
		last_error = "presentation_kit_missing"
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(kit_path))
	if not (parsed is Dictionary):
		last_error = "presentation_kit_malformed"
		return {}
	_worldgen_kit_loaded = true
	_worldgen_kit_doc = (parsed as Dictionary).duplicate(true)
	return _worldgen_kit_doc.duplicate(true)


func _generation_fail(code: String, detail: String) -> Node3D:
	last_error = code if not code.is_empty() else "generation_failed"
	if not last_outcome.begins_with("fallback_"):
		last_outcome = "failed"
	push_error("SHIP GENERATOR FAIL %s" % detail)
	return null


func _documents_fail(code: String, detail: String) -> Dictionary:
	last_error = code if not code.is_empty() else "generation_failed"
	if not last_outcome.begins_with("fallback_"):
		last_outcome = "failed"
	push_error("SHIP GENERATOR FAIL %s" % detail)
	return {}


func _documents_reject(code: String) -> Dictionary:
	last_error = code if not code.is_empty() else "generation_rejected"
	last_outcome = "rejected"
	return {}


func _resolve_worldgen_loot_containers(
		gameplay: Dictionary,
		exported_gameplay: Dictionary,
		loot_tables: Dictionary) -> bool:
	var builder_containers: Variant = gameplay.get("loot_containers", [])
	if not (builder_containers is Array):
		push_error("SHIP GENERATOR FAIL gameplay builder loot_containers is not an Array")
		return false
	for container_variant in (builder_containers as Array):
		if not (container_variant is Dictionary):
			continue
		var container: Dictionary = container_variant
		var table_id: String = str(container.get("loot_table", ""))
		if not loot_tables.has(table_id):
			push_error("SHIP GENERATOR FAIL gameplay builder loot table missing: %s" % table_id)
			return false

	var exported_containers_variant: Variant = exported_gameplay.get("loot_containers", [])
	if not (exported_containers_variant is Array):
		push_error("SHIP GENERATOR FAIL worldgen loot_containers is not an Array")
		return false
	var merged_containers: Array = (builder_containers as Array).duplicate(true)
	for exported_variant in (exported_containers_variant as Array):
		if not (exported_variant is Dictionary):
			continue
		var exported_container: Dictionary = (exported_variant as Dictionary).duplicate(true)
		var table_id: String = str(exported_container.get("loot_table", ""))
		if not loot_tables.has(table_id):
			if table_id != "worldgen_seeded":
				push_error("SHIP GENERATOR FAIL worldgen loot table missing: %s" % table_id)
				return false
			table_id = _map_worldgen_loot_table(str(exported_container.get("kind", "")), loot_tables)
			if table_id.is_empty():
				push_error("SHIP GENERATOR FAIL no game loot table mapping for worldgen container kind: %s" % str(exported_container.get("kind", "")))
				return false
			exported_container["loot_table"] = table_id
		if not _has_loot_container_at(merged_containers, exported_container):
			merged_containers.append(exported_container)
	gameplay["loot_containers"] = merged_containers
	return true


func _map_worldgen_loot_table(container_kind: String, loot_tables: Dictionary) -> String:
	var candidate: String = ""
	match container_kind:
		"cargo_crate", "supply_crate":
			candidate = "salvage_cargo"
		"parts_locker", "tool_rack":
			candidate = "salvage_engineering"
		"bridge_locker", "footlocker", "med_cabinet", "food_locker", "weapon_locker", "ammo_crate", "filter_cabinet", "suit_locker":
			candidate = "generic_locker"
		_:
			if container_kind.contains("crate"):
				candidate = "generic_crate"
			elif container_kind.contains("locker"):
				candidate = "generic_locker"
	if loot_tables.has(candidate):
		return candidate
	return ""


func _has_loot_container_at(containers: Array, candidate: Dictionary) -> bool:
	var candidate_room: String = str(candidate.get("room_id", ""))
	var candidate_cell: Variant = candidate.get("approach_cell", [])
	for existing_variant in containers:
		if not (existing_variant is Dictionary):
			continue
		var existing: Dictionary = existing_variant
		if str(existing.get("room_id", "")) != candidate_room:
			continue
		if str(existing.get("approach_cell", [])) == str(candidate_cell):
			return true
	return false


func _load_layout_as_scene(layout: Dictionary) -> Node3D:
	# Skip recompile when ShipLayoutGenerator already stamped a validated plan.
	# Never restamp wreck here — module_damage keys would drift from the plan.
	var plan_variant: Variant = layout.get("structural_plan", {})
	var plan_ready: bool = plan_variant is Dictionary \
		and not (plan_variant as Dictionary).is_empty() \
		and bool(layout.get("structural_plan_validated", false))
	if not plan_ready:
		var compiler: RefCounted = StructuralEdgeCompilerScript.new()
		var structural_plan: Dictionary = compiler.compile(layout)
		var verdict: Dictionary = StructuralPlanValidatorScript.new().validate(structural_plan, layout)
		if not bool(verdict.get("ok", false)):
			push_error("SHIP GENERATOR FAIL structural plan validation failed: %s" % JSON.stringify(verdict.get("errors", [])))
			return null
		layout["structural_plan"] = structural_plan
		layout["structural_plan_validated"] = true

	# Build the gameplay slice FIRST so builder-authored hazard links can be
	# stamped onto the layout before it is handed to GeneratedShipLoader. The
	# retained migration oracle uses the same in-memory assembly seam as the
	# authoritative bundle path; it never publishes shared temporary files.
	var gameplay_builder: GameplaySliceBuilderScript = GameplaySliceBuilderScript.new()
	var gameplay: Dictionary = gameplay_builder.build(layout)
	var layout_arcs: Variant = layout.get("arc_zones", [])
	var slice_arcs: Variant = gameplay.get("arc_zones", [])
	if (not (layout_arcs is Array) or (layout_arcs as Array).is_empty()) \
			and slice_arcs is Array and not (slice_arcs as Array).is_empty():
		layout["arc_zones"] = (slice_arcs as Array).duplicate(true)

	# Layout kit_id selects the structural JSON. Hazard/industrial catalogs have
	# no modules[].godot_wrapper_scene array yet, so they fall back to v0 wrappers.
	var kit_path: String = kit_path_for_layout(layout)
	# FileAccess.file_exists natively supports res:// and works in exported
	# builds (.pck); ProjectSettings.globalize_path would break inside a pack.
	if not FileAccess.file_exists(kit_path):
		push_error("SHIP GENERATOR FAIL structural kit not found: %s" % kit_path)
		return null
	var kit_variant: Variant = JSON.parse_string(FileAccess.get_file_as_string(kit_path))
	if not kit_variant is Dictionary:
		push_error("SHIP GENERATOR FAIL structural kit is malformed: %s" % kit_path)
		return null

	var loader: Node3D = GeneratedShipLoaderScript.new()
	# Generated derelicts are the away branch; pass that context to the loader's
	# single atmosphere hook so biome fog can deepen without playable edits.
	var success: bool = loader.load_from_documents(
		layout.duplicate(true),
		(kit_variant as Dictionary).duplicate(true),
		gameplay.duplicate(true),
		true,
		{"kit": kit_path},
	)
	if not success:
		push_error("SHIP GENERATOR FAIL loader returned false")
		loader.queue_free()
		return null

	# Give the returned root a stable, meaningful name. The loader builds
	# "StructuralRoot" (geometry + nav) and "ObjectiveRoot" children under it.
	loader.name = "GeneratedShip"
	return loader


func kit_path_for_layout(layout: Dictionary) -> String:
	var kit_id: String = str(layout.get("kit_id", "ship_structural_v0"))
	if kit_id.is_empty():
		kit_id = "ship_structural_v0"
	var kit_path: String = "res://data/kits/%s.json" % kit_id
	if not _kit_has_wrapper_map(kit_path):
		kit_path = "res://data/kits/ship_structural_v0.json"
	return kit_path


func _kit_has_wrapper_map(kit_path: String) -> bool:
	if _wrapper_map_cache.has(kit_path):
		return bool(_wrapper_map_cache[kit_path])
	var ok: bool = false
	if FileAccess.file_exists(kit_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(kit_path))
		if parsed is Dictionary:
			var modules_v: Variant = (parsed as Dictionary).get("modules", [])
			if modules_v is Array and not (modules_v as Array).is_empty():
				ok = true
				for entry in (modules_v as Array):
					if not (entry is Dictionary) \
							or str((entry as Dictionary).get("module_id", "")).is_empty() \
							or str((entry as Dictionary).get("godot_wrapper_scene", "")).is_empty():
						ok = false
						break
	_wrapper_map_cache[kit_path] = ok
	return ok

