# 00 Vision Brief

## Working title

The Sargasso of Stars

## Current locked premise

A locked-isometric 3D Godot game about a player hub ship trapped in a biomatter web / cosmic Sargasso, exploring procedurally generated derelict spacecraft interiors to survive, repair, and escape.

## One-sentence pitch

Explore trapped derelict ships from a readable locked-isometric view, restore ship systems through real runtime interactions, and carve routes through the Sargasso toward extraction.

## North Star: open-world ship survival (directional vision)

The long-term game is an open-world survival sim in the Project Zomboid mold, where
**derelict ships are buildings**. A derelict is not a level to "complete" — it is a
persistent place you:

1. **Loot** — scavenge parts, tools, and supplies into your inventory. (realized for derelicts in sub-project #3 — see ADR-0014).
2. **Repair** — fix systems over multiple visits, gated by parts looted from other ships.
3. **Occupy & fortify** — make it a base; reinforce doors and chokepoints.
4. **Defend** — hold it against monsters (a later pillar).
5. **Fly** — a sufficiently repaired ship becomes a mobile base you pilot through the Sargasso.

**Architectural consequence — the home/derelict distinction is transitional.** Today the
starting ship is special-cased (always-functional, rich persistent sim) versus lighter
derelicts. In the North Star, *any* repaired ship can become a home / mobile base, so the
architecture converges toward **every ship being a uniform `ShipInstance`** (the deferred
"Approach B" of ADR-0011). Loot and repair must therefore be built as *any-ship* systems,
not "derelict features," to avoid entrenching that asymmetry. Repair restoring propulsion /
navigation is exactly what turns a derelict travel-capable — replacing the placeholder
"derelicts are always travel-capable" short-circuit (ADR-0011) with real condition-gating, so
the "fly around" payoff falls out of repair plus the existing travel system.

**New pillar beyond the original 8-system core spec:** monsters, fortification, and base
defense (the original spec listed *Combat* as out of scope). This reframes derelicts from
loot-containers into defensible positions and reuses the existing route-control / door /
breach systems as the seed of "reinforce." It is decomposed *after* the loot → repair →
occupy base is solid.

The "objectives / `reach_goal` / `cleared`" framing in the current derelict loop (ADR-0013)
is **transitional scaffolding** built on the generated objective specs — it gives boarding
immediate purpose, but the real "why board a derelict" is loot + repair, not
level-completion. Expect it to be reframed or retired as the loot/repair sub-projects land.

The build still proceeds incrementally via the sub-project decomposition (persistence →
derelict activity → loot → repair → fortify/defend); this section is the destination those
steps aim at, not current-gate scope.

## Target player fantasy

The player should feel like a stranded spacer/ship operator making practical, high-stakes progress through dangerous derelict interiors: restoring power, opening routes, reading spatial layouts, and turning a dead ship back into a traversable system.

## Target experience

- Spatially coherent exploration.
- Systems that visibly change the ship state.
- Readable locked-isometric navigation.
- Procedural interiors that feel assembled, traversable, and purposeful.
- Tense but understandable survival/progression pressure.

## Explicit non-goals for the current gate

- No proof-only scenes as milestone substitutes.
- No HTML mockups or PNG/contact-sheet churn as gameplay deliverables.
- No full content production before the core playable systems slice is stable.
- No multiplayer/live-service assumptions.
- No broad art-polish pass before runtime systems are validated.

## Current project state summary

The current playable slice includes a main scene, generated ship loader, objective tracker, player controller, interactables, ship-system state, and route-control state. Route gates now have real runtime state and collision/passability consequences.

## Open questions

- ~~What is the final player meta-loop: repair hub ship, chart escape routes, rescue/salvage, or faction/narrative progression?~~ **Direction now defined: open-world ship survival (loot → repair → occupy/fortify → defend → fly) — see "North Star" above.** The Gate-1/2 *single-ship slice* deferral (ADR-0002/0003) still holds for that gate's content, but the meta-loop is now being built incrementally via the sub-project decomposition (persistence and derelict activity already merged).
- ~~What hazards/survival pressures define risk during exploration?~~ **Resolved for Gate 1: one oxygen breach pressure loop per `features/hazards.md`.** Broader hazard variety remains future scope.
- What is the minimum vertical slice target for Gate 1 exit?
- What content scope is acceptable before Alpha?
