extends RefCounted
class_name ThreatInitialStateBuilder

const ThreatAIStateScript := preload("res://scripts/systems/threat_ai_state.gd")
const ThreatSaveContractScript := preload("res://scripts/systems/threat_save_contract.gd")


static func build_initial_v2(
        layout: Dictionary,
        markers: Array,
        anchor: Vector3,
        definitions: Dictionary) -> Dictionary:
    if layout == null or definitions == null or definitions.is_empty():
        return {"ok": false, "reason": "missing_combat_initialization_source"}
    var effective_markers: Array = markers.duplicate(true)
    if effective_markers.is_empty():
        effective_markers = _fallback_markers_from_layout(layout)
    var threats: Array = []
    var index: int = 0
    for marker_value in effective_markers:
        if not marker_value is Dictionary:
            return {"ok": false, "reason": "invalid_combat_encounter_marker"}
        var marker: Dictionary = marker_value as Dictionary
        var encounter_kind: String = _normalize_encounter_kind(
            str(marker.get("encounter_kind", "biomatter_swarm")))
        var definition_value: Variant = definitions.get(encounter_kind, null)
        if not definition_value is Dictionary or (definition_value as Dictionary).is_empty():
            return {"ok": false, "reason": "unknown_combat_definition:%s" % encounter_kind}
        var count: int = max(1, int(marker.get("count", 1)))
        var local_position: Variant = marker.get("local_position", null)
        for offset in range(count):
            var merged: Dictionary = (definition_value as Dictionary).duplicate(true)
            merged["instance_id"] = "%s_%d" % [str(marker.get("id", encounter_kind)), offset]
            merged["archetype_id"] = encounter_kind
            merged["room_id"] = str(marker.get("room_id", ""))
            merged["cell"] = marker.get("cell", [0, 0])
            if local_position is Array and (local_position as Array).size() >= 3:
                merged["world_position"] = [
                    anchor.x + float(local_position[0]) + float(offset) * 0.5,
                    anchor.y + float(local_position[1]),
                    anchor.z + float(local_position[2]),
                ]
            else:
                merged["world_position"] = [
                    anchor.x + cos(float(index)) * 4.0,
                    anchor.y,
                    anchor.z + sin(float(index)) * 4.0,
                ]
            var threat = ThreatAIStateScript.new()
            threat.configure(merged)
            threats.append(threat.get_summary())
            index += 1
    var summary: Dictionary = {
        "schema": ThreatSaveContractScript.SCHEMA,
        "encounter_markers": effective_markers,
        "threats": threats,
        "detection": {
            "noise_level": 0.0,
            "light_level": 0.0,
            "sight_level": 0.0,
            "crouching": false,
            "room_id": "",
            "detect_threshold": 0.75,
            "memory_seconds": 5.0,
            "memory_remaining": 0.0,
            "awareness_score": 0.0,
            "detected": false,
            "heard": false,
            "seen": false,
            "last_reason": "idle",
        },
        "awareness_indicator": 0.0,
        "combat_engaged": false,
        "last_attack_result": {},
        "damage_pipeline": {
            "processed_hits": 0,
            "total_damage_applied": 0.0,
            "total_noise_generated": 0.0,
            "last_result": {},
            "armor_resolver": {
                "armor_profile": {
                    "flat_reduction": {},
                    "resistance": {},
                    "durability": 0.0,
                    "max_durability": 0.0,
                    "wear_factor": 0.35,
                },
                "last_resolution": {},
            },
        },
    }
    return ThreatSaveContractScript.validate_current(summary)


static func _fallback_markers_from_layout(layout: Dictionary) -> Array:
    var room_ids: Array = []
    var rooms_value: Variant = layout.get("rooms", [])
    if rooms_value is Array:
        for room_value in rooms_value as Array:
            if room_value is Dictionary:
                var room_id: String = str((room_value as Dictionary).get("id", ""))
                if not room_id.is_empty():
                    room_ids.append(room_id)
    var archetypes: Array = [
        "biomatter_swarm", "puppet_corpse", "stalker", "mimic", "hull_tendril",
    ]
    var result: Array = []
    for index in range(archetypes.size()):
        result.append({
            "id": "fallback_%d" % index,
            "room_id": room_ids[index % max(1, room_ids.size())] \
                if not room_ids.is_empty() else "fallback_room_%d" % index,
            "cell": [index, 0],
            "encounter_kind": archetypes[index],
            "count": 1,
        })
    return result


static func _normalize_encounter_kind(kind: String) -> String:
    match kind:
        "biomatter_lurker":
            return "biomatter_swarm"
        "breach_lurker":
            return "mimic"
        "drone_scout":
            return "stalker"
        "derelict_pirate":
            return "puppet_corpse"
        _:
            return kind
