# Focused-Nine Staged Procgen Derelict Preview

- Source root: `assets/_staging/focused_nine` (staged-only).
- Runtime generator seed: `17` (seed=17).
- Generated room count: `7` (room_count=7, small derelict range 5-8).
- Canonical structural placement count: `51` (placements=51).
- Canonical wall/portal edge counts: walls=44, portals=7.
- Generated staged wrapper count: `51` (staged_wrapper_count=51).
- Staged focused-nine input count: `17` (staged_input_count=17).
- Capture: `focused-nine-staged-derelict.png`, 1600x900.
- Canonical debug bundle: `artifacts/validation-previews/focused-nine/edge_map.json` (`edge_map.json`).
- The disposable overlay copied regular staged GLBs to canonical production import paths.
- Pressure-door intact/damaged/breached triplet was preserved byte-for-byte in the overlay.
- Tree inspection found no fallback or live imported visual references.
- The generated derelict graph contains an actual dock role; no lifeboat scene was instantiated.
- No runtime promotion occurred.
- Acceptance marker: `FOCUSED_NINE_STAGED_DERELICT_CAPTURE PASS seed=17 rooms=7 placements=51 walls=44 portals=7 staged_wrapper_count=51 staged=17 debug=res://artifacts/validation-previews/focused-nine/edge_map.json output=res://artifacts/validation-previews/focused-nine/focused-nine-staged-derelict.png`
