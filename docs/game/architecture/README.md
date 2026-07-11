# The Synaptic Sea — As-Built Architecture

## Purpose

This directory is the developer-onboarding path for the current Godot runtime. It explains a small set of architectural questions without replacing the exhaustive system inventory, feature contracts, requirements, ADRs, or validation evidence.

## Reading order

1. [System context](01-c4-system-context.md) — runtime boundary and outside actors.
2. [Containers and data stores](02-c4-containers.md) — executable, bundled content, and local persistence.
3. [Gameplay interaction sequence](03-gameplay-interaction-sequence.md) — input through models, consequences, and checkpointing.
4. [Threat-AI state machine](04-threat-ai-state-machine.md) — implemented threat states and guards.
5. [Runtime component dependencies](05-runtime-component-dependencies.md) — boot spine, composition root, and stable clusters.

Each source document links its matching SVG under `rendered/`.

## Notation

- Flowchart solid edge: ownership, construction, direct call, or runtime control.
- Flowchart long-dash edge: signal or event callback.
- Flowchart short-dot edge: data/resource or persistence access.
- Sequence solid message: synchronous direct call.
- Sequence dashed message: emitted signal, callback, or return.
- State transition label: `event [guard] / action`.
- `inferred` means Godot lifecycle behavior supported by engine semantics but not directly called by repository source.
- Color is supplementary; labels and line/arrow conventions carry meaning.

## Evidence hierarchy

1. Current `project.godot`, scenes, scripts, resources, and JSON.
2. `docs/game/inventory/system_inventory.json`.
3. Accepted feature specs, requirements, and ADRs.
4. Older prose only after confirmation against current source.

## Freshness policy

The diagrams describe the implementation at evidence baseline `ae28d95`, reconfirmed on 2026-07-10. Update a diagram whenever a cited ownership, call, event, state transition, resource path, or persistence boundary changes. Line numbers are supplemental; path plus symbol is the durable anchor.

## Regeneration and validation

```bash
npm --prefix tools/architecture ci
python3 tools/validate_architecture_diagrams.py --update
python3 tools/validate_architecture_diagrams.py --check
```

Update mode renders all five diagrams before replacing any SVG. Check mode performs a fresh syntax render and verifies each export's source hash and exact renderer version.

## Exhaustive maps

- [Canonical system inventory](../inventory/SYSTEM_INVENTORY.md)
- [Interactive system map and integration matrix](../inventory/system_map.html)
- [Structured inventory source](../inventory/system_inventory.json)

The curated dependency view intentionally does not draw all 191 systems or 327 integration relationships.
