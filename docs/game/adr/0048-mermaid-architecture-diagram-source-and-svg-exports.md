# ADR-0048: Mermaid architecture source and validated SVG exports

- **Status:** Accepted
- **Date:** 2026-07-10
- **Supersedes / amends:** extends ADR-0040 documentation-currency policy

## Context

The canonical inventory contains 191 systems and 324 relationships, while the older architecture reference predates the current title bootstrap and later integration work. Developer onboarding needs a small set of current views that can be diffed, rendered, exported, and validated without a visual-editor binary format.

## Decision

Maintain five curated architecture views as one Mermaid fence per Markdown document. Use native GitHub/Codex rendering for normal reading and a repository-local exact-version Mermaid CLI for validation and SVG export. Commit SVG exports beside the sources. Each SVG carries the normalized Mermaid source SHA-256 and renderer version. Check mode performs a fresh syntax render and verifies metadata; it does not compare cross-platform SVG geometry bytes. Update mode renders every diagram successfully before replacing any export.

Flowchart views use stable edge IDs plus solid ownership/call edges, long-dash signal edges, and short-dot data/persistence edges. Sequence and state views use their native message/transition semantics. Every view has a text equivalent and source evidence.

## Alternatives considered

- PlantUML was rejected because it adds a less repository-native renderer for this documentation audience.
- Structurizr + PlantUML + Graphviz was rejected because three source formats and toolchains outweigh the layout benefit for five curated views.
- SVG-only or visual-editor files were rejected because they obscure semantic review and drift from source.

## Consequences

- Mermaid CLI and its browser dependency are development-only, locked under `tools/architecture/`.
- Generated SVG geometry may differ across platforms; freshness is based on source/renderer metadata plus successful current rendering and visual review.
- Exhaustive dependencies remain in the generated inventory/matrix instead of one unreadable node-link diagram.
- Diagram claims must be updated with source changes or validation fails.

## Validation

- `python3 tools/test_validate_architecture_diagrams.py`
- `python3 tools/validate_architecture_diagrams.py --update`
- `python3 tools/validate_architecture_diagrams.py --check`
- Full Godot 4.6.2 regression bundle with clean diagnostic output.
