# Feature: Character Art Direction and Must-Have Asset Inventory

## Status

In implementation (2026-10-24). Tranche 1 (player kit, runtime seam, validation) is landed by
this feature; tranches 2–4 are scoped below and not yet built.

## Requirement cross-reference

- `REQ-CHR-001` … `REQ-CHR-006` in `docs/game/05_requirements.md`
- ADR-0070 (art direction, procedural Blender authoring, character visual seam)
- ADR-0052 (visual-only runtime binding), ADR-0058 (Blender master authority), ADR-0069
  (procedural biomass threats)
- Art gate: `docs/game/art_shippable_gate.md`
- Vertical slice contract: `docs/game/features/vertical_slice_v1.md` (§ "Art source: hand-authored
  Blender/kitbash preferred")

## Design pillar alignment

- **Pillar 1 (spatial coherence first):** the player and threats must read as bodies with a facing
  direction at gameplay distance; a capsule reads as nothing.
- **Pillar 3 (every action has visible consequence):** worn equipment, crouching, working, swinging,
  aiming and dying are state the sim already tracks; the body must show them.
- **Pillar 5 (source-backed structure):** every asset is contract-first, regenerated from
  repository source, validated by a smoke, and gated by the art gate.

## Player fantasy

A stranded spacer in a patched jumpsuit, visibly heavier when wearing the hardsuit and EVA pack,
hunched when crouching through a dark derelict, bent over a junction while welding, swinging a
crowbar at something that used to be crew.

## Art direction: "Project Zomboid, but a bit more detailed"

| Rule | Value | Why |
|---|---|---|
| Style | Low-poly segmented humanoid: bevelled boxes, 8-segment cylinders, coarse spheres, flat shading, no textures, palette materials | PZ register; reads at 50–100 px; cheap to iterate procedurally |
| Budget (body) | 800–3 200 triangles (shipped `survivor_v1`: 1 540) | PZ bodies are ~1 k; "a bit more detailed" = bevels, joint caps, pockets, cuffs |
| Budget (kit) | ≤ 7 000 triangles with every equipment node (shipped: 3 396) | Many bodies on screen stay cheap |
| Scale | 1.75 m tall, pivot at floor centre, `+Z` forward, metres, Y-up | Matches capsule 0.35 r × 1.6 h, `CELL_SIZE = 4.0`, ADR-0058 conventions |
| Camera budget | `IsoCameraRig` ortho `size = 22` at 1280×720 → 1 m ≈ 33 px → body ≈ 57 px tall | Detail below ~3 cm is invisible; silhouette + colour blocking carry everything |
| Recommended | Evaluate `size = 12–14` (body ≈ 104–90 px) for readability; preview `gameplay_distance_iso_size12.png` | PZ renders bodies at ~100–150 px on 1080p |
| Materials | `MAT_SuitFabric`, `MAT_SuitPlate`, `MAT_Skin`, `MAT_Boot`, `MAT_Strap`, `MAT_Metal`, `MAT_Visor` (emissive), `MAT_ClassAccent` (runtime-recolourable), `MAT_Lamp` (emissive) | Nine named palette slots; Godot imports them as `StandardMaterial3D` by name |
| Rig | 20 deform bones (`root, hips, spine, chest, neck, head, shoulder/upper_arm/forearm/hand ×2, thigh/shin/foot ×2`), rigid per-part skinning | PZ-style segmented bodies; cheap, deterministic, reusable for corpses/stalker |
| Clips | `idle, walk, crouch_idle, crouch_walk, work` (looping) + `melee_swing, aim_ranged, downed` | One clip per live state the sim can put the player in today |
| Sockets | `Socket_HandR/HandL/Back/Head` bone-parented nodes | Handheld tools, packs, headlamp mount without mesh edits |

Everything above is encoded in `tools/character_kit/character_kit_spec.py` and enforced by
`tools/character_kit/validate_character_glb.py`.

## Gameplay problem

The simulation closes 18 loops but the player is an unshaded blue `CapsuleMesh`
(`scripts/player/player_controller.gd`), every threat is a coloured primitive
(`data/combat/threat_visual_catalog.json`, all `mesh_path: ""`), and nothing under `assets/`
contains a skin, humanoid node, or animation. The presentation cannot show equipment, crouch,
work, combat, or death, so the vertical slice's "feel the fantasy" bar is unreachable.

## Review of existing assets and plans (frank)

| Family | What is there | Verdict for the character/art track |
|---|---|---|
| Player visual | Blue unshaded capsule built in code | **Replaced** by `survivor_v1` (this feature); capsule remains the fallback |
| Threat visuals | Six archetypes, all primitives (`mesh_path: ""`) | **Unusable as art**; keep the catalog seam, bind GLBs in tranche 3. `ThreatPlaceholderRenderer` mounts a `PackedScene` *beside* the primitive instead of replacing it — must hide the primitive before binding |
| `assets/imported/structural/ship_structural_v0` | 15 modules, intact/damaged/breached + `_textured` variants (~700-tri class), placement contracts | **Usable** as the environment baseline; boxy but on-grid and validated; not character work |
| `assets/imported/props/{components,dressing,objectives}` | 26 self-authored props with sidecars + generated index | **Usable** placeholders; visually weak, but every one is bound through ADR-0052 |
| `assets/imported/props/ithappy/**` (+ structural/ithappy) | ~2 170 licensed sci-fi prop GLBs (2 materials each, 350–3 600 tris), catalog JSON | **Usable** for environment dressing; contains **no characters, no rigs, no animations** |
| `assets/_staging/meshy/{loot_container,stalker}_v1` | 4 + 6 provider candidates (GLBs gitignored; review JSON tracked) | **Unusable** for final art (ADR-0048 records "terrible"); keep as pipeline evidence only |
| `assets/_staging/focused_nine` | 9 staged structural/prop GLBs for a comparison batch | Evidence only; superseded by v0 kit for runtime |
| `assets/tiles/synaptic_sea` | ComfyUI/LoRA PoC texture tiles (~2 MB each) | **Non-runtime by policy** (`art_shippable_gate.md`); not relevant to characters |
| `assets/tilesets/{winlu,dithart}` | 2D top-down tilesets for the ADR-0048 pivot | **Dead path**: the boot chain never left 3D; no production script references `scenes/topdown` |
| `assets/placeholder/*.png` | 69-byte empty PNG status icons | Placeholders; UI track, not this feature |
| Blender/Meshy tooling (`tools/meshy_*`, `tools/blender_addons`, `tools/recover_modules.py`) | Heavy governance for provider candidates; masters on `/Volumes/Untitled` | **Not reusable for characters** as-is (provider + external-drive dependencies); contract/sidecar/validator ideas are reused by `tools/character_kit` |

Lessons carried into this feature: no provider calls, no external masters, no proof-only
galleries, one spec module shared by builder/validator/smoke, evidence rendered from the exported
GLB round trip, both coordinator branches covered by validation.

## Must-have asset inventory

Priority: **must** = needed for the vertical slice to show the fantasy; **should** = next; **could**
= later. Status: ✅ landed by this feature · ⏳ scoped, not built.

### Tranche 1 — player body and equipment (this feature)

| ID | Asset | Class | Runtime consumer | Priority | Status |
|---|---|---|---|---|---|
| CHR-P01 | `survivor_v1` base body (jumpsuit, gloves, boots, head) | skinned character | `PlayerController` → `CharacterVisual` via `character_visual_catalog.json` | must | ✅ |
| CHR-P02 | `hardsuit` plates + `Equip_Helmet` (visor emissive, lamp, comms puck) | equipment node set | `EquipmentState.slots["suit"]` → `Equip_Hardsuit_*`, `Equip_Helmet` | must | ✅ |
| CHR-P03 | `eva_backpack` (life-support box, twin tanks, straps) | equipment node | `slots["back"]` → `Equip_EVABackpack` | must | ✅ |
| CHR-P04 | `field_pack` (soft duffel, flap, side pockets) | equipment node | `slots["back"]` → `Equip_FieldPack` | must | ✅ |
| CHR-P05 | `tool_belt` (belt, four pouches, holster) | equipment node | `slots["waist"]` → `Equip_ToolBelt` | must | ✅ |
| CHR-P06 | Class accent patch (`Body_ClassAccent`, `MAT_ClassAccent`) | recolourable node | `CharacterVisual.set_class_accent()` | should | ✅ node + API; class→colour table wiring ⏳ |
| CHR-P07 | Clip set: `idle, walk, crouch_idle, crouch_walk, work, melee_swing, aim_ranged, downed` | animation | `CharacterVisual` from velocity / crouch / `WorkActionDriver.is_working()` / attack / `end_run("death")` | must | ✅ |
| CHR-P08 | Sockets `Socket_HandR/HandL/Back/Head` | bone-parented nodes | `CharacterVisual.get_socket()` | must | ✅ |
| CHR-P09 | Handheld tools: `crowbar`, `welding_lance`, `flare_pistol`, `shock_probe`, `portable_oxygen_pump`, `junction_calibrator` | static props, grip at origin, `+Z` working end | hand-slot mount via `Socket_HandR/L` | should | ✅ assets; mount seam ⏳ (tranche 2) |
| CHR-P10 | Review previews (turnarounds × 3 variants, pose sheet, gameplay-distance frames) | evidence | art gate item 7 | must | ✅ |

### Tranche 2 — player states the sim already has but the body cannot show yet

| ID | Asset | Driven by | Priority | Status |
|---|---|---|---|---|
| CHR-P11 | Hand-slot mounting seam (BoneAttachment3D on `Socket_HandR/L`, swap on `primary_hand`/`secondary_hand`) | `EquipmentState.slots` | must | ⏳ |
| CHR-P12 | `reload` clip + `hurt_flinch` clip | `_reload_equipped_weapon`, `DamagePipeline` player hit | should | ⏳ |
| CHR-P13 | `cart_push` clip (two hands forward) + cart grab pose | `CartState` grabbed | should | ⏳ |
| CHR-P14 | `heavy_load` and `exhausted` idle/walk overlays (slumped shoulders) | `Encumbrance` tier, `VitalsState` stamina | should | ⏳ |
| CHR-P15 | Wound dressings per body part (`Equip_Bandage_{Head,Torso,Arm_L/R,Leg_L/R}`) | `WoundState.body_part` | should | ⏳ |
| CHR-P16 | Helmet lamp as a real `SpotLight3D` on `Socket_Head`, on only with `hardsuit` | equipment + ambient lighting mode | should | ⏳ |
| CHR-P17 | Soft EVA suit (second suit item) and bare-head hair/cap variants | future `suit` items | could | ⏳ |
| CHR-P18 | Second body type (proportion preset in the builder) | class/start selection (vertical slice Phase 3) | could | ⏳ |
| CHR-P19 | `interact_reach` and `pickup` one-shots | interact dispatch, tool pickup | could | ⏳ |

### Tranche 3 — humanoid non-player characters (reuse the rig)

| ID | Asset | Runtime consumer | Priority | Status |
|---|---|---|---|---|
| CHR-N01 | `puppet_corpse` body: survivor rig, biomatter-crusted materials, lurch/idle/attack clips | `threat_visual_catalog.json` `mesh_path` → `ThreatPlaceholderRenderer` (after the primitive-hide fix) | must (vertical slice "distinct threat silhouette") | ⏳ |
| CHR-N02 | `stalker` humanoid variant: elongated proportions preset, low stalking idle, lunge | same seam; replaces the rejected Meshy pilot | must | ⏳ |
| CHR-N03 | Searchable corpse prop (downed survivor, static) | `ShipInstance.pending_corpse_loot` spawn | should | ⏳ |
| CHR-N04 | Hallucination phantom (survivor silhouette, `MAT_Visor`-style translucent) | `HallucinationManager` → `build_placeholder(PHANTOM_ARCHETYPE)` | should | ⏳ |
| CHR-N05 | Crew/NPC survivor (talkable) | none today (social suite is abstract) | could | ⏳ |

Non-humanoid threats (`hull_tendril`, `biomatter_swarm`, `mimic`, `drone_swarm`) stay on the
ADR-0069 procedural biomass track and are out of scope here.

### Tranche 4 — environment assets that frame the character (brief)

Not the focus of this feature; listed so the character work is not evaluated against empty rooms.
Existing `ship_structural_v0` + ithappy dressing are usable for the slice. The three props the
player interacts with most, and that are still box-class, should follow the same procedural
Blender route next: pressure door (open/closed/breached), loot container (closed/open/looted;
the Meshy candidate is superseded), crafting/salvage station. Each is a `prop_visual_binding`
sidecar consumer (ADR-0052), not a character seam.

## Core behavior (in-engine)

1. `PlayerController._ready()` creates a `CharacterVisual` and calls `mount_catalog_entry("player_survivor")`.
   On success the capsule marker is hidden; on any failure the capsule stays and
   `get_visual_source()` reports `"fallback"`.
2. Each physics tick the controller feeds `velocity`, crouch, the injected equipment-slots
   provider (`EquipmentState.slots`) and the injected `WorkActionDriver.is_working()` provider to
   the visual. The visual yaws its `+Z` to the planar travel direction and selects the clip.
3. `_attack_with_equipped_weapon()` plays `melee_swing`, or `aim_ranged` for ammo-consuming
   weapons, on every attempted attack. `end_run("death")` plays `downed` and holds.
4. Equipping/unequipping through the real `EquipmentState` shows/hides `Equip_*` nodes by prefix
   on the next tick, on the home and away branches alike.

## Inputs

- `data/characters/character_visual_catalog.json` (entry `player_survivor`)
- `assets/imported/characters/survivor_v1/survivor_v1.glb` + `.manifest.json`
- `EquipmentState.slots`, `WorkActionDriver.is_working()`, `PlayerController.velocity`,
  `is_crouching()`, attack dispatch, `end_run()`

## Outputs

- Visible body with equipment, facing, locomotion, action and death poses; capsule hidden
- No collision, navigation, save, or gameplay state changes

## Rules

- Collision authority stays on the `CharacterBody3D` capsule; the visual never carries shapes.
- Equipment truth stays in `EquipmentState`; the visual only mirrors it.
- Visual state is fed from the player's physics tick, never from the coordinator's `_process`
  branches.
- A missing asset degrades to the capsule; it never borrows another visual.
- Runtime GLBs are regenerated from `tools/character_kit/` source; hand edits to
  `assets/imported/characters/**` are not accepted.

## Non-goals

- Textured or sculpted characters, facial animation, cloth, IK.
- Threat GLB binding, handheld mounting, wounds, headlamp light (tranches 2–3).
- Any change to the camera rig (the `size = 12` preview is evidence for a separate decision).
- Any change to ADR-0069's non-humanoid threat plan.

## Technical design

- `tools/character_kit/character_kit_spec.py` — contract (bones, parts, equipment prefixes,
  sockets, clips, materials, budgets, manifest)
- `tools/character_kit/build_survivor_kit.py`, `bpy_lowpoly.py`, `survivor_animation.py`,
  `build_handheld_tools.py` — Blender-only authoring
- `tools/character_kit/validate_character_glb.py` — host validator; `render_character_previews.py`
  — Cycles round-trip previews; `build_kit.py` — host launcher
- `data/characters/character_visual_catalog.json` — runtime catalog
- `scripts/systems/character_visual_catalog.gd` — pure loader
- `scripts/player/character_visual.gd` — scene consumer; `scripts/player/player_controller.gd` —
  mount + physics-tick feed; `scripts/procgen/playable_generated_ship.gd` — provider injection,
  attack and death hooks
- `tests/test_character_kit.py`, `scripts/validation/player_character_visual_smoke.gd`,
  `scripts/validation/main_playable_player_visual_smoke.gd`

## Acceptance criteria

- Given the main playable path, when the ship is ready, then the player node has a mounted
  `CharacterVisual` with 20 bones and 8 clips and the capsule marker is hidden.
- Given `EquipmentState.equip("hardsuit")`, when one physics tick passes, then
  `Equip_Hardsuit_Chest` and `Equip_Helmet` are visible and the pack/belt nodes are not.
- Given `away_from_start = true` and scripted `+X` travel, when the body moves, then the clip is
  `walk` and the model yaw is `+90°`.
- Given an attempted attack with the default crowbar, then `melee_swing` plays over locomotion.
- Given `end_run("death")`, then `downed` plays and holds.
- Given a catalog id with no asset, then `mount_catalog_entry` returns false and the capsule stays.
- Given a rebuild from source, then the validator passes with the same budgets, bone list, clip
  list, height, pivot and forward axis.

## Validation

```bash
PYTHONPATH=. PYTHONDONTWRITEBYTECODE=1 python3 tools/character_kit/validate_character_glb.py \
  --glb assets/imported/characters/survivor_v1/survivor_v1.glb \
  --manifest assets/imported/characters/survivor_v1/survivor_v1.manifest.json
PYTHONPATH=. PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -q tests/test_character_kit.py
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/player_character_visual_smoke.gd
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_player_visual_smoke.gd
# rebuild (Blender required):
PYTHONPATH=. PYTHONDONTWRITEBYTECODE=1 python3 tools/character_kit/build_kit.py --project-root . --previews
```

Expected markers are registered in `docs/game/06_validation_plan.md` (§ "Procedural character
kit"). Visual evidence: `artifacts/validation-previews/characters/survivor_v1/`.

## Risks

- **Joint gaps at extreme bends** with rigid skinning — mitigated by sphere joint caps; revisit
  with blended weights only if gameplay-distance captures show it.
- **Camera size** makes the body 57 px tall; the inventory recommends evaluating `size 12–14`,
  which is a separate presentation decision.
- **Godot import naming**: the importer strips `-loop` from clip names; the catalog uses the
  imported names and restates the looping set, and the smoke checks both.
- **Threat seam double-render**: binding a GLB to `threat_visual_catalog.json` today shows the
  primitive and the GLB together; tranche 3 must fix `ThreatPlaceholderRenderer` first.
- **Local tooling drift**: Blender 4.2 LTS exporter options are pinned in the builder; a newer
  Blender may rename options — the launcher fails loudly rather than silently exporting a
  different GLB.

## ADRs

- ADR-0070 (this feature's decision record)
- ADR-0052, ADR-0058, ADR-0069 (boundaries preserved)
- ADR-0048 (superseded for the production art path)
