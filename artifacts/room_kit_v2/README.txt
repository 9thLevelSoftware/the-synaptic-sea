Room kit v2 — execution handoff

Status: PARTIAL IMPLEMENTATION / STRUCTURAL GATE HOLD.
This is real code and generated asset work, not a completed 31-asset rollout.

Execution checkout
  /Volumes/Untitled/SynapticSeaAssets/worktrees/room-kit-v2
Branch
  feat/blender-room-kit-v2
Base
  d07a4011

Implemented and exercised
  Three editable Blender masters and strict staged GLBs:
    fabrication_station_derelict_v1 (improved existing)
    coolant_pump_skid_derelict_v1 (new)
    suit_service_stand_derelict_v1 (new)
  Deterministic Blender pilot recipe using the existing named material library.
  Frozen 16-row roster (four improvements and twelve genuinely new IDs).
  Static prop exporter with real Blender negative fixtures, source preservation,
  world-transform baking, UVs, normals, identity GLB nodes, helper/rig rejection.
  Fail-closed command/log runner with required marker and diagnostic checks.
  Pure deterministic room-role selection rules and Godot smoke; not enabled in
  GameplaySliceBuilder or GeneratedShipLoader yet.
  Real-GLB manual diagnostic pilot scene and actual Godot viewport captures.

Parent execution evidence
  Final combined focused suite: review/focused-tests.log — 97 passed,
    44 subtests passed. Real staged-asset subset: review/staged-assets.log —
    three passed. Independent quality review found substring-marker acceptance;
    reproduced RED, fixed with line-anchored escaped matching, sixteen runner
    tests green. No independent post-fix release approval is claimed.
  baseline/python-focused.log: 54 passed, 44 subtests passed.
  baseline/new-tooling-parent.log: 34 passed.
  baseline/pilot-artifacts-green.log: three pilot assets passed; fifteen
    deselected cases are NOT coverage of the unauthored remainder.
  baseline/pilot-empty-green.log: ROOM_KIT_PILOT_TEST_PASS, including rejection
    of a valid GLB container with no visual mesh (real RED/GREEN fixture).
  rules/parent-green.log: ROOM_KIT_V2_RULES_PASS; sixteen rows and IDs,
    deterministic choices, aliases and malformed-document rejection.
  baseline/pilot-final-before.log and pilot-final-after.log: clean captures,
    four PNGs per invocation. Capture JSON records input and image SHA-256.
  review/preservation-check.json: 2,792 protected files unchanged; original
    main and room-assets checkout HEADs and exact porcelain states unchanged.

Visual evidence
  review/index.html: local image gallery; open it in a browser.
  review/before-after.png: side-by-side actual Godot orthographic captures.
  pilot-room/final/{baseline,candidate}/: eight original Godot PNGs + receipts.
  pilot-props/<id>/renders/: actual Blender six-view normal/clay renders.
  review/asset-inventory.json: exact source/GLB paths, byte sizes and hashes.
  Source masters are under:
    /Volumes/Untitled/SynapticSeaAssets/meshes/source/room_kit_v2/props/
  Staged GLBs are under assets/_staging/room_kit_v2/props/.

Important evidence boundaries
  The final candidate scene deliberately uses the unchanged EXISTING shell.
  --baseline-shell is an explicit diagnostic mode, not a silent fallback.
  No new structural candidate, structural approval, full-pilot approval,
  procedural-consumer proof, runtime promotion, merge or release is claimed.
  Twenty-eight planned authored assets remain: fifteen structural improvements
  and thirteen props. Structural baseline failure prevents bulk expansion.
  Earlier pilot-room/candidate renders had collapsed source-clone transforms
  and are REJECTED; only pilot-room/final is the corrected Godot evidence.
  Earlier logs named *green* can include failed intermediate iterations. The
  exact parent logs listed above are authoritative for the stated assertions.
  Baseline editor import timed out. start_scenario_smoke exits zero but emits
  its pre-existing resource warning; this is not a fully green project suite.
  Blender underside views initially contained an occluding authoring helper.
  They were recaptured with the helper hidden in memory only; frozen master and
  GLB bytes were not changed. The recipe now hides that helper for future builds.
  Parent visually inspected the corrected six-view sheets; no full-pilot art
  approval is inferred. Godot final captures were produced from b2968278; the
  later 06e33168 adds empty-payload rejection without changing camera/placement.

Structural blocker
  baseline/structural-sources-all.log: 138 errors, including source-contract
  hashes and socket positions/angles that do not match the checkout.
  baseline/structural-bindings.log: fourteen damaged/breached bindings still
  reference intact GLBs.
  The frozen wall/doorway visual AABBs have zero depth; extruding art would
  violate the current bounds. No source contracts/helpers were changed to hide it.
  Separate decision card: synaptic-sea-stage-gate / t_5dbc3f3a (blocked).
  The required decision is the authoritative structural source/contract pairing
  and authorized reconciliation scope. Existing originals remain untouched.

Repeat focused checks (from execution checkout)
  PYTHONPATH=. /opt/homebrew/bin/python3.11 -m pytest -q \
    tests/test_room_kit_v2_roster.py tests/test_export_static_room_prop.py \
    tests/test_run_room_kit_gate.py
  ROOM_KIT_ASSET_ROOT="$PWD/assets/_staging/room_kit_v2/props" PYTHONPATH=. \
    /opt/homebrew/bin/python3.11 -m pytest -q tests/test_room_kit_v2_artifacts.py \
    -k 'test_asset and (fabrication or coolant_pump or suit_service)'
  /opt/homebrew/bin/python3.11 tools/run_room_kit_gate.py --log /tmp/room-kit-rules.log \
    --marker ROOM_KIT_V2_RULES_PASS --timeout 60 -- \
    /opt/homebrew/bin/godot --headless --path . \
    --rendering-method gl_compatibility --rendering-driver opengl3 \
    --script scripts/validation/room_kit_v2_rules_smoke.gd

Subsequent review reconciliation
  review/spec-review-reconciliation.txt records the delayed spec review and
  exact-integer validation correction. Its focused checks supplement, rather
  than replace, the historical implementation evidence above.

Do not promote this staged partial pack or call the approved full plan complete.
