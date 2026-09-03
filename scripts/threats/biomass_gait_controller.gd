extends RefCounted

## Authoritative biomass gait controller — socket-space motion synthesis.
##
## A small RefCounted that the visual owns privately. The controller never
## reaches into the scene tree directly: it asks the visual for per-frame
## mount/part references and the visual reads back the derived transforms.
## Every frame is derived from the immutable Task 5 assembly rest snapshot
## taken at `configure()` time. Non-driven mounts and the core/root/world
## are never touched.
##
## Profiles (locomotion_hint -> freq Hz, swing deg, phases rad):
##   biped     locomotor  1.8 Hz  24 deg [0, PI]
##   quadruped locomotor  2.2 Hz  20 deg [0, PI, PI, 0]
##   crawl     locomotor  2.6 Hz  28 deg [0, 2.094, 4.189]
##   drag      puller     1.4 Hz  18 deg [0]
##   slither   slither    1.7 Hz  30 deg [0, 1.571, 3.142, 4.712]
##
## ACTIVE: investigate/hunt/attack/telegraph/flee. REST: idle/stun/dead plus
## any unknown AI state.
##
## Speed reference 2.5; near-zero 0.01 (active advance only when above);
## rest decay 4/s. Non-finite / negative delta -> no-op.

const VisualScript: GDScript = preload("res://scripts/threats/biomass_threat_visual.gd")
const PartCatalogScript: GDScript = preload("res://scripts/systems/biomass_part_catalog.gd")
const RecipeScript: GDScript = preload("res://scripts/systems/biomass_recipe.gd")

const PROFILES: Dictionary = {
	"biped":     {"role": "locomotor", "freq_hz": 1.8, "swing_deg": 24.0, "phases": [0.0, PI]},
	"quadruped": {"role": "locomotor", "freq_hz": 2.2, "swing_deg": 20.0, "phases": [0.0, PI, PI, 0.0]},
	"crawl":     {"role": "locomotor", "freq_hz": 2.6, "swing_deg": 28.0, "phases": [0.0, 2.0943951023931953, 4.188790204786391]},
	"drag":      {"role": "puller",    "freq_hz": 1.4, "swing_deg": 18.0, "phases": [0.0]},
	"slither":   {"role": "slither",   "freq_hz": 1.7, "swing_deg": 30.0, "phases": [0.0, 1.5707963267948966, 3.141592653589793, 4.71238898038469]},
}
const ACTIVE_STATES: Array[String] = ["investigate", "hunt", "attack", "telegraph", "flee"]
const REST_STATES: Array[String] = ["idle", "stun", "dead"]
const SPEED_REFERENCE: float = 2.5
const NEAR_ZERO_SPEED: float = 0.01
const REST_DECAY_RATE: float = 4.0
const MAX_RELATIVE_DEG: float = 35.0
const ORTHONORMAL_EPS: float = 1e-5
const SNAP_EPS: float = 1e-6

var _configured: bool = false
var _profile_key: String = ""
var _profile_role: String = ""
var _freq: float = 0.0
var _swing_rad: float = 0.0
var _seed_phase: float = 0.0
var _driven_ids: PackedStringArray = PackedStringArray()
var _driven_phases: PackedFloat32Array = PackedFloat32Array()
var _mount_rest: Dictionary = {}
var _part_rest: Dictionary = {}
var _derived_mounts: Dictionary = {}
var _elapsed: float = 0.0
var _rest_elapsed: float = 0.0
var _active: bool = false
var _last_snapshot: Dictionary = {}

## Configures the controller against the assembled visual + recipe.
## Returns true on success; on failure the controller remains in an
## exact-rest/no-op state and `_configured` is left false.
func configure(visual: Variant, parts: Variant, recipe: Variant, seed: int) -> bool:
	_reset_state()
	if not _valid_inputs(visual, parts, recipe):
		return false
	var hint: String = String(((recipe as Object).to_dict()).get("locomotion_hint", ""))
	if not PROFILES.has(hint):
		return false
	var profile: Dictionary = PROFILES[hint]
	var freq: float = float(profile.get("freq_hz", 0.0))
	var swing: float = float(profile.get("swing_deg", 0.0))
	if not (is_finite(freq) and freq > 0.0 and is_finite(swing) and swing >= 0.0):
		return false
	var phases_value: Variant = profile.get("phases", [])
	if not phases_value is Array or (phases_value as Array).is_empty():
		return false
	var profile_phases: PackedFloat32Array = PackedFloat32Array()
	for p in phases_value as Array:
		var pf: float = float(p)
		if not is_finite(pf):
			return false
		profile_phases.append(pf)
	var recipe_doc: Dictionary = (recipe as Object).to_dict()
	var attachments_value: Variant = recipe_doc.get("attachments", [])
	if not attachments_value is Array:
		return false
	var attachments: Array = attachments_value
	var driven_entries: Array = []
	for edge_value in attachments:
		if not edge_value is Dictionary:
			return false
		var edge: Dictionary = edge_value
		var instance_id: String = String(edge.get("instance_id", ""))
		var part_id: String = String(edge.get("part_id", ""))
		if instance_id.is_empty() or part_id.is_empty():
			return false
		var entry: Dictionary = (parts as Object).get_part(part_id)
		if entry.is_empty():
			return false
		if not _entry_has_role(entry, String(profile.get("role", ""))):
			continue
		driven_entries.append({"instance_id": instance_id})
	if driven_entries.is_empty():
		return false
	driven_entries.sort_custom(_compare_instance_id)
	var driven_ids: PackedStringArray = PackedStringArray()
	var driven_phases: PackedFloat32Array = PackedFloat32Array()
	for index in range(driven_entries.size()):
		var entry_value: Dictionary = driven_entries[index]
		driven_ids.append(String(entry_value.get("instance_id", "")))
		driven_phases.append(profile_phases[index % profile_phases.size()])
	if not _snapshot_rest(visual as Object, attachments):
		return false
	_profile_key = hint
	_profile_role = String(profile.get("role", ""))
	_freq = freq
	_swing_rad = deg_to_rad(swing)
	_seed_phase = deg_to_rad(float(posmod(int(seed), 360)))
	_driven_ids = driven_ids
	_driven_phases = driven_phases
	_elapsed = 0.0
	_rest_elapsed = 0.0
	_active = false
	# Pre-populate derived mounts at exact rest so the visual can read
	# before any step() has run.
	_populate_derived_at_rest()
	_configured = true
	return true

## Advances the gait by `delta` seconds given the current world-space
## velocity and AI state string. Updates the cached derived mount
## transforms in `_derived_mounts` for the visual to read back.
func step(delta: float, velocity: Variant, ai_state: String) -> void:
	if not _configured:
		return
	if not is_finite(delta) or delta < 0.0:
		return
	var speed: float = _speed_of(velocity)
	var now_active: bool = ACTIVE_STATES.has(String(ai_state))
	if not now_active:
		_active = false
		_rest_elapsed += delta
		_populate_derived_at_rest()
		return
	_active = true
	_rest_elapsed = 0.0
	if speed <= NEAR_ZERO_SPEED:
		_populate_derived_at_rest()
		return
	_elapsed += delta
	var weight: float = clampf(speed / SPEED_REFERENCE, 0.0, 1.0)
	for index in range(_driven_ids.size()):
		var instance_id: String = _driven_ids[index]
		var phase: float = _driven_phases[index]
		var rest_value: Variant = _mount_rest.get(instance_id, null)
		if not rest_value is Transform3D:
			continue
		var rest: Transform3D = rest_value
		var angle: float = _swing_rad * weight * sin(TAU * _freq * _elapsed + phase + _seed_phase)
		var derived: Transform3D = _derive_basis(rest, angle)
		if not derived.basis.is_finite() or not _is_orthonormal_within(derived.basis, ORTHONORMAL_EPS):
			derived = Transform3D(rest.basis, rest.origin)
		_derived_mounts[instance_id] = derived

## Returns the configured driven instance IDs (lex-sorted).
func driven_ids() -> PackedStringArray:
	return _driven_ids

## Returns the per-driven phase array (radians).
func driven_phases() -> PackedFloat32Array:
	return _driven_phases

## Returns the seed phase (radians).
func seed_phase() -> float:
	return _seed_phase

## Returns the frequency (Hz) of the configured profile.
func freq_hz() -> float:
	return _freq

## Returns the swing amplitude (radians) of the configured profile.
func swing_rad() -> float:
	return _swing_rad

## Returns the configured rest mount transforms keyed by instance_id.
func mount_rest() -> Dictionary:
	return _mount_rest.duplicate(true)

## Returns the rest part transforms keyed by instance_id.
func part_rest() -> Dictionary:
	return _part_rest.duplicate(true)

## Returns the most recently derived mount transforms keyed by instance_id.
func derived_mounts() -> Dictionary:
	return _derived_mounts.duplicate(true)

## Returns the derived Transform3D for the given driven ID, or null when
## unknown or non-driven.
func derived_mount_transform(instance_id: String) -> Variant:
	var value: Variant = _derived_mounts.get(instance_id, null)
	if value is Transform3D:
		return value as Transform3D
	return null

## Returns the controller's configured profile key (locomotion_hint) or "".
func profile_key() -> String:
	return _profile_key

## Returns the role used to filter driven attachments.
func profile_role() -> String:
	return _profile_role

## Returns whether the controller was successfully configured.
func is_configured() -> bool:
	return _configured

## Returns the most recent canonical snapshot dictionary.
func last_snapshot() -> Dictionary:
	return _last_snapshot.duplicate(true)

## Returns a defensive canonical snapshot: origin (3 floats, snapped 1e-6)
## + 9 basis floats (snapped 1e-6) for every mount and every part, sorted
## lexicographically by instance_id. Skips IDs without a current transform.
## Mounts use the most recent derived transform when available (active
## gait state); parts always use the rest snapshot.
func snapshot() -> Dictionary:
	var result: Dictionary = {}
	if not _configured:
		return result
	var sorted_mounts: PackedStringArray = PackedStringArray()
	for key in _mount_rest.keys():
		sorted_mounts.append(String(key))
	sorted_mounts.sort()
	var mounts: Dictionary = {}
	for instance_id in sorted_mounts:
		var source_xform: Transform3D
		var derived_value: Variant = _derived_mounts.get(instance_id, null)
		if derived_value is Transform3D:
			source_xform = derived_value
		else:
			var rest_value: Variant = _mount_rest.get(instance_id, null)
			if not rest_value is Transform3D:
				continue
			source_xform = rest_value
		mounts[instance_id] = _snapped_xform_dict(source_xform)
	result["mounts"] = mounts
	var sorted_parts: PackedStringArray = PackedStringArray()
	for key in _part_rest.keys():
		sorted_parts.append(String(key))
	sorted_parts.sort()
	var parts: Dictionary = {}
	for instance_id in sorted_parts:
		var xform_value: Variant = _part_rest[instance_id]
		if not xform_value is Transform3D:
			continue
		parts[instance_id] = _snapped_xform_dict(xform_value as Transform3D)
	result["parts"] = parts
	result["driven_ids"] = Array(_driven_ids)
	result["profile_key"] = _profile_key
	result["profile_role"] = _profile_role
	result["freq_hz"] = _freq
	result["seed_phase_rad"] = _seed_phase
	result["phases_rad"] = Array(_driven_phases)
	result["elapsed"] = _elapsed
	result["rest_elapsed"] = _rest_elapsed
	result["active"] = _active
	_last_snapshot = result
	return result

# ---------------------------------------------------------------------------
# Internal — input validation
# ---------------------------------------------------------------------------

func _reset_state() -> void:
	_configured = false
	_profile_key = ""
	_profile_role = ""
	_freq = 0.0
	_swing_rad = 0.0
	_seed_phase = 0.0
	_driven_ids = PackedStringArray()
	_driven_phases = PackedFloat32Array()
	_mount_rest.clear()
	_part_rest.clear()
	_derived_mounts.clear()
	_elapsed = 0.0
	_rest_elapsed = 0.0
	_active = false
	_last_snapshot = {}

func _valid_inputs(visual: Variant, parts: Variant, recipe: Variant) -> bool:
	if visual == null or parts == null or recipe == null:
		return false
	if not visual is Object:
		return false
	if (visual as Object).get_script() != VisualScript:
		return false
	if not parts is Object or (parts as Object).get_script() != PartCatalogScript:
		return false
	if not recipe is Object or (recipe as Object).get_script() != RecipeScript:
		return false
	if not (recipe as Object).is_valid():
		return false
	# Loader-validity proxy.
	if (parts as Object).get_part("biomass_human_arm_v1").is_empty():
		return false
	if not (visual as Object).is_built():
		return false
	return true

func _entry_has_role(entry: Dictionary, role: String) -> bool:
	var roles: Variant = entry.get("assembly_roles", [])
	if not roles is Array:
		return false
	for r in roles as Array:
		if String(r) == role:
			return true
	return false

func _compare_instance_id(a: Dictionary, b: Dictionary) -> bool:
	return String(a.get("instance_id", "")) < String(b.get("instance_id", ""))

func _snapshot_rest(visual: Object, attachments: Array) -> bool:
	var visual_obj: Object = visual
	var core_doc: Variant = (visual_obj.recipe_document()).get("core", null)
	if not core_doc is Dictionary:
		return false
	var core_instance_id: String = String((core_doc as Dictionary).get("instance_id", ""))
	if core_instance_id.is_empty():
		return false
	var core_part: Variant = visual_obj.part(core_instance_id)
	if core_part == null:
		return false
	_part_rest[core_instance_id] = (core_part as Node3D).transform
	for edge_value in attachments:
		if not edge_value is Dictionary:
			return false
		var edge: Dictionary = edge_value
		var instance_id: String = String(edge.get("instance_id", ""))
		if instance_id.is_empty():
			return false
		var mount: Variant = visual_obj.attachment_mount(instance_id)
		if mount == null:
			return false
		var part_node: Variant = visual_obj.part(instance_id)
		if part_node == null:
			return false
		_mount_rest[instance_id] = (mount as Node3D).transform
		_part_rest[instance_id] = (part_node as Node3D).transform
	return true

func _populate_derived_at_rest() -> void:
	for instance_id in _driven_ids:
		var rest_value: Variant = _mount_rest.get(instance_id, null)
		if rest_value is Transform3D:
			_derived_mounts[instance_id] = Transform3D((rest_value as Transform3D).basis, (rest_value as Transform3D).origin)

func _speed_of(velocity: Variant) -> float:
	if velocity is Vector2:
		var v2: Vector2 = velocity
		return v2.length()
	if velocity is Vector3:
		var v3: Vector3 = velocity
		return v3.length()
	if velocity is float or velocity is int:
		var f: float = float(velocity)
		if is_finite(f):
			return absf(f)
	return 0.0

func _derive_basis(rest: Transform3D, angle: float) -> Transform3D:
	if not rest.basis.is_finite():
		return rest
	var rx: Basis = Basis(Vector3(1.0, 0.0, 0.0), angle)
	var ry: Basis = Basis(Vector3(0.0, 1.0, 0.0), angle * 0.25)
	var derived_basis: Basis = rest.basis * rx * ry
	if not derived_basis.is_finite():
		return Transform3D(rest.basis, rest.origin)
	# Cap relative rotation: shortest-arc quaternion angle.
	var rel: Basis = derived_basis * rest.basis.inverse()
	var rel_quat: Quaternion = rel.get_rotation_quaternion()
	if not rel_quat.is_finite():
		return Transform3D(rest.basis, rest.origin)
	var rel_angle: float = rel_quat.get_angle()
	if rel_angle > deg_to_rad(MAX_RELATIVE_DEG):
		var axis: Vector3 = rel_quat.get_axis()
		if not axis.is_finite() or axis.length() < 1e-6:
			return Transform3D(rest.basis, rest.origin)
		var cap: Basis = Basis(Quaternion(axis.normalized(), deg_to_rad(MAX_RELATIVE_DEG)))
		derived_basis = cap * rest.basis
	if not derived_basis.is_finite() or not _is_orthonormal_within(derived_basis, ORTHONORMAL_EPS):
		return Transform3D(rest.basis, rest.origin)
	return Transform3D(derived_basis, rest.origin)

func _is_orthonormal_within(basis: Basis, tolerance: float) -> bool:
	# Godot 4.7's Basis.is_orthonormal() takes no arguments; emulate a
	# tolerance check by checking each axis length and cross-pair orthogonality
	# against `tolerance`.
	if not basis.is_finite():
		return false
	var x: Vector3 = basis.x
	var y: Vector3 = basis.y
	var z: Vector3 = basis.z
	if absf(x.length() - 1.0) > tolerance:
		return false
	if absf(y.length() - 1.0) > tolerance:
		return false
	if absf(z.length() - 1.0) > tolerance:
		return false
	if absf(x.dot(y)) > tolerance:
		return false
	if absf(y.dot(z)) > tolerance:
		return false
	if absf(x.dot(z)) > tolerance:
		return false
	return true

func _snapped_xform_dict(xform: Transform3D) -> Dictionary:
	var origin: Vector3 = xform.origin
	var snapped_origin: Array = [
		snappedf(origin.x, SNAP_EPS),
		snappedf(origin.y, SNAP_EPS),
		snappedf(origin.z, SNAP_EPS),
	]
	var basis: Basis = xform.basis
	var snapped_basis: Array = []
	# Iterate columns (basis.x, basis.y, basis.z) and append row-major to
	# match the standard Transform3D serialization shape (origin + 9 floats).
	for column in [basis.x, basis.y, basis.z]:
		snapped_basis.append(snappedf(column.x, SNAP_EPS))
		snapped_basis.append(snappedf(column.y, SNAP_EPS))
		snapped_basis.append(snappedf(column.z, SNAP_EPS))
	return {"origin": snapped_origin, "basis": snapped_basis}
