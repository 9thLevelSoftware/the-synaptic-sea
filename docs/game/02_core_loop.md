# 02 Core Loop

## Moment-to-moment loop

1. Read the locked-isometric ship space.
2. Move through coherent rooms/corridors.
3. Identify an affordance, obstacle, hazard, or objective.
4. Interact or choose a route.
5. Game state changes visibly: system state, route state, HUD state, collision/passability, resource/hazard state.
6. Reassess the ship layout with new options unlocked.

## 5-minute loop

1. Enter or load a derelict ship interior.
2. Navigate from entry toward system objectives.
3. Restore or exploit ship systems.
4. Unlock previously blocked routes.
5. Stabilize extraction or secure a reward.
6. Return progress to the hub/meta state.

## Session loop

1. Choose a target derelict or route through the Sargasso.
2. Prepare based on known risks/resources.
3. Explore a generated ship slice.
4. Complete core objectives or abort.
5. Apply gains/losses to the hub ship.
6. Unlock next decisions.

### Gate 1 hub/meta stance: DEFERRED (with cut line)

The Gate 1 playable slice is a single-ship loop. The full session loop above is the **target loop** for later milestone work, not the Gate 1 or Gate 2 deliverable. Hub/meta progression is explicitly **deferred through Gate 2** with the following cut line:

- **Cut line (in scope for Gate 1):** One generated derelict ship slice, four objective sequence, system/route state, extraction as a completion signal. The "return progress to the hub" step is satisfied by the reactor-stabilization completion state; no hub scene, hub ship, or persistent meta-currency exists.
- **Cut line (out of scope for Gate 1):** Hub ship scene/UI, derelict selection/queueing, persistent unlocks across runs, meta-currency/economy, faction/narrative progression, save/load of hub state.
- **Trigger to revisit:** ADR-0003 resolved the Gate 2 entry review as Option A: re-affirm deferral through Gate 2. The next hub/meta decision anchor is Gate 3 entry planning, before Alpha scope is accepted.
- **Source:** ADR-0002 and ADR-0003.

## Current implemented loop evidence

- Main playable slice loads generated ship data.
- Player and camera spawn.
- Four objectives can be completed in sequence.
- Ship systems update during objectives.
- Route-control gates open after systems restoration.
- Extraction unlocks after reactor stabilization.
- Hazard pressure loop drains oxygen while the player is inside the unsealed breach zone on the objective 3 → objective 4 corridor, and seals on objective 2 completion.

## Loop gaps to resolve before Gate 1 exit

- ~~Inventory/tools are not yet a real runtime loop.~~ Addressed in Gate 2 by `features/inventory_tools.md` / REQ-007.
- ~~Hub/meta progression is not yet specified.~~ Resolved by deferral (see ADR-0002). Not a Gate 1 exit blocker.
- Fresh-player playtest evidence has not yet been collected using `docs/game/playtests/gate-1-playtest-protocol.md`.

## Gate 2 scope additions

- Inventory/tool loop (`features/inventory_tools.md`, REQ-007).
- Second hazard variety (`features/hazard_variety.md`, REQ-010).
- Multi-step objective variation (`features/objective_variation.md`, REQ-011).
- Current-run save/load persistence (`features/save_load.md`, REQ-012).
