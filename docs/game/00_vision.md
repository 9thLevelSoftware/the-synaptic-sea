# 00 Vision Brief

## Working title

The Sargasso of Stars

## Current locked premise

A locked-isometric 3D Godot game about a player hub ship trapped in a biomatter web / cosmic Sargasso, exploring procedurally generated derelict spacecraft interiors to survive, repair, and escape.

## One-sentence pitch

Explore trapped derelict ships from a readable locked-isometric view, restore ship systems through real runtime interactions, and carve routes through the Sargasso toward extraction.

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

- ~~What is the final player meta-loop: repair hub ship, chart escape routes, rescue/salvage, or faction/narrative progression?~~ **Resolved through Gate 2: deferred past Gate 2 per ADR-0002 and ADR-0003.** Full meta-loop design is anchored to Gate 3 entry planning.
- ~~What hazards/survival pressures define risk during exploration?~~ **Resolved for Gate 1: one oxygen breach pressure loop per `features/hazards.md`.** Broader hazard variety remains future scope.
- What is the minimum vertical slice target for Gate 1 exit?
- What content scope is acceptable before Alpha?
