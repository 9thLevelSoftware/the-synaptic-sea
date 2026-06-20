# Main Playable Slice v2 Readability Proof

## What This Proves

The actual `project.godot` main path now presents the coherent playable ship with semantic objective/blocker/ramp/entry/destination props instead of relying on giant in-world debug text. The existing objective loop remains completable, and the new readability smoke verifies the normal scene exposes semantic props with no visible label clutter.

## Final Acceptance

- [x] `READABILITY PROP FACTORY PASS props=9`
- [x] `MAIN PLAYABLE SLICE READABILITY PASS objective_props=4 blocked=1 ramp=1`
- [x] `MAIN PLAYABLE SLICE HUD PASS canvas_layer=true width=520 current_sequence=1`
- [x] `MAIN PLAYABLE SLICE COMPLETE PASS completed=4 current_sequence=5 run_complete=true`
- [x] `MAIN PLAYABLE SLICE AFFORDANCE PASS objectives=4 blocked=1 vertical=1 landmarks=2`
- [x] `MAIN PLAYABLE INPUT LOOP PASS moved=true camera_followed=true interaction_input_path=true current_sequence=2`
- [x] `MAIN COHERENT BOOT PASS scene=playable_coherent_ship objectives=4 critical_path=5 landmarks=2`
- [x] `COHERENT PLAYABLE TRAVERSAL PASS rooms_traversed=5 side_rooms=3 blocked_route_blocked=true objective_completed=true`
- [x] `PLAYABLE SHIP SMOKE PASS player_spawned=true collision_checked=true interaction_completed=true objectives_completed=1 objective_count=4`
- [x] `MAIN PLAYABLE SLICE CAPTURE SEQUENCE PASS frames=6 mode=viewport output_dir=/Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/main_playable_slice_v2_readability`

## Capture Frames

- `/Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/main_playable_slice_v2_readability/01_spawn_airlock.png`
  - sha256: `23ba45c68caa43085facedc80549a08d2c7ba2a1989b11d532b23f006e23b92c`
- `/Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/main_playable_slice_v2_readability/02_objective_01_prompt.png`
  - sha256: `586a27ffe33214010fba248b4839d44edd437fdf1204291b450b78968198413a`
- `/Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/main_playable_slice_v2_readability/03_objective_01_complete.png`
  - sha256: `b8429f1308ca6c22306931c1573a1c39dbba7bb40121302f6c7559c5c288a148`
- `/Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/main_playable_slice_v2_readability/04_blocked_route.png`
  - sha256: `77c33b40f8c0d3c9f77c80bd268653751def048e11b7966f2d450b1fd169342e`
- `/Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/main_playable_slice_v2_readability/05_vertical_transition.png`
  - sha256: `9e801fc8b13493baaf5c95300c20afd0a131897bff4a70f945bab5a209b9edff`
- `/Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/main_playable_slice_v2_readability/06_slice_complete.png`
  - sha256: `543731baf4a9a528138d07b152d4cb0bc7fb8eb231176485b0c282242f26b42e`

## Contact Sheet

`/Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/main_playable_slice_v2_readability/main_playable_slice_v2_readability_contact_sheet.png`

Contact sheet sha256: `602826bbbddc655e8aebcd489a63b5385b613a533ba94fa54f1ad03681ea3dc6`

## Visual Inspection

The contact sheet was visually inspected after generation (vision analysis of the rendered 2x3 sheet, 1328x1246 PNG, 319.4 KB, six 1280x720 viewport frames). Findings:

- 01 Spawn / entry: A blue entry beacon cylinder with a glowing top sphere sits on the floor near the spawn tile. Yellow route-cue strips connect the spawn room toward the next room. Walls/floors are flat grey slabs; this reads as a prototype ship interior, not a debug word pile.
- 02 Objective prop: An orange supply-cache cube with a yellow lid (the recover_supplies objective) is visible in the upper right room. A yellow route strip leads to it. A red blocker prop is visible at a doorway. A green destination/reactor cylinder is in the lower-right room. No floating text labels.
- 03 Next route: An orange breaker-panel box with a dark switch face (the restore_systems objective) is visible mid-room. Yellow route strips continue from spawn through entry toward this objective.
- 04 Blocker prop: A red BlockedBiomatter membrane with two dark red sphere nodes is clearly blocking a doorway in the middle of the frame. The blockage reads as a prop, not a label.
- 05 Ramp cue: A yellow ramp-arrow (stem + arrowhead box pair) is visible at the top of the frame, cueing the vertical transition up. The route strip continues past it.
- 06 Destination complete: The green destination/reactor core (cylinder + glowing top sphere) is visible in the lower right. HUD shows "COMPLETE - Extraction route found" in progress 4/4.

Answers to the required questions:
1. Objective props visible as objects rather than giant words? Yes - the supply cache, breaker panel, med terminal, and reactor console all read as primitive 3D objects (boxes/crates/terminals/cylinders), not floating word labels.
2. Blocked route visibly represented by a blocker prop? Yes - red BlockedBiomatter membrane + spheres clearly mark the blocked doorway in tile 04.
3. Ramp/vertical transition visibly cued? Yes - the yellow ramp-arrow prop is visible in tile 05.
4. Entry/destination context visible enough for a prototype? Yes - the blue entry beacon at spawn (tile 01) and green destination reactor core (tile 06) frame the slice.
5. Any visible Label3D word piles? No - the only text in frame is the HUD overlay in the top-left of each tile (small framed objective-tracker panel), not in-world Label3D word piles. The normal-mode readability smoke verified visible_label3d_count=0 and visible_interaction_markers=0.

The pixels match the design intent: semantic primitive props replace debug labels, and the existing objective loop remains completable. The visual evidence is honest and matches the runtime pass markers above.

Remaining limitations: props are primitive silhouettes, walls are flat grey slabs, lighting is provisional, route cues are simple strips, and the slice does not include walls/everywhere, VFX, audio, enemies, inventory, or production art. Captures are regression artifacts at 1280x720, not marketing screenshots.

## Limitations

This is still primitive in-engine readability, not production art. Props are simple Godot primitive silhouettes. Lighting, VFX, audio, final walls, enemies, inventory, resource pressure, and broad procgen variety remain outside this slice.
