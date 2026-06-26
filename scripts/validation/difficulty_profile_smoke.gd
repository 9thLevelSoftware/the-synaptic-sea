extends SceneTree

# difficulty_profile_smoke — REQ-PG-006 verification.
#
# Asserts:
#   1. DifficultyProfile.from_dict() round-trips the standard /
#      hardened / deep_dive presets.
#   2. modifier(dial) returns the JSON value; unknown dial returns 1.0.
#   3. combined_modifier() multiplies biome × difficulty and clamps
#      the result to [0.0, 3.0] (REQ-PG-009 + RISK-012).
#   4. Unknown difficulty id is reported with a default profile.
#   5. select_difficulty(seed) is deterministic.
#   6. Hardened preset has hazard_modifier > standard; deep_dive has
#      higher encounter_density_modifier than hardened.

const DifficultyProfileScript := preload("res://scripts/procgen/difficulty_profile.gd")
const BiomeProfileScript := preload("res://scripts/procgen/biome_profile.gd")


func _initialize() -> void:
	# --- Case 1: Round-trip all three presets ---
	var standard = DifficultyProfileScript.from_dict({
		"id": "standard",
		"hazard_modifier": 1.0,
		"loot_quality_modifier": 1.0,
		"encounter_density_modifier": 1.0,
	})
	if float(standard.hazard_modifier) != 1.0:
		push_error("DIFFICULTY PROFILE FAIL standard.hazard_modifier=%f" % float(standard.hazard_modifier))
		quit(1)
		return

	var hardened = DifficultyProfileScript.from_dict({
		"id": "hardened",
		"hazard_modifier": 1.4,
		"loot_quality_modifier": 0.85,
		"encounter_density_modifier": 1.3,
	})
	if float(hardened.hazard_modifier) != 1.4:
		push_error("DIFFICULTY PROFILE FAIL hardened.hazard_modifier=%f" % float(hardened.hazard_modifier))
		quit(1)
		return
	if float(hardened.loot_quality_modifier) != 0.85:
		push_error("DIFFICULTY PROFILE FAIL hardened.loot_quality_modifier=%f" % float(hardened.loot_quality_modifier))
		quit(1)
		return

	var deep_dive = DifficultyProfileScript.from_dict({
		"id": "deep_dive",
		"hazard_modifier": 1.7,
		"encounter_density_modifier": 1.6,
	})
	if float(deep_dive.hazard_modifier) != 1.7:
		push_error("DIFFICULTY PROFILE FAIL deep_dive.hazard_modifier=%f" % float(deep_dive.hazard_modifier))
		quit(1)
		return

	# --- Case 2: modifier(dial) ---
	if float(deep_dive.modifier(DifficultyProfileScript.DIAL_HAZARD)) != 1.7:
		push_error("DIFFICULTY PROFILE FAIL modifier(hazard)=%f" % float(deep_dive.modifier(DifficultyProfileScript.DIAL_HAZARD)))
		quit(1)
		return
	if float(deep_dive.modifier("unknown_dial")) != 1.0:
		push_error("DIFFICULTY PROFILE FAIL modifier(unknown)=%f" % float(deep_dive.modifier("unknown_dial")))
		quit(1)
		return

	# --- Case 3: combined_modifier() clamps to [0.0, 3.0] ---
	# breach_field (1.4) × deep_dive (1.7) = 2.38 (in range).
	var breach = BiomeProfileScript.from_dict({"id": "breach_field",
		"hazard_modifier": 1.4, "encounter_density_modifier": 1.3})
	var combined: float = float(DifficultyProfileScript.combined_modifier(
		breach, deep_dive, DifficultyProfileScript.DIAL_HAZARD))
	if abs(combined - 2.38) > 0.01:
		push_error("DIFFICULTY PROFILE FAIL combined(breach, deep_dive, hazard)=%f expected~2.38" % combined)
		quit(1)
		return
	# Composition above 3.0 must clamp. Synthesize a biome with
	# extreme hazard and pair with deep_dive.
	var extreme_biome = BiomeProfileScript.from_dict({"id": "extreme",
		"hazard_modifier": 2.5})
	var clamped: float = float(DifficultyProfileScript.combined_modifier(
		extreme_biome, deep_dive, DifficultyProfileScript.DIAL_HAZARD))
	# 2.5 * 1.7 = 4.25, clamped to 3.0.
	if clamped != 3.0:
		push_error("DIFFICULTY PROFILE FAIL combined clamp: %f expected=3.0" % clamped)
		quit(1)
		return
	# Null biome is identity (1.0).
	var with_null: float = float(DifficultyProfileScript.combined_modifier(
		null, deep_dive, DifficultyProfileScript.DIAL_HAZARD))
	if abs(with_null - 1.7) > 0.01:
		push_error("DIFFICULTY PROFILE FAIL null biome: %f expected~1.7" % with_null)
		quit(1)
		return

	# --- Case 4: Unknown id produces default ---
	var unknown = DifficultyProfileScript.from_dict({})
	if str(unknown.id) != DifficultyProfileScript.STANDARD_ID:
		push_error("DIFFICULTY PROFILE FAIL empty dict id=%s expected=%s" % [str(unknown.id), DifficultyProfileScript.STANDARD_ID])
		quit(1)
		return

	# --- Case 5: select_deterministic ---
	var pool: Array[String] = ["standard", "hardened", "deep_dive"]
	var pick_a: String = DifficultyProfileScript.select_difficulty(314, pool)
	var pick_b: String = DifficultyProfileScript.select_difficulty(314, pool)
	if pick_a != pick_b:
		push_error("DIFFICULTY PROFILE FAIL not stable: %s vs %s" % [pick_a, pick_b])
		quit(1)
		return
	if not pool.has(pick_a):
		push_error("DIFFICULTY PROFILE FAIL pick not in pool: %s" % pick_a)
		quit(1)
		return

	# --- Case 6: Order check ---
	if not (float(hardened.hazard_modifier) > float(standard.hazard_modifier)):
		push_error("DIFFICULTY PROFILE FAIL hardened hazard <= standard")
		quit(1)
		return
	if not (float(deep_dive.encounter_density_modifier) > float(hardened.encounter_density_modifier)):
		push_error("DIFFICULTY PROFILE FAIL deep_dive encounter <= hardened")
		quit(1)
		return

	print("DIFFICULTY PROFILE PASS presets=3 modifiers=ok combined_clamped=true null_safe=true select_deterministic=true order=ok")
	quit(0)
