# Feature: Governed Asset-Metadata and Visual Binding Pipeline

## Status

Approved for Task 1 contract; implementation begins in Task 2.

## Design pillar alignment

- Pillar: Salvage / Craft / Repair and source-backed in-engine production.
- Why this feature supports it: portable visual records let authored GLBs participate in
  component and objective runtime systems without moving gameplay ownership into asset
  files or relying on an unrelated visual substitute.

## Scope

This feature governs the visual metadata and binding contract for the 26 imported prop
GLBs currently grouped as components, dressing props, and supplied objective props. Each
prop is a portable record made from a same-basename GLB and adjacent
`.sidecar.json` file. The sidecar is hand-authored for gameplay-facing bindings and
provenance, while GLB-derived fields are refreshed explicitly and reproducibly.

The scope also covers the boundary between prop visuals and the existing structural kit:
structural wrappers remain authoritative for connectors, collision, and integrity state;
prop records do not replace structural wrapper contracts. The runtime may consume a
validator-produced derived index, but that index is not a second authored source of truth.

The contract is deliberately additive. Task 1 defines documentation, ownership, and
validation gates only; no GLB, sidecar, wrapper scene, gameplay script, or generated index
is changed by this task.

## Ownership

| Surface | Authoritative owner | Asset-metadata responsibility |
|---|---|---|
| Same-basename GLB + adjacent `.sidecar.json` | Asset/content pipeline | Keep the portable record adjacent, schema-valid, path-addressable, and provenance-preserving. |
| GLB-derived fields | Explicit refresh/generator | Derive source hash and visual bounds from the named GLB; do not overwrite hand-authored extensions, bindings, placement, or provenance. |
| Runtime prop index | Generator and validator | Produce a deterministic derived view from valid sidecars; never hand-edit or treat it as gameplay authority. |
| Component IDs and lifecycle | Component placement/catalog/runtime owners | Resolve authored component IDs and retain component lifecycle ownership and ship-system linkage. |
| Objective placement IDs | Gameplay objective data/controller owners | Resolve supplied `placement_id` values from gameplay data; never infer identity from objective type. |
| Fallback visual | Binding resolver/runtime owner | Make a missing or invalid binding explicit with `visual_source="fallback"`; never silently select an unrelated asset. |
| Structural wrappers | Structural placement and integrity owners | Own connector sockets, collision proxies, and intact/damaged/breached integrity variants. Prop metadata may not weaken or duplicate these contracts. |
| Sidecar extensions | Sidecar author/content owner | Preserve unknown or hand-authored extension data across an explicit GLB-derived refresh. |

## Portable asset record

A prop record has this canonical relationship:

- `assets/imported/props/<group>/<name>.glb` is the visual source.
- `assets/imported/props/<group>/<name>.sidecar.json` is the adjacent sidecar and is the
  authoritative authored record for that visual source.
- `asset_id` is stable and unique within the governed prop set.
- The sidecar records its schema version, source GLB path, source hash, visual bounds,
  category, collision policy, bindings, placement information, provenance, and optional
  extensions.

Direct prop GLBs are visual-only. Their sidecars use
`collision_policy="none_visual_only"`; gameplay collision, connector geometry, nav, and
integrity consequences remain in the owning runtime or structural wrapper. The source
hash and bounds are derived evidence, not permission to fabricate gameplay state.

### Canonical sidecar and index document contract

The canonical derived index is `data/props/visual_bindings.generated.json`. Every sidecar
is a same-basename `.sidecar.json` adjacent to its source GLB and is a document with
`schema_version: "1.0.0"` and `document_kind: "prop_visual_binding"`. The index document
at the canonical path has `schema_version: "1.0.0"` and
`document_kind: "prop_visual_binding_index"`.

Each source hash is SHA-256 encoded as exactly 64 lowercase hexadecimal characters.
Bounds are meter-space `[x, y, z]` local min/max arrays rounded to six decimal places.
Canonical JSON is lexicographically key-sorted, compact, newline-terminated, and
timestamp-free. The index is generated only from valid sidecars and their GLBs and is
never a hand-authored source of truth.

## Binding rules

1. Component bindings resolve by the authored component ID. The resolver must preserve the
   component's lifecycle owner and its linkage to the owning ship-system subcomponent.
2. Objective bindings resolve by the gameplay-authored `placement_id`. Objective type is
   not an identity key and must not be used to choose a visual.
3. A missing, malformed, stale, or otherwise invalid component binding retains the existing
   primitive fallback; the same failure in an objective binding retains the existing
   readability fallback. Both report `visual_source="fallback"`; neither silently chooses a
   different component, objective, or prop visual.
4. Bindings are visual concerns only. Sidecars and the derived index may contain visual/content
   metadata—source hash, bounds, category, visual policy, provenance, bindings, placement,
   and extensions—but gameplay state is forbidden. They must not duplicate objective
   progression, component state, collision, navigation, or structural integrity state.
5. A structural wrapper owns its connector and collision contract even when its visual
   child is replaced by intact, damaged, or breached art.

## Core behavior

The pipeline validates adjacent sidecars, checks the referenced GLB and derived metadata,
then generates a deterministic runtime index. Runtime consumers use the index to resolve
visual bindings while their existing gameplay owners continue to own state transitions.
An explicit GLB-derived refresh updates only derived fields and preserves extensions plus
hand-authored binding, placement, and provenance data.

## Acceptance criteria

- All 26 governed props have one adjacent, valid same-basename `.sidecar.json` file each.
- Every sidecar resolves its source path, schema, source hash, and visual bounds; direct
  prop records declare `collision_policy="none_visual_only"`.
- Component bindings resolve all supplied component IDs, and component lifecycle owners
  and ship-system linkage remain intact.
- Objective bindings resolve all supported supplied gameplay `placement_id` values;
  objective ownership and progression remain in the gameplay systems.
- Missing or invalid component binding retains the existing primitive fallback, and missing
  or invalid objective binding retains the existing readability fallback. Both emit
  `visual_source="fallback"`; neither substitutes an unrelated visual.
- Component-marker placement, mount, dismount, rebuild, save/load, and system linkage
  retain their current gameplay/runtime owners and behavior; visual metadata and binding
  changes must not alter those existing runtime flows.
- Structural wrappers validate and switch intact, damaged, and breached variants without
  connector/socket or collision drift.
- The runtime index is deterministic, derived-only, and fresh with respect to valid
  sidecars and their GLBs; a stale or hand-edited index fails the gate.
- The index is exactly `data/props/visual_bindings.generated.json` with
  `schema_version: "1.0.0"` and `document_kind: "prop_visual_binding_index"`; each
  sidecar has `schema_version: "1.0.0"` and `document_kind: "prop_visual_binding"`.
- Source hashes are exactly 64 lowercase SHA-256 hex characters, bounds are six-decimal
  meter-space `[x, y, z]` local min/max arrays, and canonical JSON is lexicographically
  key-sorted, compact, newline-terminated, and timestamp-free.
- An explicit GLB-derived refresh updates hashes/bounds while preserving extensions and
  hand-authored binding, placement, and provenance fields.
- The exact baseline ``WARNING: 2 ObjectDB instances were leaked at exit (run with `--verbose` for details).`` is classified as pre-existing external baseline noise owned by
  `ship-core` only for the component-marker smoke. Exactly two instances are permitted
  only while blocked Kanban card `t_b9b4e4f9` (title: Investigate ObjectDB leak in component marker smoke)
  remains unresolved. Any other warning, or any count other than two, fails this feature
  gate.

## Non-goals

- GLB re-export.
- Procedural structural assembly.
- Prop collision generation.
- New objective gameplay.
- Runtime dressing placement.
- Moving gameplay ownership into sidecars or the derived runtime index.
- Replacing structural wrapper connector, collision, or integrity contracts with prop
  metadata.

## Technical design

- Feature contract: this document.
- Architecture decision: `docs/game/adr/0052-asset-metadata-and-visual-binding-architecture.md`.
- Requirements: `REQ-AVB-001` through `REQ-AVB-009` in `docs/game/05_requirements.md`.
- Existing placement resource seam: `scripts/placement/modular_asset_spec.gd`.
- Existing structural wrapper validator:
  `scripts/placement/validate_wrapper_scenes.gd`.
- Future prop metadata validator, structural audit, and visual-binding smokes are named
  in `docs/game/06_validation_plan.md` and remain explicitly future until their scripts
  exist.

## Validation

Task 1 records the reproducible Godot 4.7.1 baseline from the repository root:

```bash
GODOT_BIN=/opt/homebrew/bin/godot
"$GODOT_BIN" --headless --editor --path . --quit
"$GODOT_BIN" --headless --path . --script res://scripts/placement/validate_wrapper_scenes.gd -- scenes/wrappers/structural/ship_structural_v0
"$GODOT_BIN" --headless --path . --script res://scripts/validation/component_markers_smoke.gd
```

The import preflight exits 0. The wrapper validator is intentionally a current baseline
failure with eight missing `VisualInstance` errors and remains pending Task 2. The
component marker smoke exits 0 and prints its marker plus exactly the classified two
ObjectDB-instance warning. Godot-generated `.godot` changes and untracked `.import`
files are restored or removed before committing documentation.

## Risks

- A stale sidecar can look valid while pointing at a changed GLB; source hashes and an
  explicit freshness check mitigate this.
- A resolver that keys objectives by type can bind two distinct placements to one visual;
  placement-ID validation and the objective smoke prevent this regression.
- Refresh tooling can erase designer intent; extension, binding, placement, and provenance
  preservation is a required acceptance criterion.
- Structural visual variants can accidentally alter gameplay geometry; wrapper validation
  and state-switch checks keep sockets and collision under structural ownership.

## ADRs

- `ADR-0052` governs portable records, derived index ownership, visual-only prop collision,
  structural wrapper authority, placement-ID resolution, fallback behavior, and refresh
  preservation.
