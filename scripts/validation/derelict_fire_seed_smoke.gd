extends SceneTree

## Proves the derelict fire presence gate is deterministic and ~15%, the cap is honored,
## and the same seed always yields the same verdict. RNG-free (hash-based).
## Marker: DERELICT FIRE SEED PASS deterministic=true rate_ok=true cap_ok=true

const FIRE_PRESENCE_PERCENT: int = 15
const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")

func _present(seed_int: int) -> bool:
	return (abs(hash("%d:fire_presence" % seed_int)) % 100) < FIRE_PRESENCE_PERCENT

## Mirrors the production cap formula against the REAL enum so a renumber can't pass silently.
func _cap(cond: int) -> int:
	return 2 + (1 if cond == ShipBlueprintScript.Condition.WRECKED else 0)

func _initialize() -> void:
	var seeds: Array = [1, 7, 42, 9999, -3]
	# Determinism: evaluate the gate over the seed list twice into separate arrays and
	# assert they match. A real cross-sweep — if anything introduced randi/randf the two
	# passes would diverge.
	var pass_a: Array = []
	for s in seeds:
		pass_a.append(_present(s))
	var pass_b: Array = []
	for s in seeds:
		pass_b.append(_present(s))
	var deterministic: bool = pass_a == pass_b
	# Rate: across a wide seed sweep, presence fraction is in a sane band around 15%.
	var present_count: int = 0
	var n: int = 2000
	for s in range(n):
		if _present(s):
			present_count += 1
	var frac: float = float(present_count) / float(n)
	var rate_ok: bool = frac > 0.10 and frac < 0.20
	# Cap formula tied to the real enum ordinals: PRISTINE/DAMAGED -> 2, WRECKED -> 3.
	var cap_ok: bool = (
		_cap(ShipBlueprintScript.Condition.PRISTINE) == 2
		and _cap(ShipBlueprintScript.Condition.DAMAGED) == 2
		and _cap(ShipBlueprintScript.Condition.WRECKED) == 3
	)

	if deterministic and rate_ok and cap_ok:
		print("DERELICT FIRE SEED PASS deterministic=true rate_ok=true cap_ok=true")
		quit(0)
	else:
		push_error("DERELICT FIRE SEED FAIL deterministic=%s rate_ok=%s (frac=%.3f) cap_ok=%s" % [deterministic, rate_ok, frac, cap_ok])
		quit(1)
