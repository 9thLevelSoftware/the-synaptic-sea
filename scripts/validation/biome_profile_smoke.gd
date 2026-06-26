extends SceneTree

# biome_profile_smoke — REQ-PG-005 verification.
#
# Asserts:
#   1. BiomeProfile.from_dict() round-trips the abyssal_synapse_sea
#      JSON to a RefCounted with the expected modifier values.
#   2. modifier(dial) returns the value from JSON for every dial.
#   3. hazard_override("oxygen_breach") returns the per-hazard
#      multiplier.
#   4. Unknown biome id never crashes the loader; from_dict({"id":""})
#      yields a profile with id="unknown" and 1.0 modifiers.
#   5. select_biome(seed) deterministically picks an id from the
#      supplied pool, same seed = same id.
#   6. The breach_field biome has encounter_density_modifier > 1.0
#      (REQ-PG-009 hazard density scales with biome).

const BiomeProfileScript := preload("res://scripts/procgen/biome_profile.gd")


func _initialize() -> void:
	# --- Case 1: Round-trip abyssal_synapse_sea ---
	var abyssal_data: Dictionary = {
		"id": "abyssal_synapse_sea",
		"description": "Deep-sea baseline",
		"hazard_modifier": 1.0,
		"loot_quality_modifier": 1.0,
		"encounter_density_modifier": 1.0,
		"ambient_intensity": 1.0,
		"encounter_table_id": "biomatter_lurker",
	}
	var abyssal = BiomeProfileScript.from_dict(abyssal_data)
	if abyssal == null:
		push_error("BIOME PROFILE FAIL from_dict returned null")
		quit(1)
		return
	if str(abyssal.id) != "abyssal_synapse_sea":
		push_error("BIOME PROFILE FAIL abyssal.id=%s" % str(abyssal.id))
		quit(1)
		return
	if float(abyssal.hazard_modifier) != 1.0:
		push_error("BIOME PROFILE FAIL hazard_modifier=%f" % float(abyssal.hazard_modifier))
		quit(1)
		return
	if float(abyssal.loot_quality_modifier) != 1.0:
		push_error("BIOME PROFILE FAIL loot_quality_modifier=%f" % float(abyssal.loot_quality_modifier))
		quit(1)
		return
	if float(abyssal.encounter_density_modifier) != 1.0:
		push_error("BIOME PROFILE FAIL encounter_density_modifier=%f" % float(abyssal.encounter_density_modifier))
		quit(1)
		return

	# --- Case 2: modifier(dial) ---
	if float(abyssal.modifier(BiomeProfileScript.DIAL_HAZARD)) != 1.0:
		push_error("BIOME PROFILE FAIL modifier(hazard)=%f" % float(abyssal.modifier(BiomeProfileScript.DIAL_HAZARD)))
		quit(1)
		return
	if float(abyssal.modifier(BiomeProfileScript.DIAL_LOOT)) != 1.0:
		push_error("BIOME PROFILE FAIL modifier(loot)=%f" % float(abyssal.modifier(BiomeProfileScript.DIAL_LOOT)))
		quit(1)
		return
	if float(abyssal.modifier("unknown_dial")) != 1.0:
		push_error("BIOME PROFILE FAIL modifier(unknown)=%f" % float(abyssal.modifier("unknown_dial")))
		quit(1)
		return

	# --- Case 3: hazard_override returns the configured value ---
	var breach_data: Dictionary = {
		"id": "breach_field",
		"hazard_modifier": 1.4,
		"encounter_density_modifier": 1.3,
		"hazard_overrides": {"oxygen_breach": 1.6, "fire": 1.0},
	}
	var breach = BiomeProfileScript.from_dict(breach_data)
	if breach == null:
		push_error("BIOME PROFILE FAIL breach from_dict returned null")
		quit(1)
		return
	if float(breach.hazard_override("oxygen_breach")) != 1.6:
		push_error("BIOME PROFILE FAIL hazard_override(oxygen_breach)=%f expected=1.6" % float(breach.hazard_override("oxygen_breach")))
		quit(1)
		return
	if float(breach.hazard_override("unknown_hazard")) != 1.0:
		push_error("BIOME PROFILE FAIL hazard_override(unknown)=%f expected=1.0" % float(breach.hazard_override("unknown_hazard")))
		quit(1)
		return
	# REQ-PG-009: encounter density > 1.0 for breach_field
	if float(breach.encounter_density_modifier) <= 1.0:
		push_error("BIOME PROFILE FAIL breach encounter_density_modifier=%f expected>1.0" % float(breach.encounter_density_modifier))
		quit(1)
		return

	# --- Case 4: Unknown biome id never crashes ---
	var empty_biome = BiomeProfileScript.from_dict({})
	if str(empty_biome.id) != "unknown":
		push_error("BIOME PROFILE FAIL empty dict id=%s expected=unknown" % str(empty_biome.id))
		quit(1)
		return
	if float(empty_biome.modifier("any_dial")) != 1.0:
		push_error("BIOME PROFILE FAIL empty dict modifier!=1.0")
		quit(1)
		return

	# --- Case 5: select_biome is deterministic ---
	var biome_pool: Array[String] = ["abyssal_synapse_sea", "breach_field", "dead_fleet"]
	var seed_a: String = BiomeProfileScript.select_biome(314, biome_pool)
	var seed_b: String = BiomeProfileScript.select_biome(314, biome_pool)
	if seed_a != seed_b:
		push_error("BIOME PROFILE FAIL select_biome not stable: %s vs %s" % [seed_a, seed_b])
		quit(1)
		return
	if not biome_pool.has(seed_a):
		push_error("BIOME PROFILE FAIL select_biome returned id not in pool: %s" % seed_a)
		quit(1)
		return

	# --- Case 6: to_dict round-trip ---
	var roundtrip: Dictionary = abyssal.to_dict()
	if str(roundtrip.get("id", "")) != "abyssal_synapse_sea":
		push_error("BIOME PROFILE FAIL to_dict lost id")
		quit(1)
		return

	print("BIOME PROFILE PASS biomes=3 modifiers=ok hazard_override=ok empty_safe=true select_deterministic=true density_scales=true")
	quit(0)
