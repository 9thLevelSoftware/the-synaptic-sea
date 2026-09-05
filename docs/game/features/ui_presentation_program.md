# UI presentation program — design and acceptance proposal

**Status:** Proposed for review, 2026-09-05. Planning only; no UI implementation or visual acceptance is claimed.
**Baseline:** `f4a65669`, including the user's existing, uncommitted September 4 crafting/restoration planning documents as dependency inputs.
**Review:** [repository and asset audit](../audits/2026-09-05-ui-repository-review.md).
**Execution:** [phased implementation plan](../../superpowers/plans/2026-09-05-ui-presentation-program.md).

## Purpose

Make the existing survival simulation understandable, usable, and visually coherent from title to death or extraction. The interface should feel like equipment carried by a stranded spacer: sturdy industrial instruments, concise readings, visible consequences, and unsettling space beyond them. Its complexity belongs in deliberate inspection screens; ordinary movement should remain a view of the ship.

This program covers creation of missing UI components and assets, refinement of working screens, and enhancement of navigation and feedback. It preserves the existing gameplay models. Crafting/restoration functionality remains owned by the [September 4 program](crafting_derelict_feature_completion.md), especially P09 and P21 of its plan.

## Authority and boundaries

Read in this order: current user direction and `AGENTS.md`; [vision](../00_vision.md) and [pillars](../01_design_pillars.md); active feature contracts and accepted ADRs; current code; historical plans and captures. Inventory percentages describe recorded coverage, not visual quality or complete player acceptance.

Global constraints for this program:

- Native Godot 4.7.1 Forward+ is the repository validation target; verify the executable and imports before runtime work. `project.godot` declares 4.7; older 4.6.2 status/tool paths are historical.
- Keep the locked-isometric 3D camera and the live title → main → coherent hub/away path.
- Preserve pure typed `RefCounted`/`Resource` state, injected dependencies, signals, and scene-owned consequences.
- Use one writer at a time for `scripts/procgen/playable_generated_ship.gd` and `scripts/ui/menu_coordinator.gd`.
- Preserve player oxygen/load's single HUD home under ADR-0027.
- Preserve ADR-0045: no interior minimap, room map, or omniscient enemy radar. Web charts remain item-gated, ship-position based, read-only, and session-only.
- Preserve ADR-0043 permadeath freeze, load refusal, save guards, and Save & Exit behavior.
- Support keyboard, mouse, and gamepad across supported menus and workflows; glyph display alone is insufficient.
- Support text scale 1.0×, 1.5×, and 2.0× without clipping critical information or reducing the requested text size.
- Milestone A keeps the fixed default start, `breach_field`/`standard`, seeds 42 and 777, and 20–40-minute cold-player journey. No new title class picker is required.
- Windows and macOS are the native release targets in the slice/demo contract. Linux is optional. Mobile/touch and a browser port are separate future product decisions.
- Do not promote PoC tiles or unreviewed art into runtime. Use the existing shippable-art gate and record provenance for new UI assets.
- UI models must never fabricate eligibility, travel knowledge, inventory quantities, quality, repair costs, or flight readiness.

The named game-ui-frontend skill supplies hierarchy, restrained motion, and playfield-protection principles. Translate its CSS theme/DOM recommendations to Godot `Theme`, containers, and `Control` nodes. Blender supports asset production, not replacement of accessible interactive controls with meshes.

## Decisions proposed by this plan

These are reviewable proposals, not newly accepted ADRs. U00 in the execution plan records their disposition before dependent implementation.

| Decision | Recommendation | Consequence |
|---|---|---|
| Visual direction | Worn industrial instrumentation with restrained cyan information and amber/red warnings | Extends current dark panel and colored-outline icon language; avoids a new unrelated aesthetic |
| UI ownership | Shared native theme/components; retain existing presenters and model commands | Incremental screen replacement instead of a UI/gameplay rewrite |
| Menu time | Pause, settings, records, and their confirmation dialogs suspend simulation; gameplay inspection panels retain live simulation | Corrects the current input-only pause; requires an explicit simulation/input ADR and both-branch tests |
| Accessible layout | Reflow/scroll/tab larger content; keep important readings visible | Replaces multiplying entire fixed rectangles by text scale |
| Settings ownership | One user preference source shared by title and in-run UI, with compatible migration from saved settings | First-run accessibility works before gameplay; persistence changes require review |
| Chart enhancement | Graphical presentation only of knowledge already permitted by the chart model | Visual polish cannot accidentally reveal hidden positions/routes or turn the chart into travel controls |

The proposed layout ADR supersedes ADR-0027's requirement to keep Tool/item/Repair Skill/system-detail lines in ObjectiveTracker and the older UI feature's bottom-center hotbar placement. It retains ADR-0027's oxygen/load source and single persistent-home invariant. The proposed preferences ADR explicitly supersedes ADR-0043 §6's deferral of a standalone settings file; its permadeath, save/load, title lifecycle and Save & Exit decisions remain in force. Milestone A difficulty is displayed read-only as Standard; user preferences and accessibility presets cannot override the run profile.

Do not assume tree pause alone solves time suspension: world time, run time, threats, oxygen, fire, food, work, station jobs, autosave timing, and offscreen catch-up all need a coherent policy. Presentation/audio needed to operate a pause menu must continue. Resuming must not apply paused wall-clock time as survival damage or craft progress.

## Visual system

### Direction and assets

Use desaturated alloy, graphite polymer, subtle seams, and small instrument markings. Biomatter can intrude into title artwork, world terminals, or explicitly unreliable hallucination layers; it should not obscure reading, focus, or commands. Do not put grit, scanlines, glow, or animation over text. Reserve distressed textures for broad backing surfaces at low contrast.

The eight existing 64×64 achievement images are references for a colored-outline icon family, not automatic final-art approvals. Status artwork is missing in practical terms: the eight status PNGs are 1×1 placeholders. Imported terminal atlases belong primarily on world props; their saturated graphics should not become the global HUD.

Starting tokens below are proposed design values, to be measured in rendered screenshots before acceptance:

| Role | Starting value/use |
|---|---|
| Backing / raised panel | `#0D151C` / `#17232C`; essential readings use sufficiently opaque backing |
| Main / secondary text | `#E8EEE9` / `#B6C4C9`; test composited contrast, including disabled controls |
| Information / keyboard focus | `#69D2DF`; focus also has a visible outline, not hue alone |
| Caution / danger | `#F2BE62` / `#F17B72`; pair with a distinct symbol and explicit wording |
| Success / completion | `#9CCB9B`; retain text and shape cues in all colorblind modes |
| Spacing | 4/8/12/16/24/32 logical pixels; 18-pixel base safe inset |
| Type | Body/action text 18 px minimum at 1×; secondary metadata 16 px; headings 24/32 px |
| Control size | 44 logical-pixel baseline row/button height; expand to fit scaled text |
| Motion | 120–180 ms open/close/focus transitions; no idle pulsing on ordinary HUD |

Use one licensed, legible sans family for prose/actions; optionally one compatible mono family for quantities, ship IDs, and instrument readings. Evaluate `I/l/1`, `O/0`, minus signs, decimals, accented characters, and the catalog's supported scripts before selecting files. Do not choose a decorative sci-fi font for body copy. Record font licenses and fallback coverage. No font purchase or new font dependency is selected by this proposal.

Targets: at least 4.5:1 text contrast and 3:1 meaningful component/focus boundaries, measured over actual normal/emergency/dark backgrounds. These are project acceptance targets, not a claim of formal accessibility certification.

### Asset production with Blender

Blender is installed at `C:\Program Files\Blender Foundation\Blender 5.2\blender.exe`. Existing structural and Meshy validation scripts can inform source/export discipline, but the repository has no finished UI thumbnail renderer. Create a small dedicated rendering recipe rather than adapting structural collision/export validators into icon validators.

Use Blender for approved item/tool/equipment thumbnails: fixed orthographic camera, consistent three-quarter silhouette, transparent background, neutral lighting, safe padding, and reproducible naming. Render 256 px masters; inspect 32/48/64/96 px outputs before promotion. Small status and input glyphs should remain simplified 2D symbols; detailed 3D renders are unsuitable at that scale. Render title artwork from approved world assets only after the live scene's composition is representative.

Author in `artifacts/ui-presentation/source/` or a documented available external source root; record the actual Windows path instead of copying unavailable macOS source paths. Stage in `artifacts/ui-presentation/staged/`. Promote approved exports under `assets/ui/`, with editable source location, source asset ID, provenance/license, authoring method, render recipe, dimensions, and consumer recorded in the planned manifest. Do not derive UI textures from third-party atlases until their source rights are documented.

Native Blender background CLI is sufficient for batch rendering and reproducibility. An interactive Blender MCP is optional for later scene/material iteration if it provides a needed capability; installing a connector is not a prerequisite to this plan. The user has authorized using Blender and installing supporting MCPs/CLIs when useful.

The full asset denominator includes every item/status/command displayed by the supported UI, not just the opening slice. Slice-critical assets require individually reviewed icons. Other items may use an approved category silhouette plus their exact text name; record that mapping explicitly for every item ID. A missing/1×1 asset or an unresolved ID is never an approved fallback. The Blender executable is configurable per host and its actual version and render settings are recorded with each batch.

## Information architecture and screen behavior

### Persistent HUD and disclosure

One primary cluster at the lower-left contains health, personal oxygen, stamina, urgent status, and quick-use/weapon information. One small upper-left objective chip gives the current actionable step. Full objective history, detailed ship diagnostics, controls, skill numbers, and recent logs live behind inspection surfaces.

- Health, personal oxygen, and stamina remain readable without hover. Distinguish suit supply, compartment pressure, and hub life support in labels/details; do not merge them into a misleading number.
- Hunger/thirst/fatigue, temperature, wounds, sanity effects, and encumbrance become severity-ranked status symbols with text access. Show imminent danger immediately; detailed values remain accessible in the survivor view.
- Preserve one source and one persistent display for oxygen and carried load. Show weapon magazine/reserve and reload state beside the active weapon; keep consumable slots in the same cluster rather than another full-width bar.
- Context prompts are short and transient: bound glyph, verb, target, essential blocker. Anchor near the relevant focus with edge clamping, or above the primary cluster when that would obscure the player/target.
- Work progress appears directly above the cluster while active, with verb, progress, interruption/blocker, and relevant noise/stamina consequence. It is not a permanent third panel.
- World-space affordance, fire and unsafe-room labels share the hierarchy: show nearby actionable information clearly, suppress redundant distant label clutter, and test distance/occlusion/scale against the HUD prompt. Preserve intentional hazard/route affordances; do not turn world labels into through-wall information reveals or silently remove required warnings.
- Normal 1× HUD target is ≤20% viewport coverage; 25% is a ceiling. At 1.5×/2×, target ≤30% and ceiling 35% using reflow and disclosure, never smaller text. Measure the union of visible backed regions, not a sum that double-counts overlaps.
- Persistent UI must not cover the central 40% width × 45% height play area or the lower-middle traversal corridor (x=35–65%, y=70–100%). Transient prompts and explicit inspection screens are reviewed separately.

```text
┌────────────────────────────────────────────────────────┐
│ [Current objective — one actionable line]               │
│                                                        │
│                CLEAR SHIP / PLAYER VIEW                 │
│               transient target prompt only              │
│                                                        │
│ [captions / active work, only when needed]               │
│ [health · O2 · stamina]                                 │
│ [urgent states · weapon · quick use]                    │
└────────────────────────────────────────────────────────┘
```

This is a zoning proposal, not an in-engine screenshot or accepted UI composition. At large text sizes, the objective can wrap to two lines and the primary cluster reflows internally. Never hide a critical alarm to meet a coverage metric.

### Menus, inspection, and time

| Surface | Proposed time/input contract | Required feedback |
|---|---|---|
| Normal play | Simulation and gameplay input active | Current goal, survival, interaction |
| Inventory, crafting, wounds, scanner, chart, modification/restoration | Simulation live; all gameplay commands blocked; one top-level panel | Clear `LIVE` state, critical readings/alarms remain visible, immediate close and pause paths |
| Pause/settings/records/save dialogs | Simulation suspended, menu input only | Clear `PAUSED`; nested Back returns one level and restores focus |
| Travel/load transition | Single authoritative request; block duplicate commands | Progress/state text and recoverable failure; never a cosmetic completed transition |
| Death/extraction results | Existing terminal run state; result actions only | Cause/outcome, consequences, safe next action |

From any live inspection panel, a dedicated pause action opens pause above it; Back closes the topmost surface and restores prior focus. Resolve the current shared Escape cancel/pause binding in the input contract: Escape/Back closes the topmost inspection/dialog; Start or an explicit on-screen Pause action enters pause. From normal play Escape enters pause. Opening pause above inspection must not cause two surfaces to process one input. A held confirm key must not activate the restored underlying view.

Blocking means every gameplay action is denied by default, including movement, attack, reload, crouch, hotbar/use, field craft, held work/interact, developer save/load shortcuts, and competing panel toggles. Explicit UI actions invoke only their intended guarded command. Verify both `_input` and `_unhandled_input` paths. Surface time/blocking policy is registered once by ID, and focus restores from a stable item/command token rather than a potentially freed Control.

### Screen-by-screen target

| Workflow | Create/refine/enhance | Required states and behavior |
|---|---|---|
| Title/start | Refine existing flow into real buttons over restrained approved artwork | New Run; Continue valid/absent/frozen/corrupt; accessible Settings before play; loading/failure; fixed slice start |
| Pause/settings | Replace text-row settings with tabs, toggles, sliders, selectors | Resume; accessibility, input, audio, language; runtime application; preferences survive restart; correct focus/Back |
| Saves/results | Refine existing presenters, keep service semantics | World vs ship slot scope labeled; manual/auto/quick provenance; timestamp/playtime; failed write; frozen epitaph; delete confirmation; no false Continue |
| Inventory/equipment/loot | Keep list-based PZ-inspired logistics; structured two-pane transfer and detail area | Empty/full/unavailable container; sorting/filtering; quantity, raw/effective mass, equipped destination; partial transfers; use/equip/drop/split; keyboard/gamepad alternative for every drag action |
| Survivor/wounds | Integrate health detail with existing wounds actions | Critical condition first; affected body part only if model supplies one; treatment availability/cost/outcome; keyboard/gamepad Bandage/Treat; no invented diagnosis |
| Recipes/stations/field craft | Refine current recipe picker; integrate P09 transaction presentation when ready | Selected station/recipe, available vs required inputs, actual blockers, output; later quality/lot selection, paid queue, power pause, cancellation loss/refund, pending output |
| Work and repairs | Refine existing WorkAction feedback | Correct ship/target/verb, progress, noise, stamina, interruption reason; no progress fabrication or double execution |
| Scanner/travel | Build backed selectable contact list with detail/confirmation | Empty/no signal/blocked travel/fuel shortage; known data versus unknown; boarding and return states; cost preview if model supports it |
| Web chart | Enhance text chart into optional diagram with equivalent text list | Possessed chart gate; recorded ships/routes only; unknown/unavailable route; no interior rooms or travel action; session knowledge preserved |
| Ship modification/restoration | Style current slots first; integrate P21 restoration screen after model gates | Ship/room/module identity; selected condition; compatibility/power; later repair vs rebuild costs/blockers, paid work, installed machinery, ownership and flight readiness |
| Codex/tutorial/audio log | Refine into readable navigation, progressive teaching, transcripts | Locked/unlocked/empty/new; unread state only with persistence contract; replay/skip; captions and log controls; no lore over combat |
| Skills/upgrades/classes/achievements | Apply common list/detail/control patterns to existing screens | Cost, prerequisites, locked/unlocked/maxed, pending/failure; actual command outcomes; class roster remains outside A title flow |
| Build info/credits | Quiet secondary records | Readable version/support/build information and attribution; no diagnostic HUD noise during play |

For all actionable surfaces: normal, hover, keyboard focus, selected, disabled-with-reason, busy, success, failure, empty, and long-content states are required. Maintain selection by stable model identity after refresh, transfers, sorting, load, or travel; choose a deterministic adjacent row when the selected item disappears.

### Feedback, tutorials, and horror

Priority order: critical danger → action denial → active work → contextual instruction → tutorial → reward/lore. Critical danger stays until resolved; denial stays while its affected action is focused, with a short toast for immediate feedback. Deduplicate repeated events and throttle audio per semantic event. Tooltips from the topmost focused panel own the detail area; world proximity cannot overwrite an inventory selection.

Teach move/interact, take/equip/use, oxygen interpretation, fire/breach response, craft/repair, scanner/boarding/return, threat response, and death/extraction meaning through existing runtime events. Preserve once-per-run/skip/codex semantics. Add the crafting/restoration beats from P21 only when their real events exist. Keep a replayable help destination; avoid timed text as the sole way to learn a critical control.

Preserve authored hallucination behavior and uncertainty. Unreliable contacts stay in the intended hallucination presentation layer; focus rings, action costs, confirmations, accessibility settings, and save/death semantics remain trustworthy. Do not repurpose accessibility color changes to conceal actual severity. Keep essential captions when decorative motion is reduced.

## Responsive, input, accessibility, and performance acceptance

Test 1280×720, 1920×1080, 2560×1440, 3440×1440, and 1280×800 at 1×/1.5×/2×; include a 4K/high-DPI native-window check. 1280×800 is a compact-screen stress target, not a Steam Deck certification or new port commitment.

Use anchors and containers; choose layout by usable logical area after UI/text scaling. Dense panels use a two-pane layout when it fits and labeled pane tabs plus a shared details region when it does not. Headers, critical status, action bar, and Back stay reachable while lists scroll. Tooltips clamp to the viewport. Do not change the camera to compensate for UI overflow or blur UI with lower-resolution 3D rendering.

Every major UI workflow must complete with keyboard-only, mouse-only UI navigation, and gamepad-only UI navigation, including transfer quantities, treatment, recipe/queue actions, and nested settings. Full gameplay testing uses the supported movement/action bindings; this UI program does not require new mouse-driven locomotion. Provide explicit initial focus, directional neighbors, focus restoration, scroll-into-view, visible focus, and connected/disconnected-device behavior. Actual remapped bindings supply glyphs; do not show unsupported controller promises.

Check all colorblind presets on actual consumers, caption toggle and readability, reduced motion on tutorials/title/hallucination effects within their contracts, hold/tap semantics, and preferences on title/new/load/restart. Audit the custom localization catalog and renderer before using engine pseudolocalization; a custom raw-string renderer needs an explicit pseudo-catalog path. Stress strings with 40% expansion and accented glyphs. RTL and screen-reader certification are not asserted by the current contracts; do not mislabel their absence as already supported.

Refresh structured UI only on relevant changes or bounded display ticks. A theme change must not rebuild entire inventory lists every frame. Profile an actual full inventory and chart after the baseline; target no sustained >1 ms UI CPU delta or >5% frame-time regression on the recorded test machine, and no growth after 100 panel open/close cycles. These are provisional budgets to record against measured hardware, not claims about current performance.

## Proposed requirement register

IDs below are reserved proposals in this document, not claims that the canonical requirement registry or Kanban board has been updated. U00 reconciles REQ-UI-001..016 (only 001/003/006 currently appear as canonical rows), preserves historical IDs, and registers these additional criteria with traceable verification.

| ID | Observable acceptance | Plan packages |
|---|---|---|
| REQ-UIP-001 | Current sources, UI routes, requirement denominator, dependencies, and approved scope agree | U00 |
| REQ-UIP-002 | Shared theme renders title, one live HUD cluster, a modal and all control states consistently | U01 |
| REQ-UIP-003 | Every promoted slice-critical icon/font has a real asset, readable small-size proof, provenance, and live consumer | U02 |
| REQ-UIP-004 | No clipped/overlapping critical UI at the resolution/text-scale matrix; protected playfield and coverage targets met | U01,U04,U12 |
| REQ-UIP-005 | Exactly one UI input owner; Back/focus/held-input behavior works; approved pause policy holds on home and away | U03,U12 |
| REQ-UIP-006 | Title, preferences, save/load/failure and terminal results work through real controls without weakening save guards | U05,U12 |
| REQ-UIP-007 | Survival, objectives, work, captions, and denial feedback are legible, prioritized, accurate, and nonduplicated | U04,U06 |
| REQ-UIP-008 | Inventory/equipment/transfer/treatment complete with keyboard, mouse, and gamepad and accurate state | U07 |
| REQ-UIP-009 | Recipe/job UI exposes authoritative eligibility, cost, cancellation and pending-output behavior from P09 | U08 |
| REQ-UIP-010 | Scanner/chart preserve knowledge and item gates, communicate travel/blockers, and never reveal an interior map | U09 |
| REQ-UIP-011 | Restoration UI identifies selected ship/target and shows model-backed costs, blockers, work and readiness from P21 | U10 |
| REQ-UIP-012 | Tutorial/codex/records/progression/log surfaces are reachable, coherent, replayable where supported, and accessible | U06,U11 |
| REQ-UIP-013 | Supported settings visibly apply, persist, and survive title/new/load/restart; localized copy fits | U01,U05,U11,U12 |
| REQ-UIP-014 | Fresh production-path evidence, clean marker-based regression, performance checks, and cold-player acceptance exist | U12 |

## Definition of done and deliberate deferrals

An individual screen is done only with real model bindings, all relevant states, three-input navigation, supported scaling, asset provenance, focused tests, and live captures. Screenshots of a gallery are design evidence; they cannot satisfy a player workflow gate.

The first delivery target is a coherent Milestone A journey through existing working mechanics. The complete UI program additionally requires P09/P21 integration and every existing supported surface to meet the new UI contract. An unavailable gameplay dependency remains an explicit open row; it cannot be represented by a disabled mock screen and counted complete.

Interior mapping remains excluded by ADR-0045. Defer arbitrary freeform construction UI, Steam/cloud features, mobile/touch, a browser frontend, new simulation domains, new title class selection, decorative animation systems, and full screen-reader/RTL certification. Existing required features outside Milestone A remain in the complete program instead of disappearing from the denominator.
