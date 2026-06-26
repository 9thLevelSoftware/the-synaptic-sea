# ADR-0010: Player progression is current-run state in RunSnapshot

Date: 2026-06-21
Status: Accepted
Amends: ADR-0007 (save/load service scope)
Relates to: ADR-0002 / ADR-0003 (hub/meta progression deferral — NOT reopened)

## Context
Phase 3 adds player progression (classes + skills + XP). It must survive
save/load within a sandbox session. ADR-0007 restricts RunSnapshot to current-run
state and requires a new ADR to add a field.

## Decision
Player progression is current-run state: a `player_progression_summary` field is
added to RunSnapshot (SUMMARY_FIELDS count 7 -> 8), round-tripped via
get_summary/apply_summary like the other models. It does NOT introduce a cross-run
meta-progression store; ADR-0002/0003's deferral of hub/meta progression stands.
The "run" is one continuous sandbox session (the player keeps ship, skills, and
inventory while travelling between derelicts; death/restart is undefined).

## Consequences
- Save-smoke count contracts move from summaries=7 to summaries=8.
- Skills/XP persist across save/load within a session.
- force_repair remains the live repair mechanism until Phase 6 supplies parts/tools
  to drive the gated repair() path that consumes the repair skill.
