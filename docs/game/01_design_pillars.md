# 01 Design Pillars

These pillars are decision filters. If a proposed feature does not support at least one pillar, it should be cut, deferred, or rewritten.

## Pillar 1: Spatial coherence first

The player must be able to read the ship layout, traversal routes, obstacles, and destination affordances from the locked-isometric view.

In scope:
- Corridor-mediated room topology.
- Clear route gates, ramps, entrances, objectives, and exits.
- Validation that catches jumbled/overlapping placement.

Out of scope:
- Pretty scenes that are not navigable.
- Random prop scatter that harms route legibility.

## Pillar 2: Runtime systems over proof artifacts

Gameplay progress must change live game state: collision, passability, objective state, system state, HUD state, hazards, inventory, or save data.

In scope:
- Route-control gates that open by disabling collision.
- Ship systems that unlock capabilities.
- Hazards that affect traversal or resources.

Out of scope:
- Proof-only screenshots.
- HTML concept mocks as replacements for in-engine behavior.
- Contact sheets as milestone deliverables.

## Pillar 3: Every action has visible consequence

The player should understand what changed after an interaction.

In scope:
- HUD lines sourced from real state.
- Gates visibly/collisively opening.
- Objective state updates and clear progression.

Out of scope:
- Hidden counters with no scene effect.
- Ambiguous state changes that require reading logs.

## Pillar 4: Small vertical slices before broad systems

Build one representative, end-to-end piece before scaling content.

In scope:
- One coherent generated ship slice.
- One hazard loop before multiple hazard types.
- One inventory/tool loop before broad itemization.

Out of scope:
- Large content lists without validated mechanics.
- Parallel feature branches that lack validation gates.

## Pillar 5: Source-backed structure, not ad-hoc taste

Major design, process, and architecture choices should cite the framework docs, feature specs, requirements, or ADRs.

In scope:
- ADRs for architecture choices.
- Requirements with acceptance criteria.
- Gate reviews before milestone advancement.

Out of scope:
- “Because the agent decided so.”
- Untracked changes to core premise or architecture.
