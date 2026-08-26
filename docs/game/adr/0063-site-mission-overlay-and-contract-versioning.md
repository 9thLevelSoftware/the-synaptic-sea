# ADR-0063: Version the validated site mission overlay independently

- **Status:** Accepted
- **Date:** 2026-08-26
- **Related:** ADR-0057, ADR-0058, ADR-0061;
  `docs/game/features/unified_procgen_platform.md`; REQ-PG-002, REQ-PG-005,
  REQ-PG-006; Gate 2 card `t_0901bbf`

## Context

Task 6 introduces platform-v3 coordinate-world semantics while deliberately
leaving `SiteIR` as the Gate 1 wrapper around the proven structural-v2 `Ship`.
Task 7 must add mission ordering, locks and keys, repair gates, functional prop
sockets, navigation clearance, visibility/cover annotations, and objective
reachability. Those fields are authoritative mechanics and cannot be added to
`site-ir-1` or an already checked complete-bundle schema in place.

The structural ship is still valid evidence and must not be regenerated or
relabelled merely because a mission overlay now consumes its rooms, portals,
cells, and entities. Godot also cannot infer the missing mission mechanics after
the bundle returns without violating Rust authority.

## Decision

1. Task 7 advances the site layer to `site-ir-2`. `site-ir-1` remains immutable
   migration evidence. `SiteIR` v2 contains the unchanged structural-v2 `Ship`
   plus closed typed mission, functional-prop, navigation, clearance,
   line-of-sight/cover, and objective-reachability records.
2. Because the site definition and its four named channels/stage-qualified
   fallback identity are embedded in the complete contract, Task 7 advances
   the site to `site-ir-2`, trace to `generation-trace-2`, complete bundle to
   `procgen-bundle-3`, and lifecycle result to
   `procgen-lifecycle-result-3`. Because capability, runtime-manifest, and
   build-manifest envelopes constrain those nested schema maps, they advance to
   `procgen-capabilities-2`, `procgen-generator-manifest-2`, and
   `procgen-build-manifest-2` rather than rewriting their v1 definitions. The
   Task 6 `world-ir-2` definition and all other unchanged schema IDs remain
   stable. Every earlier schema file remains checked and unmodified.
3. The platform generator remains version 3 and the nested structural ship
   remains version 2. The bundle envelope's export-schema map and changed
   content-manifest hash distinguish the Task 7 contract/content. Validation
   checks all three identities explicitly: request/envelope/runtime/build
   manifests equal platform 3, only `SiteIR.ship.generator_version` equals
   structural 2, and the ship seed separately equals the full-key-derived
   `WorldIR.site_seed`. It never equates schema version with either algorithm
   version or equates the ship version with the request version.
4. The site compiler consumes exactly one already validated structural ship and
   the selected `WorldIR` marker. It annotates stable room/cell/entity IDs; it
   does not mutate or rerun topology, damage, structural compilation, or loot.
5. Mission graphs use closed node, edge, gate, objective, and prerequisite
   families. A lock names its earlier key source; a repair gate names its
   reachable repair socket; objectives and extraction are ordered. Acquire-key
   nodes and key-lock gates carry the same unique nonempty `key_id`; repair
   nodes, props, and gates similarly share a unique nonempty `repair_id`.
   Stable IDs derive from the full Task 6 site key plus named site channels,
   never array discovery order or a shared mutable RNG stream.
6. Each functional prop socket records an anchor cell and a distinct cardinally
   adjacent approach cell. Both cells belong to the same `RoomSpec`, and the
   structural plan's occupancy maps both cells to that named room. The approach
   cell must be reachable in the progression state where the prop is required;
   required props cannot share anchor or approach cells. Every required prop
   carries its nonempty `mission_node_id`; key and repair props also carry their
   matching `key_id` or `repair_id`. The one required extraction-console prop
   additionally carries `extraction_portal_ref`, which equals the canonical
   `edge_key` of the unique exterior `Door` portal from `Ship.entry_room`.
   Validation rejects zero or multiple matching entry portals and any other use
   of `extraction_portal_ref`; other exterior damage/breach portals are not
   extraction points. Navigation edges bind existing portals/verticals and
   carry integer traversal cost, clearance, gate, and passability annotations.
   LOS and cover are bounded integer/cell annotations; filenames and
   presentation paths never control mechanics.
   Every non-exterior portal and every vertical emits two directed navigation
   edges. All exterior portals are excluded from internal navigation; the
   designated entry `Door` is represented only by the extraction prop's binding.
   Ungated `Door`, `Hatch`, and `Breach` portals are passable. A `Locked` portal
   remains present but is initially blocked and must bind its key-lock gate; any
   other mission-gated edge is initially blocked until its prerequisite is
   complete. `Solid` and `Open` portal intents are invalid. Portal navigation
   references use the structural plan's canonical `edge_key`. A vertical
   reference is `vertical:<a>:<b>`, where each endpoint is the
   `(deck,x,y,room_id)` integer tuple and `a/b` are lexicographically ordered;
   direction remains a separate edge field.
7. Validation uses an automated progression agent that proves start,
   prerequisites, every required objective, and extraction are reachable in
   order. It also proves every referenced structural identity exists, every
   socket is traversable and nonconflicting, locks/keys and repairs are acyclic,
   and clearance/visibility/cover values stay inside authored envelopes.
   Traversable portal edges cost 1,000 basis units and vertical edges 1,500;
   both have one-cell clearance. Cover cells are room cells adjacent to a
   canonical `Solid` structural edge, sorted by `(deck,x,y)`, capped at 64 per
   room. LOS pairs are distinct same-deck/same-room cells sharing x or y with
   every intermediate cell in the room, Manhattan distance 1..8,
   lexicographically ordered by endpoint tuple, capped at 128 per room. These
   constants live in authored rules and schema validation rejects deviations.
8. Failure follows `validate -> named bounded local repair -> full revalidate ->
   complete manifest-bound authored mission fallback -> full revalidate/fail
   closed`. Repairs and fallback are trace-visible. No partial overlay enters a
   bundle, and Godot cannot supply a missing mission record. The fallback return
   path is exactly the reverse of the structural ship's validated
   `critical_path`; no return path is read from or written into `Ship`.

## Consequences

- Site mechanics can evolve without invalidating structural-v2 goldens or
  rewriting prior public schema files.
- Task 7 requires refreshed native/Web source parity, schemas, manifests, and
  checked artifacts before its runtime contract can be promoted.
- A platform-v3 save still distinguishes Task 6 from Task 7 through its export
  schema map, content hash, site semantic hash, and bundle identity.
- Complete authored mission fallback content becomes source-controlled gameplay
  data rather than a best-effort runtime repair.

## Rejected alternatives

- Add fields to `site-ir-1` or `procgen-bundle-2`: breaks immutable checked
  schema identifiers and makes identical envelopes mean different documents.
- Bump structural ship generation to version 3: relabels an unchanged compiler
  and invalidates useful goldens without changing structural bytes.
- Persist or mutate a second Godot mission graph: creates another authority and
  breaks native/Web/save replay parity.
- Treat every invalid mission as repairable: hides authored/content failures and
  makes repair bounds meaningless.

## Verification

- Schema round trips accept SiteIR v2/bundle v3/lifecycle v3 and reject every
  prior/future substitution while preserving earlier schema bytes.
- Mission progression, lock/key, repair, socket, clearance, navigation,
  LOS/cover, and extraction agents cover valid, malformed, cyclic, unreachable,
  and adversarial cases.
- Repair-count and complete authored-fallback tests prove full revalidation and
  no partial export.
- Existing structural-v2 goldens, invariants, mutation tests, and 1,800-ship
  stress sweep remain unchanged and green.
- Native and Web adapters return the same semantic hashes and schema identities.
