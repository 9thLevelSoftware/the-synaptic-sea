# ADR-0061: Procgen-safe Blender room kit v2

Status: Accepted for implementation; assets remain staged until reviewed.

## Context
The four recent dressing GLBs need identity-normalized assembled geometry; additional room-role props must remain static, subordinate to essentials and the existing placement owners. Structural wrappers and contracts, not Blender art, own navigation/collision/topology. The approved plan defines twelve genuinely new IDs plus four prop improvements and fifteen structural improvements.

## Decision
Retain the existing source -> staged GLB -> sidecar -> derived index -> factory/binder -> generated-ship pipeline. Introduce one authored content roster (`data/procgen/dressing/room_kit_v2.json`) and one selector (`scripts/procgen/room_dressing_rules.gd`). Normalize only this deliberately static prop subset by exporting evaluated clones with identity node transforms, Y-up meters, floor-centered origin and +Z front. Reject animation, rigs, morphs, helpers and invalid output; do not reinterpret arbitrary historical GLBs.

Objectives and loot allocate first; optional dressing uses actual leftover interior slots with safe inward facing, at most one per eligible room. Both ambient dressing and component population consume the real authored occupancy. Preserve component RNG/order. Missing safe slots cause omission, never arbitrary floor fallback. Visual-only sidecars add no gameplay interactions, collision, sockets, navigation or system health.

Use immutable original external masters and copied candidate sources; preserve helper inventories. Require independently imported geometry, real factory/binder/boarded consumers, scored pilot artwork, exact provenance/backups, per-state structural proof and full diagnostic-aware gates before promotion. No automatic main-checkout integration. Frozen art rows and budgets live in the feature spec; schemas/roles are not worker choices.

## Consequences
Accessor-based bounds are valid only after static normalization is proven. Numeric tests do not approve artwork. Pre-existing structural faults hold structural delivery while independent prop work proceeds. Fine-grained reviewed promotion and source backups permit rollback without resetting dirty checkouts.
