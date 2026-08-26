extends RefCounted
class_name ProcgenBundleConsumer

const CanonicalJsonScript := preload("res://scripts/procgen/procgen_canonical_json.gd")

const GENERATOR_VERSION: int = 3
const STRUCTURAL_GENERATOR_VERSION: int = 2
const MAX_SAFE_JSON_INTEGER: int = 9007199254740991
const CONTENT_HASH: String = "0923a378b923021172606f0c678383a5ca14c261e20b498369d3768b852e7385"
const DOMAINS: Array[String] = ["world", "site", "gameplay", "presentation"]
const SUPPORTED_ARCHETYPES: Array[String] = ["shuttle", "corvette", "freighter", "frigate"]
const SUPPORTED_DIFFICULTIES: Array[String] = ["standard", "hardened", "deep_dive"]
const PLAYER_SIGNAL_KINDS: Array[String] = [
	"combat_mastery", "damage_pressure", "resource_pressure", "objective_pace",
]
const ROOM_ROLES: Array[String] = [
	"Airlock", "Dock", "Corridor", "MainSpine", "Hub", "Ramp", "Elevator", "Bridge",
	"Engineering", "Reactor", "LifeSupport", "Maintenance", "Cargo", "Hangar", "Storage",
	"Armory", "Security", "Medical", "CrewQuarters", "MessHall", "Compartment",
]
const EDGE_KINDS: Array[String] = ["Solid", "Open", "Door", "Locked", "Hatch", "Breach"]
const DIRECTIONS: Array[String] = ["North", "South", "East", "West"]
const DAMAGE_VARIANTS: Array[String] = ["Intact", "Damaged", "Breached"]
const CAUSES_OF_LOSS: Array[String] = [
	"ReactorBreach", "Depressurization", "PirateBoarding", "Plague", "DriveMisjump", "Unknown",
]
const RNG_CHANNELS: Array[String] = [
	"world.archetype", "world.biome", "world.hazard", "world.resource", "world.landmark", "world.route_cost", "site.structural",
	"site.mission_template", "site.gate_order", "site.functional_props", "site.spatial_annotations",
	"meta", "hull", "template", "topology", "residual_fill", "door", "furnish", "story",
	"intact", "breach", "scorch", "seal", "bodies", "fracture", "debris", "loot",
	"gameplay.creature_blueprint", "gameplay.creature_ability", "gameplay.creature_material",
	"gameplay.encounter_candidate", "gameplay.encounter_faction", "gameplay.encounter_reward",
	"gameplay.encounter_selection", "gameplay.item_family", "gameplay.item_affix",
	"presentation.asset_assembly",
]
const EXPORT_SCHEMAS: Dictionary = {
	"procgen_request": "procgen-request-2", "procgen_bundle": "procgen-bundle-5",
	"world_ir": "world-ir-2", "site_ir": "site-ir-2", "gameplay_ir": "gameplay-ir-3",
	"presentation_ir": "presentation-ir-2", "generation_trace": "generation-trace-4",
	"adaptive_proposal": "adaptive-proposal-2",
}
const ADAPTER_SCHEMAS: Dictionary = {
	"lifecycle_result": "procgen-lifecycle-result-5",
	"capabilities": "procgen-capabilities-4",
	"generator_manifest": "procgen-generator-manifest-4",
}
const BUILD_MANIFEST_SCHEMA: String = "procgen-build-manifest-4"
const ADAPTIVE_TRACE_SCHEMA: String = "adaptive-decision-trace-1"
const ADAPTIVE_RULE_VERSION: String = "adaptive-classical-1"
const ADAPTIVE_RATIONALES: Array[String] = [
	"validated_candidate", "challenge_fit", "pace_fit", "resource_pressure_fit", "stable_tie_break",
	"authored_envelope", "combat_mastery", "damage_pressure", "resource_pressure", "objective_pace",
	"no_validated_candidate", "classical_fallback",
]
const ENCOUNTER_RNG_CHANNELS: Array[String] = [
	"gameplay.encounter_candidate", "gameplay.encounter_faction", "gameplay.encounter_reward",
]
const ENCOUNTER_RATIONALES: Array[String] = [
	"accepted", "incompatible_faction", "incompatible_role", "protected_room",
	"protected_cell", "no_clearance", "footprint_out_of_room", "occupied",
	"navigation_unreachable", "exposed_los", "no_cover", "threat_budget_exceeded",
	"performance_budget_exceeded", "economy_budget_exceeded", "group_cap_exceeded",
	"instance_cap_exceeded", "no_fair_spawn",
]
const CREATURE_SPECS: Dictionary = {
	"creature_brute": {"body_plan_id":"body_brute", "footprint_id":"fp_large", "rig_id":"rig_brute", "animation_set_id":"anim_brute", "ability_id":"ability_bash", "behavior_id":"behavior_guard", "material_id":"material_armor", "counterplay_id":"counter_armor", "threat_role":"tank", "threat_cost":500, "performance_cost":300, "instance_cap":4, "clearance":2, "footprint":[Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]},
	"creature_drone": {"body_plan_id":"body_drone", "footprint_id":"fp_small", "rig_id":"rig_drone", "animation_set_id":"anim_drone", "ability_id":"ability_dash", "behavior_id":"behavior_patrol", "material_id":"material_chitin", "counterplay_id":"counter_evade", "threat_role":"scout", "threat_cost":200, "performance_cost":150, "instance_cap":12, "clearance":1, "footprint":[Vector2i(0, 0)]},
	"creature_siren": {"body_plan_id":"body_siren", "footprint_id":"fp_small", "rig_id":"rig_siren", "animation_set_id":"anim_siren", "ability_id":"ability_pulse", "behavior_id":"behavior_ambush", "material_id":"material_synthetic", "counterplay_id":"counter_interrupt", "threat_role":"controller", "threat_cost":400, "performance_cost":250, "instance_cap":6, "clearance":1, "footprint":[Vector2i(0, 0)]},
}
const ENCOUNTER_FACTIONS: Dictionary = {
	"biomatter": {"blueprints":["creature_drone", "creature_siren"], "roles":["scout", "controller"], "abilities":["ability_dash", "ability_pulse"]},
	"raiders": {"blueprints":["creature_brute", "creature_drone"], "roles":["scout", "tank"], "abilities":["ability_bash", "ability_dash"]},
}
const ITEM_FAMILIES: Dictionary = {
	"armor": {"socket_id":"socket_armor", "visual_tag":"item_armor", "affix_id":"affix_armor", "stat":"armor", "base_value":40, "frequency_bp":5000},
	"tool": {"socket_id":"socket_tool", "visual_tag":"item_tool", "affix_id":"affix_capacity", "stat":"capacity", "base_value":25, "frequency_bp":7000},
	"weapon": {"socket_id":"socket_weapon", "visual_tag":"item_weapon", "affix_id":"affix_damage", "stat":"damage", "base_value":60, "frequency_bp":3500},
}
const PRESENTATION_ASSET_BINDINGS: Dictionary = {
	"asset:primitive:structural":"binding:primitive:structural",
	"asset:audio:ambient":"binding:audio:ambient",
	"asset:primitive:creature_brute":"binding:threat:brute",
	"asset:primitive:creature_drone":"binding:threat:drone",
	"asset:primitive:creature_siren":"binding:threat:siren",
	"asset:primitive:item_armor":"binding:item:armor",
	"asset:primitive:item_tool":"binding:item:tool",
	"asset:primitive:item_weapon":"binding:item:weapon",
	"asset:primitive:objective":"binding:objective:default",
}
const PLATFORM_ADAPTERS: Dictionary = {
	"x86_64-pc-windows-msvc": {
		"artifact_kind": "gdextension",
		"artifact_path": "addons/derelict/bin/win64/derelict_godot.dll",
		"adapter_kind": "native",
		"worker_mode": "thread_pool",
		"worker_count": 2,
	},
	"wasm32-unknown-unknown": {
		"artifact_kind": "wasm",
		"artifact_path": "addons/derelict/bin/web/derelict_wasm_bg.wasm",
		"adapter_kind": "web",
		"worker_mode": "cooperative",
		"worker_count": 0,
	},
}
const MISSION_NODE_KINDS: Array[String] = ["start", "acquire_key", "repair", "objective", "extraction"]
const MISSION_GATE_KINDS: Array[String] = ["key_lock", "repair"]
const NAVIGATION_KINDS: Array[String] = ["portal", "vertical"]
const FUNCTIONAL_PROP_KINDS: Array[String] = ["key_pickup", "repair_panel", "objective_console", "extraction_console"]
const SHIP_FIELDS: Array[String] = [
	"generator_version", "seed", "archetype_id", "template_id", "intactness", "cause_of_loss",
	"topology", "plan", "entry_room", "goal_room", "critical_path", "decks", "room_graph",
	"entities", "damage_events", "fractured", "fragments",
]

var last_error: String = ""

func build_request(
		seed_value: int,
		size: int,
		condition: int,
		runtime_manifest: Dictionary = {},
		difficulty_value: String = "standard",
		archetype_override: String = "",
		site_id_override: String = "",
		site_x: int = 0,
		site_y: int = 0,
		player_signals: Array = [],
		presentation_seed_override: int = -1,
		locale_value: String = "en-US") -> Dictionary:
	last_error = ""
	if seed_value < 0 or seed_value > MAX_SAFE_JSON_INTEGER:
		return _fail("json_unsafe_seed")
	var archetypes: Dictionary = {0: "shuttle", 1: "corvette", 2: "freighter"}
	var intactness: Dictionary = {0: 9500, 1: 6000, 2: 2000}
	if not archetypes.has(size) or not intactness.has(condition):
		return _fail("unsupported_ship_parameters")
	if not SUPPORTED_DIFFICULTIES.has(difficulty_value):
		return _fail("unsupported_difficulty")
	var archetype_id: String = str(archetypes[size]) if archetype_override.is_empty() else archetype_override
	if not SUPPORTED_ARCHETYPES.has(archetype_id):
		return _fail("unsupported_archetype")
	var generator_version: int = GENERATOR_VERSION
	var content_hash: String = CONTENT_HASH
	if not runtime_manifest.is_empty():
		if str(runtime_manifest.get("schema_version", "")) != ADAPTER_SCHEMAS.generator_manifest \
				or not _is_json_integer(runtime_manifest.get("generator_version", null)) \
				or int(runtime_manifest.get("generator_version", -1)) != GENERATOR_VERSION \
				or not _is_sha256(str(runtime_manifest.get("content_manifest_hash", ""))):
			return _fail("runtime_request_identity")
		generator_version = int(runtime_manifest.generator_version)
		content_hash = str(runtime_manifest.content_manifest_hash)
	var site_id: String = "site_%d_%d_%d" % [seed_value, size, condition] if site_id_override.is_empty() else site_id_override
	var presentation_seed: int = seed_value if presentation_seed_override < 0 else presentation_seed_override
	var request: Dictionary = {
		"schema_version": EXPORT_SCHEMAS.procgen_request, "world_seed": seed_value,
		"site": {"site_id": site_id, "x": site_x, "y": site_y, "archetype_id": archetype_id,
			"kit_id": "ship_structural_v0", "intactness_override_bp": int(intactness[condition]),
			"cause_of_loss": null, "loot_richness_bp": 5000},
		"difficulty_id": difficulty_value,
		"player_model": {"schema_version": "player-model-2", "signals": player_signals.duplicate(true)},
		"requested_domains": DOMAINS.duplicate(), "generator_version": generator_version,
		"content_manifest_hash": content_hash,
		"presentation": {"seed": presentation_seed, "locale": locale_value},
	}
	if not _validate_request(request): return {}
	last_error = ""
	return request

func consume(
		result_json: String,
		request: Dictionary,
		build_manifest: Dictionary = {},
		runtime_manifest: Dictionary = {},
		capabilities: Dictionary = {}) -> Dictionary:
	last_error = ""
	if request.is_empty() or result_json.is_empty(): return _fail("missing_bundle")
	if not _validate_request(request): return {}
	if not _validate_context(request, build_manifest, runtime_manifest, capabilities): return {}
	var parser := JSON.new()
	if parser.parse(result_json) != OK or not parser.data is Dictionary: return _fail("malformed_bundle_json")
	var lifecycle: Dictionary = parser.data
	if not _has_exact_keys(lifecycle, ["schema_version", "status", "request_id", "bundle", "failure", "events"]): return _fail("lifecycle_shape")
	if str(lifecycle.get("schema_version", "")) != ADAPTER_SCHEMAS.lifecycle_result: return _fail("lifecycle_schema")
	if str(lifecycle.get("status", "")) != "completed": return _fail("lifecycle_not_completed")
	if lifecycle.get("request_id", null) != null: return _fail("lifecycle_request_id")
	if lifecycle.get("failure", null) != null: return _fail("unexpected_failure_payload")
	var events: Variant = lifecycle.get("events", null)
	if not events is Array or not _same_json(events, ["admitted", "started", "completed"]): return _fail("lifecycle_events")
	if (events as Array).size() > int(capabilities.get("max_events", 0)): return _fail("lifecycle_event_cap")
	var bundle_value: Variant = lifecycle.get("bundle", null)
	if not bundle_value is Dictionary: return _fail("missing_bundle")
	var bundle: Dictionary = bundle_value
	if not _validate_bundle(bundle, request, build_manifest, capabilities): return {}
	if not _verify_hash(result_json, bundle): return {}
	return bundle.duplicate(true)

func _validate_request(request: Dictionary) -> bool:
	var request_keys: Array[String] = [
		"schema_version", "world_seed", "site", "difficulty_id", "player_model",
		"requested_domains", "generator_version", "content_manifest_hash", "presentation",
	]
	if not _has_exact_keys(request, request_keys): return _reject("request_shape")
	if str(request.get("schema_version", "")) != EXPORT_SCHEMAS.procgen_request: return _reject("request_schema")
	var world_seed: Variant = request.get("world_seed", null)
	if not _is_bounded_integer(world_seed, 0, MAX_SAFE_JSON_INTEGER): return _reject("request_bounds")

	var site_value: Variant = request.get("site", null)
	var site_keys: Array[String] = [
		"site_id", "x", "y", "archetype_id", "kit_id", "intactness_override_bp",
		"cause_of_loss", "loot_richness_bp",
	]
	if not site_value is Dictionary or not _has_exact_keys(site_value, site_keys): return _reject("request_site_shape")
	var site: Dictionary = site_value
	if not _is_valid_world_id(str(site.get("site_id", ""))) \
			or not SUPPORTED_ARCHETYPES.has(str(site.get("archetype_id", ""))) \
			or str(site.get("kit_id", "")) != "ship_structural_v0": return _reject("request_identity")
	for coordinate in [site.get("x", null), site.get("y", null)]:
		if not _is_bounded_integer(coordinate, -2147483647, 2147483646): return _reject("request_bounds")
	var intactness: Variant = site.get("intactness_override_bp", null)
	var loot_richness: Variant = site.get("loot_richness_bp", null)
	if (intactness != null and not _is_bounded_integer(intactness, 0, 10000)) \
			or not _is_bounded_integer(loot_richness, 0, 30000): return _reject("request_bounds")
	var cause: Variant = site.get("cause_of_loss", null)
	if cause != null and (not cause is String or not CAUSES_OF_LOSS.has(str(cause))): return _reject("request_identity")

	if not SUPPORTED_DIFFICULTIES.has(str(request.get("difficulty_id", ""))): return _reject("request_difficulty")
	var player_value: Variant = request.get("player_model", null)
	if not player_value is Dictionary or not _has_exact_keys(player_value, ["schema_version", "signals"]): return _reject("request_player_model")
	var player: Dictionary = player_value
	if str(player.get("schema_version", "")) != "player-model-2" \
			or not player.get("signals", null) is Array \
			or (player.get("signals", []) as Array).size() > 4: return _reject("request_player_model")
	var previous_signal_index: int = -1
	for signal_value in player.get("signals", []):
		if not signal_value is Dictionary or not _has_exact_keys(signal_value, ["kind", "value_bp"]): return _reject("request_player_model")
		var signal_record: Dictionary = signal_value
		var kind: String = str(signal_record.get("kind", ""))
		var signal_index: int = PLAYER_SIGNAL_KINDS.find(kind)
		if signal_index < 0 \
				or not _is_bounded_integer(signal_record.get("value_bp", null), 0, 10000) \
				or signal_index <= previous_signal_index: return _reject("request_player_model")
		previous_signal_index = signal_index
	var domains_value: Variant = request.get("requested_domains", null)
	if not domains_value is Array or (domains_value as Array).is_empty(): return _reject("request_domains")
	var seen_domains: Dictionary = {}
	for domain_value in domains_value:
		if not domain_value is String or not DOMAINS.has(str(domain_value)) or seen_domains.has(str(domain_value)):
			return _reject("request_domains")
		seen_domains[str(domain_value)] = true
	if not _is_json_integer(request.get("generator_version", null)) \
			or int(request.get("generator_version", -1)) != GENERATOR_VERSION \
			or str(request.get("content_manifest_hash", "")) != CONTENT_HASH: return _reject("request_version")

	var presentation_value: Variant = request.get("presentation", null)
	if not presentation_value is Dictionary or not _has_exact_keys(presentation_value, ["seed", "locale"]): return _reject("request_presentation")
	var presentation: Dictionary = presentation_value
	if not _is_bounded_integer(presentation.get("seed", null), 0, MAX_SAFE_JSON_INTEGER) \
			or not _is_locale(str(presentation.get("locale", ""))): return _reject("request_presentation")
	return true

func _validate_context(request: Dictionary, build: Dictionary, runtime: Dictionary, caps: Dictionary) -> bool:
	var build_keys: Array[String] = ["manifest_schema", "rust_source_commit", "generator_version", "content_manifest_path", "content_manifest_hash", "target", "artifact", "export_schemas"]
	if not _has_exact_keys(build, build_keys): return _reject("build_manifest_shape")
	if str(build.get("manifest_schema", "")) != BUILD_MANIFEST_SCHEMA: return _reject("build_manifest_schema")
	if str(build.get("content_manifest_path", "")) != "data/procgen/manifests/content_manifest.json": return _reject("build_manifest_path")
	if not _is_lower_hex(str(build.get("rust_source_commit", "")), 40): return _reject("build_manifest_source")
	if not _is_sha256(str(build.get("content_manifest_hash", ""))) \
			or str(build.get("content_manifest_hash", "")) != CONTENT_HASH: return _reject("build_manifest_content")
	if not _is_json_integer(build.get("generator_version", null)) or int(build.get("generator_version", -1)) != GENERATOR_VERSION: return _reject("build_manifest_version")
	var build_target: String = str(build.get("target", ""))
	if not PLATFORM_ADAPTERS.has(build_target): return _reject("build_manifest_target")
	var platform: Dictionary = PLATFORM_ADAPTERS[build_target]
	var artifact: Variant = build.get("artifact", null)
	if not artifact is Dictionary or not _has_exact_keys(artifact, ["kind", "path", "sha256"]): return _reject("build_manifest_artifact")
	if str((artifact as Dictionary).get("kind", "")) != str(platform.artifact_kind) \
			or str((artifact as Dictionary).get("path", "")) != str(platform.artifact_path) \
			or not _is_sha256(str((artifact as Dictionary).get("sha256", ""))): return _reject("build_manifest_artifact")
	var runtime_keys: Array[String] = ["schema_version", "rust_source_commit", "generator_version", "content_manifest_hash", "export_schemas", "adapter_schemas", "target", "dirty_development"]
	if not _has_exact_keys(runtime, runtime_keys): return _reject("runtime_manifest_shape")
	if str(runtime.get("schema_version", "")) != ADAPTER_SCHEMAS.generator_manifest: return _reject("runtime_manifest_schema")
	if runtime.get("dirty_development", null) is not bool or bool(runtime.dirty_development): return _reject("dirty_runtime")
	if str(runtime.get("rust_source_commit", "")) != str(build.get("rust_source_commit", "")): return _reject("manifest_source")
	if not _is_json_integer(runtime.get("generator_version", null)) \
			or int(runtime.get("generator_version", -1)) != int(build.get("generator_version", -2)) \
			or int(runtime.get("generator_version", -1)) != int(request.get("generator_version", -3)): return _reject("manifest_version")
	if str(runtime.get("content_manifest_hash", "")) != str(build.get("content_manifest_hash", "")) \
			or str(runtime.get("content_manifest_hash", "")) != str(request.get("content_manifest_hash", "")): return _reject("manifest_content")
	if str(runtime.get("target", "")).is_empty() or str(runtime.get("target", "")) != str(build.get("target", "")): return _reject("manifest_target")
	if not _same_json(build.get("export_schemas", {}), EXPORT_SCHEMAS) \
			or not _same_json(runtime.get("export_schemas", {}), EXPORT_SCHEMAS): return _reject("manifest_export_schemas")
	if not _same_json(runtime.get("adapter_schemas", {}), ADAPTER_SCHEMAS): return _reject("manifest_adapter_schemas")
	if not _validate_capabilities(caps, runtime): return false
	if JSON.stringify(request).to_utf8_buffer().size() > int(caps.get("max_request_bytes", 0)): return _reject("request_cap")
	return true

func _validate_capabilities(caps: Dictionary, runtime_manifest: Dictionary) -> bool:
	var keys: Array[String] = ["schema_version", "adapter_kind", "target", "supports_sync", "supports_async", "supports_cancel", "worker_mode", "worker_count", "queue_capacity", "retained_results", "max_request_bytes", "max_entities", "max_trace_entries", "max_events", "deadline_ms", "supported_domains", "schemas"]
	if not _has_exact_keys(caps, keys): return _reject("capability_shape")
	if str(caps.get("schema_version", "")) != ADAPTER_SCHEMAS.capabilities: return _reject("capability_schema")
	var target: String = str(runtime_manifest.get("target", ""))
	if not PLATFORM_ADAPTERS.has(target): return _reject("capability_target")
	var platform: Dictionary = PLATFORM_ADAPTERS[target]
	if str(caps.get("adapter_kind", "")) != str(platform.adapter_kind) \
			or str(caps.get("worker_mode", "")) != str(platform.worker_mode): return _reject("capability_adapter")
	if str(caps.get("target", "")) != str(runtime_manifest.get("target", "")): return _reject("capability_target")
	if not _is_json_integer(caps.get("worker_count", null)) \
			or int(caps.get("worker_count", -1)) != int(platform.worker_count): return _reject("capability_worker_count")
	for flag in ["supports_sync", "supports_async", "supports_cancel"]:
		if caps.get(flag, null) is not bool or not bool(caps.get(flag, false)): return _reject("capability_%s" % flag)
	var maximums: Dictionary = {"queue_capacity": 8, "retained_results": 16, "max_request_bytes": 65536, "max_entities": 4096, "max_trace_entries": 4096, "max_events": 32, "deadline_ms": 2000}
	for key in maximums.keys():
		if not _is_json_integer(caps.get(key, null)) or int(caps.get(key, 0)) <= 0 or int(caps.get(key, 0)) > int(maximums[key]): return _reject("capability_%s" % key)
	if not _same_json(caps.get("supported_domains", []), DOMAINS): return _reject("capability_domains")
	if not _same_json(caps.get("schemas", {}), ADAPTER_SCHEMAS) \
			or not _same_json(caps.get("schemas", {}), runtime_manifest.get("adapter_schemas", {})): return _reject("capability_schemas")
	return true

func _validate_bundle(bundle: Dictionary, request: Dictionary, manifest: Dictionary, caps: Dictionary) -> bool:
	var fields: Array[String] = ["schema_version", "version", "request", "world_ir", "site_ir", "gameplay_ir", "presentation_ir", "semantic_hash", "metrics", "trace"]
	if not _has_exact_keys(bundle, fields): return _reject("bundle_shape")
	if str(bundle.get("schema_version", "")) != EXPORT_SCHEMAS.procgen_bundle: return _reject("bundle_schema")
	var version_value: Variant = bundle.get("version", null)
	if not version_value is Dictionary: return _reject("version_shape")
	var version: Dictionary = version_value
	if not _has_exact_keys(version, ["generator_version", "content_manifest_hash", "export_schemas"]): return _reject("version_shape")
	if not _is_json_integer(version.get("generator_version", null)) \
			or int(version.get("generator_version", -1)) != int(request.get("generator_version", -2)) \
			or int(version.get("generator_version", -1)) != int(manifest.get("generator_version", -3)) \
			or str(version.get("content_manifest_hash", "")) != str(request.get("content_manifest_hash", "")) \
			or not _same_json(version.get("export_schemas", {}), EXPORT_SCHEMAS): return _reject("version_mismatch")
	var returned_request: Variant = bundle.get("request", null)
	if not returned_request is Dictionary or not _same_json(returned_request, request): return _reject("request_identity")
	var world_value: Variant = bundle.get("world_ir", null)
	if not world_value is Dictionary: return _reject("world_shape")
	var world: Dictionary = world_value
	if not _has_exact_keys(world, ["schema_version", "world_seed", "site_seed", "site_id", "x", "y", "archetype_id", "markers", "anchors", "biome_fields", "hazard_fields", "resource_pressures", "landmarks", "routes", "extraction"]): return _reject("world_shape")
	if str(world.get("schema_version", "")) != EXPORT_SCHEMAS.world_ir: return _reject("world_ir_schema")
	var site_request: Dictionary = request.get("site", {})
	if not _is_json_integer(world.get("site_seed", null)) or int(world.get("site_seed", -1)) < 0 \
			or not _validate_world_ir(world, request): return false
	if not _same_json(world.get("world_seed", null), request.get("world_seed", null)) or str(world.get("site_id", "")) != str(site_request.get("site_id", "")) \
			or not _same_json(world.get("x", null), site_request.get("x", null)) or not _same_json(world.get("y", null), site_request.get("y", null)) \
			or str(world.get("archetype_id", "")) != str(site_request.get("archetype_id", "")): return _reject("world_identity")
	var presentation_value: Variant = bundle.get("presentation_ir", null)
	if not presentation_value is Dictionary: return _reject("presentation_shape")
	var presentation: Dictionary = presentation_value
	if not _has_exact_keys(presentation, ["schema_version", "instructions", "decisions", "repairs", "fallback_subjects"]): return _reject("presentation_shape")
	if str(presentation.get("schema_version", "")) != EXPORT_SCHEMAS.presentation_ir: return _reject("presentation_ir_schema")
	var site_value: Variant = bundle.get("site_ir", null)
	if not site_value is Dictionary or not _has_exact_keys(site_value, ["schema_version", "ship", "mission_graph", "navigation", "functional_props", "spatial_annotations"]): return _reject("site_shape")
	var site_ir: Dictionary = site_value
	if str(site_ir.get("schema_version", "")) != EXPORT_SCHEMAS.site_ir: return _reject("site_ir_schema")
	var ship_value: Variant = site_ir.get("ship", null)
	if not ship_value is Dictionary or not _validate_ship_shape(ship_value as Dictionary): return false
	var ship: Dictionary = ship_value
	if not _same_json(ship.get("generator_version", null), STRUCTURAL_GENERATOR_VERSION) or not _same_json(ship.get("seed", null), world.get("site_seed", null)) \
			or str(ship.get("archetype_id", "")) != str(site_request.get("archetype_id", "")): return _reject("ship_identity")
	if not _validate_site_overlay(site_ir, ship): return false
	if (ship.entities as Array).size() > int(caps.get("max_entities", 0)): return _reject("entity_cap")
	var gameplay_value: Variant = bundle.get("gameplay_ir", null)
	if not gameplay_value is Dictionary: return _reject("gameplay_shape")
	var gameplay_ir: Dictionary = gameplay_value
	if str(gameplay_ir.get("schema_version", "")) != EXPORT_SCHEMAS.gameplay_ir: return _reject("gameplay_ir_schema")
	if not _validate_gameplay_ir(gameplay_ir, ship, site_ir, request, caps): return false
	if not _validate_presentation(presentation, gameplay_ir, site_ir): return false
	if not _validate_metrics_trace(bundle.get("metrics", null), bundle.get("trace", null), site_ir, ship, gameplay_ir, caps): return false
	if not _validate_adaptive_bundle(bundle.get("trace", null), world, site_ir, gameplay_ir, request): return false
	if not _is_sha256(str(bundle.get("semantic_hash", ""))): return _reject("semantic_hash_shape")
	return true

func _validate_world_ir(world: Dictionary, request: Dictionary) -> bool:
	var site: Dictionary = request.get("site", {})
	if not _same_json(world.get("world_seed", null), request.get("world_seed", null)) \
			or not _same_json(world.get("x", null), site.get("x", null)) \
			or not _same_json(world.get("y", null), site.get("y", null)) \
			or str(world.get("site_id", "")) != str(site.get("site_id", "")) \
			or str(world.get("archetype_id", "")) != str(site.get("archetype_id", "")): return _reject("world_identity")
	for key in ["markers", "anchors", "biome_fields", "hazard_fields", "resource_pressures", "landmarks", "routes"]:
		if not world.get(key, null) is Array: return _reject("world_shape")
	var markers: Array = world.get("markers", [])
	if markers.size() != 9: return _reject("world_markers")
	var offsets: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
		Vector2i(-1, 0), Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1),
		Vector2i(1, 1),
	]
	for index in markers.size():
		var entry: Variant = markers[index]
		if not entry is Dictionary or not _has_exact_keys(entry, ["archetype_id", "marker_id", "selected", "site_id", "site_seed", "x", "y"]): return _reject("world_markers")
		var marker: Dictionary = entry
		var expected_x: int = int(world.get("x", 0)) + offsets[index].x
		var expected_y: int = int(world.get("y", 0)) + offsets[index].y
		var expected_site_id: String = str(world.get("site_id", "")) if index == 0 else "site:%d:%d" % [expected_x, expected_y]
		if str(marker.get("marker_id", "")) != "marker:%d" % index \
				or not _is_valid_world_id(str(marker.get("marker_id", ""))) \
				or not _is_valid_world_id(str(marker.get("site_id", ""))) \
				or not _is_valid_world_id(str(marker.get("archetype_id", ""))) \
				or not SUPPORTED_ARCHETYPES.has(str(marker.get("archetype_id", ""))) \
				or not marker.get("selected", null) is bool \
				or bool(marker.get("selected", false)) != (index == 0) \
				or not _is_bounded_integer(marker.get("site_seed", null), 0, MAX_SAFE_JSON_INTEGER) \
				or not _is_bounded_integer(marker.get("x", null), -2147483648, 2147483647) \
				or not _is_bounded_integer(marker.get("y", null), -2147483648, 2147483647) \
				or int(marker.get("x", 0)) != expected_x or int(marker.get("y", 0)) != expected_y \
				or str(marker.get("site_id", "")) != expected_site_id: return _reject("world_markers")
		if index == 0 and (not _same_json(marker.get("site_seed", null), world.get("site_seed", null)) \
				or str(marker.get("archetype_id", "")) != str(world.get("archetype_id", ""))): return _reject("world_markers")

	var anchors: Array = world.get("anchors", [])
	if anchors.size() != 2 \
			or not _same_json(anchors[0], {"id": "anchor:hub", "kind": "hub"}) \
			or not _same_json(anchors[1], {"id": "anchor:extraction", "kind": "extraction"}): return _reject("world_anchors")

	var biome_fields: Array = world.get("biome_fields", [])
	var hazard_fields: Array = world.get("hazard_fields", [])
	var resource_pressures: Array = world.get("resource_pressures", [])
	var landmarks: Array = world.get("landmarks", [])
	if biome_fields.size() != 9: return _reject("world_biomes")
	if hazard_fields.size() != 9: return _reject("world_hazards")
	if resource_pressures.size() != 9: return _reject("world_resources")
	if landmarks.size() != 9: return _reject("world_landmarks")
	for index in markers.size():
		var marker_id: String = "marker:%d" % index
		var biome: Variant = biome_fields[index]
		if not biome is Dictionary or not _has_exact_keys(biome, ["biome_id", "intensity_bp", "marker_id"]) \
				or str(biome.get("marker_id", "")) != marker_id \
				or not _is_valid_world_id(str(biome.get("biome_id", ""))) \
				or not _is_bounded_integer(biome.get("intensity_bp", null), 0, 10000): return _reject("world_biomes")
		var hazard: Variant = hazard_fields[index]
		if not hazard is Dictionary or not _has_exact_keys(hazard, ["hazard_id", "marker_id", "severity_bp"]) \
				or str(hazard.get("marker_id", "")) != marker_id \
				or not _is_valid_world_id(str(hazard.get("hazard_id", ""))) \
				or not _is_bounded_integer(hazard.get("severity_bp", null), 0, 10000): return _reject("world_hazards")
		var resource: Variant = resource_pressures[index]
		if not resource is Dictionary or not _has_exact_keys(resource, ["marker_id", "pressure_bp", "resource_id"]) \
				or str(resource.get("marker_id", "")) != marker_id \
				or not _is_valid_world_id(str(resource.get("resource_id", ""))) \
				or not _is_bounded_integer(resource.get("pressure_bp", null), 0, 10000): return _reject("world_resources")
		var landmark: Variant = landmarks[index]
		if not landmark is Dictionary or not _has_exact_keys(landmark, ["id", "kind", "marker_id"]) \
				or str(landmark.get("id", "")) != "landmark:%d" % index \
				or str(landmark.get("marker_id", "")) != marker_id \
				or not _is_valid_world_id(str(landmark.get("id", ""))) \
				or not _is_valid_world_id(str(landmark.get("kind", ""))): return _reject("world_landmarks")

	var known_endpoints: Dictionary = {"anchor:hub": true, "anchor:extraction": true}
	for index in markers.size(): known_endpoints["marker:%d" % index] = true
	var routes: Array = world.get("routes", [])
	if routes.size() != 10: return _reject("world_routes")
	var route_keys: Dictionary = {}
	var previous_route_key: String = ""
	for route_value in routes:
		if not route_value is Dictionary or not _has_exact_keys(route_value, ["cost_bp", "from", "to"]): return _reject("world_routes")
		var route: Dictionary = route_value
		var from_id: String = str(route.get("from", ""))
		var to_id: String = str(route.get("to", ""))
		var route_key: String = _world_edge_key(from_id, to_id)
		if not known_endpoints.has(from_id) or not known_endpoints.has(to_id) \
				or from_id >= to_id \
				or not _is_bounded_integer(route.get("cost_bp", null), 1, 10000) \
				or route_keys.has(route_key) \
				or (not previous_route_key.is_empty() and previous_route_key >= route_key): return _reject("world_routes")
		route_keys[route_key] = true
		previous_route_key = route_key
	var extraction: Variant = world.get("extraction", null)
	if not extraction is Dictionary or not _has_exact_keys(extraction, ["extraction_anchor_id", "hub_anchor_id", "path", "selected_marker_id"]) \
			or str(extraction.get("selected_marker_id", "")) != "marker:0" \
			or str(extraction.get("hub_anchor_id", "")) != "anchor:hub" \
			or str(extraction.get("extraction_anchor_id", "")) != "anchor:extraction" \
			or not _same_json(extraction.get("path", null), ["marker:0", "anchor:hub", "anchor:extraction"]): return _reject("world_extraction")
	var path: Array = extraction.get("path", [])
	for index in range(path.size() - 1):
		if not route_keys.has(_world_edge_key(str(path[index]), str(path[index + 1]))): return _reject("world_extraction")
	return true

func _world_edge_key(left: String, right: String) -> String:
	return left + "\u001f" + right if left < right else right + "\u001f" + left

func _is_valid_world_id(value: String) -> bool:
	if value.is_empty() or value.length() > 64: return false
	for code in value.to_ascii_buffer():
		if not ((code >= 97 and code <= 122) or (code >= 48 and code <= 57) \
				or code == 58 or code == 95 or code == 45 or code == 46): return false
	return true

func _is_locale(value: String) -> bool:
	var parts: PackedStringArray = value.split("-", false)
	if parts.is_empty() or parts[0].length() < 2 or parts[0].length() > 3:
		return false
	for code in parts[0].to_ascii_buffer():
		if not ((code >= 65 and code <= 90) or (code >= 97 and code <= 122)): return false
	for index in range(1, parts.size()):
		var part: String = parts[index]
		if part.length() < 2 or part.length() > 8: return false
		for code in part.to_ascii_buffer():
			if not ((code >= 65 and code <= 90) or (code >= 97 and code <= 122) or (code >= 48 and code <= 57)):
				return false
	return true

func _validate_site_overlay(site: Dictionary, ship: Dictionary) -> bool:
	var room_cells: Dictionary = _room_cell_sets(ship)
	if room_cells.is_empty(): return _reject("site_rooms")
	var navigation_edges: Dictionary = {}
	var gate_edges: Dictionary = {}
	if not _validate_site_navigation(site.get("navigation", null), ship, room_cells, navigation_edges, gate_edges): return false
	var mission_nodes: Dictionary = {}
	var mission_adjacency: Dictionary = {}
	if not _validate_site_mission(site.get("mission_graph", null), room_cells, navigation_edges, gate_edges, mission_nodes, mission_adjacency): return false
	if not _validate_functional_props(site.get("functional_props", null), ship, room_cells, mission_nodes): return false
	if not _validate_spatial_annotations(site.get("spatial_annotations", null), room_cells): return false
	return true

func _room_cell_sets(ship: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for room_value in (ship.get("topology", {}) as Dictionary).get("rooms", []):
		if not room_value is Dictionary: return {}
		var room: Dictionary = room_value
		var room_id: int = int(room.get("id", -1))
		var cells: Dictionary = {}
		for cell_value in room.get("cells", []):
			if not _validate_cell(cell_value): return {}
			var key: String = _cell_identity(cell_value as Dictionary)
			if cells.has(key): return {}
			cells[key] = true
		if cells.is_empty() or result.has(room_id): return {}
		result[room_id] = cells
	return result

func _validate_site_navigation(
		value: Variant,
		ship: Dictionary,
		room_cells: Dictionary,
		edge_index: Dictionary,
		gate_edges: Dictionary) -> bool:
	if not value is Dictionary: return _reject("site_navigation_shape")
	var navigation: Dictionary = value
	if not _has_exact_keys(navigation, ["schema_version", "nodes", "edges"]) \
			or str(navigation.get("schema_version", "")) != "site-navigation-1" \
			or not navigation.get("nodes", null) is Array \
			or not navigation.get("edges", null) is Array: return _reject("site_navigation_shape")
	var seen_rooms: Dictionary = {}
	var previous_room: int = -1
	for node_value in navigation.get("nodes", []):
		if not node_value is Dictionary or not _has_exact_keys(node_value, ["room"]) \
				or not _is_bounded_integer((node_value as Dictionary).get("room", null), 0, 65535): return _reject("site_navigation_nodes")
		var room_id: int = int((node_value as Dictionary).get("room", -1))
		if not room_cells.has(room_id) or seen_rooms.has(room_id) or (previous_room >= 0 and room_id <= previous_room): return _reject("site_navigation_nodes")
		seen_rooms[room_id] = true
		previous_room = room_id
	if seen_rooms.size() != room_cells.size(): return _reject("site_navigation_nodes")
	var structural_refs: Dictionary = _site_structural_refs(ship)
	if structural_refs.is_empty() and not (navigation.get("edges", []) as Array).is_empty(): return _reject("site_navigation_projection")
	var ref_edges: Dictionary = {}
	var previous_id: String = ""
	for edge_value in navigation.get("edges", []):
		if not edge_value is Dictionary: return _reject("site_navigation_edges")
		var edge: Dictionary = edge_value
		var fields: Array[String] = ["id", "structural_ref", "from_room", "to_room", "from_cell", "to_cell", "kind", "cost", "clearance", "gate_id", "passable"]
		if not _has_exact_keys(edge, fields): return _reject("site_navigation_edges")
		var edge_id: String = str(edge.get("id", ""))
		var reference: String = str(edge.get("structural_ref", ""))
		var kind: String = str(edge.get("kind", ""))
		var from_room: int = int(edge.get("from_room", -1))
		var to_room: int = int(edge.get("to_room", -1))
		if edge_id.is_empty() or reference.is_empty() or edge_index.has(edge_id) \
				or (not previous_id.is_empty() and edge_id <= previous_id) \
				or not NAVIGATION_KINDS.has(kind) \
				or not _is_bounded_integer(edge.get("from_room", null), 0, 65535) \
				or not _is_bounded_integer(edge.get("to_room", null), 0, 65535) \
				or from_room == to_room or not room_cells.has(from_room) or not room_cells.has(to_room) \
				or not _cell_belongs(edge.get("from_cell", null), from_room, room_cells) \
				or not _cell_belongs(edge.get("to_cell", null), to_room, room_cells) \
				or not _is_bounded_integer(edge.get("cost", null), 1, 4294967295) \
				or not _is_bounded_integer(edge.get("clearance", null), 1, 65535) \
				or int(edge.get("clearance", 0)) != 1 \
				or edge.get("passable", null) is not bool: return _reject("site_navigation_edges")
		if kind == "portal" and (int(edge.get("cost", 0)) != 1000 or not _are_cardinal_neighbors(edge.from_cell, edge.to_cell)): return _reject("site_navigation_projection")
		if kind == "vertical" and (int(edge.get("cost", 0)) != 1500 or int((edge.from_cell as Dictionary).get("deck", -1)) == int((edge.to_cell as Dictionary).get("deck", -1))): return _reject("site_navigation_projection")
		if not structural_refs.has(reference) or str(structural_refs[reference]) != kind: return _reject("site_navigation_projection")
		var expected_id: String = "portal:%s:%d:%d" % [reference, from_room, to_room] if kind == "portal" else "%s:%d:%d" % [reference, from_room, to_room]
		if edge_id != expected_id: return _reject("site_navigation_projection")
		var gate_id: Variant = edge.get("gate_id", null)
		if gate_id != null and (not gate_id is String or str(gate_id).is_empty()): return _reject("site_navigation_gate")
		if bool(edge.get("passable", false)) != (gate_id == null): return _reject("site_navigation_gate")
		edge_index[edge_id] = edge
		if not ref_edges.has(reference): ref_edges[reference] = []
		(ref_edges[reference] as Array).append(edge)
		if gate_id != null:
			if not gate_edges.has(str(gate_id)): gate_edges[str(gate_id)] = []
			(gate_edges[str(gate_id)] as Array).append(edge)
		previous_id = edge_id
	if ref_edges.size() != structural_refs.size(): return _reject("site_navigation_projection")
	for reference in ref_edges.keys():
		var pair: Array = ref_edges[reference]
		if pair.size() != 2: return _reject("site_navigation_projection")
		var left: Dictionary = pair[0]
		var right: Dictionary = pair[1]
		if int(left.from_room) != int(right.to_room) or int(left.to_room) != int(right.from_room) \
				or not _same_json(left.from_cell, right.to_cell) or not _same_json(left.to_cell, right.from_cell) \
				or str(left.kind) != str(right.kind) or int(left.cost) != int(right.cost) \
				or not _same_json(left.get("gate_id", null), right.get("gate_id", null)) \
				or bool(left.passable) != bool(right.passable): return _reject("site_navigation_projection")
	return true

func _site_structural_refs(ship: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var topology: Dictionary = ship.get("topology", {})
	for portal_value in topology.get("portals", []):
		if not portal_value is Dictionary: return {}
		var portal: Dictionary = portal_value
		if bool(portal.get("exterior", false)): continue
		var reference: String = _portal_edge_key(portal.get("from_cell", {}), portal.get("to_cell", {}))
		if reference.is_empty() or result.has(reference): return {}
		result[reference] = "portal"
	for vertical_value in topology.get("verticals", []):
		if not vertical_value is Dictionary: return {}
		var vertical: Dictionary = vertical_value
		var reference: String = _vertical_ref(vertical)
		if reference.is_empty() or result.has(reference): return {}
		result[reference] = "vertical"
	return result

func _portal_edge_key(from_value: Variant, to_value: Variant) -> String:
	if not _validate_cell(from_value) or not _validate_cell(to_value): return ""
	var from_cell: Dictionary = from_value
	var to_cell: Dictionary = to_value
	if not _are_cardinal_neighbors(from_cell, to_cell): return ""
	var deck: int = int(from_cell.get("deck", 0))
	var x: int = int(from_cell.get("x", 0))
	var y: int = int(from_cell.get("y", 0))
	var dx: int = int(to_cell.get("x", 0)) - x
	var dy: int = int(to_cell.get("y", 0)) - y
	if dy < 0: return "%d|h|%d|%d" % [deck, y - 1, x]
	if dy > 0: return "%d|h|%d|%d" % [deck, y, x]
	if dx > 0: return "%d|v|%d|%d" % [deck, y, x]
	return "%d|v|%d|%d" % [deck, y, x - 1]

func _vertical_ref(vertical: Dictionary) -> String:
	if not _validate_cell(vertical.get("from_cell", null)) or not _validate_cell(vertical.get("to_cell", null)): return ""
	var from_cell: Dictionary = vertical.get("from_cell", {})
	var to_cell: Dictionary = vertical.get("to_cell", {})
	var left: String = "%d|%d|%d|%d" % [int(from_cell.deck), int(from_cell.x), int(from_cell.y), int(vertical.get("from_room", -1))]
	var right: String = "%d|%d|%d|%d" % [int(to_cell.deck), int(to_cell.x), int(to_cell.y), int(vertical.get("to_room", -1))]
	return "vertical:%s:%s" % [left, right] if left <= right else "vertical:%s:%s" % [right, left]

func _validate_site_mission(
		value: Variant,
		room_cells: Dictionary,
		navigation_edges: Dictionary,
		gate_edges: Dictionary,
		node_index: Dictionary,
		adjacency: Dictionary) -> bool:
	if not value is Dictionary: return _reject("site_mission_shape")
	var mission: Dictionary = value
	var fields: Array[String] = ["schema_version", "mission_id", "start_node", "required_objectives", "extraction_node", "nodes", "edges", "gates"]
	if not _has_exact_keys(mission, fields) or str(mission.get("schema_version", "")) != "site-mission-1" \
			or str(mission.get("mission_id", "")).is_empty() \
			or not mission.get("required_objectives", null) is Array \
			or not mission.get("nodes", null) is Array \
			or not mission.get("edges", null) is Array \
			or not mission.get("gates", null) is Array: return _reject("site_mission_shape")
	var nodes: Array = mission.get("nodes", [])
	var edges: Array = mission.get("edges", [])
	var gates: Array = mission.get("gates", [])
	var required: Array = mission.get("required_objectives", [])
	if nodes.size() < 3 or nodes.size() > 64 or edges.size() > 128 or gates.size() > 32 \
			or required.is_empty() or required.size() > 16: return _reject("site_mission_bounds")
	var kind_counts: Dictionary = {}
	for node_value in nodes:
		if not node_value is Dictionary: return _reject("site_mission_nodes")
		var node: Dictionary = node_value
		if not _has_exact_keys(node, ["id", "kind", "room", "cell", "key_id", "repair_id"]): return _reject("site_mission_nodes")
		var node_id: String = str(node.get("id", ""))
		var kind: String = str(node.get("kind", ""))
		var room_id: int = int(node.get("room", -1))
		if node_id.is_empty() or node_index.has(node_id) or not MISSION_NODE_KINDS.has(kind) \
				or not _is_bounded_integer(node.get("room", null), 0, 65535) \
				or not _cell_belongs(node.get("cell", null), room_id, room_cells) \
				or not _optional_nonempty_string(node.get("key_id", null)) \
				or not _optional_nonempty_string(node.get("repair_id", null)): return _reject("site_mission_nodes")
		if kind == "acquire_key" and (node.get("key_id", null) == null or node.get("repair_id", null) != null): return _reject("site_mission_nodes")
		if kind == "repair" and (node.get("repair_id", null) == null or node.get("key_id", null) != null): return _reject("site_mission_nodes")
		if kind in ["start", "objective", "extraction"] and (node.get("key_id", null) != null or node.get("repair_id", null) != null): return _reject("site_mission_nodes")
		node_index[node_id] = node
		adjacency[node_id] = []
		kind_counts[kind] = int(kind_counts.get(kind, 0)) + 1
	var start_id: String = str(mission.get("start_node", ""))
	var extraction_id: String = str(mission.get("extraction_node", ""))
	if int(kind_counts.get("start", 0)) != 1 or int(kind_counts.get("extraction", 0)) != 1 \
			or int(kind_counts.get("objective", 0)) != required.size() \
			or not node_index.has(start_id) or str((node_index[start_id] as Dictionary).kind) != "start" \
			or not node_index.has(extraction_id) or str((node_index[extraction_id] as Dictionary).kind) != "extraction" \
			or str((nodes[0] as Dictionary).id) != start_id or str((nodes[-1] as Dictionary).id) != extraction_id: return _reject("site_mission_identity")
	var required_seen: Dictionary = {}
	for objective_value in required:
		if not objective_value is String: return _reject("site_mission_objectives")
		var objective_id: String = str(objective_value)
		if objective_id.is_empty() or required_seen.has(objective_id) or not node_index.has(objective_id) \
				or str((node_index[objective_id] as Dictionary).kind) != "objective": return _reject("site_mission_objectives")
		required_seen[objective_id] = true
	var indegree: Dictionary = {}
	for node_id in node_index.keys(): indegree[node_id] = 0
	var edge_seen: Dictionary = {}
	for edge_value in edges:
		if not edge_value is Dictionary or not _has_exact_keys(edge_value, ["from", "to"]): return _reject("site_mission_edges")
		var edge: Dictionary = edge_value
		var from_id: String = str(edge.get("from", ""))
		var to_id: String = str(edge.get("to", ""))
		var edge_key: String = "%s\u001f%s" % [from_id, to_id]
		if from_id == to_id or not node_index.has(from_id) or not node_index.has(to_id) or edge_seen.has(edge_key): return _reject("site_mission_edges")
		edge_seen[edge_key] = true
		(adjacency[from_id] as Array).append(to_id)
		indegree[to_id] = int(indegree[to_id]) + 1
	if int(indegree.get(start_id, -1)) != 0 or not (adjacency[extraction_id] as Array).is_empty(): return _reject("site_mission_edges")
	if not _mission_graph_is_acyclic(node_index, adjacency, indegree): return _reject("site_mission_cycle")
	for node_id in node_index.keys():
		if node_id != start_id and not _mission_reaches(adjacency, start_id, str(node_id)): return _reject("site_mission_reachability")
	var checkpoint: String = start_id
	for objective_value in required:
		if not _mission_reaches(adjacency, checkpoint, str(objective_value)): return _reject("site_mission_order")
		checkpoint = str(objective_value)
	if not _mission_reaches(adjacency, checkpoint, extraction_id): return _reject("site_mission_order")
	var gate_index: Dictionary = {}
	for gate_value in gates:
		if not gate_value is Dictionary: return _reject("site_mission_gates")
		var gate: Dictionary = gate_value
		if not _has_exact_keys(gate, ["id", "kind", "navigation_edge", "prerequisite_node", "unlock_node", "key_id", "repair_id"]): return _reject("site_mission_gates")
		var gate_id: String = str(gate.get("id", ""))
		var gate_kind: String = str(gate.get("kind", ""))
		var prerequisite: String = str(gate.get("prerequisite_node", ""))
		var unlock: String = str(gate.get("unlock_node", ""))
		if gate_id.is_empty() or gate_index.has(gate_id) or not MISSION_GATE_KINDS.has(gate_kind) \
				or not navigation_edges.has(str(gate.get("navigation_edge", ""))) \
				or prerequisite == unlock or not node_index.has(prerequisite) or not node_index.has(unlock) \
				or not _mission_reaches(adjacency, prerequisite, unlock) \
				or not gate_edges.has(gate_id) or (gate_edges[gate_id] as Array).size() != 2: return _reject("site_mission_gates")
		var bound: Array = gate_edges[gate_id]
		if str((bound[0] as Dictionary).structural_ref) != str((bound[1] as Dictionary).structural_ref) \
				or not (bound as Array).any(func(edge: Dictionary) -> bool: return str(edge.id) == str(gate.navigation_edge)): return _reject("site_mission_gates")
		var prerequisite_node: Dictionary = node_index[prerequisite]
		if gate_kind == "key_lock":
			if str(prerequisite_node.kind) != "acquire_key" or gate.get("key_id", null) == null \
					or str(gate.get("key_id", "")) != str(prerequisite_node.get("key_id", "")) \
					or gate.get("repair_id", null) != null: return _reject("site_mission_gates")
		else:
			if str(prerequisite_node.kind) != "repair" or gate.get("repair_id", null) == null \
					or str(gate.get("repair_id", "")) != str(prerequisite_node.get("repair_id", "")) \
					or gate.get("key_id", null) != null: return _reject("site_mission_gates")
		gate_index[gate_id] = true
	if gate_index.size() != gate_edges.size(): return _reject("site_mission_gates")
	return true

func _mission_graph_is_acyclic(nodes: Dictionary, adjacency: Dictionary, indegree_source: Dictionary) -> bool:
	var indegree: Dictionary = indegree_source.duplicate()
	var queue: Array[String] = []
	for node_id in nodes.keys():
		if int(indegree.get(node_id, 0)) == 0: queue.append(str(node_id))
	var visited: int = 0
	while not queue.is_empty():
		var node_id: String = queue.pop_front()
		visited += 1
		for target in adjacency.get(node_id, []):
			indegree[target] = int(indegree[target]) - 1
			if int(indegree[target]) == 0: queue.append(str(target))
	return visited == nodes.size()

func _mission_reaches(adjacency: Dictionary, from_id: String, to_id: String) -> bool:
	if from_id == to_id: return true
	var reached: Dictionary = {from_id: true}
	var queue: Array[String] = [from_id]
	while not queue.is_empty():
		var current: String = queue.pop_front()
		for target_value in adjacency.get(current, []):
			var target: String = str(target_value)
			if target == to_id: return true
			if not reached.has(target):
				reached[target] = true
				queue.append(target)
	return false

func _validate_functional_props(value: Variant, ship: Dictionary, room_cells: Dictionary, nodes: Dictionary) -> bool:
	if not value is Array or (value as Array).size() > 64: return _reject("site_prop_shape")
	var props: Array = value
	var prop_ids: Dictionary = {}
	var node_props: Dictionary = {}
	var used_cells: Dictionary = {}
	var extraction_count: int = 0
	for prop_value in props:
		if not prop_value is Dictionary: return _reject("site_prop_shape")
		var prop: Dictionary = prop_value
		if not _has_exact_keys(prop, ["id", "kind", "room", "anchor", "approach", "mission_node_id", "key_id", "repair_id", "extraction_portal_ref"]): return _reject("site_prop_shape")
		var prop_id: String = str(prop.get("id", ""))
		var kind: String = str(prop.get("kind", ""))
		var room_id: int = int(prop.get("room", -1))
		var node_id: String = str(prop.get("mission_node_id", ""))
		if prop_id.is_empty() or prop_ids.has(prop_id) or not FUNCTIONAL_PROP_KINDS.has(kind) \
				or not _is_bounded_integer(prop.get("room", null), 0, 65535) \
				or not _cell_belongs(prop.get("anchor", null), room_id, room_cells) \
				or not _cell_belongs(prop.get("approach", null), room_id, room_cells) \
				or not _are_cardinal_neighbors(prop.anchor, prop.approach) \
				or node_id.is_empty() or not nodes.has(node_id) or node_props.has(node_id) \
				or not _optional_nonempty_string(prop.get("key_id", null)) \
				or not _optional_nonempty_string(prop.get("repair_id", null)) \
				or not _optional_nonempty_string(prop.get("extraction_portal_ref", null)): return _reject("site_prop_shape")
		var anchor_key: String = _cell_identity(prop.anchor)
		var approach_key: String = _cell_identity(prop.approach)
		if used_cells.has(anchor_key) or used_cells.has(approach_key): return _reject("site_prop_overlap")
		used_cells[anchor_key] = true
		used_cells[approach_key] = true
		var node: Dictionary = nodes[node_id]
		if int(node.room) != room_id or not _same_json(node.cell, prop.anchor): return _reject("site_prop_binding")
		if kind == "key_pickup":
			if str(node.kind) != "acquire_key" or prop.get("key_id", null) == null or str(prop.key_id) != str(node.get("key_id", "")) \
					or prop.get("repair_id", null) != null or prop.get("extraction_portal_ref", null) != null: return _reject("site_prop_binding")
		elif kind == "repair_panel":
			if str(node.kind) != "repair" or prop.get("repair_id", null) == null or str(prop.repair_id) != str(node.get("repair_id", "")) \
					or prop.get("key_id", null) != null or prop.get("extraction_portal_ref", null) != null: return _reject("site_prop_binding")
		elif kind == "objective_console":
			if str(node.kind) != "objective" or prop.get("key_id", null) != null or prop.get("repair_id", null) != null \
					or prop.get("extraction_portal_ref", null) != null: return _reject("site_prop_binding")
		else:
			extraction_count += 1
			if str(node.kind) != "extraction" or prop.get("key_id", null) != null or prop.get("repair_id", null) != null \
					or prop.get("extraction_portal_ref", null) == null: return _reject("site_prop_binding")
			if not _validate_extraction_ref(ship, room_id, str(prop.extraction_portal_ref)): return _reject("site_prop_extraction")
		prop_ids[prop_id] = true
		node_props[node_id] = true
	if extraction_count != 1: return _reject("site_prop_extraction")
	for node_id in nodes.keys():
		var node_kind: String = str((nodes[node_id] as Dictionary).kind)
		var required: bool = node_kind in ["acquire_key", "repair", "objective", "extraction"]
		if node_props.has(node_id) != required: return _reject("site_prop_coverage")
	return true

func _validate_extraction_ref(ship: Dictionary, room_id: int, expected_ref: String) -> bool:
	if room_id != int(ship.get("entry_room", -1)): return false
	var matches: Array[String] = []
	for portal_value in (ship.get("topology", {}) as Dictionary).get("portals", []):
		if not portal_value is Dictionary: return false
		var portal: Dictionary = portal_value
		if int(portal.get("from_room", -1)) == room_id and int(portal.get("to_room", -1)) == 0 \
				and bool(portal.get("exterior", false)) and str(portal.get("state", "")) == "Door":
			matches.append(_portal_edge_key(portal.get("from_cell", {}), portal.get("to_cell", {})))
	return matches.size() == 1 and matches[0] == expected_ref

func _validate_spatial_annotations(value: Variant, room_cells: Dictionary) -> bool:
	if not value is Dictionary: return _reject("site_spatial_shape")
	var spatial: Dictionary = value
	if not _has_exact_keys(spatial, ["schema_version", "rooms"]) \
			or str(spatial.get("schema_version", "")) != "site-spatial-1" \
			or not spatial.get("rooms", null) is Array: return _reject("site_spatial_shape")
	var seen_rooms: Dictionary = {}
	for annotation_value in spatial.get("rooms", []):
		if not annotation_value is Dictionary: return _reject("site_spatial_shape")
		var annotation: Dictionary = annotation_value
		if not _has_exact_keys(annotation, ["room", "minimum_clearance", "cover_cells", "los_pairs"]) \
				or not _is_bounded_integer(annotation.get("room", null), 0, 65535) \
				or not _is_bounded_integer(annotation.get("minimum_clearance", null), 1, 65535) \
				or int(annotation.get("minimum_clearance", 0)) != 1 \
				or not annotation.get("cover_cells", null) is Array \
				or not annotation.get("los_pairs", null) is Array \
				or (annotation.get("cover_cells", []) as Array).size() > 64 \
				or (annotation.get("los_pairs", []) as Array).size() > 128: return _reject("site_spatial_shape")
		var room_id: int = int(annotation.get("room", -1))
		if not room_cells.has(room_id) or seen_rooms.has(room_id): return _reject("site_spatial_rooms")
		seen_rooms[room_id] = true
		var cover_seen: Dictionary = {}
		for cell_value in annotation.get("cover_cells", []):
			if not _cell_belongs(cell_value, room_id, room_cells): return _reject("site_spatial_cover")
			var cell_key: String = _cell_identity(cell_value as Dictionary)
			if cover_seen.has(cell_key): return _reject("site_spatial_cover")
			cover_seen[cell_key] = true
		var pair_seen: Dictionary = {}
		for pair_value in annotation.get("los_pairs", []):
			if not pair_value is Dictionary or not _has_exact_keys(pair_value, ["a", "b"]): return _reject("site_spatial_los")
			var pair: Dictionary = pair_value
			if not _cell_belongs(pair.get("a", null), room_id, room_cells) or not _cell_belongs(pair.get("b", null), room_id, room_cells): return _reject("site_spatial_los")
			var a: Dictionary = pair.a
			var b: Dictionary = pair.b
			var distance: int = absi(int(a.x) - int(b.x)) + absi(int(a.y) - int(b.y))
			var pair_key: String = "%s\u001f%s" % [_cell_identity(a), _cell_identity(b)]
			if _same_json(a, b) or int(a.deck) != int(b.deck) or (int(a.x) != int(b.x) and int(a.y) != int(b.y)) \
					or distance < 1 or distance > 8 or pair_seen.has(pair_key): return _reject("site_spatial_los")
			pair_seen[pair_key] = true
	if seen_rooms.size() != room_cells.size(): return _reject("site_spatial_rooms")
	return true

func _cell_belongs(value: Variant, room_id: int, room_cells: Dictionary) -> bool:
	return _validate_cell(value) and room_cells.has(room_id) \
			and (room_cells[room_id] as Dictionary).has(_cell_identity(value as Dictionary))

func _optional_nonempty_string(value: Variant) -> bool:
	return value == null or (value is String and not str(value).is_empty())

func _validate_ship_shape(ship: Dictionary) -> bool:
	if not _has_exact_keys(ship, SHIP_FIELDS): return _reject("ship_shape")
	if not _is_bounded_integer(ship.get("generator_version", null), 0, 4294967295) \
			or not _is_bounded_integer(ship.get("seed", null), 0, MAX_SAFE_JSON_INTEGER) \
			or not _is_bounded_integer(ship.get("intactness", null), 0, 10000) \
			or not _is_bounded_integer(ship.get("entry_room", null), 0, 65535) \
			or not _is_bounded_integer(ship.get("goal_room", null), 0, 65535): return _reject("ship_shape")
	for key in ["archetype_id", "template_id"]:
		if not ship.get(key, null) is String or str(ship.get(key, "")).is_empty(): return _reject("ship_shape")
	if not ship.get("cause_of_loss", null) is String \
			or not CAUSES_OF_LOSS.has(str(ship.get("cause_of_loss", ""))): return _reject("ship_shape")
	if ship.get("fractured", null) is not bool: return _reject("ship_shape")
	for key in ["critical_path", "decks", "entities", "damage_events", "fragments"]:
		if not ship.get(key, null) is Array: return _reject("ship_shape")
	var topology: Variant = ship.get("topology", null)
	if not topology is Dictionary or not _has_exact_keys(topology, ["rooms", "portals", "verticals"]): return _reject("topology_shape")
	for key in ["rooms", "portals", "verticals"]:
		if not (topology as Dictionary).get(key, null) is Array: return _reject("topology_shape")
	var room_ids: Dictionary = {}
	if not _validate_topology(topology as Dictionary, room_ids): return _reject("ship_topology_shape")
	if not room_ids.has(int(ship.get("entry_room", -1))) or not room_ids.has(int(ship.get("goal_room", -1))): return _reject("ship_path_shape")
	var critical_path: Array = ship.get("critical_path", [])
	if critical_path.is_empty() or int(critical_path[0]) != int(ship.get("entry_room", -1)) \
			or int(critical_path[-1]) != int(ship.get("goal_room", -1)): return _reject("ship_path_shape")
	var path_rooms: Dictionary = {}
	for room_id in ship.get("critical_path", []):
		if not _is_bounded_integer(room_id, 0, 65535) or not room_ids.has(int(room_id)) \
				or path_rooms.has(int(room_id)): return _reject("ship_path_shape")
		path_rooms[int(room_id)] = true
	var plan: Variant = ship.get("plan", null)
	if not plan is Dictionary or not _has_exact_keys(plan, ["occupancy", "edges", "placements", "floor_placements", "ceiling_placements", "socket_bindings", "errors"]): return _reject("structural_plan_shape")
	for key in ["occupancy", "edges"]:
		if not (plan as Dictionary).get(key, null) is Dictionary: return _reject("structural_plan_shape")
	for key in ["placements", "floor_placements", "ceiling_placements", "socket_bindings", "errors"]:
		if not (plan as Dictionary).get(key, null) is Array: return _reject("structural_plan_shape")
	if not _validate_structural_plan(plan as Dictionary, room_ids): return _reject("ship_plan_shape")
	var graph: Variant = ship.get("room_graph", null)
	if not graph is Dictionary or not _has_exact_keys(graph, ["nodes", "edges"]): return _reject("room_graph_shape")
	if not (graph as Dictionary).get("nodes", null) is Array or not (graph as Dictionary).get("edges", null) is Array: return _reject("room_graph_shape")
	return true

func _validate_topology(topology: Dictionary, room_ids: Dictionary) -> bool:
	for room_value in topology.get("rooms", []):
		if not room_value is Dictionary: return false
		var room: Dictionary = room_value
		if not _has_exact_keys(room, ["id", "role", "deck", "cells"]) \
				or not _is_bounded_integer(room.get("id", null), 0, 65535) \
				or not ROOM_ROLES.has(str(room.get("role", ""))) \
				or not _is_bounded_integer(room.get("deck", null), 0, 255) \
				or not room.get("cells", null) is Array \
				or (room.get("cells", []) as Array).is_empty(): return false
		var room_id: int = int(room.get("id", -1))
		if room_ids.has(room_id): return false
		room_ids[room_id] = true
		for cell in room.get("cells", []):
			if not _validate_cell(cell) or int((cell as Dictionary).get("deck", -1)) != int(room.get("deck", -2)): return false
	for portal_value in topology.get("portals", []):
		if not portal_value is Dictionary: return false
		var portal: Dictionary = portal_value
		if not _has_exact_keys(portal, ["from_room", "to_room", "from_cell", "to_cell", "state", "exterior"]) \
				or not _is_bounded_integer(portal.get("from_room", null), 0, 65535) \
				or not _is_bounded_integer(portal.get("to_room", null), 0, 65535) \
				or not _validate_cell(portal.get("from_cell", null)) \
				or not _validate_cell(portal.get("to_cell", null)) \
				or not EDGE_KINDS.has(str(portal.get("state", ""))) \
				or portal.get("exterior", null) is not bool: return false
		if not room_ids.has(int(portal.get("from_room", -1))): return false
		if not bool(portal.get("exterior", false)) and not room_ids.has(int(portal.get("to_room", -1))): return false
		if not _are_cardinal_neighbors(portal.from_cell, portal.to_cell): return false
	for vertical_value in topology.get("verticals", []):
		if not vertical_value is Dictionary: return false
		var vertical: Dictionary = vertical_value
		if not _has_exact_keys(vertical, ["from_room", "to_room", "from_cell", "to_cell"]) \
				or not _is_bounded_integer(vertical.get("from_room", null), 0, 65535) \
				or not _is_bounded_integer(vertical.get("to_room", null), 0, 65535) \
				or not room_ids.has(int(vertical.get("from_room", -1))) \
				or not room_ids.has(int(vertical.get("to_room", -1))) \
				or not _validate_cell(vertical.get("from_cell", null)) \
				or not _validate_cell(vertical.get("to_cell", null)): return false
	return not room_ids.is_empty()

func _validate_structural_plan(plan: Dictionary, room_ids: Dictionary) -> bool:
	var occupancy: Dictionary = plan.get("occupancy", {})
	for key in occupancy.keys():
		var record: Variant = occupancy[key]
		if not key is String or str(key).is_empty() or not _validate_cell_record(record, room_ids): return false
		if str(key) != _cell_identity((record as Dictionary).get("cell", {})): return false
	var edges: Dictionary = plan.get("edges", {})
	for key in edges.keys():
		var edge: Variant = edges[key]
		if not key is String or str(key).is_empty() or not _validate_edge_record(edge): return false
		if str(key) != str((edge as Dictionary).get("edge_key", "")): return false
	for edge in plan.get("placements", []):
		if not _validate_edge_record(edge): return false
	for placement in plan.get("floor_placements", []):
		if not _validate_floor_placement(placement, room_ids): return false
	for placement in plan.get("ceiling_placements", []):
		if not _validate_floor_placement(placement, room_ids): return false
	for binding in plan.get("socket_bindings", []):
		if not _validate_socket_binding(binding): return false
	for error in plan.get("errors", []):
		if not error is String or str(error).is_empty(): return false
	return (plan.get("errors", []) as Array).is_empty()

func _validate_cell_record(value: Variant, room_ids: Dictionary) -> bool:
	if not value is Dictionary: return false
	var record: Dictionary = value
	return _has_exact_keys(record, ["cell", "room_id", "module_id", "decal", "variant"]) \
			and _validate_cell(record.get("cell", null)) \
			and _is_bounded_integer(record.get("room_id", null), 0, 65535) \
			and room_ids.has(int(record.get("room_id", -1))) \
			and record.get("module_id", null) is String and not str(record.get("module_id", "")).is_empty() \
			and _is_bounded_integer(record.get("decal", null), 0, 255) \
			and DAMAGE_VARIANTS.has(str(record.get("variant", "")))

func _validate_edge_record(value: Variant) -> bool:
	if not value is Dictionary: return false
	var edge: Dictionary = value
	var keys: Array[String] = [
		"edge_key", "kind", "module_id", "variant", "position", "yaw_degrees", "cell",
		"direction", "room_ids", "source_cells", "portal", "exterior", "wrapper_required",
	]
	if not _has_exact_keys(edge, keys) or str(edge.get("edge_key", "")).is_empty() \
			or not EDGE_KINDS.has(str(edge.get("kind", ""))) \
			or not edge.get("module_id", null) is String \
			or not DAMAGE_VARIANTS.has(str(edge.get("variant", ""))) \
			or not _validate_number_array(edge.get("position", null), 3, false, 0, 0) \
			or not _is_bounded_integer(edge.get("yaw_degrees", null), 0, 65535) \
			or not _validate_cell(edge.get("cell", null)) \
			or not DIRECTIONS.has(str(edge.get("direction", ""))) \
			or not _validate_number_array(edge.get("room_ids", null), 2, true, 0, 65535) \
			or not edge.get("source_cells", null) is Array or (edge.get("source_cells", []) as Array).size() != 2 \
			or edge.get("portal", null) is not bool or edge.get("exterior", null) is not bool \
			or edge.get("wrapper_required", null) is not bool: return false
	for cell in edge.get("source_cells", []):
		if not _validate_cell(cell): return false
	return true

func _validate_floor_placement(value: Variant, room_ids: Dictionary) -> bool:
	if not value is Dictionary: return false
	var placement: Dictionary = value
	return _has_exact_keys(placement, ["id", "cell", "cell_key", "room_id", "module_id", "position", "yaw_degrees", "variant"]) \
			and placement.get("id", null) is String and not str(placement.get("id", "")).is_empty() \
			and _validate_cell(placement.get("cell", null)) \
			and placement.get("cell_key", null) is String \
			and str(placement.get("cell_key", "")) == _cell_identity(placement.get("cell", {})) \
			and _is_bounded_integer(placement.get("room_id", null), 0, 65535) \
			and room_ids.has(int(placement.get("room_id", -1))) \
			and placement.get("module_id", null) is String and not str(placement.get("module_id", "")).is_empty() \
			and _validate_number_array(placement.get("position", null), 3, false, 0, 0) \
			and _is_bounded_integer(placement.get("yaw_degrees", null), 0, 65535) \
			and DAMAGE_VARIANTS.has(str(placement.get("variant", "")))

func _validate_socket_binding(value: Variant) -> bool:
	if not value is Dictionary: return false
	var binding: Dictionary = value
	if not _has_exact_keys(binding, ["placement_id", "socket_id", "neighbor_placement_id", "neighbor_socket_id", "kind"]): return false
	for key in binding.keys():
		if not binding[key] is String or str(binding[key]).is_empty(): return false
	return true

func _validate_gameplay_ir(gameplay: Dictionary, ship: Dictionary, site_ir: Dictionary, request: Dictionary, caps: Dictionary) -> bool:
	if not _has_exact_keys(gameplay, ["schema_version", "legacy_slice", "creature_blueprints", "encounter", "items", "drops", "decisions"]): return _reject("gameplay_shape")
	if not _validate_gameplay(gameplay.get("legacy_slice", null), ship): return false
	var blueprints: Variant = gameplay.get("creature_blueprints", null)
	if not blueprints is Array or (blueprints as Array).size() != 3: return _reject("creature_blueprints")
	var blueprint_ids: Dictionary = {}
	var previous_blueprint_id: String = ""
	for value in blueprints:
		if not value is Dictionary or not _validate_creature_blueprint(value): return _reject("creature_blueprints")
		var id: String = str((value as Dictionary).get("id", ""))
		if blueprint_ids.has(id) or (not previous_blueprint_id.is_empty() and previous_blueprint_id >= id): return _reject("creature_blueprints")
		blueprint_ids[id] = (value as Dictionary).duplicate(true)
		previous_blueprint_id = id
	if not _validate_encounter(gameplay.get("encounter", null), blueprint_ids, site_ir, request): return false
	if not _validate_items(gameplay.get("items", null), gameplay.get("drops", null), gameplay.get("encounter", null), gameplay.get("legacy_slice", {}).get("loot_containers", [])): return false
	var gameplay_entity_count: int = (gameplay.get("encounter", {}).get("spawns", []) as Array).size() + (gameplay.get("items", []) as Array).size()
	if (ship.get("entities", []) as Array).size() + gameplay_entity_count > int(caps.get("max_entities", 0)): return _reject("entity_cap")
	var decisions: Variant = gameplay.get("decisions", null)
	if not decisions is Array or (decisions as Array).is_empty() or (decisions as Array).size() > 512: return _reject("gameplay_decisions")
	var decision_ids: Dictionary = {}
	var selected_creatures: Dictionary = {}
	var selected_items: Dictionary = {}
	var encounter_decisions: Dictionary = {}
	for encounter_decision_value in gameplay.get("encounter", {}).get("trace", {}).get("decisions", []):
		if encounter_decision_value is Dictionary:
			encounter_decisions["encounter:%s" % str((encounter_decision_value as Dictionary).get("decision_id", ""))] = encounter_decision_value
	for value in decisions:
		if not value is Dictionary or not _has_exact_keys(value, ["decision_id", "channel_id", "domain", "candidate_id", "score_bp", "accepted", "rationale_codes", "selected_id"]): return _reject("gameplay_decisions")
		var d: Dictionary = value
		var domain: String = str(d.domain)
		if decision_ids.has(str(d.decision_id)) or not _is_gameplay_id(str(d.decision_id)) or not _is_gameplay_id(str(d.channel_id)) or not _is_gameplay_id(str(d.candidate_id)) or not ["creature", "encounter", "item"].has(domain) or not _is_bounded_integer(d.score_bp, 0, 10000) or d.accepted is not bool or not d.rationale_codes is Array or (d.rationale_codes as Array).is_empty(): return _reject("gameplay_decisions")
		if bool(d.accepted) != (d.selected_id != null) or (d.selected_id != null and not _is_valid_world_id(str(d.selected_id))): return _reject("gameplay_decisions")
		if not _validate_gameplay_rationales(d.rationale_codes, domain): return _reject("gameplay_decisions")
		if domain == "creature":
			if str(d.channel_id) != "gameplay.creature_blueprint": return _reject("gameplay_decisions")
			if bool(d.accepted): selected_creatures[str(d.selected_id)] = true
		elif domain == "item":
			if not ["gameplay.item_affix", "gameplay.item_family"].has(str(d.channel_id)): return _reject("gameplay_decisions")
			if bool(d.accepted): selected_items[str(d.selected_id)] = true
		else:
			var encounter_decision: Variant = encounter_decisions.get(str(d.decision_id), null)
			if not encounter_decision is Dictionary or str(d.channel_id) != str((encounter_decision as Dictionary).get("channel_id", "")) or str(d.candidate_id) != str((encounter_decision as Dictionary).get("candidate_id", "")) or int(d.score_bp) != int((encounter_decision as Dictionary).get("score_bp", -1)) or bool(d.accepted) != bool((encounter_decision as Dictionary).get("accepted", false)) or not _same_json(d.selected_id, (encounter_decision as Dictionary).get("selected_spawn_id", null)): return _reject("gameplay_decisions")
		decision_ids[str(d.decision_id)] = true
	for blueprint_id in blueprint_ids:
		if not selected_creatures.has(str(blueprint_id)): return _reject("gameplay_decisions")
	for item_value in gameplay.get("items", []):
		if item_value is Dictionary and not selected_items.has(str((item_value as Dictionary).get("id", ""))): return _reject("gameplay_decisions")
	if encounter_decisions.size() > 0:
		for decision_id in encounter_decisions:
			if not decision_ids.has(str(decision_id)): return _reject("gameplay_decisions")
	return true

func _validate_creature_blueprint(value: Variant) -> bool:
	if not value is Dictionary: return false
	var b: Dictionary = value
	var keys: Array[String] = ["id", "body_plan_id", "footprint_id", "rig_id", "animation_set_id", "ability_id", "behavior_id", "material_id", "counterplay_id", "threat_role", "threat_cost", "performance_cost", "instance_cap"]
	if not _has_exact_keys(b, keys): return false
	var id: String = str(b.get("id", ""))
	var spec_value: Variant = CREATURE_SPECS.get(id, null)
	if not spec_value is Dictionary: return false
	var spec: Dictionary = spec_value
	for key in keys.slice(1):
		if not _same_json(b.get(key, null), spec.get(key, null)): return false
	return true

func _validate_encounter(value: Variant, blueprint_ids: Dictionary, site_ir: Dictionary, request: Dictionary) -> bool:
	if not value is Dictionary: return _reject("encounter_shape")
	var e: Dictionary = value
	if not _has_exact_keys(e, ["schema_version", "composition_id", "spawns", "total_threat", "total_performance", "total_reward_value", "trace"]): return _reject("encounter_shape")
	if str(e.schema_version) != "encounter-output-3" or not _is_valid_world_id(str(e.composition_id)) or not e.spawns is Array or (e.spawns as Array).size() > 128: return _reject("encounter_schema")
	for key in ["total_threat", "total_performance", "total_reward_value"]:
		if not _is_bounded_integer(e[key], 0, 1000000): return _reject("encounter_budget")
	var rooms: Dictionary = {}
	for room in (site_ir.get("ship", {}).get("topology", {}).get("rooms", []) as Array):
		if room is Dictionary: rooms[int((room as Dictionary).get("id", -1))] = room
	var protected_rooms: Dictionary = {int(site_ir.get("ship", {}).get("entry_room", -1)):true, int(site_ir.get("ship", {}).get("goal_room", -1)):true}
	for room_id in site_ir.get("ship", {}).get("critical_path", []): protected_rooms[int(room_id)] = true
	var decisions_by_id: Dictionary = {}
	var trace_value: Variant = e.get("trace", null)
	if not _validate_encounter_trace(trace_value, blueprint_ids, request): return false
	for decision_value in (trace_value as Dictionary).get("decisions", []):
		decisions_by_id[str((decision_value as Dictionary).get("decision_id", ""))] = decision_value
	var spawn_ids: Dictionary = {}
	var reward_sources: Dictionary = {}
	var occupied_cells: Dictionary = {}
	var instance_counts: Dictionary = {}
	var selected_spawn_ids: Array = []
	var threat_total: int = 0
	var performance_total: int = 0
	var reward_total: int = 0
	for spawn_value in e.spawns:
		if not spawn_value is Dictionary: return _reject("encounter_spawns")
		var s: Dictionary = spawn_value
		if not _has_exact_keys(s, ["spawn_id", "decision_id", "reward_source_id", "room", "cell", "blueprint_id", "faction_id", "threat_role", "ability_id", "threat_cost", "performance_cost", "reward_value"]): return _reject("encounter_spawns")
		var spawn_id: String = str(s.spawn_id)
		var reward_source: String = str(s.reward_source_id)
		var blueprint_id: String = str(s.blueprint_id)
		var faction_id: String = str(s.faction_id)
		if not blueprint_ids.has(blueprint_id) or not rooms.has(int(s.room)) or protected_rooms.has(int(s.room)) or not _validate_cell(s.cell) or not _is_valid_world_id(spawn_id) or not _is_valid_world_id(str(s.decision_id)) or not _is_valid_world_id(reward_source) or not ENCOUNTER_FACTIONS.has(faction_id) or spawn_ids.has(spawn_id) or reward_sources.has(reward_source): return _reject("encounter_spawns")
		for key in ["threat_cost", "performance_cost", "reward_value"]:
			if not _is_bounded_integer(s[key], 0, 10000): return _reject("encounter_spawns")
		var blueprint: Dictionary = blueprint_ids[blueprint_id]
		var faction: Dictionary = ENCOUNTER_FACTIONS[faction_id]
		if str(s.threat_role) != str(blueprint.threat_role) or str(s.ability_id) != str(blueprint.ability_id) or int(s.threat_cost) != int(blueprint.threat_cost) or int(s.performance_cost) != int(blueprint.performance_cost) or not (faction.blueprints as Array).has(blueprint_id) or not (faction.roles as Array).has(str(s.threat_role)) or not (faction.abilities as Array).has(str(s.ability_id)) or not [25, 50, 100].has(int(s.reward_value)): return _reject("encounter_spawns")
		var decision: Variant = decisions_by_id.get(str(s.decision_id), null)
		if not decision is Dictionary or not bool((decision as Dictionary).get("accepted", false)) or str((decision as Dictionary).get("selected_spawn_id", "")) != spawn_id: return _reject("encounter_spawns")
		var room_cells: Dictionary = {}
		for cell_value in (rooms[int(s.room)] as Dictionary).get("cells", []):
			if cell_value is Dictionary: room_cells[_cell_identity(cell_value)] = true
		var spec: Dictionary = CREATURE_SPECS[blueprint_id]
		for offset_value in spec.footprint:
			var offset: Vector2i = offset_value
			var footprint_cell: Dictionary = {"deck":int(s.cell.deck), "x":int(s.cell.x) + offset.x, "y":int(s.cell.y) + offset.y}
			var cell_key: String = _cell_identity(footprint_cell)
			if not room_cells.has(cell_key) or occupied_cells.has(cell_key): return _reject("encounter_spawns")
			occupied_cells[cell_key] = true
		instance_counts[blueprint_id] = int(instance_counts.get(blueprint_id, 0)) + 1
		if int(instance_counts[blueprint_id]) > int(blueprint.instance_cap): return _reject("encounter_spawns")
		spawn_ids[spawn_id] = true
		reward_sources[reward_source] = true
		selected_spawn_ids.append(spawn_id)
		threat_total += int(s.threat_cost)
		performance_total += int(s.performance_cost)
		reward_total += int(s.reward_value)
	var trace: Dictionary = trace_value
	if not _same_json(trace.selected_spawn_ids, selected_spawn_ids): return _reject("encounter_spawns")
	var budgets: Dictionary = trace.budgets
	if threat_total != int(e.total_threat) or performance_total != int(e.total_performance) or reward_total != int(e.total_reward_value) or threat_total > int(budgets.threat_limit) or performance_total > int(budgets.performance_limit) or reward_total > int(budgets.economy_limit) or (e.spawns as Array).size() > int(budgets.group_cap): return _reject("encounter_budget")
	if (e.spawns as Array).is_empty():
		if int(e.total_threat) != 0 or int(e.total_performance) != 0 or int(e.total_reward_value) != 0 or str(trace.fallback) != "encounter-safe-empty" or str(trace.fallback_rationale) != "no_fair_spawn": return _reject("encounter_fallback")
	elif trace.fallback != null or trace.fallback_rationale != null:
		return _reject("encounter_fallback")
	return true

func _validate_encounter_trace(value: Variant, blueprint_ids: Dictionary, request: Dictionary) -> bool:
	if not value is Dictionary: return _reject("encounter_trace")
	var t: Dictionary = value
	var keys: Array[String] = ["rules_version", "channel_ids", "player_values_bp", "budgets", "candidates", "decisions", "selected_spawn_ids", "fallback", "fallback_rationale", "adaptive"]
	if not _has_exact_keys(t, keys) or str(t.rules_version) != "encounter-rules-2" or not _same_json(t.channel_ids, ENCOUNTER_RNG_CHANNELS) or not _validate_number_array(t.player_values_bp, 4, true, 0, 10000) or not t.candidates is Array or not t.decisions is Array or not t.selected_spawn_ids is Array or (t.candidates as Array).size() != (t.decisions as Array).size() or (t.candidates as Array).size() > 128: return _reject("encounter_trace")
	var expected_values: Array = [5000, 5000, 5000, 5000]
	for signal_value in request.get("player_model", {}).get("signals", []):
		if signal_value is Dictionary:
			var index: int = PLAYER_SIGNAL_KINDS.find(str((signal_value as Dictionary).get("kind", "")))
			if index >= 0: expected_values[index] = int((signal_value as Dictionary).get("value_bp", 5000))
	if not _same_json(t.player_values_bp, expected_values) or not _validate_encounter_budgets(t.budgets, request, expected_values): return _reject("encounter_trace")
	var candidate_ids: Dictionary = {}
	var decision_ids: Dictionary = {}
	var decision_selected_ids: Array = []
	for index in (t.candidates as Array).size():
		var candidate_value: Variant = (t.candidates as Array)[index]
		var decision_value: Variant = (t.decisions as Array)[index]
		if not candidate_value is Dictionary or not decision_value is Dictionary: return _reject("encounter_trace")
		var candidate: Dictionary = candidate_value
		var decision: Dictionary = decision_value
		if not _has_exact_keys(candidate, ["candidate_id", "channel_id", "room", "cell", "blueprint_id", "faction_id", "score_bp", "navigation_distance", "has_cover", "accepted", "rationale_codes"]) or not _has_exact_keys(decision, ["decision_id", "channel_id", "candidate_id", "score_bp", "accepted", "rationale_codes", "selected_spawn_id"]): return _reject("encounter_trace")
		if not _is_valid_world_id(str(candidate.candidate_id)) or candidate_ids.has(str(candidate.candidate_id)) or str(candidate.channel_id) != "gameplay.encounter_candidate" or not blueprint_ids.has(str(candidate.blueprint_id)) or not ENCOUNTER_FACTIONS.has(str(candidate.faction_id)) or not _validate_cell(candidate.cell) or not _is_bounded_integer(candidate.room, 0, 65535) or not _is_bounded_integer(candidate.score_bp, 0, 10000) or not _is_bounded_integer(candidate.navigation_distance, 0, 65535) or candidate.has_cover is not bool or candidate.accepted is not bool or not _validate_encounter_rationales(candidate.rationale_codes): return _reject("encounter_trace")
		if not _is_valid_world_id(str(decision.decision_id)) or decision_ids.has(str(decision.decision_id)) or str(decision.channel_id) != "gameplay.encounter_selection" or str(decision.candidate_id) != str(candidate.candidate_id) or int(decision.score_bp) != int(candidate.score_bp) or bool(decision.accepted) != bool(candidate.accepted) or not _same_json(decision.rationale_codes, candidate.rationale_codes): return _reject("encounter_trace")
		if bool(candidate.accepted) != (decision.selected_spawn_id != null) or (bool(candidate.accepted) and (not decision.selected_spawn_id is String or not _is_valid_world_id(str(decision.selected_spawn_id)) or not _same_json(candidate.rationale_codes, ["accepted"]))) or (not bool(candidate.accepted) and (candidate.rationale_codes as Array).has("accepted")): return _reject("encounter_trace")
		if bool(candidate.accepted): decision_selected_ids.append(str(decision.selected_spawn_id))
		candidate_ids[str(candidate.candidate_id)] = true
		decision_ids[str(decision.decision_id)] = true
	for selected_id in t.selected_spawn_ids:
		if not selected_id is String or not _is_valid_world_id(str(selected_id)): return _reject("encounter_trace")
	if not _same_json(t.selected_spawn_ids, decision_selected_ids): return _reject("encounter_trace")
	if t.fallback != null and (not t.fallback is String or str(t.fallback) != "encounter-safe-empty"): return _reject("encounter_trace")
	if t.fallback_rationale != null and (not t.fallback_rationale is String or not ENCOUNTER_RATIONALES.has(str(t.fallback_rationale))): return _reject("encounter_trace")
	return true

func _validate_items(items_value: Variant, drops_value: Variant, encounter: Variant, containers: Variant) -> bool:
	if not items_value is Array or not drops_value is Array or not encounter is Dictionary or not containers is Array or (items_value as Array).size() != (drops_value as Array).size() or (items_value as Array).size() > 64: return _reject("items_shape")
	var eligible_sources: Dictionary = {}
	for container_value in containers:
		if not container_value is Dictionary: return _reject("items_shape")
		eligible_sources[str((container_value as Dictionary).get("id", ""))] = true
	for spawn_value in (encounter as Dictionary).get("spawns", []):
		if not spawn_value is Dictionary: return _reject("items_shape")
		eligible_sources[str((spawn_value as Dictionary).get("reward_source_id", ""))] = true
	var item_ids: Dictionary = {}
	var drop_sources: Dictionary = {}
	var economy_total: int = 0
	for index in (items_value as Array).size():
		var value: Variant = (items_value as Array)[index]
		var drop_value: Variant = (drops_value as Array)[index]
		if not value is Dictionary or not _has_exact_keys(value, ["id", "family_id", "rarity_id", "socket_id", "affixes", "stat_budget", "economy_value", "visual_tag"]): return _reject("items_shape")
		if not drop_value is Dictionary or not _has_exact_keys(drop_value, ["item_id", "source_id", "frequency_bp"]): return _reject("drops_shape")
		var item: Dictionary = value
		var drop: Dictionary = drop_value
		var family_value: Variant = ITEM_FAMILIES.get(str(item.family_id), null)
		if not family_value is Dictionary or item_ids.has(str(item.id)) or not _is_valid_world_id(str(item.id)) or str(item.rarity_id) != "common" or not item.affixes is Array or (item.affixes as Array).size() > 1: return _reject("items_shape")
		var family: Dictionary = family_value
		if str(item.socket_id) != str(family.socket_id) or str(item.visual_tag) != str(family.visual_tag) or not _is_bounded_integer(item.stat_budget, 0, 200) or not _is_bounded_integer(item.economy_value, 0, 1000): return _reject("items_shape")
		var expected_budget: int = 0
		for affix_value in item.affixes:
			if not affix_value is Dictionary or not _has_exact_keys(affix_value, ["affix_id", "stat", "value"]): return _reject("items_shape")
			var affix: Dictionary = affix_value
			if str(affix.affix_id) != str(family.affix_id) or str(affix.stat) != str(family.stat) or not _is_bounded_integer(affix.value, 10, 50): return _reject("items_shape")
			expected_budget += int(affix.value)
		var fallback_item: bool = str(item.id) == "item_baseline"
		var expected_economy: int = int(family.base_value) + expected_budget * 2
		var expected_frequency: int = 0 if fallback_item else int(family.frequency_bp)
		if int(item.stat_budget) != expected_budget or int(item.economy_value) != expected_economy or (fallback_item and (str(item.family_id) != "tool" or not (item.affixes as Array).is_empty())): return _reject("items_shape")
		if str(drop.item_id) != str(item.id) or not eligible_sources.has(str(drop.source_id)) or drop_sources.has(str(drop.source_id)) or not _is_bounded_integer(drop.frequency_bp, 0, 10000) or int(drop.frequency_bp) != expected_frequency: return _reject("drops_shape")
		item_ids[str(item.id)] = true
		drop_sources[str(drop.source_id)] = true
		economy_total += int(item.economy_value)
	if economy_total > 10000: return _reject("items_economy")
	return true

func _validate_encounter_budgets(value: Variant, request: Dictionary, player_values: Array) -> bool:
	if not value is Dictionary or not _has_exact_keys(value, ["difficulty_id", "player_factor_bp", "threat_limit", "performance_limit", "economy_limit", "group_cap", "minimum_reward_value"]): return false
	var difficulty_id: String = str(request.get("difficulty_id", ""))
	var authored: Dictionary = {
		"standard":{"threat":1000, "performance":800, "economy":400, "group":4},
		"hardened":{"threat":1600, "performance":1200, "economy":600, "group":6},
		"deep_dive":{"threat":2400, "performance":1800, "economy":800, "group":8},
	}
	if not authored.has(difficulty_id): return false
	var base: Dictionary = authored[difficulty_id]
	var factor: int = 10000 + _adaptive_encounter_delta(player_values)
	var loot_richness: int = int(request.get("site", {}).get("loot_richness_bp", 0))
	var expected: Dictionary = {
		"difficulty_id":difficulty_id,
		"player_factor_bp":factor,
		"threat_limit":mini(int(int(base.threat) * factor / 10000.0), 3000),
		"performance_limit":mini(int(base.performance), 3000),
		"economy_limit":mini(int(int(base.economy) * (30000 + loot_richness) / 30000.0), 2000),
		"group_cap":int(base.group),
		"minimum_reward_value":25,
	}
	return _same_json(value, expected)

func _validate_encounter_rationales(value: Variant) -> bool:
	if not value is Array or (value as Array).is_empty(): return false
	for rationale in value:
		if not rationale is String or not ENCOUNTER_RATIONALES.has(str(rationale)): return false
	return true

func _validate_gameplay_rationales(value: Variant, domain: String) -> bool:
	if not value is Array or (value as Array).is_empty(): return false
	var unit_codes: Dictionary = {
		"creature":["creature_validated", "creature_incompatible", "creature_selected"],
		"item":["item_authored_compatible", "item_no_compatible_affix", "item_arithmetic_overflow", "item_incompatible", "item_economy_cap", "item_authored_baseline", "item_safe_empty"],
	}
	for rationale_value in value:
		if not rationale_value is Dictionary: return false
		var rationale: Dictionary = rationale_value
		if domain == "encounter":
			if not _has_exact_keys(rationale, ["code", "detail"]) or str(rationale.get("code", "")) != "encounter" or not ENCOUNTER_RATIONALES.has(str(rationale.get("detail", ""))): return false
		elif not unit_codes.has(domain) or not _has_exact_keys(rationale, ["code"]) or not (unit_codes[domain] as Array).has(str(rationale.get("code", ""))):
			return false
	return true

func _is_gameplay_id(value: String) -> bool:
	return _is_bounded_contract_id(value, 128)

func _is_presentation_id(value: String) -> bool:
	return _is_bounded_contract_id(value, 96)

func _is_bounded_contract_id(value: String, maximum: int) -> bool:
	if value.is_empty() or value.length() > maximum: return false
	for code in value.to_ascii_buffer():
		if not ((code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code in [58, 95, 45, 46]): return false
	return true

func _validate_gameplay(value: Variant, ship: Dictionary) -> bool:
	if not value is Dictionary: return _reject("gameplay_slice_shape")
	var gameplay: Dictionary = value
	var keys: Array[String] = ["schema_version", "document_kind", "program_id", "start_room", "goal_room", "critical_path", "fire_zones", "objectives", "loot_containers", "summary"]
	if not _has_exact_keys(gameplay, keys): return _reject("gameplay_slice_shape")
	if str(gameplay.get("schema_version", "")) != "1.1.0" or str(gameplay.get("document_kind", "")) != "ship_gameplay_slice": return _reject("gameplay_slice_schema")
	var expected_program: String = "worldgen-%s-%d" % [str(ship.get("archetype_id", "")), int(ship.get("seed", 0))]
	if str(gameplay.get("program_id", "")) != expected_program: return _reject("gameplay_identity")
	for key in ["start_room", "goal_room", "summary"]:
		if not gameplay.get(key, null) is String or str(gameplay.get(key, "")).is_empty(): return _reject("gameplay_slice_shape")
	for key in ["critical_path", "fire_zones", "objectives", "loot_containers"]:
		if not gameplay.get(key, null) is Array: return _reject("gameplay_slice_shape")
	for room_id in gameplay.get("critical_path", []):
		if not room_id is String or str(room_id).is_empty(): return _reject("gameplay_slice_shape")
	for fire_zone in gameplay.get("fire_zones", []):
		if not fire_zone is Dictionary or not (fire_zone as Dictionary).is_empty(): return _reject("gameplay_slice_shape")
	for objective in gameplay.get("objectives", []):
		if not _validate_objective(objective): return _reject("gameplay_slice_shape")
	for container in gameplay.get("loot_containers", []):
		if not _validate_loot_container(container): return _reject("gameplay_slice_shape")
	return true

func _validate_presentation(value: Dictionary, gameplay: Dictionary, site_ir: Dictionary) -> bool:
	if not value.instructions is Array or not value.decisions is Array or not value.repairs is Array or not value.fallback_subjects is Array or value.instructions.is_empty() or value.instructions.size() != value.decisions.size() or value.instructions.size() > 128 or value.repairs.size() > 1: return _reject("presentation_shape")
	var expected_assets: Dictionary = {
		"environment:ambient":"asset:audio:ambient",
		"ship:structural":"asset:primitive:structural",
	}
	for blueprint_value in gameplay.get("creature_blueprints", []):
		if not blueprint_value is Dictionary: return _reject("presentation_shape")
		var blueprint_id: String = str((blueprint_value as Dictionary).get("id", ""))
		expected_assets["creature:%s" % blueprint_id] = "asset:primitive:%s" % blueprint_id
	for item_value in gameplay.get("items", []):
		if not item_value is Dictionary: return _reject("presentation_shape")
		var item: Dictionary = item_value
		var family: String = str(item.get("family_id", ""))
		expected_assets["item:%s" % str(item.get("id", ""))] = "asset:primitive:item_%s" % family
	for index in (site_ir.get("functional_props", []) as Array).size():
		expected_assets["objective:%02d" % index] = "asset:primitive:objective"
	var expected_subjects: Array = expected_assets.keys()
	expected_subjects.sort()
	if value.instructions.size() != expected_subjects.size() or not (value.fallback_subjects as Array).is_empty(): return _reject("presentation_shape")
	var catalogue_assets: Array = PRESENTATION_ASSET_BINDINGS.keys()
	catalogue_assets.sort()
	for i in value.instructions.size():
		var instruction: Variant = value.instructions[i]
		var decision: Variant = value.decisions[i]
		if not instruction is Dictionary or not decision is Dictionary or not _has_exact_keys(instruction, ["subject_id", "asset_ids", "adapter_binding_ids"]) or not _has_exact_keys(decision, ["decision_id", "channel", "considered", "rejected", "selected"]): return _reject("presentation_shape")
		var subject_id: String = str((instruction as Dictionary).get("subject_id", ""))
		var assets: Variant = (instruction as Dictionary).get("asset_ids", null)
		var bindings: Variant = (instruction as Dictionary).get("adapter_binding_ids", null)
		if subject_id != str(expected_subjects[i]) or not _is_presentation_id(subject_id) or not assets is Array or (assets as Array).size() != 1 or not bindings is Array or (bindings as Array).size() != 1: return _reject("presentation_instruction")
		var asset_id: String = str((assets as Array)[0])
		var binding_id: String = str((bindings as Array)[0])
		if asset_id != str(expected_assets[subject_id]) or not PRESENTATION_ASSET_BINDINGS.has(asset_id) or binding_id != str(PRESENTATION_ASSET_BINDINGS[asset_id]): return _reject("presentation_binding")
		var d: Dictionary = decision
		if str(d.get("decision_id", "")) != "decision:%d" % i or str(d.get("channel", "")) != "presentation.asset_assembly" or str(d.get("selected", "")) != asset_id or not d.get("considered", null) is Array or not d.get("rejected", null) is Array or (d.considered as Array).size() + (d.rejected as Array).size() != catalogue_assets.size(): return _reject("presentation_decision")
		var candidate_assets: Dictionary = {}
		var selected_accepted: bool = false
		for accepted_group in [true, false]:
			var records: Array = d.considered if accepted_group else d.rejected
			for record_value in records:
				if not record_value is Dictionary or not _has_exact_keys(record_value, ["asset_id", "accepted", "rationale"]): return _reject("presentation_decision")
				var record: Dictionary = record_value
				var candidate_asset: String = str(record.get("asset_id", ""))
				var rationale: String = str(record.get("rationale", ""))
				if not PRESENTATION_ASSET_BINDINGS.has(candidate_asset) or candidate_assets.has(candidate_asset) or record.get("accepted", null) is not bool or bool(record.accepted) != accepted_group or (accepted_group and rationale != "eligible") or (not accepted_group and not ["incompatible_subject_kind", "missing_compatible_tag"].has(rationale)): return _reject("presentation_decision")
				candidate_assets[candidate_asset] = true
				if accepted_group and candidate_asset == asset_id: selected_accepted = true
		if candidate_assets.size() != catalogue_assets.size() or not selected_accepted: return _reject("presentation_decision")
	for repair in value.repairs:
		if not repair is String or str(repair).is_empty(): return _reject("presentation_shape")
	return true

func _validate_objective(value: Variant) -> bool:
	if not value is Dictionary: return false
	var objective: Dictionary = value
	var keys: Array[String] = [
		"id", "sequence", "type", "kind", "room_id", "room_role", "semantic", "cell",
		"approach_cell", "approach_distance_cells", "interactable",
	]
	if not _has_exact_keys(objective, keys): return false
	for key in ["id", "type", "kind", "room_id", "room_role", "semantic"]:
		if not objective.get(key, null) is String or str(objective.get(key, "")).is_empty(): return false
	return _is_bounded_integer(objective.get("sequence", null), 0, 4294967295) \
			and _validate_number_array(objective.get("cell", null), 3, true, -2147483648, 2147483647) \
			and _validate_number_array(objective.get("approach_cell", null), 3, true, -2147483648, 2147483647) \
			and _is_bounded_integer(objective.get("approach_distance_cells", null), 0, 4294967295) \
			and objective.get("interactable", null) is bool

func _validate_loot_container(value: Variant) -> bool:
	if not value is Dictionary: return false
	var container: Dictionary = value
	if not _has_exact_keys(container, ["id", "kind", "room_id", "approach_cell", "loot_table"]): return false
	for key in ["id", "kind", "room_id", "loot_table"]:
		if not container.get(key, null) is String or str(container.get(key, "")).is_empty(): return false
	return _validate_number_array(container.get("approach_cell", null), 3, true, -2147483648, 2147483647)

func _validate_metrics_trace(metrics_value: Variant, trace_value: Variant, site_ir: Dictionary, ship: Dictionary, gameplay_ir: Dictionary, caps: Dictionary) -> bool:
	if not metrics_value is Dictionary or not trace_value is Dictionary: return _reject("diagnostic_shape")
	var metrics: Dictionary = metrics_value
	var trace: Dictionary = trace_value
	if not _has_exact_keys(metrics, ["schema_version", "pipeline_executions", "room_count", "entity_count", "structural_placement_count", "stage_timings_micros"]): return _reject("metrics_shape")
	if not _has_exact_keys(trace, ["schema_version", "rng_channels", "candidate_decisions", "failed_constraints", "repairs", "retries", "fallback", "stage_timings_micros", "adaptive_decisions"]): return _reject("trace_shape")
	if str(metrics.get("schema_version", "")) != "generation-metrics-1" or str(trace.get("schema_version", "")) != EXPORT_SCHEMAS.generation_trace: return _reject("diagnostic_schema")
	for key in ["pipeline_executions", "room_count", "entity_count", "structural_placement_count"]:
		if not _is_json_integer(metrics.get(key, null)) or int(metrics.get(key, -1)) < 0: return _reject("metrics_shape")
	if int(metrics.get("pipeline_executions", 0)) != 1: return _reject("pipeline_count")
	var graph: Dictionary = ship.get("room_graph", {})
	var plan: Dictionary = ship.get("plan", {})
	var placements: int = (plan.get("placements", []) as Array).size() + (plan.get("floor_placements", []) as Array).size() + (plan.get("ceiling_placements", []) as Array).size()
	var gameplay_entities: int = (gameplay_ir.get("encounter", {}).get("spawns", []) as Array).size() + (gameplay_ir.get("items", []) as Array).size()
	if int(metrics.get("room_count", -1)) != (graph.get("nodes", []) as Array).size() or int(metrics.get("entity_count", -1)) != (ship.get("entities", []) as Array).size() + gameplay_entities \
			or int(metrics.get("structural_placement_count", -1)) != placements: return _reject("metrics_identity")
	var trace_cap: int = int(caps.get("max_trace_entries", 0))
	for key in ["rng_channels", "candidate_decisions", "failed_constraints", "repairs", "retries"]:
		var entries: Variant = trace.get(key, null)
		if not entries is Array or (entries as Array).size() > trace_cap: return _reject("trace_cap")
		for entry in entries:
			if not entry is String or str(entry).is_empty(): return _reject("trace_shape")
	if not _same_json(trace.get("rng_channels", []), RNG_CHANNELS): return _reject("trace_channels")
	var fallback: Variant = trace.get("fallback", null)
	if fallback != null and (not fallback is String or str(fallback).is_empty()): return _reject("trace_fallback")
	var world_fallback: bool = false
	var site_fallback: bool = false
	if fallback != null:
		var parts: PackedStringArray = str(fallback).split("|", false)
		if parts.is_empty() or parts.size() > 2: return _reject("trace_fallback")
		for index in parts.size():
			var part: String = parts[index]
			if part == "world:safe-world-v3" and index == 0 and not world_fallback:
				world_fallback = true
			elif part == "site:authored-safe-return" and not site_fallback:
				site_fallback = true
			else:
				return _reject("trace_fallback")
	var decisions: Array = trace.get("candidate_decisions", [])
	var rejected_world_candidate: bool = decisions.has("rejected_candidate")
	var selected_world_fallback: bool = decisions.has("selected_fallback")
	if (world_fallback and (not rejected_world_candidate or not selected_world_fallback)) \
			or (not world_fallback and (rejected_world_candidate or selected_world_fallback)):
		return _reject("world_fallback_trace")
	var rejected_site_candidate: bool = decisions.has("site:rejected_candidate")
	var selected_site_fallback: bool = decisions.has("site:selected_fallback")
	if (site_fallback and (not rejected_site_candidate or not selected_site_fallback)) \
			or (not site_fallback and (rejected_site_candidate or selected_site_fallback)):
		return _reject("site_fallback_trace")
	var mission_graph: Dictionary = site_ir.get("mission_graph", {})
	if site_fallback != (str(mission_graph.get("mission_id", "")) == "authored-safe-return"):
		return _reject("site_fallback_trace")
	var trace_timings: Variant = trace.get("stage_timings_micros", null)
	var metric_timings: Variant = metrics.get("stage_timings_micros", null)
	if not trace_timings is Dictionary or not metric_timings is Dictionary or (trace_timings as Dictionary).size() > trace_cap or not _same_json(trace_timings, metric_timings): return _reject("trace_metrics_timings")
	for key in (trace_timings as Dictionary).keys():
		var timing: Variant = (trace_timings as Dictionary)[key]
		if str(key).is_empty() or not _is_json_integer(timing) or int(timing) < 0 or int(timing) > 3600000000: return _reject("trace_timing_bounds")
	return true

func _validate_adaptive_bundle(trace_value: Variant, world: Dictionary, site_ir: Dictionary, gameplay: Dictionary, request: Dictionary) -> bool:
	if not trace_value is Dictionary: return _reject("adaptive_trace_shape")
	var traces: Variant = (trace_value as Dictionary).get("adaptive_decisions", null)
	if not traces is Array or (traces as Array).size() != 3: return _reject("adaptive_trace_order")
	for decision_value in traces:
		if not decision_value is Dictionary: return _reject("adaptive_trace_shape")
	var player_values: Array = [5000, 5000, 5000, 5000]
	for signal_value in request.get("player_model", {}).get("signals", []):
		if signal_value is Dictionary:
			var index: int = PLAYER_SIGNAL_KINDS.find(str((signal_value as Dictionary).get("kind", "")))
			if index >= 0: player_values[index] = int((signal_value as Dictionary).get("value_bp", 5000))
	var world_trace: Dictionary = traces[0]
	var site_trace: Dictionary = traces[1]
	var encounter_trace: Dictionary = traces[2]
	var fallback_value: Variant = (trace_value as Dictionary).get("fallback", null)
	var fallback_summary: String = "" if fallback_value == null else str(fallback_value)
	var expects_world_fallback: bool = fallback_summary.begins_with("world:")
	var expects_site_fallback: bool = fallback_summary.begins_with("site:") or fallback_summary.contains("|site:")
	if not _validate_adaptive_trace(world_trace, "world_ranker", "decision:world-ranker", player_values, world.get("archetype_id", ""), null): return false
	if (world_trace.get("fallback", null) != null) != expects_world_fallback: return _reject("adaptive_world_fallback_binding")
	if not expects_world_fallback and not _validate_world_adaptive_candidate(world_trace, world.get("archetype_id", ""), world): return false
	if not _validate_adaptive_trace(site_trace, "site_ranker", "decision:site-ranker", player_values, site_ir.get("mission_graph", {}).get("mission_id", ""), null): return false
	if (site_trace.get("fallback", null) != null) != expects_site_fallback: return _reject("adaptive_site_fallback_binding")
	if expects_site_fallback and str(site_ir.get("mission_graph", {}).get("mission_id", "")) != "authored-safe-return": return _reject("adaptive_site_fallback_binding")
	if not _validate_site_adaptive_candidates(site_trace): return false
	var encounter_data: Dictionary = gameplay.get("encounter", {})
	if not _validate_adaptive_trace(encounter_trace, "encounter_director", "decision:encounter-director", player_values, "", encounter_data.get("composition_id", "")): return false
	if not _same_json(encounter_trace, encounter_data.get("trace", {}).get("adaptive", null)): return _reject("adaptive_encounter_binding")
	return true

func _validate_world_adaptive_candidate(trace: Dictionary, archetype_id: String, world: Dictionary) -> bool:
	var candidates: Array = trace.get("candidates", [])
	if candidates.size() != 1: return _reject("adaptive_world_candidates")
	var marker_id: String = str(trace.get("selected_candidate_id", ""))
	var candidate: Dictionary = candidates[0]
	var features: Dictionary = candidate.get("features", {})
	var extraction: Dictionary = world.get("extraction", {})
	var selected_marker: String = str(extraction.get("selected_marker_id", ""))
	var challenge: int = -1
	var resource: int = -1
	var pace: int = -1
	for entry in world.get("hazard_fields", []):
		if entry is Dictionary and str(entry.get("marker_id", "")) == selected_marker: challenge = int(entry.get("severity_bp", -1))
	for entry in world.get("resource_pressures", []):
		if entry is Dictionary and str(entry.get("marker_id", "")) == selected_marker: resource = int(entry.get("pressure_bp", -1))
	for entry in world.get("routes", []):
		if entry is Dictionary and ((str(entry.get("from", "")) == selected_marker and str(entry.get("to", "")) == str(extraction.get("hub_anchor_id", ""))) or (str(entry.get("to", "")) == selected_marker and str(entry.get("from", "")) == str(extraction.get("hub_anchor_id", "")))): pace = int(entry.get("cost_bp", -1))
	return str(candidate.get("candidate_id", "")) == archetype_id and marker_id == archetype_id and features.get("challenge_bp", -1) == challenge and features.get("pace_bp", -1) == pace and features.get("resource_cost_bp", -1) == resource

func _validate_site_adaptive_candidates(trace: Dictionary) -> bool:
	var expected: Dictionary = {
		"key_lock_salvage": [7000, 5000, 6500],
		"repair_recovery": [5500, 6500, 5000],
		"survey": [3500, 4000, 3000],
	}
	for candidate_value in trace.get("candidates", []):
		if not candidate_value is Dictionary: return _reject("adaptive_site_candidates")
		var candidate: Dictionary = candidate_value
		var id: String = str(candidate.get("candidate_id", ""))
		if not expected.has(id) or not _same_json(candidate.get("features", {}), {"challenge_bp": expected[id][0], "pace_bp": expected[id][1], "resource_cost_bp": expected[id][2]}): return _reject("adaptive_site_candidates")
	return true

func _validate_adaptive_trace(value: Variant, kind: String, decision_id: String, player_values: Array, selected_id: String, encounter_id: Variant) -> bool:
	if not value is Dictionary: return _reject("adaptive_trace_shape")
	var t: Dictionary = value
	var keys: Array[String] = ["schema_version", "decision_id", "kind", "rule_version", "player_values_bp", "candidates", "proposal", "selected_candidate_id", "applied", "fallback"]
	if not _has_exact_keys(t, keys) or str(t.schema_version) != ADAPTIVE_TRACE_SCHEMA or str(t.decision_id) != decision_id or str(t.kind) != kind or str(t.rule_version) != ADAPTIVE_RULE_VERSION: return _reject("adaptive_trace_shape")
	if not _same_json(t.player_values_bp, player_values) or t.applied is not bool or not t.candidates is Array or (t.candidates as Array).size() > 64: return _reject("adaptive_trace_player")
	var proposal: Variant = t.get("proposal", null)
	if not proposal is Dictionary or not _validate_adaptive_proposal(proposal, kind, selected_id, encounter_id): return false
	var candidate_ids: Dictionary = {}
	var best_score: int = -10001
	var best_id: String = ""
	for candidate_value in t.candidates:
		if not candidate_value is Dictionary: return _reject("adaptive_candidate")
		var candidate: Dictionary = candidate_value
		if not _has_exact_keys(candidate, ["candidate_id", "features", "score", "action", "rationale_codes"]): return _reject("adaptive_candidate")
		var id: String = str(candidate.candidate_id)
		var features: Variant = candidate.features
		if candidate_ids.has(id) or not _is_bounded_contract_id(id, 96) or not features is Dictionary or not _has_exact_keys(features, ["challenge_bp", "pace_bp", "resource_cost_bp"]): return _reject("adaptive_candidate")
		for key in ["challenge_bp", "pace_bp", "resource_cost_bp"]:
			if not _is_bounded_integer(features.get(key, null), 0, 10000): return _reject("adaptive_candidate")
		var score: int = _adaptive_score(features as Dictionary, player_values)
		if int(candidate.score) != score or not _validate_adaptive_action(candidate.action, "select_candidate", id) or not _validate_adaptive_rationales(candidate.rationale_codes): return _reject("adaptive_candidate")
		candidate_ids[id] = true
		if score > best_score or (score == best_score and (best_id.is_empty() or id < best_id)):
			best_score = score; best_id = id
		if candidate_ids.size() > 1:
			var previous_id: String = str(t.candidates[candidate_ids.size() - 2].get("candidate_id", ""))
			if previous_id >= id: return _reject("adaptive_candidate_order")
	if kind != "encounter_director":
		if t.candidates.is_empty():
			if t.selected_candidate_id != null or bool(t.applied) or t.fallback != "no_validated_candidate" or str(proposal.action) != "no_op" or int(proposal.score) != 0 or int(proposal.confidence_bp) != 0 or not _same_json(proposal.rationale_codes, ["no_validated_candidate", "classical_fallback"]): return _reject("adaptive_fallback")
		else:
			var best_count: int = 0
			for tie_value in t.candidates:
				if int(tie_value.get("score", -10001)) == best_score: best_count += 1
			var tie: bool = best_count > 1
			for candidate_check in t.candidates:
				var check_features: Dictionary = candidate_check.get("features", {})
				var expected_candidate_rationale: Array = ["validated_candidate"]
				if _adaptive_fit(int(check_features.get("challenge_bp", 0)), int(player_values[0])) >= 9000: expected_candidate_rationale.append("challenge_fit")
				if _adaptive_fit(int(check_features.get("pace_bp", 0)), int(player_values[3])) >= 9000: expected_candidate_rationale.append("pace_fit")
				if _adaptive_fit(int(check_features.get("resource_cost_bp", 0)), int(player_values[2])) >= 9000: expected_candidate_rationale.append("resource_pressure_fit")
				if tie and int(candidate_check.get("score", -10001)) == best_score: expected_candidate_rationale.append("stable_tie_break")
				if not _same_json(candidate_check.get("rationale_codes", []), expected_candidate_rationale): return _reject("adaptive_candidate")
			var expected_proposal_rationale: Array = ["validated_candidate"]
			var winner_features: Dictionary = {}
			for winner_value in t.candidates:
				if str(winner_value.get("candidate_id", "")) == best_id: winner_features = winner_value.get("features", {})
			if _adaptive_fit(int(winner_features.get("challenge_bp", 0)), int(player_values[0])) >= 9000: expected_proposal_rationale.append("challenge_fit")
			if _adaptive_fit(int(winner_features.get("pace_bp", 0)), int(player_values[3])) >= 9000: expected_proposal_rationale.append("pace_fit")
			if _adaptive_fit(int(winner_features.get("resource_cost_bp", 0)), int(player_values[2])) >= 9000: expected_proposal_rationale.append("resource_pressure_fit")
			if tie: expected_proposal_rationale.append("stable_tie_break")
			if t.fallback != null or t.selected_candidate_id != best_id or not bool(t.applied) or str(proposal.get("action", {}).get("select_candidate", {}).get("candidate_id", "")) != best_id or int(proposal.score) != best_score or int(proposal.confidence_bp) != clampi(5000 + int(float(best_score) / 2.0), 0, 10000) or not _same_json(proposal.rationale_codes, expected_proposal_rationale): return _reject("adaptive_binding")
	else:
		if not t.candidates.is_empty() or t.selected_candidate_id != null or t.fallback != null or not bool(t.applied): return _reject("adaptive_encounter_shape")
		var expected_delta: int = _adaptive_encounter_delta(player_values)
		if int(proposal.score) != expected_delta or int(proposal.confidence_bp) != clampi(5000 + int(float(expected_delta) / 2.0), 0, 10000) or not _same_json(proposal.rationale_codes, ["authored_envelope", "combat_mastery", "damage_pressure", "resource_pressure", "objective_pace"]) or int(proposal.action.get("adjust_encounter", {}).get("pacing_delta_bp", 99999)) != expected_delta or str(proposal.action.get("adjust_encounter", {}).get("encounter_id", "")) != str(encounter_id): return _reject("adaptive_encounter_binding")
	return true

func _validate_adaptive_proposal(value: Variant, kind: String, selected_id: String, encounter_id: Variant) -> bool:
	var p: Dictionary = value
	if not _has_exact_keys(p, ["schema_version", "score", "rationale_codes", "confidence_bp", "rule_model_version", "action"]): return _reject("adaptive_proposal")
	if str(p.schema_version) != EXPORT_SCHEMAS.adaptive_proposal or str(p.rule_model_version) != ADAPTIVE_RULE_VERSION or not _is_bounded_integer(p.score, -10000, 10000) or not _is_bounded_integer(p.confidence_bp, 0, 10000) or not _validate_adaptive_rationales(p.rationale_codes): return _reject("adaptive_proposal")
	if kind == "encounter_director": return _validate_adaptive_action(p.action, "adjust_encounter", str(encounter_id))
	if p.action is String: return str(p.action) == "no_op"
	return _validate_adaptive_action(p.action, "select_candidate", selected_id)

func _validate_adaptive_action(value: Variant, expected: String, expected_id: String) -> bool:
	if expected == "select_candidate":
		return value is Dictionary and _has_exact_keys(value, ["select_candidate"]) and value.select_candidate is Dictionary and _has_exact_keys(value.select_candidate, ["candidate_id"]) and str(value.select_candidate.candidate_id) == expected_id and _is_bounded_contract_id(expected_id, 96)
	if expected == "adjust_encounter":
		return value is Dictionary and _has_exact_keys(value, ["adjust_encounter"]) and value.adjust_encounter is Dictionary and _has_exact_keys(value.adjust_encounter, ["encounter_id", "pacing_delta_bp"]) and str(value.adjust_encounter.encounter_id) == expected_id and _is_bounded_integer(value.adjust_encounter.pacing_delta_bp, -2500, 2500) and [-2500, -1250, 0, 1250, 2500].has(int(value.adjust_encounter.pacing_delta_bp))
	return value is String and str(value) == "no_op"

func _validate_adaptive_rationales(value: Variant) -> bool:
	if not value is Array or (value as Array).is_empty() or (value as Array).size() > 64: return false
	var seen: Dictionary = {}
	for code in value:
		if not code is String or not ADAPTIVE_RATIONALES.has(str(code)) or seen.has(str(code)): return false
		seen[str(code)] = true
	return true

func _adaptive_score(features: Dictionary, player: Array) -> int:
	return (_adaptive_fit(int(features.challenge_bp), int(player[0])) + _adaptive_fit(int(features.pace_bp), int(player[3])) + _adaptive_fit(int(features.resource_cost_bp), int(player[2]))) / 3

func _adaptive_fit(actual: int, target: int) -> int: return 10000 - absi(actual - target)

func _adaptive_encounter_delta(values: Array) -> int:
	var utility: int = int(values[0]) - 5000 - int(float(int(values[1]) - 5000) / 2.0) - int(float(int(values[2]) - 5000) / 2.0) + int(float(int(values[3]) - 5000) / 4.0)
	utility = clampi(utility, -2500, 2500)
	var best: int = 0
	var best_distance: int = 99999
	for delta in [-2500, -1250, 0, 1250, 2500]:
		var distance: int = absi(utility - delta)
		if distance < best_distance or (distance == best_distance and delta < best): best = delta; best_distance = distance
	return best

func _verify_hash(result_json: String, bundle: Dictionary) -> bool:
	var helper: RefCounted = CanonicalJsonScript.new()
	var actual: String = helper.semantic_hash(result_json)
	if actual.is_empty(): return _reject("semantic_projection")
	if actual != str(bundle.get("semantic_hash", "")): return _reject("semantic_hash")
	return true

func _has_exact_keys(value: Variant, expected: Array) -> bool:
	if not value is Dictionary or (value as Dictionary).size() != expected.size(): return false
	for key in expected:
		if not (value as Dictionary).has(key): return false
	return true

func _validate_cell(value: Variant) -> bool:
	if not value is Dictionary: return false
	var cell: Dictionary = value
	return _has_exact_keys(cell, ["deck", "x", "y"]) \
			and _is_bounded_integer(cell.get("deck", null), 0, 255) \
			and _is_bounded_integer(cell.get("x", null), -2147483648, 2147483647) \
			and _is_bounded_integer(cell.get("y", null), -2147483648, 2147483647)

func _are_cardinal_neighbors(from_cell: Dictionary, to_cell: Dictionary) -> bool:
	if int(from_cell.get("deck", -1)) != int(to_cell.get("deck", -2)): return false
	var dx: int = absi(int(from_cell.get("x", 0)) - int(to_cell.get("x", 0)))
	var dy: int = absi(int(from_cell.get("y", 0)) - int(to_cell.get("y", 0)))
	return dx + dy == 1

func _cell_identity(value: Dictionary) -> String:
	return "%d|%d|%d" % [int(value.get("deck", 0)), int(value.get("x", 0)), int(value.get("y", 0))]

func _validate_number_array(value: Variant, expected_size: int, integers: bool, minimum: int, maximum: int) -> bool:
	if not value is Array or (value as Array).size() != expected_size: return false
	for number in value:
		if integers:
			if not _is_bounded_integer(number, minimum, maximum): return false
		elif not _is_finite_number(number):
			return false
	return true

func _is_finite_number(value: Variant) -> bool:
	if value is int: return int(value) >= -MAX_SAFE_JSON_INTEGER and int(value) <= MAX_SAFE_JSON_INTEGER
	return value is float and is_finite(float(value))

func _is_bounded_integer(value: Variant, minimum: int, maximum: int) -> bool:
	return _is_json_integer(value) and int(value) >= minimum and int(value) <= maximum

func _is_json_integer(value: Variant) -> bool:
	if value is int: return int(value) >= -MAX_SAFE_JSON_INTEGER and int(value) <= MAX_SAFE_JSON_INTEGER
	return value is float and is_finite(float(value)) and float(value) == floor(float(value)) and absf(float(value)) <= float(MAX_SAFE_JSON_INTEGER)

func _is_lower_hex(value: String, length: int) -> bool:
	if value.length() != length or value != value.to_lower(): return false
	for code in value.to_ascii_buffer():
		if not ((code >= 48 and code <= 57) or (code >= 97 and code <= 102)): return false
	return true

func _is_sha256(value: String) -> bool: return _is_lower_hex(value, 64)

func _same_json(left: Variant, right: Variant) -> bool:
	if left is int and right is int: return int(left) == int(right)
	if left is float and right is float:
		return is_finite(float(left)) and is_finite(float(right)) and float(left) == float(right)
	if (left is int and right is float) or (left is float and right is int):
		var integer: int = int(left) if left is int else int(right)
		var floating: float = float(right) if left is int else float(left)
		return integer >= -MAX_SAFE_JSON_INTEGER and integer <= MAX_SAFE_JSON_INTEGER \
				and is_finite(floating) and floating == floor(floating) \
				and absf(floating) <= float(MAX_SAFE_JSON_INTEGER) and integer == int(floating)
	if left is Dictionary and right is Dictionary:
		if left.size() != right.size(): return false
		for key in left.keys():
			if not right.has(key) or not _same_json(left[key], right[key]): return false
		return true
	if left is Array and right is Array:
		if left.size() != right.size(): return false
		for index in left.size():
			if not _same_json(left[index], right[index]): return false
		return true
	return left == right

func _reject(code: String) -> bool:
	last_error = code
	return false

func _fail(code: String) -> Dictionary:
	last_error = code
	return {}
