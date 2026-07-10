# As-Built Architecture Visualizations — Design Specification

**Date:** 2026-07-10  
**Status:** Approved design; awaiting written-spec review  
**Audience:** Developers onboarding to and maintaining The Synaptic Sea  
**Evidence baseline:** `main` at `ae28d95` before this specification commit

## Context

The repository has a canonical, code-verified system inventory with 191 systems and
327 directed integration relationships. It also has an older 959-line architectural
reference, an interactive status map, and several feature-specific ADRs. Those sources
do not currently provide a small, current, developer-onboarding diagram set:

- `docs/game/inventory/system_map.html` and `SYSTEM_INVENTORY.md` are exhaustive status
  views, not curated architecture explanations.
- `docs/superpowers/specs/architecture-map.md` predates the title-screen bootstrap and
  later runtime integrations.
- `docs/SYNAPTIC_SEA_COMPLETE_SYSTEMS_MAP.md` is a package/status ledger rather than a
  runtime component model.
- Several older GDD/TDD statements and environment paths have drifted from current code.

The requested deliverable is a set of individual, source-backed architecture diagrams
covering C4 context/container structure, a gameplay sequence, a state machine, and a
component/dependency map. The diagrams describe the current implementation only.

## Goals

1. Give a new developer a trustworthy reading path from system boundary to runtime detail.
2. Keep each diagram focused on one modeling question and one abstraction level.
3. Preserve current class, script, scene, resource, event, and persistence names.
4. Distinguish direct ownership/calls, signals, data reads, and inferred engine lifecycle.
5. Make every diagram maintainable as reviewable text and verifiable as rendered output.
6. Supply text equivalents and evidence anchors so the diagrams remain useful without a
   visual renderer.

## Non-goals

- Diagramming planned, deferred, or aspirational architecture as though it exists.
- Rendering all 191 systems or all 327 integration edges in one node-link view.
- Replacing the generated inventory, integration matrix, feature specs, requirements,
  ADRs, or validation plan.
- Refactoring runtime code, introducing autoloads, or changing game behavior.
- Creating a general-purpose interactive architecture explorer.
- Formal UML interchange through XMI or UMLDI.

## Chosen approach

Use Mermaid-first Markdown under `docs/game/architecture/`.

This is UML-like, documentation-as-code rather than formal UML. GitHub and Codex are the
primary reading surfaces. A repository-local Mermaid CLI dependency validates syntax and
produces SVG exports without relying on a globally installed renderer. The installed CLI
version is locked by `tools/architecture/package-lock.json`; validation never uses a
floating package version.

Alternatives considered and rejected:

1. **PlantUML suite:** stronger formal UML semantics, but adds a less familiar rendering
   dependency and weaker native repository rendering.
2. **Hybrid Structurizr + PlantUML + Graphviz:** best notation-specific fidelity, but three
   formats and toolchains impose unnecessary onboarding and maintenance cost for five
   curated diagrams.

## Source authority and evidence rules

Diagram claims use this authority order:

1. Current `project.godot`, `.tscn`, `.gd`, `.tres`, and JSON sources.
2. `docs/game/inventory/system_inventory.json`, the canonical runtime-status source.
3. Accepted feature specs, requirements, and ADRs.
4. Older architecture prose only after reconfirmation against current source.

Each diagram document must contain:

- a purpose statement and one-sentence conclusion;
- one canonical Mermaid source fence;
- a relationship legend;
- a structured text outline or relationship table;
- an evidence table citing stable repository paths and symbols;
- an explicit-versus-inferred note;
- known omissions and current implementation gaps;
- a freshness date and evidence baseline commit.

Stable class, scene, script, model, event, and data names are the diagram source IDs. Line
numbers may supplement a citation, but the durable anchor is `path + symbol` because the
coordinator file changes frequently.

## Artifact set and reading order

### `docs/game/architecture/README.md`

An onboarding index, not a sixth diagram. It explains the reading order, notation,
freshness contract, evidence hierarchy, regeneration commands, and the boundary between
the curated diagrams and the exhaustive inventory/matrix.

### `01-c4-system-context.md`

**Primary question:** Who uses The Synaptic Sea, and what is the runtime system boundary?

**Diagram type:** C4 system-context view expressed as a Mermaid flowchart.  
**Fallback:** concise actor/system table.

Scope:

- Player as the primary person.
- The Synaptic Sea as one software system.
- Local platform/runtime as the provider of execution, input, rendering, audio, and local
  filesystem facilities.
- No network service, cloud backend, or game autoload is invented.

This view intentionally omits internal Godot scenes and domain modules.

### `02-c4-containers.md`

**Primary question:** How do the executable runtime, bundled read-only content, and local
mutable save data relate?

**Diagram type:** C4 container view expressed as a Mermaid flowchart.  
**Fallback:** UML component view.

Containers/data stores:

- Godot game executable and runtime scene tree.
- Bundled `res://` scenes, scripts, JSON, resources, audio, and imported assets.
- Local `user://` saves, slot index, metadata, and settings/state files.

The diagram labels bundled content reads separately from local persistence reads/writes.
It does not misuse source modules as independently deployable C4 containers.

### `03-gameplay-interaction-sequence.md`

**Primary question:** How does the core player interaction move from input to model and
scene consequences, then to run progress or checkpoint persistence?

**Diagram type:** UML sequence diagram in Mermaid.  
**Fallback:** numbered interaction flow.

Primary lifelines:

- Player
- `PlayerController`
- `PlayableGeneratedShip`
- `Interactable`
- grouped pure gameplay models
- scene/HUD/audio consequences
- `SaveLoadService`

Required flow:

1. Godot dispatches input to `PlayerController`.
2. `PlayerController` emits `interact_requested`.
3. `PlayableGeneratedShip` performs ordered interaction dispatch.
4. `Interactable.try_interact()` validates and emits `interaction_completed`.
5. The coordinator updates objective, ship-system, progression, route, and hazard models.
6. The coordinator applies scene, HUD, and audio consequences.
7. The coordinator emits the public playable interaction event.
8. A final objective completes the slice; otherwise the sequence advances and writes a
   checkpoint autosave.

Required alternate branches:

- blocked or rejected interaction;
- multi-step objective not yet complete;
- final objective and slice completion;
- next objective and checkpoint autosave.

Godot input dispatch and same-stack signal delivery are labeled as engine/lifecycle facts
or inferences where the repository does not call them directly.

### `04-threat-ai-state-machine.md`

**Primary question:** Which threat-AI states exist, and what implemented events and guards
move between them?

**Diagram type:** UML state machine in Mermaid.  
**Fallback:** state-transition table.

States:

- `IDLE`
- `INVESTIGATE`
- `HUNT`
- `ATTACK`
- `STUN`
- `FLEE`
- `DEAD`
- manager-owned removal after `DEAD`

Transition priority and guards:

1. `health <= 0` forces `DEAD`.
2. An active stun timer forces `STUN`.
3. Awareness, room equality, and decaying memory select `ATTACK`, `HUNT`,
   `INVESTIGATE`, or `IDLE`.
4. Low health applies the final living-state `FLEE` override.
5. Damage can enter `DEAD`, `STUN`, or `FLEE` directly.
6. The manager sweeps `DEAD`, emits `threat_killed`, and removes model and placeholder.

The document must state two current gaps without drawing desired transitions:

- `FLEE` is reachable but has no move-away scene behavior.
- `INVESTIGATE` has no distinct scene action, and stored `last_known_room` is not consumed
  outside the model.

### `05-runtime-component-dependencies.md`

**Primary question:** How do the stable runtime layers depend on the composition root?

**Diagram type:** UML-like component/dependency graph in Mermaid.  
**Fallback:** package diagram or the existing generated integration matrix.

Graph classification and layout:

- clustered directed graph with one dominant hub;
- left-to-right layered layout;
- boot spine first;
- `PlayableGeneratedShip` as the central high-degree composition root;
- collapsed procgen/loading, world/domain, persistence, UI, audio, resources, and
  validation clusters;
- validation shown as a separate band pointing at production targets.

The diagram must not expand the coordinator's 109 direct load edges. It links to the
generated 191-system matrix for exhaustive tracing.

Principal relationships include:

- `project.godot` -> `TitleMain` -> `Main` -> playable scene ->
  `PlayableGeneratedShip`;
- coordinator ownership of `GeneratedShipLoader`, player/camera, domain state,
  `MenuCoordinator`, `AudioManager`, `ThreatManager`, and `SaveLoadService`;
- procgen pipeline stages ending in `GeneratedShipLoader` and instantiated wrapper scenes;
- `ShipInstance` aggregation of mutable per-ship state;
- snapshot and save-service persistence boundaries;
- child-to-coordinator and playable-to-title event feedback.

## Relationship notation

Every edge carries a verb, event name, protocol, or data name.

- Solid arrow: ownership, construction, direct call, or runtime control.
- Dashed arrow: signal or event callback.
- Dotted arrow: data/resource read or persistence read/write.
- Explicit `inferred` label: engine lifecycle relationship not directly invoked by source.

Line style and labels carry meaning; color is supplementary only.

## Key as-built architecture facts

The diagrams preserve these current facts:

- `project.godot` boots `res://scenes/title_main.tscn`.
- `TitleMain` lazily instantiates `Main` for New Game or Continue.
- `Main` instantiates the configured coherent playable scene.
- `PlayableGeneratedShip` is the scene-aware runtime composition root.
- There are no configured project autoloads.
- Gameplay services are session-owned rather than global singletons.
- Pure `RefCounted`/`Resource` models own gameplay state; Nodes own scene consequences.
- Direct signals and dependency injection are preferred over a global event bus.
- Bundled content under `res://` is read-only runtime input.
- `get_summary()` / `apply_summary()` boundaries feed `RunSnapshot`, `WorldSnapshot`, and
  `SaveLoadService` persistence under `user://`.
- Mutable `ShipInstance` state persists while geometry can be regenerated from source data.

## Layout and readability

- One abstraction level and one primary question per diagram.
- Context and container views use simple left-to-right reading order.
- The sequence diagram is chronological top-to-bottom with no more than seven primary
  lifelines; related pure models are grouped.
- The state machine uses a layered directional layout and concise guard/action labels.
- The dependency diagram uses Mermaid subgraphs and collapsed clusters rather than a dense
  force-directed layout.
- Node text remains readable at normal zoom. Wide views scroll horizontally instead of
  shrinking labels.
- Exports are inspected for clipped labels, overlapping nodes, confusing crossings, and
  long unlabeled edges.

## Accessibility

- Each diagram has a plain-language summary and structured text equivalent.
- Essential labels remain visible without hover.
- Relationship meaning never relies on color alone.
- Text and edge contrast must remain legible in light and dark repository viewers.
- SVG exports preserve searchable text when the Mermaid renderer permits it.
- Static documentation has no custom pointer, keyboard, pan, or zoom behavior. Browser or
  Markdown-viewer scrolling owns navigation; the text outline provides a non-visual path.
- On narrow portrait screens, the summary and outline remain useful before horizontal
  diagram scrolling. Landscape is recommended for the sequence and dependency exports.

## Source, renderer, and export contract

- Canonical source: one Mermaid fence inside each diagram Markdown file.
- Primary renderer: native GitHub/Codex Mermaid rendering.
- Validation renderer: repository-local Mermaid CLI under `tools/architecture/`.
- Committed exports: `docs/game/architecture/rendered/*.svg`.
- Renderer dependencies: `tools/architecture/package.json` and lockfile.
- Extraction/rendering owner: `tools/validate_architecture_diagrams.py`.

The validator extracts the canonical fence to a temporary `.mmd` file, renders it with the
locked local CLI, writes a temporary SVG, and compares it with the committed export. Failed
renders never replace a committed export. A separate explicit update mode regenerates the
SVG files after successful rendering.

## Error handling and diagnostics

Validation fails with the diagram path and actionable reason when:

- an expected diagram or export is missing;
- a diagram has zero or multiple canonical Mermaid fences;
- required metadata, summary, outline, legend, evidence, or omissions are absent;
- a cited repository path does not exist;
- Mermaid parsing or rendering fails;
- a committed SVG differs from a fresh deterministic render;
- the diagram uses an unsupported relationship style without a legend;
- prohibited stale terms or retired authoritative models appear as current architecture.

Relationships without sufficient current evidence are omitted from diagram semantics and
listed as caveats. They are never silently promoted from old prose or plans.

## Governance integration

Implementation adds or updates the following source-of-truth artifacts before diagram
completion is claimed:

- `docs/game/features/architecture_visualizations.md` with acceptance criteria, allowed
  files, non-goals, and verification commands;
- `REQ-DOC-009` in `docs/game/05_requirements.md` for current, source-backed, individually
  rendered architecture views;
- ADR-0048 under `docs/game/adr/` recording Mermaid Markdown as the maintained diagram
  source, local locked rendering, and SVG export policy;
- the ADR index and relevant documentation-currency sources;
- a scoped Kanban implementation card on `synaptic-sea-stage-gate`, assigned according to
  the repository operating model;
- `docs/game/06_validation_plan.md` registration of the feature validator and PASS marker.

The ADR records a documentation/workflow decision, not a change to game runtime
architecture.

## Validation plan

### Focused feature validation

1. Install the locked renderer dependencies with `npm --prefix tools/architecture ci`.
2. Run the architecture validator in check mode.
3. Expect an exact success marker shaped as:

   `ARCHITECTURE DIAGRAMS PASS diagrams=5 exports=5 references=<count>`

4. Run the system-inventory drift check.
5. Run the requirement, ADR, and documentation-currency validators affected by the new
   feature/requirement/ADR rows.

### Visual review

Open all five fresh SVGs and verify:

- readable default scale;
- no clipped or overlapping text;
- obvious reading direction;
- traceable edges and limited crossings;
- correct arrow styles and labels;
- agreement with the text outline and evidence table;
- grayscale readability and no color-only distinctions.

### Regression

Run the repository's current Godot 4.6.2 headless regression bundle from
`docs/game/06_validation_plan.md`. Any unexpected `ERROR:` or `WARNING:` line blocks
completion unless explicitly classified and accepted by the coordinator.

## Acceptance criteria

1. The index and all five individual diagram documents exist in the approved reading order.
2. Each document contains exactly one canonical Mermaid source, summary, text equivalent,
   legend, evidence table, omissions, freshness date, and baseline commit.
3. The diagrams answer their declared modeling questions without mixing abstraction levels.
4. All nodes and relationships map to current source or are explicitly labeled inferred.
5. Planned and deferred behavior is absent from diagram semantics.
6. Current gaps in threat behavior and other included systems are disclosed outside the
   diagram rather than repaired or hidden.
7. The component view stays curated and links to the exhaustive inventory/matrix.
8. All five Mermaid sources render successfully to current committed SVG exports.
9. The validator, inventory check, documentation-currency checks, and Godot regression
   bundle pass with fresh clean output.
10. A developer can follow the index from system boundary to runtime detail and locate the
    cited source for every major node and edge.

## Risks and mitigations

- **Coordinator churn:** line numbers drift in the large composition root. Cite stable
  symbols and paths first, with line numbers only as supplemental evidence.
- **Diagram drift:** Markdown and SVG can diverge. Deterministic fresh-render comparison
  blocks stale exports.
- **Overloaded dependency view:** the runtime hub has 109 direct load edges. Collapse stable
  clusters and defer exhaustive tracing to the generated matrix.
- **False architectural certainty:** old docs contain stale claims. Apply the authority
  hierarchy and label inferred engine behavior.
- **Renderer drift:** a floating Mermaid CLI could change layout or syntax. Lock the local
  package version and validate committed exports.
- **Accessibility loss in graphics:** provide summaries, relationship outlines, visible
  labels, and line-style semantics in every file.

