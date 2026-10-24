# ADR-0070: Project-Zomboid-Style Character Art, Procedural Blender Authoring, and the Character Visual Seam

## Status

Accepted (2026-10-24). Supersedes the production-path portion of ADR-0048 (top-down 2D pivot):
ADR-0048's Status line and index row now say so, the `scenes/topdown` / `scripts/topdown` tree
stays as non-production legacy (smoke-only), and no replacement "ADR-0060 restore-3D" file is
needed because number 0060 is already taken twice.
Complements ADR-0052 (visual-only runtime binding), ADR-0058 (Blender canonical master authority),
and ADR-0069 (procedural biomass assembly for threats).

## Context

The project has no character art. The player is an unshaded blue `CapsuleMesh` built in
`scripts/player/player_controller.gd`, every threat archetype in
`data/combat/threat_visual_catalog.json` has an empty `mesh_path` and renders a primitive, and
no GLB anywhere under `assets/` contains a skin, a humanoid node, or an animation. The art
attempts recorded in `.hermes/plans/` (ComfyUI/LoRA tile textures, Meshy image-to-3D candidates,
the ithappy prop pack, the 2D top-down pivot) produced environment props and evidence, not a
character.

Three facts shape the decision:

1. **The production presentation is locked-isometric 3D, not top-down 2D.** ADR-0048
   (2026-08-18) declared a 2D pivot, but the boot chain `project.godot -> title_main.tscn ->
   main.tscn -> playable_coherent_ship.tscn` never changed, no production script references
   `scenes/topdown/`, and every later accepted ADR (0058, 0060–0069) and the 2026-09-04
   feature-completion program continued in 3D. ADR-0048 is therefore contradicted in practice
   and is superseded here for the art path.
2. **Provider-generated characters were rejected.** ADR-0048 itself records the Meshy pipeline
   output as "terrible" for final art; the `stalker_v1` batch produced no usable creature. A
   character pipeline cannot depend on a paid provider, an external drive master
   (`/Volumes/Untitled/...`), or a reviewer-only screenshot gallery.
3. **The game's camera budget is small.** `IsoCameraRig` is orthographic with `size = 22.0`
   (vertical metres at 1280×720, offset (16, 18, 16) → 38.5° pitch), so a 1.76 m figure is
   ~45 px tall on screen at 720p (~67 px at 1080p) after foreshortening. Detail beyond
   silhouette, colour blocking, and a few readable accents is wasted; this is exactly the
   Project Zomboid register ("PZ, but a bit more detailed").

## Decision

> Character art is authored **procedurally in headless Blender from in-repo Python**
> (`tools/character_kit/`), exported as one normalized skinned GLB per kit, validated by a
> host-side contract validator, and consumed at runtime through a **data-driven character
> visual seam** that keeps collision, equipment truth, and gameplay state in Godot.

### Art direction

- Low-poly segmented humanoids (bevelled boxes, 8-segment cylinders, coarse spheres), flat
  shaded, palette materials with no textures. Base body 800–3 200 triangles; full kit with all
  equipment ≤ 7 000 (`TRIANGLE_BUDGET` in `character_kit_spec.py`).
- Readability first: silhouette, colour blocking (suit fabric vs. hardsuit plate vs. visor
  emissive), one class accent patch the runtime can recolour. No facial detail.
- 1.75 m tall, pivot at the floor centre, `+Z` forward, metres, Y-up (ADR-0058 conventions).
  Blender authoring is Z-up facing `-Y`; the exporter's Y-up conversion yields `+Z` forward.
  Full-kit rest bounds with every equipment node are 1.80 m tall (helmet) and extend 0.37 m
  behind the origin (EVA pack), past the 0.35 m collision radius; that overhang is visual only
  and is recorded by the validator (`kit_bounds_*`), not by collision.
- Bone sockets (`Socket_HandR/HandL/Back/Head`) are counter-rotated at build time so that in
  rest pose their local `+Z` is the character's forward and `+Y` is up; the validator composes
  the exported rest transforms and fails any socket that is not, so a handheld prop authored
  "grip at origin, working end `+Z`" mounts with an identity transform.

### Procedural Blender authoring (not Meshy, not hand-modelled masters)

- `tools/character_kit/character_kit_spec.py` is the single contract: bones, body parts,
  equipment parts, sockets, animation clips, materials, budgets.
- `build_survivor_kit.py` (Blender-only) builds meshes, a 20-bone deform rig with rigid per-part
  skinning (PZ style), procedurally keyframed clips on NLA tracks, bone-parented socket
  empties, and exports `assets/imported/characters/survivor_v1/survivor_v1.glb` plus the
  manifest. `build_handheld_tools.py` exports static tool props with the grip at the origin.
- `validate_character_glb.py` (host Python, no Blender/Godot) re-reads the GLB and enforces
  the contract; `render_character_previews.py` re-imports the GLB (round trip) and renders the
  review set with Cycles CPU. `build_kit.py` is the host launcher.
- The Python source **is** the editable master. A `.blend` may be saved outside the repo for
  artists, but regeneration from source must always reproduce the runtime asset. This removes
  the external-drive dependency that stalled ADR-0058's masters. Reproduction is
  content-level, not byte-level: Blender's glTF exporter does not order accessors
  deterministically, so two builds of the same source differ in bytes while passing the same
  validator with identical bones, clips, triangle counts, bounds and socket axes. Hash
  sidecars are therefore not used for this kit; the validator report is the evidence.

### Runtime seam (Godot authority preserved)

- `data/characters/character_visual_catalog.json` (`version: character-visual-1`) maps a
  character id to its scene path, equipment-item → `Equip_*` node-prefix table, socket names
  and logical → clip animation names. `scripts/systems/character_visual_catalog.gd` is the pure
  loader.
- `scripts/player/character_visual.gd` (`CharacterVisual`, Node3D) mounts the GLB scene,
  toggles equipment nodes from `EquipmentState.slots`, faces the model along its planar
  velocity, selects locomotion clips (idle/walk/crouch/work), plays one-shot actions
  (melee/aim) and the downed pose.
- `PlayerController` mounts the visual in `_ready()` and hides its capsule marker; the
  `CollisionShape3D` capsule is untouched. Equipment and work state are read through Callables
  injected by the coordinator so the visual follows the LIVE `EquipmentState` /
  `WorkActionDriver` instances (both are replaced on load). Locomotion is fed from
  `PlayerController._physics_process`, so the seam is independent of the coordinator's
  home/away `_process` split (CLAUDE.md dual-branch rule) by construction.
- A missing catalog entry or GLB leaves the capsule marker in place and reports
  `visual_source = "fallback"`; nothing borrows another visual (ADR-0052 §6).
- Threat archetypes keep the existing `ThreatPlaceholderRenderer.mesh_path` seam. Note: that
  renderer currently mounts a `PackedScene` **beside** the primitive instead of replacing it;
  it must hide the primitive before any threat GLB is bound (tracked as a follow-up, see the
  inventory).

### Process

Feature spec `docs/game/features/character_asset_inventory.md` carries the must-have inventory
and acceptance criteria; requirements `REQ-CHR-001..006`; validation registered in
`docs/game/06_validation_plan.md` (host validator + pytest + two Godot smokes, one on the away
branch). The art gate (`docs/game/art_shippable_gate.md`) applies unchanged: live consumer,
iso readability evidence under `artifacts/validation-previews/characters/`, budget noted,
human sign-off in the PR.

## Consequences

### Positive

- The player finally has a readable, modular, animated body that reflects worn equipment, with
  zero provider cost and no external masters; every rebuild is reproducible from git.
- The same rig and clip contract can be reused for `puppet_corpse` and a humanoid stalker
  variant (PZ zombie analogy), and the socket contract lets handheld tools mount without
  touching meshes.
- Validation is deterministic and headless on Linux/macOS/Windows; the kit's Godot smokes run
  inside the existing bundle.

### Costs and limitations

- Procedural geometry caps fidelity: no cloth, no faces, no hand-authored sculpt detail. This is
  intended for the camera budget but will need an artist pass if the camera size ever drops
  below ~10 m.
- Rigid per-part skinning shows joint gaps at extreme bends (deep crouch); sphere joint caps
  hide most of it at gameplay distance.
- Animation clips are mathematically authored; they read correctly at iso distance but are not
  motion-captured quality.
- `.import` sidecars for the new GLBs are tracked like the rest of `assets/`; `.godot/` stays
  untracked.

## Alternatives considered

1. **Finish the ADR-0048 2D pivot and ship 2D sprites.** Rejected: the production boot chain,
   all later ADRs, and the feature-completion program are 3D; redoing presentation would
   discard the readability and procgen work and still need character sprites.
2. **Meshy/AI character candidates (ADR-0058 path).** Rejected for characters: the pilot
   produced nothing usable, output is not editable source, and rigging is provider-dependent.
3. **Purchase a character pack.** Deferred, not rejected: no pack matches the suit/pack/belt
   equipment slots and the required `-loop` clip set; a purchased pack can still be bound
   through the same catalog seam later.
4. **Hand-modelled Blender masters on an external drive.** Rejected: ADR-0058's masters stalled
   on exactly this dependency; the source of truth must be in the repository.
5. **Skinned equipment as separate GLBs merged at runtime.** Rejected for v1: one GLB with
   named `Equip_*` nodes toggled by prefix is simpler, deterministic, and matches how PZ layers
   clothing on one skeleton.

## Validation

- Host: `PYTHONPATH=. python3 tools/character_kit/validate_character_glb.py --glb
  assets/imported/characters/survivor_v1/survivor_v1.glb --manifest
  assets/imported/characters/survivor_v1/survivor_v1.manifest.json` →
  `CHARACTER KIT VALIDATE PASS ...`; `python3 -m pytest -q tests/test_character_kit.py`.
- Godot: `player_character_visual_smoke.gd` → `PLAYER CHARACTER VISUAL PASS ...`;
  `main_playable_player_visual_smoke.gd` → `MAIN PLAYABLE PLAYER VISUAL PASS ... away_ticks=true ...`.
- Visual: `artifacts/validation-previews/characters/survivor_v1/*.png` (turnarounds per
  equipment variant, pose contact sheet, gameplay-distance iso frame at camera size 22 and 12).
