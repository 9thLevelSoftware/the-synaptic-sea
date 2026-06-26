# Release Candidate Task List

## Purpose

Define the concrete work required to move the Synapse Sea build from Beta exit to Gate 5 (release candidate) entry. This document is the source of truth for RC tasks, owners, effort estimates, and stop conditions.

## Scope boundary

Release-candidate work begins after Beta is accepted (Gate 4 exit). It covers build/export verification, platform compliance, final regression, release notes, and postmortem preparation. It does **not** include new gameplay content, feature work, or scope changes; those belong in Gate 3/4.

## Assumptions

- Primary engine: Godot 4.6.2.
- Current target platform for Alpha/Beta: Windows and macOS desktop (PC).
- Distribution target for first public build: itch.io.
- Steam is a tracked stretch target but not a Gate 5 blocker unless a later ADR changes the target.
- Hub/meta progression remains deferred past Alpha per ADR-0003; the RC build is a single-derelict session.

## Questions answered

### 1. What export/build pipeline is needed?

A headless, reproducible Godot export pipeline that produces signed/stamped builds for each supported platform from a clean checkout.

| ID | Task | Owner | Effort | Stop condition |
|---|---|---|---|---|
| RC-001 | Install/configure Windows and macOS export templates for Godot 4.6.2. Verify offline export from CLI. | synapse_seaworker | 2h | Export fails with official templates on a clean machine. |
| RC-002 | Create `scripts/export/build_release.sh` (or `.ps1`/`.bat` pair) that exports Windows and macOS executables, names artifacts with version + git-less build stamp, and exits non-zero on Godot export errors. | synapse_seaworker | 4h | Cannot produce deterministic artifact names without manual rename. |
| RC-003 | Add export presets (`export_presets.cfg`) checked into the project with classified baseline warnings accepted. | synapse_seaworker | 1h | Preset file cannot be versioned without leaking local paths. |
| RC-004 | Smoke-test the export by running the headless regression bundle against the exported executable (not just the editor). | synapse_seareview | 2h | Exported build fails a smoke that passes in editor. |

Platform targets for Gate 5:

- Windows x86_64 (primary).
- macOS Apple Silicon + Intel universal or separate builds (secondary).
- Linux x86_64 (optional; defer if it adds >2h).

### 2. What store/platform requirements apply?

| ID | Task | Owner | Effort | Stop condition |
|---|---|---|---|---|
| RC-005 | Create itch.io project page structure (draft title, summary, genre, tags, cover image placeholder, build channels). | synapse_seadocs | 2h | itch.io project cannot be created or requires paid tier. |
| RC-006 | Define butler upload workflow: command, API key handling, channel naming (`win-rc`, `mac-rc`), and rollback plan. | synapse_seaworker | 2h | Butler unavailable or key cannot be stored outside repo. |
| RC-007 | Verify EULA/privacy notice draft covers save-file location and no third-party telemetry. | synapse_seadocs | 1h | Legal text cannot be sourced. |
| RC-008 | Create Steamworks stretch checklist (app ID, depot config, Steam Input, achievements, build upload) but do **not** block Gate 5 on it. | synapse_seadocs | 2h | Steamworks checklist would require implementation beyond documentation. |

Gate 5 hard requirement: itch.io RC channel is uploadable. Steam is a post-Gate-5 follow-up tracked separately.

### 3. What final regression pass is needed?

A full validation sweep run against the release-exported build, not the editor, with all known warnings classified.

| ID | Task | Owner | Effort | Stop condition |
|---|---|---|---|---|
| RC-009 | Run `docs/game/06_validation_plan.md` regression bundle on the exported Windows build and record results. | synapse_seareview | 2h | Exported build fails regression bundle smoke that passes in editor. |
| RC-010 | Run the same regression bundle on the exported macOS build and record results. | synapse_seareview | 2h | macOS export cannot run headless smokes. |
| RC-011 | Perform a manual fresh-player sanity pass on each platform: start new run, complete one objective, save/load, reach extraction or abort. | synapse_seareview | 3h | Manual pass reveals a crash or soft-lock not caught by smokes. |
| RC-012 | Classify and accept any remaining Godot `ERROR:`/`WARNING:` lines in the RC regression report. | synapse_seareview | 1h | New unclassified error or warning appears in RC build. |
| RC-013 | Verify save-file path (`user://saves/current_run.json`) is created/cleared correctly in installed builds on both platforms. | synapse_seaworker | 1h | Save path is wrong or permissions fail on installed build. |

### 4. What release notes format?

| ID | Task | Owner | Effort | Stop condition |
|---|---|---|---|---|
| RC-014 | Create `docs/game/release_notes/RC_v0.1.0.md` using the release-notes template (see below). | synapse_seadocs | 1h | Cannot identify which Alpha/Beta changes belong in v0.1.0. |
| RC-015 | Add a player-facing `CHANGELOG.txt` packaged next to the executable with the same content trimmed to player-relevant items. | synapse_seadocs | 1h | Build script cannot copy the file into the export. |

Release-notes template:

```markdown
# Synapse Sea v0.1.0 — Release Candidate

## Build info
- Version: v0.1.0
- Date: YYYY-MM-DD
- Engine: Godot 4.6.2
- Platforms: Windows x86_64, macOS

## What's in this build
- Up to 3 ship layout templates.
- 5 objective types.
- 3 hazard types.
- 2 tools / inventory items.
- Single derelict run per session (4–6 minute target).

## Known issues
- List classified warnings and accepted limitations.

## Controls
- Keyboard/mouse defaults.

## Save data
- Location per platform.
- Current-run save only; no persistent meta-progression.

## Credits / attribution
- Third-party assets/tools and license notices.
```

### 5. What postmortem template?

| ID | Task | Owner | Effort | Stop condition |
|---|---|---|---|---|
| RC-016 | Create `docs/game/postmortem/postmortem_template.md` covering scope, schedule, quality, process, and actionable improvements. | synapse_seadocs | 1h | Template is rejected by coordinator. |
| RC-017 | Schedule the Gate 5 exit review meeting and assign note-taker. | default | 0.5h | Cannot schedule within one week of RC build. |
| RC-018 | Populate the postmortem with preliminary notes during Beta exit so it is not written from memory after release. | synapse_seadocs | 1h | No Beta exit data available. |

Postmortem template sections:

1. Summary (one-paragraph project status at RC).
2. What went well (evidence-backed).
3. What went wrong (bugs, delays, process friction).
4. Scope decisions that held up or that should change.
5. Metrics (smoke pass count, regression runtime, bug counts by severity).
6. Actionable improvements for next milestone.
7. Decisions pending for post-RC (e.g., hub/meta, Steam, additional platforms).

## Dependency graph

```
RC-001 export templates
  -> RC-002 build script
    -> RC-003 export presets
      -> RC-004 export smoke test
        -> RC-009 Windows regression
        -> RC-010 macOS regression
          -> RC-011 manual fresh-player pass
            -> RC-012 classify RC warnings
              -> RC-013 save-path verification
RC-005 itch.io project draft
  -> RC-006 butler workflow
RC-007 EULA/privacy notice
RC-008 Steamworks stretch checklist
RC-014 release notes (internal)
  -> RC-015 CHANGELOG.txt packaging
RC-016 postmortem template
  -> RC-018 preliminary notes
RC-017 schedule review meeting
```

## Acceptance criteria

- [ ] RC task list exists with concrete items (this document).
- [ ] Every task has an owner and estimated effort.
- [ ] Export pipeline tasks cover Windows and macOS with a headless build script.
- [ ] Store/platform tasks cover itch.io as Gate 5 target and Steam as documented stretch.
- [ ] Final regression tasks run against exported builds, not only the editor.
- [ ] Release notes format and postmortem template are defined.
- [ ] This document is cited in `docs/game/08_milestone_gates.md` Gate 4 exit criteria.

## Non-goals

- No mobile or console ports in Gate 5.
- No new gameplay content, hazards, tools, or objectives.
- No persistent hub/meta progression.
- No marketing campaign or trailer production.
- No store page art finalization (placeholders accepted for RC).

## Verification

1. Read `docs/game/rc_task_list.md` and confirm the five RC questions are answered.
2. Confirm every task row has owner, effort, and stop condition.
3. Confirm `docs/game/08_milestone_gates.md` Gate 4 section cites this document.
