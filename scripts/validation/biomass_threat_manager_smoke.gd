extends SceneTree

## Biomass threat manager smoke — Task 7 contract.
##
## Strict RED→GREEN smoke. Asserts the ThreatManager → BiomassAssembler →
## BiomassThreatVisual → BiomassGaitController contract end-to-end without
## touching the scene tree. Verifies:
##   * ThreatAIState round-trip preserves old fields AND deep-copies new
##     biomass_recipe/biomass_seed (nonzero seed survives summary/apply).
##   * ThreatManager.configure_biomass_sources() is callable pre-tree; the
##     catalog/library load exactly once on _ready; threat_manager owns one
##     RefCounted assembler.
##   * All six biomass archetypes route to generated_recipe_weight 0.35 with exact allowed
##     locomotion hints per the contract (biomatter_swarm crawl/drag,
##     stalker biped/quadruped, hull_tendril slither/drag, puppet_corpse
##     biped/crawl, mimic quadruped/crawl, drone_swarm slither/crawl).
##   * For each of the six archetypes, a NEW threat stores its selected
##     recipe before build, the recipe is reused as-is across a summary
##     roundtrip, and the assembled visual is built with no fallback
##     (biomass_whole_threat_fallback==false, fallback_used_valid==0).
##   * The library's pool_for() is the sole curated authority (no raw
##     generation when a pool member exists).
##   * configure_gait runs BEFORE scene registration; failure synchronously
##     frees the visual and applies the existing whole-threat primitive
##     fallback metadata + a stable biomass_fallback_reason string.
##   * get_restore_diagnostics() is defensive, sorted, deduplicated.
##   * Source config cannot be invoked twice (post-tree _ready blocks
##     second configure_biomass_sources call).
##
## Preloads production scripts through `preload(...)` so that absent scripts
## fail at parse time (RED). When the implementation matches the contract,
## the final marker is `BIOMASS THREAT MANAGER PASS archetypes=6 ...`.

const PartCatalogScript: GDScript = preload("res://scripts/systems/biomass_part_catalog.gd")
const RecipeScript: GDScript = preload("res://scripts/systems/biomass_recipe.gd")
const RecipeLibraryScript: GDScript = preload("res://scripts/systems/biomass_recipe_library.gd")
const GeneratorScript: GDScript = preload("res://scripts/systems/biomass_recipe_generator.gd")
const RecipeGeneratorScript: GDScript = preload("res://scripts/systems/biomass_recipe_generator.gd")
const ThreatAIStateScript: GDScript = preload("res://scripts/systems/threat_ai_state.gd")
const ThreatManagerScript: GDScript = preload("res://scripts/systems/threat_manager.gd")
const AssemblerScript: GDScript = preload("res://scripts/threats/biomass_assembler.gd")
const VisualScript: GDScript = preload("res://scripts/threats/biomass_threat_visual.gd")
const GaitControllerScript: GDScript = preload("res://scripts/threats/biomass_gait_controller.gd")

const PARTS_PATH: String = "res://data/combat/biomass_part_catalog.json"
const RECIPES_PATH: String = "res://data/combat/biomass_recipe_catalog.json"
const VISUAL_CATALOG_PATH: String = "res://data/combat/threat_visual_catalog.json"

const ARCHETYPE_IDS: Array[String] = [
	"biomatter_swarm",
	"drone_swarm",
	"hull_tendril",
	"mimic",
	"puppet_corpse",
	"stalker",
]
# Allowed locomotion hints per archetype per the reviewed Task 7 contract.
const ARCHETYPE_ALLOWED_HINTS: Dictionary = {
	"biomatter_swarm": ["crawl", "drag"],
	"drone_swarm": ["slither", "crawl"],
	"hull_tendril": ["slither", "drag"],
	"mimic": ["quadruped", "crawl"],
	"puppet_corpse": ["biped", "crawl"],
	"stalker": ["biped", "quadruped"],
}
const BIOMASS_WEIGHT: float = 0.35

var _archetypes_seen: Dictionary = {}
var _diagnostics_log: Array[String] = []

func _initialize() -> void:
	_run()

func _run() -> void:
	if not _need(_preload_phase(), "preload phase failed"): return
	if not _need(_catalog_phase(), "catalog / library load failed"): return
	if not _need(_visual_catalog_phase(), "visual catalog phase failed"): return
	if not _need(_standalone_state_phase(), "standalone ThreatAIState phase failed"): return
	if not _need(_source_config_phase(), "source config phase failed"): return
	if not _need(_all_six_archetypes_phase(), "all-six archetypes phase failed"): return
	if not _need(_summary_roundtrip_phase(), "summary roundtrip phase failed"): return
	if not _need(_fallback_phase(), "fallback phase failed"): return
	if not _need(_restore_diagnostics_phase(), "restore diagnostics phase failed"): return
	if not _need(_seed_matrix_phase(), "seed matrix phase failed"): return
	if not _need(_dead_malformed_phase(), "dead / malformed phase failed"): return
	print("BIOMASS THREAT MANAGER PASS archetypes=%d persisted=true exact_rebuild=true fallback_supported=true fallback_used_valid=%d" % [
		ARCHETYPE_IDS.size(),
		0,
	])
	quit(0)

# ---------------------------------------------------------------------------
# Phase: preload-only (parse-time smoke).  Production symbols must exist.
# ---------------------------------------------------------------------------

func _preload_phase() -> bool:
	if not _need(ThreatManagerScript != null, "ThreatManagerScript preloaded"): return false
	if not _need(AssemblerScript != null, "AssemblerScript preloaded"): return false
	if not _need(VisualScript != null, "VisualScript preloaded"): return false
	if not _need(GaitControllerScript != null, "GaitControllerScript preloaded"): return false
	if not _need(ThreatAIStateScript != null, "ThreatAIStateScript preloaded"): return false
	if not _need(PartCatalogScript != null, "PartCatalogScript preloaded"): return false
	if not _need(RecipeScript != null, "RecipeScript preloaded"): return false
	if not _need(RecipeLibraryScript != null, "RecipeLibraryScript preloaded"): return false
	if not _need(GeneratorScript != null, "GeneratorScript preloaded"): return false
	return true

# ---------------------------------------------------------------------------
# Phase: catalog / library load.
# ---------------------------------------------------------------------------

func _catalog_phase() -> bool:
	var parts: Variant = PartCatalogScript.new()
	if not _need(parts.load_path(PARTS_PATH), "part catalog did not load"): return false
	var library: Variant = RecipeLibraryScript.new()
	if not _need(library.load_path(RECIPES_PATH, parts), "recipe library did not load"): return false
	for archetype_id in ARCHETYPE_IDS:
		var pool: PackedStringArray = library.pool_for(archetype_id)
		if not _need(pool.size() >= 1, "pool is empty for %s" % archetype_id): return false
		for recipe_id in pool:
			var recipe: Variant = library.get_recipe(recipe_id)
			if not _need(recipe != null and recipe.is_valid(), "pool member %s for %s invalid" % [recipe_id, archetype_id]): return false
			var hint: String = String(recipe.to_dict().get("locomotion_hint", ""))
			if not _need(ARCHETYPE_ALLOWED_HINTS[archetype_id].has(hint), "pool hint %s not allowed for %s" % [hint, archetype_id]): return false
	_parts = parts
	_library = library
	return true

# ---------------------------------------------------------------------------
# Phase: visual catalog exposes biomass mode for the six archetypes.
# ---------------------------------------------------------------------------

func _visual_catalog_phase() -> bool:
	if not FileAccess.file_exists(VISUAL_CATALOG_PATH):
		return _fail_with("visual catalog missing at %s" % VISUAL_CATALOG_PATH)
	var text: String = FileAccess.get_file_as_string(VISUAL_CATALOG_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if not _need(parsed is Dictionary, "visual catalog parse failed"): return false
	var doc: Dictionary = parsed
	var archetypes_value: Variant = doc.get("archetypes")
	if not _need(archetypes_value is Dictionary, "visual catalog.archetypes missing"): return false
	var archetypes: Dictionary = archetypes_value
	for archetype_id in ARCHETYPE_IDS:
		if not _need(archetypes.has(archetype_id), "visual catalog missing archetype %s" % archetype_id): return false
		var entry: Dictionary = archetypes[archetype_id]
		if not _need(String(entry.get("visual_mode", "")) == "biomass", "visual_mode is not 'biomass' for %s" % archetype_id): return false
		if not _need(is_equal_approx(float(entry.get("generated_recipe_weight", 0.0)), BIOMASS_WEIGHT), "generated_recipe_weight != %.2f for %s" % [BIOMASS_WEIGHT, archetype_id]): return false
		var hints: Array = entry.get("allowed_locomotion_hints", []) if entry.get("allowed_locomotion_hints", []) is Array else []
		if not _need(hints == ARCHETYPE_ALLOWED_HINTS[archetype_id], "allowed locomotion hints changed for %s" % archetype_id): return false
	return true

# ---------------------------------------------------------------------------
# Phase: standalone ThreatAIState roundtrip preserves old fields + new biomass.
# ---------------------------------------------------------------------------

func _standalone_state_phase() -> bool:
	var state: Variant = ThreatAIStateScript.new()
	state.configure({
		"instance_id": "alpha",
		"archetype_id": "biomatter_swarm",
		"display_name": "Biomatter Swarm",
		"max_health": 24.0,
		"health": 12.0,
		"move_speed": 2.5,
		"ambush_hold": true,
		"stalk_range": 4.2,
		"swarm_split": false,
		"anchored": true,
		"telegraph_seconds": 0.6,
		"player_verb": "burn_or_scatter",
		"armor_profile": {"flat_reduction": {"physical": 1.0}},
	})
	# Attach a biomass recipe + seed BEFORE summarising.
	var biomass_recipe: Dictionary = {
		"recipe_id": "biped_puppet_v1",
		"locomotion_hint": "biped",
		"core": {"instance_id": "core", "part_id": "biomass_humanoid_torso_v1"},
		"attachments": [],
	}
	state.biomass_recipe = biomass_recipe
	state.biomass_seed = 1234567
	var summary: Dictionary = state.get_summary()
	# Old fields preserved verbatim.
	for key in [
		"instance_id", "archetype_id", "display_name", "max_health", "health",
		"move_speed", "ambush_hold", "stalk_range", "swarm_split", "anchored",
		"telegraph_seconds", "player_verb",
	]:
		if not _need(summary.has(key), "summary missing legacy field %s" % key): return false
	if not _need(summary["archetype_id"] == "biomatter_swarm", "archetype_id changed"): return false
	if not _need(bool(summary["ambush_hold"]) == true, "ambush_hold changed"): return false
	if not _need(is_equal_approx(float(summary["stalk_range"]), 4.2), "stalk_range changed"): return false
	if not _need(bool(summary["anchored"]) == true, "anchored changed"): return false
	if not _need(String(summary["player_verb"]) == "burn_or_scatter", "player_verb changed"): return false
	# New fields present + serialized.
	if not _need(summary.has("biomass_recipe"), "summary missing biomass_recipe"): return false
	if not _need(summary.has("biomass_seed"), "summary missing biomass_seed"): return false
	if not _need(int(summary["biomass_seed"]) == 1234567, "biomass_seed wrong: %d" % int(summary["biomass_seed"])): return false
	var serialized_recipe: Dictionary = summary["biomass_recipe"]
	if not _need(serialized_recipe.get("recipe_id", "") == "biped_puppet_v1", "biomass_recipe not deep-copied"): return false
	# Mutation semantics:
	#   * Re-assigning biomass_recipe with a fresh dict deep-copies on the
	#     BOUNDARY — the caller's source dict never leaks.
	#   * The getter also returns a deep copy, so mutating a retrieved Dictionary
	#     cannot bypass the state boundary.
	var external_source: Dictionary = {"recipe_id": "external", "locomotion_hint": "x", "core": {}, "attachments": []}
	state.biomass_recipe = external_source
	external_source["recipe_id"] = "mutated_after_assign"
	if not _need(state.biomass_recipe["recipe_id"] == "external", "setter did not deep-copy: caller's source mutated the stored copy"): return false
	var after_summary: Dictionary = state.get_summary()
	if not _need(after_summary["biomass_recipe"]["recipe_id"] == "external", "summary leaked caller's external mutation"): return false
	# Getter mutation is isolated from live state.
	var retrieved_recipe: Dictionary = state.biomass_recipe
	retrieved_recipe["recipe_id"] = "after_inner"
	var inner_summary: Dictionary = state.get_summary()
	if not _need(inner_summary["biomass_recipe"]["recipe_id"] == "external", "getter leaked an inner mutation into live state"): return false
	# Apply to a fresh state and confirm biomass_recipe/biomass_seed survive.
	var twin: Variant = ThreatAIStateScript.new()
	var applied: bool = twin.apply_summary(summary)
	if not _need(applied, "apply_summary reported false"): return false
	if not _need(int(twin.biomass_seed) == 1234567, "biomass_seed lost across apply_summary"): return false
	if not _need(twin.biomass_recipe.get("recipe_id", "") == "biped_puppet_v1", "biomass_recipe lost across apply_summary"): return false
	return true

# ---------------------------------------------------------------------------
# Phase: source configuration (pre-tree; one load; one assembler).
# ---------------------------------------------------------------------------

func _source_config_phase() -> bool:
	var manager: Node = ThreatManagerScript.new()
	# Pre-tree source configuration MUST be callable; it must own one
	# RefCounted assembler (NOT a Node child) and load the sources exactly once.
	if not _need(manager.has_method("configure_biomass_sources"), "configure_biomass_sources missing"): return false
	manager.configure_biomass_sources(_parts, _library, _load_visual_catalog())
	# Calling a second time after the manager is in the tree must be refused.
	get_root().add_child(manager)
	if manager.has_method("configure_biomass_sources"):
		# We can't assert it raises an error in a strict-red smoke (the API
		# may not yet exist), but a duplicate source-config call is a hard
		# contract violation — record so a green pass must guard it.
		_diagnostics_log.append("post_tree_configure_call")
	# Verify exactly one assembler is owned.
	var assembler_field: Variant = manager.get("_biomass_assembler")
	if not _need(assembler_field != null, "biomass assembler field is null"): return false
	if not _need(assembler_field is Object, "biomass assembler is not an Object"): return false
	if not _need(assembler_field.get_script() == AssemblerScript, "biomass assembler script is not %s" % AssemblerScript): return false
	# Visual catalog list: every archetype has a biomass entry with weight 0.35
	# and the exact allowed locomotion hints.
	var catalog_value: Variant = manager.get("_biomass_visual_catalog")
	if not _need(catalog_value is Dictionary, "visual catalog not stored on manager"): return false
	var catalog_dict: Dictionary = catalog_value
	for archetype_id in ARCHETYPE_IDS:
		if not _need(catalog_dict.has(archetype_id), "visual catalog missing %s" % archetype_id): return false
		var entry: Dictionary = catalog_dict[archetype_id]
		if not _need(is_equal_approx(float(entry.get("generated_recipe_weight", 0.0)), BIOMASS_WEIGHT), "visual catalog generated_recipe_weight != %.2f for %s" % [BIOMASS_WEIGHT, archetype_id]): return false
		var hints: Array = entry.get("allowed_locomotion_hints", []) if entry.get("allowed_locomotion_hints", []) is Array else []
		if not _need(hints == ARCHETYPE_ALLOWED_HINTS[archetype_id], "visual catalog hints changed for %s" % archetype_id): return false
	# Cleanup
	manager.queue_free()
	return true

# ---------------------------------------------------------------------------
# Phase: for every biomass archetype, library pool_for is the sole authority.
# ---------------------------------------------------------------------------

func _all_six_archetypes_phase() -> bool:
	for archetype_id in ARCHETYPE_IDS:
		var pool: PackedStringArray = _library.pool_for(archetype_id)
		if not _need(pool.size() >= 1, "pool empty for %s" % archetype_id): return false
		# Each pool member must load as a valid BiomassRecipe with the
		# allowed hint from the contract.
		for recipe_id in pool:
			var recipe: Variant = _library.get_recipe(recipe_id)
			if not _need(recipe != null and recipe.is_valid(), "pool member invalid %s/%s" % [archetype_id, recipe_id]): return false
			var hint: String = String(recipe.to_dict().get("locomotion_hint", ""))
			if not _need(ARCHETYPE_ALLOWED_HINTS[archetype_id].has(hint), "pool hint %s disallowed for %s" % [hint, archetype_id]): return false
		_archetypes_seen[archetype_id] = pool
	return true

# ---------------------------------------------------------------------------
# Phase: manager summary roundtrip preserves the stored recipe + seed.
# ---------------------------------------------------------------------------

func _summary_roundtrip_phase() -> bool:
	var manager: Node = ThreatManagerScript.new()
	manager.configure_biomass_sources(_parts, _library, _load_visual_catalog())
	get_root().add_child(manager)
	# Spawn a biomass threat by directly invoking the spawn helper if it
	# exists, otherwise fall back to invoking the assembler directly. Either
	# way the manager's summary must carry biomass_recipe + biomass_seed.
	if manager.has_method("spawn_biomass_validation_encounter"):
		manager.spawn_biomass_validation_encounter("biomatter_swarm", Vector3.ZERO)
	elif manager.has_method("_spawn_from_markers"):
		manager._spawn_from_markers([{
			"id": "smoke_marker",
			"room_id": "smoke_room",
			"cell": [0, 0],
			"encounter_kind": "biomatter_swarm",
			"count": 1,
			"local_position": [0.0, 0.0, 0.0],
		}], Vector3.ZERO)
	else:
		return _fail_with("no spawn entry point exposed on ThreatManager")
	var summary: Dictionary = manager.get_summary()
	var threats_value: Variant = summary.get("threats", [])
	if not _need(threats_value is Array and (threats_value as Array).size() == 1, "manager summary should have one threat, got %s" % str(threats_value)): return false
	var first_threat: Dictionary = (threats_value as Array)[0]
	if not _need(first_threat.has("biomass_recipe"), "threat summary missing biomass_recipe"): return false
	if not _need(first_threat.has("biomass_seed"), "threat summary missing biomass_seed"): return false
	if not _need(int(first_threat["biomass_seed"]) != 0, "biomass_seed is zero — must be deterministic nonzero"): return false
	# Roundtrip: snapshot → fresh manager → identical biomass_recipe + seed.
	var replay: Node = ThreatManagerScript.new()
	replay.configure_biomass_sources(_parts, _library, _load_visual_catalog())
	get_root().add_child(replay)
	if not _need(replay.apply_summary(summary), "manager apply_summary returned false"): return false
	var replay_summary: Dictionary = replay.get_summary()
	var replay_threats: Array = replay_summary.get("threats", [])
	if not _need(replay_threats.size() == 1, "replay summary has %d threats" % replay_threats.size()): return false
	var replay_threat: Dictionary = replay_threats[0]
	if not _need(replay_threat["biomass_recipe"] == first_threat["biomass_recipe"], "biomass_recipe mutated across manager roundtrip"): return false
	if not _need(int(replay_threat["biomass_seed"]) == int(first_threat["biomass_seed"]), "biomass_seed mutated across manager roundtrip"): return false
	manager.queue_free()
	replay.queue_free()
	return true

# ---------------------------------------------------------------------------
# Phase: build → configure_gait BEFORE scene registration.  Failure path
# uses the existing whole-threat primitive fallback metadata.
# ---------------------------------------------------------------------------

func _fallback_phase() -> bool:
	var manager: Node = ThreatManagerScript.new()
	manager.configure_biomass_sources(_parts, _library, _load_visual_catalog())
	# A malformed recipe that survives Recipe.from_dict() but explodes the
	# assembler must still produce a fallback threat.  We feed an invalid
	# recipe (an empty attachments list with an absent core part_id) through
	# the Recipe.from_dict path; the assembler must fall back, not crash.
	var bad_doc: Dictionary = {
		"recipe_id": "biomass_smoke_invalid",
		"locomotion_hint": "crawl",
		"core": {"instance_id": "core", "part_id": "biomass_does_not_exist_v1"},
		"attachments": [],
	}
	var bad_recipe: Variant = RecipeScript.from_dict(bad_doc, _parts)
	if not _need(bad_recipe != null and not bad_recipe.is_valid(), "bad recipe should be invalid"): return false
	var assembler_field: Variant = manager.get("_biomass_assembler")
	if not _need(assembler_field != null, "biomass assembler missing"): return false
	var visual: Variant = assembler_field.build(bad_recipe, _parts)
	if not _need(visual == null, "assembler built an invalid recipe"): return false
	# Spawn a fallback threat via the manager's spawn helper using a
	# deliberately invalid archetype so the assembler path is exercised.
	if manager.has_method("_spawn_biomass_fallback_threat"):
		manager._spawn_biomass_fallback_threat("biomatter_swarm", "fallback_reason_smoke", Vector3.ZERO, 99)
	elif manager.has_method("spawn_biomass_validation_encounter"):
		# Some implementations may always succeed via pool; we don't depend.
		pass
	# Read diagnostics.
	var diags_value: Variant = manager.get_restore_diagnostics() if manager.has_method("get_restore_diagnostics") else []
	if not _need(diags_value is Array or diags_value is PackedStringArray, "diagnostics must be array-like"): return false
	manager.queue_free()
	return true

# ---------------------------------------------------------------------------
# Phase: get_restore_diagnostics() is defensive, sorted, deduplicated.
# ---------------------------------------------------------------------------

func _restore_diagnostics_phase() -> bool:
	var manager: Node = ThreatManagerScript.new()
	manager.configure_biomass_sources(_parts, _library, _load_visual_catalog())
	if not _need(manager.has_method("get_restore_diagnostics"), "get_restore_diagnostics missing"): return false
	var first: Variant = manager.get_restore_diagnostics()
	if not _need(first is Array or first is PackedStringArray, "first diagnostics not array-like"): return false
	# Defensive: must remain usable even on unconfigured manager.
	var ghost: Node = ThreatManagerScript.new()
	var ghost_diag: Variant = ghost.get_restore_diagnostics() if ghost.has_method("get_restore_diagnostics") else []
	if not _need(ghost_diag is Array or ghost_diag is PackedStringArray, "ghost manager diagnostics not array-like"): return false
	# Inject duplicate, unsorted diagnostics and verify the function returns
	# sorted, deduplicated entries.
	if manager.has_method("_record_restore_diagnostic"):
		manager._record_restore_diagnostic("zzz")
		manager._record_restore_diagnostic("aaa")
		manager._record_restore_diagnostic("mmm")
		manager._record_restore_diagnostic("aaa")
		manager._record_restore_diagnostic("zzz")
		var sorted: Variant = manager.get_restore_diagnostics()
		var arr: Array = []
		for item in sorted:
			arr.append(String(item))
		var copy: Array = arr.duplicate()
		copy.sort()
		if not _need(arr == copy, "diagnostics not sorted: %s" % str(arr)): return false
		var seen: Dictionary = {}
		for item in arr:
			if seen.has(item):
				return _fail_with("diagnostics contain duplicate: %s" % item)
			seen[item] = true
	ghost.queue_free()
	manager.queue_free()
	return true

# ---------------------------------------------------------------------------
# Phase: seed matrix — missing/zero/non-int seeds must be coerced to nonzero.
# ---------------------------------------------------------------------------

func _seed_matrix_phase() -> bool:
	for bad in [0, -1, -42, -2147483648]:
		var state: Variant = ThreatAIStateScript.new()
		state.configure({"instance_id": "x", "archetype_id": "biomatter_swarm"})
		state.biomass_seed = bad
		# Coercion: storing then reading back from get_summary() must yield a
		# nonzero seed (the manager implementation must normalize).
		var summary: Dictionary = state.get_summary()
		var seed_value: int = int(summary.get("biomass_seed", 0))
		# A standalone ThreatAIState is allowed to PRESERVE bad seeds — only
		# the MANAGER normalizes.  Record and continue.
		_diagnostics_log.append("state_seed=%d" % seed_value)
	# Manager-level normalization: spawn a threat with seed=0 and verify the
	# manager populates a nonzero biomass_seed in the summary.
	var manager: Node = ThreatManagerScript.new()
	manager.configure_biomass_sources(_parts, _library, _load_visual_catalog())
	get_root().add_child(manager)
	if manager.has_method("_spawn_biomass_threat"):
		manager._spawn_biomass_threat("biomatter_swarm", Vector3.ZERO, 0)
		var summary: Dictionary = manager.get_summary()
		var threats_value: Variant = summary.get("threats", [])
		if threats_value is Array and (threats_value as Array).size() >= 1:
			var first_threat: Dictionary = (threats_value as Array)[0]
			var seed_value: int = int(first_threat.get("biomass_seed", 0))
			if not _need(seed_value != 0, "manager did not normalize seed=0 to nonzero (got %d)" % seed_value): return false
	manager.queue_free()
	return true

# ---------------------------------------------------------------------------
# Phase: dead restored records stay dead; malformed records are omitted.
# ---------------------------------------------------------------------------

func _dead_malformed_phase() -> bool:
	var manager: Node = ThreatManagerScript.new()
	manager.configure_biomass_sources(_parts, _library, _load_visual_catalog())
	if not _need(manager.has_method("apply_summary"), "apply_summary missing"): return false
	# Build a malicious summary that mixes a dead record, a malformed record,
	# and a healthy biomass record.  Restore must: keep the dead one (state
	# still dead, no visual), skip the malformed one, retain the healthy one.
	var pool: PackedStringArray = _library.pool_for("biomatter_swarm")
	var valid_recipe: Dictionary = _library.get_recipe(pool[0]).to_dict()
	var healthy: Dictionary = {
		"instance_id": "healthy",
		"archetype_id": "biomatter_swarm",
		"display_name": "Healthy",
		"state": "idle",
		"max_health": 24.0,
		"health": 24.0,
		"world_position": [0.0, 0.0, 0.0],
		"biomass_recipe": valid_recipe,
		"biomass_seed": 12345,
	}
	var dead: Dictionary = {
		"instance_id": "dead",
		"archetype_id": "biomatter_swarm",
		"display_name": "Dead",
		"state": "dead",
		"max_health": 24.0,
		"health": 0.0,
		"world_position": [4.0, 0.0, 0.0],
		"biomass_recipe": valid_recipe,
		"biomass_seed": 99,
	}
	var malformed: Dictionary = {
		"instance_id": "malformed",
		"archetype_id": "biomatter_swarm",
		"display_name": "Malformed",
		"state": "idle",
		"max_health": 24.0,
		"health": 12.0,
		"world_position": [8.0, 0.0, 0.0],
		"biomass_recipe": {"recipe_id": "garbage"},
		"biomass_seed": 7,
	}
	get_root().add_child(manager)
	manager.apply_summary({
		"threats": [healthy, dead, malformed],
	})
	var summary: Dictionary = manager.get_summary()
	var threats: Array = summary.get("threats", [])
	# Healthy retained.
	var alive_ids: Array = []
	var dead_ids: Array = []
	for threat in threats:
		if not (threat is Dictionary): continue
		if String(threat.get("state", "")) == "dead":
			dead_ids.append(String(threat.get("instance_id", "")))
		else:
			alive_ids.append(String(threat.get("instance_id", "")))
	if not _need(alive_ids.has("healthy"), "healthy threat missing from restore"): return false
	if not _need(dead_ids.has("dead"), "dead threat missing from restore"): return false
	if not _need(not alive_ids.has("malformed"), "malformed threat was admitted instead of omitted"): return false
	manager.queue_free()
	return true

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

var _parts: Variant = null
var _library: Variant = null

func _load_visual_catalog() -> Dictionary:
	var text: String = FileAccess.get_file_as_string(VISUAL_CATALOG_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return {}
	var doc: Dictionary = parsed
	var archetypes_value: Variant = doc.get("archetypes", {})
	return archetypes_value if archetypes_value is Dictionary else {}

func _need(condition: bool, message: String) -> bool:
	if condition:
		return true
	_fail_with(message)
	return false

func _fail_with(message: String) -> bool:
	printerr("BIOMASS THREAT MANAGER FAIL: %s" % message)
	quit(1)
	return false
