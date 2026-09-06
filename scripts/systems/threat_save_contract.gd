extends RefCounted
class_name ThreatSaveContract

const SCHEMA: String = "threat-manager-2"
const LEGACY_STRUCTURE_DAMAGE: Dictionary = {
    "hull_tendril": 0.4,
    "biomatter_swarm": 0.0,
    "puppet_corpse": 0.0,
    "stalker": 0.0,
    "mimic": 0.0,
    "drone_swarm": 0.0,
}

const THREAT_STRING_FIELDS: Array[String] = [
    "instance_id", "archetype_id", "display_name", "room_id", "state",
    "previous_state", "attack_type", "last_known_room", "status_on_hit",
    "player_verb",
]
const THREAT_NUMBER_FIELDS: Array[String] = [
    "max_health", "health", "attack_damage", "structure_damage",
    "attack_noise", "attack_interval", "attack_cooldown", "noise_sensitivity",
    "light_sensitivity", "sight_sensitivity", "memory_seconds",
    "memory_remaining", "flee_threshold", "stunned_remaining",
    "awareness_score", "move_speed", "hunt_speed_mult", "flee_speed_mult",
    "investigate_speed_mult", "attack_range", "stalk_range",
    "telegraph_seconds", "telegraph_remaining",
]
const THREAT_BOOL_FIELDS: Array[String] = [
    "ambush_hold", "swarm_split", "anchored",
]
const DETECTION_NUMBER_FIELDS: Array[String] = [
    "noise_level", "light_level", "sight_level", "detect_threshold",
    "memory_seconds", "memory_remaining", "awareness_score",
]
const DETECTION_BOOL_FIELDS: Array[String] = [
    "crouching", "detected", "heard", "seen",
]
const ATTACK_RESULT_BASE_FIELDS: Array[String] = [
    "damage_type", "incoming", "flat_reduction", "resistance", "absorbed",
    "final_damage", "durability", "profile", "source_id", "status_effect_id",
    "noise",
]
const ATTACK_RESULT_WEAPON_FIELDS: Array[String] = [
    "stun_seconds", "ok", "weapon_id", "target_id", "ammo_item_id",
    "ammo_remaining",
]
const ATTACK_RESULT_PROFILE_FIELDS: Array[String] = [
    "flat_reduction", "resistance", "durability", "max_durability",
    "wear_factor",
]


static func validate_current(summary: Variant) -> Dictionary:
    if not summary is Dictionary:
        return _failure("combat_summary_not_dictionary")
    var source: Dictionary = summary as Dictionary
    if source.is_empty():
        return _failure("combat_summary_empty")
    if typeof(source.get("schema", null)) != TYPE_STRING \
            or str(source.get("schema", "")) != SCHEMA:
        return _failure("unsupported_combat_schema")
    for key in [
        "encounter_markers", "threats", "detection", "awareness_indicator",
        "combat_engaged", "last_attack_result", "damage_pipeline",
    ]:
        if not source.has(key):
            return _failure("combat_missing_%s" % key)
    if not source.encounter_markers is Array:
        return _failure("combat_invalid_encounter_markers")
    for marker in source.encounter_markers as Array:
        if not marker is Dictionary or not _valid_json_value(marker):
            return _failure("combat_invalid_encounter_marker")
    if not source.threats is Array:
        return _failure("combat_invalid_threats")
    var seen_ids: Dictionary = {}
    for row in source.threats as Array:
        var reason: String = _validate_threat(row)
        if not reason.is_empty():
            return _failure(reason)
        var instance_id: String = str((row as Dictionary).instance_id)
        if seen_ids.has(instance_id):
            return _failure("combat_duplicate_threat_id")
        seen_ids[instance_id] = true
    var detection_reason: String = _validate_detection(source.detection)
    if not detection_reason.is_empty():
        return _failure(detection_reason)
    if not _finite_number(source.awareness_indicator) \
            or float(source.awareness_indicator) < 0.0 \
            or float(source.awareness_indicator) > 3.0:
        return _failure("combat_invalid_awareness_indicator")
    if typeof(source.combat_engaged) != TYPE_BOOL:
        return _failure("combat_invalid_engaged")
    var attack_result_reason: String = _validate_last_attack_result(
        source.last_attack_result)
    if not attack_result_reason.is_empty():
        return _failure(attack_result_reason)
    var damage_reason: String = _validate_damage_pipeline(source.damage_pipeline)
    if not damage_reason.is_empty():
        return _failure(damage_reason)
    return {"ok": true, "reason": "", "summary": source.duplicate(true)}


static func migrate_legacy(summary: Variant) -> Dictionary:
    if not summary is Dictionary:
        return _failure("legacy_combat_not_dictionary")
    var source: Dictionary = summary as Dictionary
    if source.is_empty():
        return _failure("legacy_combat_empty_requires_bootstrap")
    if source.has("schema"):
        return _failure("legacy_combat_has_schema")
    var threats_value: Variant = source.get("threats", null)
    if not threats_value is Array:
        return _failure("legacy_combat_invalid_threats")
    var migrated: Dictionary = source.duplicate(true)
    var rows: Array = (migrated.threats as Array).duplicate(true)
    for index in range(rows.size()):
        if not rows[index] is Dictionary:
            return _failure("legacy_combat_invalid_threat_row")
        var row: Dictionary = (rows[index] as Dictionary).duplicate(true)
        if row.has("structure_damage"):
            return _failure("legacy_combat_mixed_structure_damage")
        if typeof(row.get("archetype_id", null)) != TYPE_STRING \
                or str(row.archetype_id).is_empty():
            return _failure("legacy_combat_invalid_archetype")
        var archetype_id: String = row.archetype_id as String
        if not LEGACY_STRUCTURE_DAMAGE.has(archetype_id):
            return _failure("legacy_combat_unknown_archetype:%s" % archetype_id)
        row["structure_damage"] = LEGACY_STRUCTURE_DAMAGE[archetype_id]
        rows[index] = row
    migrated["threats"] = rows
    migrated["schema"] = SCHEMA
    return validate_current(migrated)


static func _validate_threat(value: Variant) -> String:
    if not value is Dictionary:
        return "combat_invalid_threat_row"
    var row: Dictionary = value as Dictionary
    for key in THREAT_STRING_FIELDS:
        if not row.has(key) or typeof(row[key]) != TYPE_STRING:
            return "combat_invalid_threat_%s" % key
    if str(row.instance_id).is_empty() or str(row.archetype_id).is_empty():
        return "combat_invalid_threat_identity"
    for key in THREAT_NUMBER_FIELDS:
        if not row.has(key) or not _finite_number(row[key]):
            return "combat_invalid_threat_%s" % key
    if float(row.max_health) < 1.0 or float(row.health) < 0.0 \
            or float(row.health) > float(row.max_health):
        return "combat_invalid_threat_health"
    for key in [
        "attack_damage", "structure_damage", "attack_noise", "attack_cooldown",
        "noise_sensitivity", "light_sensitivity", "sight_sensitivity",
        "memory_seconds", "memory_remaining", "stunned_remaining", "stalk_range",
        "telegraph_seconds", "telegraph_remaining",
    ]:
        if float(row[key]) < 0.0:
            return "combat_invalid_threat_%s" % key
    if float(row.attack_interval) < 0.1 \
            or float(row.flee_threshold) < 0.0 or float(row.flee_threshold) > 0.95 \
            or float(row.awareness_score) < 0.0 or float(row.awareness_score) > 3.0 \
            or float(row.move_speed) < 0.1 or float(row.hunt_speed_mult) < 0.1 \
            or float(row.flee_speed_mult) < 0.1 \
            or float(row.investigate_speed_mult) < 0.1 \
            or float(row.attack_range) < 0.3:
        return "combat_invalid_threat_bounded_number"
    for key in THREAT_BOOL_FIELDS:
        if not row.has(key) or typeof(row[key]) != TYPE_BOOL:
            return "combat_invalid_threat_%s" % key
    if not _valid_numeric_array(row.get("cell", null), 2, false):
        return "combat_invalid_threat_cell"
    if not _valid_numeric_array(row.get("world_position", null), 3, true):
        return "combat_invalid_threat_world_position"
    var last_position: Variant = row.get("last_known_position", null)
    if not last_position is Array \
            or (not (last_position as Array).is_empty() \
                and not _valid_numeric_array(last_position, 3, true)):
        return "combat_invalid_threat_last_known_position"
    if not row.get("tags", null) is Array:
        return "combat_invalid_threat_tags"
    for tag in row.tags as Array:
        if typeof(tag) != TYPE_STRING:
            return "combat_invalid_threat_tag"
    if not row.get("armor_profile", null) is Dictionary \
            or not _validate_armor_profile(row.armor_profile as Dictionary, false).is_empty():
        return "combat_invalid_threat_armor_profile"
    return ""


static func _validate_detection(value: Variant) -> String:
    if not value is Dictionary:
        return "combat_invalid_detection"
    var detection: Dictionary = value as Dictionary
    for key in DETECTION_NUMBER_FIELDS:
        if not detection.has(key) or not _finite_number(detection[key]):
            return "combat_invalid_detection_%s" % key
    for key in DETECTION_BOOL_FIELDS:
        if not detection.has(key) or typeof(detection[key]) != TYPE_BOOL:
            return "combat_invalid_detection_%s" % key
    for key in ["room_id", "last_reason"]:
        if not detection.has(key) or typeof(detection[key]) != TYPE_STRING:
            return "combat_invalid_detection_%s" % key
    if float(detection.noise_level) < 0.0 or float(detection.noise_level) > 2.0 \
            or float(detection.light_level) < 0.0 or float(detection.light_level) > 2.0 \
            or float(detection.sight_level) < 0.0 or float(detection.sight_level) > 2.0 \
            or float(detection.detect_threshold) < 0.0 \
            or float(detection.memory_seconds) < 0.0 \
            or float(detection.memory_remaining) < 0.0 \
            or float(detection.awareness_score) < 0.0 \
            or float(detection.awareness_score) > 3.0:
        return "combat_invalid_detection_bounds"
    return ""


static func _validate_damage_pipeline(value: Variant) -> String:
    if not value is Dictionary:
        return "combat_invalid_damage_pipeline"
    var damage: Dictionary = value as Dictionary
    for key in ["processed_hits", "total_damage_applied", "total_noise_generated"]:
        if not damage.has(key) or not _finite_number(damage[key]) or float(damage[key]) < 0.0:
            return "combat_invalid_damage_%s" % key
    if float(damage.processed_hits) != floor(float(damage.processed_hits)):
        return "combat_invalid_damage_processed_hits"
    if not damage.get("last_result", null) is Dictionary \
            or not _valid_json_value(damage.last_result):
        return "combat_invalid_damage_last_result"
    var resolver_value: Variant = damage.get("armor_resolver", null)
    if not resolver_value is Dictionary:
        return "combat_invalid_armor_resolver"
    var resolver: Dictionary = resolver_value as Dictionary
    if not resolver.get("armor_profile", null) is Dictionary:
        return "combat_invalid_armor_profile"
    var armor_reason: String = _validate_armor_profile(
        resolver.armor_profile as Dictionary, true)
    if not armor_reason.is_empty():
        return armor_reason
    if not resolver.get("last_resolution", null) is Dictionary \
            or not _valid_json_value(resolver.last_resolution):
        return "combat_invalid_armor_last_resolution"
    return ""


static func _validate_last_attack_result(value: Variant) -> String:
    if not value is Dictionary:
        return "combat_invalid_last_attack_result"
    var result: Dictionary = value as Dictionary
    if result.is_empty():
        return ""
    var expected: Array[String] = ATTACK_RESULT_BASE_FIELDS.duplicate()
    var is_weapon_receipt: bool = result.has("weapon_id")
    if is_weapon_receipt:
        expected.append_array(ATTACK_RESULT_WEAPON_FIELDS)
    if not _has_exact_string_keys(result, expected):
        return "combat_invalid_last_attack_result_shape"
    for key in ["damage_type", "source_id", "status_effect_id"]:
        if typeof(result[key]) != TYPE_STRING:
            return "combat_invalid_last_attack_result_%s" % key
    if str(result.damage_type).is_empty() or str(result.source_id).is_empty():
        return "combat_invalid_last_attack_result_identity"
    for key in [
        "incoming", "flat_reduction", "absorbed", "final_damage",
        "durability", "noise",
    ]:
        if not _finite_number(result[key]) or float(result[key]) < 0.0:
            return "combat_invalid_last_attack_result_%s" % key
    if not _finite_number(result.resistance) \
            or float(result.resistance) < -0.9 \
            or float(result.resistance) > 0.95:
        return "combat_invalid_last_attack_result_resistance"
    if not result.profile is Dictionary \
            or not _has_exact_string_keys(
                result.profile as Dictionary, ATTACK_RESULT_PROFILE_FIELDS):
        return "combat_invalid_last_attack_result_profile"
    var profile_reason: String = _validate_armor_profile(
        result.profile as Dictionary, true)
    if not profile_reason.is_empty():
        return "combat_invalid_last_attack_result_profile"
    if not is_weapon_receipt:
        return ""
    for key in ["weapon_id", "target_id", "ammo_item_id"]:
        if typeof(result[key]) != TYPE_STRING:
            return "combat_invalid_last_attack_result_%s" % key
    if str(result.weapon_id).is_empty() or str(result.target_id).is_empty() \
            or str(result.source_id) != str(result.weapon_id):
        return "combat_invalid_last_attack_result_weapon_identity"
    if typeof(result.ok) != TYPE_BOOL or not bool(result.ok):
        return "combat_invalid_last_attack_result_ok"
    if not _finite_number(result.stun_seconds) or float(result.stun_seconds) < 0.0:
        return "combat_invalid_last_attack_result_stun_seconds"
    if not _finite_number(result.ammo_remaining) \
            or float(result.ammo_remaining) != floor(float(result.ammo_remaining)) \
            or float(result.ammo_remaining) < -1.0:
        return "combat_invalid_last_attack_result_ammo_remaining"
    return ""


static func _has_exact_string_keys(value: Dictionary, expected: Array[String]) -> bool:
    if value.size() != expected.size():
        return false
    for key in value:
        if typeof(key) != TYPE_STRING or not expected.has(key as String):
            return false
    return true


static func _validate_armor_profile(profile: Dictionary, require_complete: bool) -> String:
    for key in ["flat_reduction", "resistance"]:
        if not profile.get(key, null) is Dictionary:
            return "combat_invalid_armor_%s" % key
        for damage_type in (profile[key] as Dictionary):
            if typeof(damage_type) != TYPE_STRING \
                    or not _finite_number((profile[key] as Dictionary)[damage_type]):
                return "combat_invalid_armor_%s_value" % key
    for key in ["durability"]:
        if not profile.has(key) or not _finite_number(profile[key]) \
                or float(profile[key]) < 0.0:
            return "combat_invalid_armor_%s" % key
    if require_complete:
        for key in ["max_durability", "wear_factor"]:
            if not profile.has(key) or not _finite_number(profile[key]) \
                    or float(profile[key]) < 0.0:
                return "combat_invalid_armor_%s" % key
    elif profile.has("max_durability") and (
            not _finite_number(profile.max_durability) or float(profile.max_durability) < 0.0):
        return "combat_invalid_armor_max_durability"
    elif profile.has("wear_factor") and (
            not _finite_number(profile.wear_factor) or float(profile.wear_factor) < 0.0):
        return "combat_invalid_armor_wear_factor"
    return ""


static func _valid_numeric_array(value: Variant, size: int, allow_float: bool) -> bool:
    if not value is Array or (value as Array).size() != size:
        return false
    for component in value as Array:
        if not _finite_number(component):
            return false
        if not allow_float and float(component) != floor(float(component)):
            return false
    return true


static func _valid_json_value(value: Variant) -> bool:
    match typeof(value):
        TYPE_STRING, TYPE_BOOL, TYPE_INT:
            return true
        TYPE_FLOAT:
            return is_finite(float(value))
        TYPE_ARRAY:
            for entry in value as Array:
                if not _valid_json_value(entry):
                    return false
            return true
        TYPE_DICTIONARY:
            for key in (value as Dictionary):
                if typeof(key) != TYPE_STRING or not _valid_json_value((value as Dictionary)[key]):
                    return false
            return true
        _:
            return false


static func _finite_number(value: Variant) -> bool:
    return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) \
        and is_finite(float(value))


static func _failure(reason: String) -> Dictionary:
    return {"ok": false, "reason": reason}
