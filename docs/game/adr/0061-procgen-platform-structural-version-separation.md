# ADR-0061: Separate platform and structural procgen versions

- **Status:** Accepted
- **Date:** 2026-08-26
- **Related:** ADR-0057, ADR-0058, ADR-0060;
  `docs/game/features/unified_procgen_platform.md`; REQ-PG-002, REQ-PG-004,
  REQ-PG-005, REQ-PG-012; Gate 2 card `t_0901bbf`

## Context

Gate 1 deliberately wrapped the proven worldgen v2 ship pipeline without
changing its topology, damage, structural-plan, or gameplay-export goldens.
Gate 2 now adds coordinate-addressed world generation whose stable keys include
the platform generator version, content-manifest hash, site identity,
coordinate, domain, and named channel. Those semantics are incompatible with
the identity-only `WorldIR` shipped during Gate 1.

Using one integer for both layers creates two bad choices: silently change
WorldIR under generator version 2, or relabel every unchanged v2 ship and
regenerate its goldens. Public JSON also crosses Godot and JavaScript, so an
unrestricted Rust `u64` site seed can lose precision before a consumer verifies
the semantic hash.

## Decision

1. Platform generation and structural ship generation are separate version
   axes. Gate 2 introduces platform generator version 3. The existing ship
   topology/compiler remains structural generator version 2.
2. `ProcgenRequest`, the bundle version envelope, runtime generator manifest,
   and checked build manifest report platform version 3. The nested
   `SiteIR.ship.generator_version` continues to report structural version 2.
   Bundle validation checks both constants explicitly; it never equates them.
3. Platform v3 derives the structural ship seed from the full stable site key.
   `SiteIR.ship.seed` equals that derived site seed, while
   `WorldIR.world_seed` retains the requested world seed. `WorldIR` exports the
   derived site seed so consumers and saves do not infer it.
4. The public JSON seed range is `0..=9_007_199_254_740_991` (the exact integer
   range shared by Rust, Godot, and JavaScript). Stable-key derivation masks its
   digest to 53 bits. Inputs outside that range fail before generation; they are
   not rounded, wrapped, or serialized as strings.
5. Stable keys use an unambiguous length-delimited encoding of world seed,
   platform version, lowercase content hash, site identity, signed coordinates,
   domain, named channel, and sub-index. Each domain/channel derives directly
   from that immutable key; no discovery loop or adapter consumes a shared RNG
   stream.
6. `WorldIR` advances to `world-ir-2`. Because its expanded definition is
   embedded in the complete bundle and lifecycle schemas, the complete bundle
   advances to `procgen-bundle-2` and the lifecycle result advances to
   `procgen-lifecycle-result-2`. Version-1 schema files remain immutable as
   migration evidence; v2 schema files are added rather than overwriting them.
   Unchanged layer and adapter schemas retain their existing identifiers.
7. Platform v3 `WorldIR` owns coordinate markers, routes, biome/hazard fields,
   site archetypes, resource pressure, landmarks, and an explicit reachable
   extraction path. It validates, performs only named bounded local repair,
   revalidates, then selects a complete manifest-bound authored fallback or
   fails closed.
8. Direct structural v2 generation and its golden corpus remain unchanged.
   Legacy migration-oracle exports may wrap a platform-v3 request, but the
   exported ship continues to identify structural v2 and is produced exactly
   once.
9. Adding world rules/fallback content changes the content-manifest hash.
   Native and Web artifacts are promoted only with matching v3 source, content,
   schemas, and build manifests. A v2 save is incompatible with v3 and follows
   ADR-0058's preserved-file/new-world flow; profile and settings remain
   portable.

## Consequences

- Coordinate-world semantics can evolve without pretending the unchanged ship
  compiler is a new algorithm.
- Consumers and persistence can identify both the world/bundle contract and
  the structural ship that mutation deltas address.
- Gate 2 is an intentional pre-release clean break and therefore requires fresh
  native/Web artifacts and parity evidence before production cutover.
- The 53-bit public seed boundary slightly reduces the available numeric seed
  space while preserving exact cross-language hashing and more than enough
  deterministic identities for the game.

## Rejected alternatives

- Change WorldIR while retaining platform version 2: silently changes an
  identical request/version/content identity.
- Bump the structural `Ship` constant and regenerate unchanged v2 goldens:
  conflates bundle evolution with a structural algorithm change.
- Mutate `world-ir-1`, `procgen-bundle-1`, or lifecycle-result v1 schemas in
  place: makes checked schema identifiers non-immutable.
- Export full-width unsigned seeds and trust Godot/JavaScript parsing: permits
  precision loss before semantic-hash verification.
- Derive neighbor sites by consuming one mutable RNG stream: makes discovery
  order, optional domains, and parallel scheduling observable.

## Verification

- Structural v2 golden, determinism, invariant, mutation, and 1,800-ship stress
  suites remain byte-for-byte green.
- Platform v3 schema round trips reject v1/v2 substitution and unknown majors.
- Full-key tests vary version, content hash, coordinate, site, domain, channel,
  and sub-index and prove exact 53-bit output.
- Coordinate golden, order/concurrency, optional-domain, locale, and
  presentation-seed metamorphic tests pass.
- Route/extraction validation plus bounded repair/authored-fallback tests pass.
- Native and Web manifests/artifacts report platform v3 while bundles retain
  structural ship v2 and produce identical semantic hashes.
