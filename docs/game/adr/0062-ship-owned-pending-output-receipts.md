# ADR-0062: Ship-owned pending-output receipt records

- Status: **Accepted for P08 implementation; focused validation pending.**
- Date: 2026-09-05
- Related: [ADR-0059](0059-crafting-and-derelict-restoration-transactions.md),
  FC-08, FC-09, and the P08 implementation brief.
- Supersedes: only the `pending_outputs_v1` identity row in ADR-0059. All
  other ADR-0059 payload names, owners, and transaction decisions remain locked.

## Context

ADR-0059 reserved `pending_outputs_v1` as a station or destroyed-station holder
with the placeholder fields `owner_id`, `receipt_id`, `lots`, and
`collected_quantities`. P08 must also preserve immutable publication data across
partial collection, distinguish station location from ship ownership, and keep
an empty tombstone after collection or orphan conversion. A single mutable
`lots` field cannot prove that a restored remainder came from the originally
published receipt.

The placeholder was never a shipped save contract. A 2026-09-05 search of the
repository at the P08 base revision found `pending_outputs_v1` only in the
ADR-0059 placeholder and the feature-acceptance manifest reservation. There was
no runtime serializer, deserializer, migration fixture, or released save payload
for the key. This permits a reviewed contract correction without a migration
from an implemented earlier pending-output schema.

## Decision

`ShipInstance` owns exactly one `PendingOutputStore`. Physical stations are
record-level locations within that ship-owned store; neither a station node nor
the coordinator serializes another copy.

The additive `pending_outputs_v1` value has this exact top-level shape:

- `schema`: `pending-outputs-1`
- `ship_id`: stable owning ship ID
- `records`: array of receipt records

Each receipt record contains:

- `receipt_id`, `ship_id`, and `station_instance_id`
- `producer_kind` and `producer_id`
- `purpose`, restricted to `output` or `refund`
- `source_holder_id`, empty only when no source holder applies
- `state`, restricted to `pending`, `collected`, or `orphaned`
- `original_lots`, the immutable exact `item_lots_v1` publication
- `remaining_lots`, an exact metadata-preserving subset of `original_lots`
- `collected_quantities`, keyed by original lot ID and equal to the exact
  difference between original and remaining quantities

`receipt_id` is the idempotency key. An existing receipt can match only the same
ship, station, producer, purpose, source holder, and immutable original lots.
Collected and orphaned records remain as zero-remainder tombstones. Lot IDs may
not overlap between receipts in the same store.

Missing `pending_outputs_v1` data is the legacy empty state. A present malformed
payload is rejected atomically before any live holder is changed. This additive
current-format field does not advance the outer `world-4` schema. P10 still owns
the reserved ordered `world-5` migration, historical save fixtures, and any
future change to the outer save version.

JSON serializes integer quantities and receipt sequences as numbers that parse
back as floating-point values in Godot. Current readers therefore accept only
finite, exactly integral numeric values within the IEEE-754 safe integer range,
then canonicalize them to integers. Strings, fractions, infinities, NaN, and
values above `2^53 - 1` are malformed. Identifier fields remain actual strings;
readers do not coerce numbers into IDs.

Portable field work has no station owner while it follows the attended player.
Its additive `field_pending_v1` summary retains the player-run-stable
`active_receipt_id` and `receipt_sequence`, plus
`pinned_destination_ship_id` and `pinned_local_position`. The pinned fields are
empty until first publication. At that boundary the coordinator requires the
player's current physical occupancy to be an attached `ShipInstance`, transforms
the player position into that ship's local coordinates, and pins that ship and
position before depositing. Once pinned, every retry, reload, orphan projection,
and collection uses that same ship. Movement to another ship cannot rebind or
teleport an existing receipt. If no attached occupied ship exists, the completed
producer remains intact and retries after a valid occupancy appears.

## Consequences

- Partial collection can prove exact conservation against immutable originals.
- Station destruction can move remaining lots to a ship-owned floor descriptor
  and retain the receipt tombstone without creating a second authority.
- Persisted data is larger because original lots and tombstones are retained.
- A paid portable job may cross ships before publication; after publication its
  physical receipt remains with the ship where completion was first published.
- Any later rename or reinterpretation of these keys requires another
  superseding ADR and explicit migration evidence.
