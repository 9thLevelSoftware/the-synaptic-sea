# Alpha Content-Complete Target

## Purpose

Define what "content complete" means for Synaptic Sea Alpha so Gate 3 exit criteria and Gate 4 Beta entry criteria are unambiguous. This document is the source of truth for Alpha scope; any new content category introduced after it is approved must either fit inside these targets or trigger a gate re-decision.

## Scope boundary

Content-complete for Alpha does **not** mean final release content. It means the derelict-exploration loop has enough distinct templates, objectives, hazards, and tools that Beta can focus on polish, performance, accessibility, input, and release-candidate tasks rather than closing core content gaps.

Hub/meta progression remains deferred past Alpha per ADR-0003 unless a new ADR explicitly revisits it during Gate 3 entry planning. Therefore the Alpha "session" is one generated derelict run.

## Content targets

| Category | Current (post-Gate 2) | Alpha target | Gap | Source |
|---|---|---|---|---|
| Unique ship layout templates | 1 (`coherent_ship_001`) | 3 | +2 templates | This document |
| Objective types | 5 (`recover_supplies`, `restore_systems`, `download_logs`, `stabilize_reactor`, `repair_junction`) | 5 | 0 | REQ-011 + existing objective pipeline |
| Hazard types | 2 (`oxygen_breach`, `timed_fire`) | 3 | +1 hazard type | REQ-006, REQ-010, REQ-013 |
| Tool / inventory items | 1 (`portable_oxygen_pump`) | 2 | +1 tool | REQ-007, REQ-014 |

### Ship layout templates: 3

A layout template is a distinct hand-authored `ship_layout` JSON under `data/procgen/golden/` with its own `program_id`, room graph, critical path, and gameplay-slice companion. Templates must differ in topology (not merely prop permutation) so a player can recognize the ship shape on repeated runs.

- Template A (existing): `coherent_ship_001` — horizontal spine with side rooms, one deck transition via ramp.
- Template B (new): a bifurcated layout where the player must choose/traverse two major branches before converging on the reactor.
- Template C (new): a stacked layout with two meaningful vertical layers and multiple ramp/elevator transitions.

Procedural variation is achieved by seed-driven room dimensions, prop placement, objective/hazard/tool placement, and blocked-link selection within each template. Three templates plus per-template variation is sufficient for Alpha; no additional hand-authored templates are required for Beta entry.

### Objective types: 5

The five objective types implemented by the end of Gate 2 are sufficient for Alpha. Alpha work may vary which sequences use `repair_junction` and may adjust narrative framing, but does not need a sixth objective archetype.

### Hazard types: 3

Alpha adds exactly one new hazard type to the two validated in Gate 2. The third hazard must:

- Have its own pure state model and main-scene smoke.
- Toggle real passability, resource pressure, or traversal timing.
- Not duplicate oxygen-breach or timed-fire semantics.
- Be placed on at least one non-critical link in each new template where it fits the topology.

Candidate: an `electrical_arc` hazard that toggles a doorway/corridor passability state on a timer complementary to fire, or a `radiation_leak` zone that drains a resource or blocks traversal until a system objective clears it. The final choice is left to the implementation plan, constrained by the acceptance criteria above.

Selected: `electrical_arc`. Full specification is in `docs/game/features/hazard_type_3.md`, including the pure state model, scene integration, smoke tests, and placement rules for each new template. The `radiation_leak` alternative is deferred past Alpha.

### Tools / inventory items: 2

Alpha adds exactly one new tool to the portable oxygen pump. The new tool must:

- Be acquired by interaction with a pickup.
- Modify an environmental system or traversal decision.
- Have its own direct model smoke and main-scene smoke.
- Be serializable by the current-run save/load service.

Selected: a `junction_calibrator` that reduces the number of repair-junction steps by one (minimum one step remains). See `docs/game/features/tool_type_2.md` for the full feature spec, acceptance criteria, and verification commands.

## Run length and session loop target

- Target run length: 4–6 minutes for a complete derelict from spawn to extraction or abort.
- Target session loop count: 1 derelict run per Alpha session.
- No persistent hub/meta loop is required for Alpha content-complete (per ADR-0003).

The 4–6 minute target preserves the existing 5-minute loop in `02_core_loop.md` while allowing the larger templates to push toward the upper bound. Run length is measured by automated playtest timing or by stopwatch during human fresh-player sessions, not by content count alone.

## Procedural variation stance

Procedural variation within templates is sufficient for Alpha. The variation must include:

- At least two valid objective placements per objective sequence slot per template.
- At least two valid hazard placements per hazard-supporting link per template.
- At least two valid tool-pickup rooms per template.
- At least two blocked-link configurations per template.

A run must not be mechanically identical to the previous run on a different seed. The exact randomization rules are owned by the procedural generator and validated by seed-diversity smoke tests.

## Dependencies before implementation

- REQ-013 (Alpha hazard variety) and REQ-014 (Alpha tool variety) must be added to `docs/game/05_requirements.md`.
- ADR-0005 (Multi-Hazard Architecture) should be authored before the third hazard is implemented if it shares any code with `FireState` or `OxygenState`.
- ADR-0004 (Inventory/Tool Data Model) should be authored before the second tool is implemented if the tool/effect system is generalized beyond hard-coded multipliers.
- New template JSON files must follow the `schema_version` and `document_kind` contract established by `coherent_ship_001/layout.json` and `coherent_ship_001/gameplay_slice.json`.

## Verification

Alpha content-complete is verified by:

1. The regression bundle in `docs/game/06_validation_plan.md` passes with all new smokes included.
2. Each of the 3 layout templates loads and completes end-to-end via a main-scene smoke.
3. Each of the 3 hazard types has a passing direct model smoke and at least one main-scene placement smoke.
4. Each of the 2 tools has a passing direct model smoke and at least one main-scene placement smoke.
5. Automated or human playtest confirms a 4–6 minute run length on at least two seeds per template.
6. This document is cited in `docs/game/08_milestone_gates.md` Gate 3 exit criteria.

## Non-goals for Alpha

- No enemies or combat AI.
- No narrative branching or faction progression.
- No production art pipeline beyond what supports gameplay validation.
- No hub ship scene, derelict selection, persistent meta-currency, persistent unlocks, or cross-run progression.
- No multiplayer.
