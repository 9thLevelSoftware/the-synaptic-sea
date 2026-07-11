# Feature: As-Built Architecture Visualizations

## Status

In implementation under `REQ-DOC-009` and ADR-0048.

## Design pillar alignment

- Source-backed structure: every major node and relationship cites current source.
- Runtime systems over proof artifacts: diagrams describe actual runtime behavior and do not substitute for gameplay.
- Stage-Gate discipline: the feature has requirements, an ADR, scoped Kanban cards, and fresh validation.

## Player fantasy

This is a developer-facing documentation feature. It protects the player experience indirectly by helping maintainers understand and change the runtime without breaking closed gameplay loops.

## Gameplay problem

The code-verified inventory is exhaustive but too dense for onboarding, while older architecture prose predates the current title bootstrap and later system integrations.

## Core behavior

Five individual Mermaid documents explain system context, runtime containers/data stores, the core gameplay-interaction sequence, implemented threat-AI states, and curated runtime component dependencies. Each document includes a text equivalent, current evidence, inference labels, omissions, and current gaps. A locked renderer produces five SVG exports; a host-side validator blocks schema, evidence, render, and freshness drift.

## Inputs

- Current `project.godot`, scene, GDScript, resource, and JSON sources.
- `docs/game/inventory/system_inventory.json` and its generated views.
- Accepted feature specs, requirements, and ADRs.
- Approved design `docs/superpowers/specs/2026-07-10-as-built-architecture-visualizations-design.md`.

## Outputs

- `docs/game/architecture/README.md`.
- Five individually rendered Markdown/Mermaid documents.
- Five SVG exports with source SHA-256 and renderer version metadata.
- `ARCHITECTURE DIAGRAMS PASS diagrams=5 exports=5 references=N`.

## Rules

- Current implementation only; planned behavior is never drawn as current.
- One primary question and abstraction level per diagram.
- No game autoload, network service, cloud backend, or deployable source module is invented.
- Relationship meaning uses labels and line/arrow conventions, never color alone.
- A failed render cannot partially replace committed exports.
- Every evidence-table path is repository-relative and exists.

## Non-goals

- No runtime, gameplay, scene, input, save, or data changes.
- No exhaustive 191-system/327-edge node-link graph.
- No interactive architecture explorer, XMI, UMLDI, PDF, or PNG deliverable.
- No repair of current threat-AI behavior gaps.

## Technical design

Mermaid source lives inside the five Markdown documents. `tools/validate_architecture_diagrams.py` parses and renders with the exact local `@mermaid-js/mermaid-cli` version locked under `tools/architecture/`. Update mode renders all five before atomically replacing any SVG. Check mode re-renders for syntax and validates committed export metadata rather than byte-comparing cross-platform SVG geometry.

## Allowed files

- `docs/game/architecture/**`
- `docs/game/features/architecture_visualizations.md`
- `docs/game/05_requirements.md`
- `docs/game/06_validation_plan.md`
- `docs/game/adr/0048-mermaid-architecture-diagram-source-and-svg-exports.md`
- `docs/game/adr/README.md`
- `docs/SYNAPTIC_SEA_COMPLETE_SYSTEMS_MAP.md`
- `scripts/validation/doc_currency_validators.py`
- `tools/architecture/**`
- `tools/validate_architecture_diagrams.py`
- `tools/test_validate_architecture_diagrams.py`
- `.gitignore`

## Acceptance criteria

- Given the architecture index, a developer can follow the approved reading order and reach the exhaustive inventory/matrix.
- Given each diagram document, the exact metadata, heading, Mermaid, legend, text-equivalent, evidence, inference/omission, gap, and export schema is present.
- Given current source, every diagram node and relationship is explicit or labeled inferred.
- Given the five Mermaid sources, update mode renders five SVGs atomically and embeds current source hash and renderer version.
- Given unchanged sources/exports, check mode prints the anchored ARCHITECTURE DIAGRAMS PASS marker.
- Given the full validation bundle, it finishes with `SYNAPTIC_SEA REGRESSION PASS commands=208 clean_output=true` and no unclassified diagnostics.

## Validation

```bash
npm --prefix tools/architecture ci
python3 tools/test_validate_architecture_diagrams.py
python3 tools/validate_architecture_diagrams.py --update
python3 tools/validate_architecture_diagrams.py --check
python3 tools/build_system_inventory.py --check
python3 scripts/validation/doc_currency_validators.py requirement-trace
```

## Risks

- Coordinator line drift is mitigated by path-plus-symbol evidence.
- Dense graphs are mitigated by stable clusters and the exhaustive-matrix link.
- Renderer drift is mitigated by exact package/lock metadata and fresh render checks.
- Visual-only information loss is mitigated by text equivalents and labeled relationships.

## ADRs

- `docs/game/adr/0048-mermaid-architecture-diagram-source-and-svg-exports.md`
