# As-Built Architecture Visualizations — Design Specification

**Date:** 2026-07-10

**Status:** Approved; ADR-0048 is the first implementation gate

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
produces SVG exports without relying on a globally installed renderer. `package.json`
declares an exact CLI version, `package-lock.json` locks its transitive dependencies, and
validation never uses a floating package version.

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
**Fallback:** container relationship table.

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
**Fallback:** component relationship table, with the generated matrix linked for exhaustive
tracing.

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

Every edge carries a verb, event name, protocol, or data name. Mermaid diagram families do
not expose identical line-style semantics, so each family has an explicit notation contract:

- **Flowchart-based C4 and dependency views:** solid arrow for ownership, construction,
  direct call, or runtime control; dashed arrow for signal/event callback; dotted arrow for
  data/resource or persistence access.
- **Sequence view:** solid message for direct synchronous call; dashed message for emitted
  signal, callback, or return; data/persistence operations use explicit message labels and
  notes rather than a third line style.
- **State view:** standard state-transition arrows only. Labels use
  `event [guard] / action`; priority and global overrides are expressed through choice
  nodes and notes rather than line style.
- **All views:** an explicit `inferred` label marks engine lifecycle behavior not directly
  invoked by repository source.

Labels and diagram-specific line conventions carry meaning; color is supplementary only.

## Document schema and validator rules

Each of the five diagram documents uses these exact second-level headings, in order:

1. `## Purpose and conclusion`
2. `## Diagram`
3. `## Relationship legend`
4. `## Text equivalent`
5. `## Evidence`
6. `## Explicit, inferred, and omitted`
7. `## Known current gaps`
8. `## Export and regeneration`

The title is a single level-one heading. Directly below it, a metadata block contains
`Diagram ID`, `Audience`, `Scope`, `Evidence baseline`, and `Freshness date`. `## Diagram`
contains exactly one canonical `mermaid` fence. `## Evidence` contains a Markdown table
with these columns: `Element or relationship`, `Source path`, `Symbol`, and `Basis`. `Basis`
is one of `explicit`, `engine lifecycle`, `inventory`, `feature spec`, `ADR`, or
`requirement`.

`README.md` has no Mermaid fence. It uses the exact second-level headings `Purpose`,
`Reading order`, `Notation`, `Evidence hierarchy`, `Freshness policy`, `Regeneration and
validation`, and `Exhaustive maps`.

Automated semantic guardrails apply only to Mermaid source, where they are unambiguous.
Current-architecture Mermaid fences may not contain the retired/currently false source IDs
`ShipSystemState`, `FireState`, `MinimapPanel`, `MapFogState`, or `GDAIMCPRuntime`.
Historical prose may name them only under `Known current gaps` or the index's freshness
guidance. Manual review remains responsible for higher-order architectural correctness.

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
- Runtime compatibility: `package.json` pins the CLI exactly and constrains Node to one
  supported major; the lockfile pins the renderer's browser dependency.
- Reproducible render configuration: `tools/architecture/mermaid.config.json` owns the
  deterministic ID seed and repository-safe font/theme policy; validator-owned CLI flags
  fix export width, height, background, and SVG ID.
- Extraction/rendering owner: `tools/validate_architecture_diagrams.py`.

The validator extracts the canonical fence to a temporary `.mmd` file, renders it with the
locked local CLI and configuration, and verifies that a temporary SVG is produced. Update
mode injects the Mermaid-source SHA-256 and locked renderer version into each committed SVG.
Check mode verifies those freshness fields against current source and package metadata; it
does not byte-compare browser-generated SVG geometry across operating systems. Failed
renders never replace a committed export. Update mode replaces the SVG set only after all
five temporary renders succeed, preventing a partially refreshed export set.

## Error handling and diagnostics

Validation fails with the diagram path and actionable reason when:

- an expected diagram or export is missing;
- a diagram has zero or multiple canonical Mermaid fences;
- the exact document schema, heading order, metadata keys, evidence columns, or `Basis`
  vocabulary is violated;
- a repository path in an evidence-table path cell does not exist (runtime identifiers such
  as `res://` and `user://` elsewhere in prose are not treated as local evidence paths);
- Mermaid parsing or rendering fails;
- an SVG's embedded source hash or renderer version differs from current source/tooling;
- a diagram violates its family-specific relationship notation or lacks its legend;
- a prohibited retired source ID appears in a current-architecture Mermaid fence.

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
- a scoped Kanban card set on `synaptic-sea-stage-gate`, assigned according to the
  repository operating model;
- `docs/game/06_validation_plan.md` registration of the feature validator and PASS marker.

The ADR records a documentation/workflow decision, not a change to game runtime
architecture. ADR-0048 must be accepted before renderer or diagram implementation begins.

The implementation is decomposed into six Kanban cards:

1. governance contract: feature spec, `REQ-DOC-009`, ADR-0048, ADR index, and validation-plan
   registration;
2. renderer and validator: locked tooling, configuration, validator, and validator tests;
3. overview content: index plus the system-context and container diagrams;
4. behavior content: gameplay sequence and threat-AI state-machine diagrams;
5. runtime structure content: component/dependency diagram and exhaustive-map linkage;
6. exports and verification: SVG refresh, visual QA, documentation checks, inventory check,
   and Godot regression evidence.

Every card must cite this design and `REQ-DOC-009`, enumerate allowed files, state non-goals,
and list exact verification commands. Content cards keep disjoint allowed files and their
own focused render/evidence checks.

## Validation plan

### Focused feature validation

1. Install the locked renderer dependencies with `npm --prefix tools/architecture ci`.
2. Run the architecture validator in check mode.
3. Expect a success marker matching the exact regular expression below. The validator also
   asserts that the reference count equals the number of non-empty evidence-table path
   cells across the five diagram documents.

   `^ARCHITECTURE DIAGRAMS PASS diagrams=5 exports=5 references=[1-9][0-9]*$`

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
2. Each of the five diagram documents contains exactly one canonical Mermaid source and
   follows the exact metadata, heading, evidence-table, and vocabulary schema.
3. The index contains no Mermaid fence and follows its separate required-heading schema.
4. The diagrams answer their declared modeling questions without mixing abstraction levels.
5. All nodes and relationships map to current source or are explicitly labeled inferred.
6. Planned and deferred behavior is absent from diagram semantics.
7. Current gaps in threat behavior and other included systems are disclosed outside the
   diagram rather than repaired or hidden.
8. The component view stays curated and links to the exhaustive inventory/matrix.
9. All five Mermaid sources render successfully; each committed SVG carries the matching
   source hash and locked renderer version.
10. The validator, inventory check, documentation-currency checks, and Godot regression
   bundle pass with fresh clean output.
11. A developer can follow the index from system boundary to runtime detail and locate the
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
