# Gate 2 Scope Note — Hub/Meta Branch and Must-Haves

## Decision branch

Gate 2 follows **Option A: re-affirm hub/meta deferral**. ADR-0003 is Accepted and states that hub/meta progression remains deferred through Gate 2 while Gate 2 focuses on derelict exploration depth: inventory/tools, expanded hazards, objective/procedural variation, and current-run persistence (`docs/game/adr/0003-reaffirm-hub-meta-deferral-through-gate-2.md`, lines 20-31). `docs/game/08_milestone_gates.md` repeats the same Gate 2 stance and explicitly excludes hub ship UI, derelict selection/queueing, meta-currency, persistent unlocks, faction/narrative progression, hub save state, and `features/hub_progression.md` from Gate 2 (lines 83-93). The later kickoff comment on `t_9b3386cd` says "switch to option A then", resolving the earlier dashboard "option b" comment in favor of the recorded ADR.

## REQ-001..REQ-009 disposition

| Requirement | Gate 2 disposition | Rationale |
|---|---|---|
| REQ-001 Route gates are real runtime blockers | In scope as validated baseline | Preserve route-gate collision/passability while adding Gate 2 systems. |
| REQ-002 Restoring systems opens powered route gates | In scope as validated baseline | New tools/hazards must not break objective-2 route unlock behavior. |
| REQ-003 Reactor stabilization unlocks extraction | In scope as validated baseline | Gate 2 must retain the current extraction/completion signal. |
| REQ-004 New gameplay systems require model and scene validation | In scope / blocking process requirement | Every Gate 2 feature needs direct model validation when practical plus main-scene validation before done. |
| REQ-005 No proof-only milestone substitution | In scope / blocking process requirement | Gate 2 deliverables must be in-engine runtime behavior, not mockups or proof docs. |
| REQ-006 Hazard pressure loop | In scope as foundation touched by expansion | Existing oxygen loop stays valid; hazard variety should extend it without coupling hazard state to route/extraction state. |
| REQ-007 Inventory/tool loop | In scope as a must-have implementation surface | Proposed requirement becomes Gate 2 work: at least one acquired/selected tool or inventory item affects a runtime obstacle, route, hazard, or objective and persists for the current ship slice. |
| REQ-008 Hub/meta progression stance for Gate 1 | Deferred feature surface / in-scope guardrail | Its hub/meta exclusions continue to guard Gate 2 via ADR-0003; no hub ship, derelict selection, meta-currency, persistent unlocks, faction progression, or hub save state. |
| REQ-009 Gate 2 hub/meta re-decision trigger | Resolved governance, not build scope | ADR-0003 selected Option A. Gate 2 cards cite it; no `features/hub_progression.md` or Option B implementation cards should be created. |

## Gate 2 must-have decisions

| Must-have | In scope? | Blocking dependencies | Contradictions / reconciliation |
|---|---:|---|---|
| Inventory/tool loop (REQ-007) | Yes | Author `docs/game/features/inventory_tools.md`; define the first tool/item, affected obstacle/route/hazard/objective, current-slice persistence boundary, validation smoke(s), and whether an inventory/tool data-model ADR is needed (`04_tdd.md`, lines 53-59). | `route_control.md` currently says no inventory keys/tools and `hazards.md` says no oxygen tanks, pickups, or inventory items until REQ-007 ships. Those are Gate 1 non-goals, not permanent cuts; REQ-007 work must supersede them explicitly and preserve REQ-001..003 behavior. |
| Expanded hazard variety | Yes | Author a second-hazard or hazard-variety feature spec; mint a new requirement during Gate 2 decomposition; define generalized multi-hazard architecture if the new hazard cannot reuse the oxygen pattern; add model + main-scene smokes per REQ-004. | `hazards.md` says no multiple hazard types in the Gate 1 slice. Gate 2 may lift that cut only with a spec/requirement and without changing REQ-006's validated oxygen semantics. |
| Additional objective types or procedural variation | Yes | Author an objective/procedural-variation spec; mint a new requirement during Gate 2 decomposition; define data/schema changes and validation proving generated variation remains playable and readable. | No direct REQ-001..009 contradiction, but `03_gdd.md` warns against content-scale work before systems are stable. Keep scope to one validated variation path before broad content lists. |
| Save/load run persistence | Yes, limited to current-run/current-ship-slice state | Author a save/load scope spec and likely ADR for a formal save/load service (`04_tdd.md`, lines 53-59); define serialized state for objectives, route gates, hazards, inventory/tools, and player/run position; add load/resume validation. | Must not become hub save state, cross-run unlocks, meta-currency, or derelict selection persistence. ADR-0003 line 31 limits Gate 2 save/load to run/ship-slice persistence unless a Gate 3 hub/meta decision expands it. |

## Stop conditions

Stop and re-escalate if any Gate 2 card introduces hub ship scene/UI, derelict selection or queueing, persistent meta-currency, persistent unlocks, faction/narrative progression, hub save state, or `features/hub_progression.md` without a new ADR revising ADR-0003. Stop if any must-have proceeds without a feature spec, requirement entry, and validation plan, or if current-run persistence is interpreted as cross-run/hub-level persistence.
