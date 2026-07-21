# ADR-0049: Threat Pathfinding via Pure Layout Nav-Graph

## Status

Accepted

## Context

Threat combat (ADR-0037) is pure-model: `ThreatAIState` + `ThreatManager` with scene placeholders. Live motion was a straight-line **lerp** toward the player in HUNT/ATTACK (`ThreatManager._update_placeholder`), so threats phase through walls, ignore sealed hatches/fire/route gates, and give INVESTIGATE/FLEE no distinct motion.

`GeneratedShipLoader` already bakes a `NavigationRegion3D` for walkability smokes and the debug runner uses `NavigationAgent3D`. Putting production threat authority on `NavigationAgent3D` would:

1. Couple combat to scene-tree / NavigationServer map-sync timing (weak headless determinism).
2. Make save/load repath brittle.
3. Force expensive navmesh rebakes for dynamic blockers (hatches, fire, gates).

## Decision

1. **Primary pathfinding for threats is pure `RefCounted`:**
   - `ShipNavGraph` — walkable cell graph from ship layout floor placements (4-connected, optional vertical edges).
   - `ThreatPathfinder` — A* over the graph → ordered waypoint list.
2. **`ThreatManager` owns path advance** each `tick_threats` (already both `_process` branches): step with `move_toward` along waypoints; sync `world_position` + placeholder node.
3. **Dynamic costs** (not mesh rebake): sealed-hatch bulkhead pairs, active fire intensity, closed route gates mark edges blocked or expensive.
4. **State targets:** HUNT/ATTACK → player (stop at attack range); INVESTIGATE → last known position/room; FLEE → farthest reachable node; IDLE/STUN/DEAD → no motion.
5. **Baked NavigationRegion remains** for walkability tooling and debug agents only — not production threat authority.
6. **Do not persist waypoints** in save summaries; repath after restore from position + graph.

## Consequences

- Headless unit smokes prove walls, detours, and blockers without NavigationServer bake frames.
- Threats stop tunneling through geometry when the graph matches layout floors.
- INVESTIGATE/FLEE become visually distinct.
- Graph quality depends on floor placement completeness in layouts (same source as navmesh bake).
- Optional future: debug overlay comparing graph path vs NavigationAgent.

## Rejected alternatives

- **NavigationAgent3D-first for threats** — scene-bound, map-sync lag, weak dynamic blockers.
- **Keep lerp** — fails wall/door/fire semantics.
- **Full RVO crowd avoidance** — polish later; out of v1.
- **Player auto-path** — separate feature.

## Verification

- `ship_nav_graph_smoke.gd`
- `threat_pathfinder_smoke.gd`
- `threat_path_follow_smoke.gd`
- `main_playable_threat_pathfinding_smoke.gd`
- Existing combat smokes remain green
