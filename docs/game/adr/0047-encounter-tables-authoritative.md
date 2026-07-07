# ADR-0047: Encounter tables are authoritative over the role constants

- **Status:** Accepted
- **Date:** 2026-07-07
- **Supersedes / amends:** extends the Stage-6 EncounterInjector design (REQ-PG-007/009/010)

## Context

The 2026-07-06 foundation audit found the three authored encounter tables
(`data/procgen/encounter_tables/{biomatter_lurker,derelict_pirate,threat_drone_swarm}.json`)
loaded by **nothing**: `EncounterInjector` resolved every marker kind from the
hardcoded `ROLE_TO_ENCOUNTER_KIND` dictionary with `count = 1`, and the
biome's `encounter_table_id` — stamped on every marker — selected nothing
(dead metadata). The tables diverge from the constants in gameplay-relevant
ways: `derelict_pirate` maps `bay`/`corridor`/`hangar` to `drone_scout`
(constants say `drone_swarm`/`biomatter_lurker`), authors **dual rolls** for
`compartment` (drone_scout w=5 / biomatter_lurker w=4), and expresses count
ranges (`[1, 2]`).

## Decision

**The biome's encounter table is the authoritative source for marker kind and
count; the constants are the fallback tier.** Full table semantics (user
decision, 2026-07-07):

1. `EncounterInjector` loads `res://data/procgen/encounter_tables/<encounter_table_id>.json`
   (cached in a class-scope `static var` so warn-once and the parse both hold
   process-wide — production creates one injector per pipeline run; tables
   are read-only data, so the shared cache cannot affect per-seed
   determinism. PR #67 review). `encounter_table_id` comes from the biome
   profile and is now LIVE — it selects the table.
2. For a role the table covers: the kind is a **deterministic weighted roll**
   among that role's table rolls (single roll consumes no rng draw); the
   marker `count` comes from the roll's authored int-or-`[min, max]` value
   (ranges consume one rng draw, floored at 1). `ThreatManager._spawn_from_markers`
   already honors `count` (fans multiple threats out per marker), so ranges
   are live end-to-end.
3. For roles the table does not cover — and for biomes whose table file is
   missing or malformed (warn-once) — `ROLE_TO_ENCOUNTER_KIND` + `count = 1`
   apply exactly as before. `breach_lurker` intentionally has no table file:
   it reaches markers only through the constants (`airlock`).
4. Spawn **probability** is unchanged: `ENCOUNTER_BASE_PROBABILITY` × the
   biome × difficulty density modifier still gates whether a room rolls a
   marker at all. Tables govern *what spawns*, not *whether* it spawns.

## Consequences

- dead_fleet derelicts now spawn scouts (not swarms) in bays/hangars/corridors
  per the authored table — a deliberate balance shift the table author
  intended; per-seed marker replay changes for table-covered biomes.
- Editing a table JSON changes spawns without touching GDScript; the constants
  remain the single fallback and the procgen↔combat kind contract.
- Validation: `encounter_injector_smoke` cases 9–11 pin the divergent
  `derelict_pirate` kinds, the authored count range, dual-roll determinism,
  the uncovered-role constants fallback, and the missing-table warn-once
  fallback.
