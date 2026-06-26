# Store / Platform Requirements Checklist

## Purpose

Define the release-readiness checklist for publishing *The Synapse Sea* v0.1.0. This document is the source of truth for store/platform requirements, owners, current status, and evidence needed before Gate 5 (release candidate) can exit.

## Scope

- **Primary target:** itch.io (Gate 5 blocker).
- **Stretch target:** Steam (documented, tracked, **not** a Gate 5 blocker).
- **Excluded:** mobile, console, and other stores for v0.1.0.

## Assumptions

- Engine: Godot 4.6.2.
- Gate 5 build targets: Windows x86_64 and macOS desktop (Linux x86_64 optional).
- The build is a single-derelict session with current-run save/load only (no persistent meta-progression).
- Store page art may use placeholders for the RC; final art is a post-RC polish task unless a later card scopes it.

---

## Primary target: itch.io

### Account and project setup

| ID | Requirement | Owner | Status | Evidence / task | Stop condition |
|---|---|---|---|---|---|
| ITCH-001 | itch.io developer account exists and is accessible to the release owner. | default | pending | Account credentials stored outside repo. | Cannot create or recover account. |
| ITCH-002 | Project page is created for *The Synapse Sea* with a unique URL slug. | synapse_sea_docs | pending | RC-005; itch.io project dashboard screenshot or URL. | Slug unavailable or requires paid tier. |
| ITCH-003 | Project kind is set to "Game" and visibility is configured (draft until RC, then public). | synapse_sea_docs | pending | Project settings page. | Platform does not support free browser + downloadable combo. |

### Store page metadata

| ID | Requirement | Owner | Status | Evidence / task | Stop condition |
|---|---|---|---|---|---|
| ITCH-004 | Title is finalized and consistent across page, builds, and release notes. | synapse_sea_docs | pending | Page draft; `docs/game/release_notes/RC_v0.1.0.md`. | Title conflicts with existing itch.io project. |
| ITCH-005 | Short summary (≤250 chars) describes the core loop. | synapse_sea_docs | pending | Page draft. | Cannot express premise within limit. |
| ITCH-006 | Full description covers premise, controls, session length, save data, and known issues. | synapse_sea_docs | pending | Page draft; links to `CHANGELOG.txt` content. | Description omits required legal/save notices. |
| ITCH-007 | Genre and tags are selected to match discoverability goals (e.g., roguelike, sci-fi, survival, exploration). | synapse_sea_docs | pending | Page draft with tag list. | Tags inconsistent with actual gameplay. |
| ITCH-008 | Release status is set accurately ("In development" or "Released") and platform compatibility is listed. | synapse_sea_docs | pending | Page settings. | Unsupported platform is accidentally advertised. |

### Media assets

| ID | Requirement | Owner | Status | Evidence / task | Stop condition |
|---|---|---|---|---|---|
| ITCH-009 | Cover image (630×500 PNG/JPEG) is uploaded and readable at thumbnail size. | synapse_sea_docs | pending | Placeholder or final cover file. | No placeholder art can be produced. |
| ITCH-010 | At least 3 screenshots are uploaded showing distinct gameplay situations (exploration, hazard, objective). | synapse_sea_docs | pending | Screenshot files or placeholders. | Cannot capture representative in-engine frames. |
| ITCH-011 | Optional trailer / GIF is uploaded (stretch; placeholder accepted for RC). | synapse_sea_docs | pending | Video or GIF file. | N/A for RC. |

### Builds and channels

| ID | Requirement | Owner | Status | Evidence / task | Stop condition |
|---|---|---|---|---|---|
| ITCH-012 | HTML5/web embed build is exported and tested in-browser (optional if downloadable builds are primary). | synapse_sea_worker | pending | Export log; browser smoke pass. | Web export fails Godot 4.6.2 templates. |
| ITCH-013 | Windows x86_64 downloadable build is exported and smoke-tested. | synapse_sea_worker | pending | RC-002, RC-004, RC-009. | Export fails or regression smoke fails. |
| ITCH-014 | macOS downloadable build is exported and smoke-tested. | synapse_sea_worker | pending | RC-002, RC-004, RC-010. | macOS export fails or regression smoke fails. |
| ITCH-015 | Linux x86_64 downloadable build is exported and smoke-tested (optional; defer if >2h). | synapse_sea_worker | pending | RC-002, RC-004. | Linux export blocks Windows/macOS release. |
| ITCH-016 | Build filenames include version/build stamp (e.g., `synapse-sea-of-stars-v0.1.0-win.zip`). | synapse_sea_worker | pending | `scripts/export/build_release.sh` output. | Build script cannot produce stamped names. |
| ITCH-017 | Each uploaded channel is labeled correctly (`win-rc`, `mac-rc`, `linux-rc`, `html5-rc` or equivalent). | synapse_sea_worker | pending | Butler channel list. | Channel names collide or confuse players. |

### Pricing and availability

| ID | Requirement | Owner | Status | Evidence / task | Stop condition |
|---|---|---|---|---|---|
| ITCH-018 | Pricing model is decided: free, paid, or donation-enabled. | default | pending | Project settings; business decision logged. | No decision by RC review. |
| ITCH-019 | If paid, payment/tax settings are configured and payout method is verified. | default | pending | itch.io payout settings. | Cannot complete verification in time. |
| ITCH-020 | Download keys or press builds are prepared if needed for reviewers. | synapse_sea_docs | pending | Key list or press build channel. | N/A if free. |

### Legal, privacy, and player notices

| ID | Requirement | Owner | Status | Evidence / task | Stop condition |
|---|---|---|---|---|---|
| ITCH-021 | EULA or terms of use are drafted and linked from the store page. | synapse_sea_docs | pending | RC-007; `docs/game/eula.md` or linked text. | Legal text cannot be sourced. |
| ITCH-022 | Privacy notice explains save-file location and confirms no third-party telemetry. | synapse_sea_docs | pending | RC-007; store page description section. | Save path or telemetry facts are unknown. |
| ITCH-023 | Content warnings are added if applicable (sci-fi peril, environmental hazard). | synapse_sea_docs | pending | Page metadata. | Platform requires ratings not supported. |

### Community and devlog

| ID | Requirement | Owner | Status | Evidence / task | Stop condition |
|---|---|---|---|---|---|
| ITCH-024 | Devlog post 0 is drafted announcing the RC release (optional but recommended). | synapse_sea_docs | pending | Draft post. | N/A for RC gate. |
| ITCH-025 | Comment/moderation settings are configured. | synapse_sea_docs | pending | Project settings. | Cannot disable spam-prone defaults. |

### Upload workflow

| ID | Requirement | Owner | Status | Evidence / task | Stop condition |
|---|---|---|---|---|---|
| ITCH-026 | Butler CLI is installed and authenticated with an API key stored outside the repo. | synapse_sea_worker | pending | RC-006; `butler --version` output. | Butler unavailable or key cannot be secured. |
| ITCH-027 | Butler push command and channel naming convention are documented in `docs/game/release_notes/RC_v0.1.0.md` or runbook. | synapse_sea_worker | pending | Documented command snippet. | Command cannot be reproduced from docs. |
| ITCH-028 | Rollback plan exists: previous build is retained or channel can be reverted quickly. | synapse_sea_worker | pending | Runbook note. | No recovery path from a bad upload. |

---

## Stretch target: Steam

Steam is a documented stretch target. The following items are tracked but **do not block Gate 5**.

| ID | Requirement | Owner | Status | Evidence / task | Stop condition |
|---|---|---|---|---|---|
| STEAM-001 | Steamworks partner account and App ID path are documented (no App ID required for RC). | default | pending | Steamworks checklist note. | N/A for RC. |
| STEAM-002 | Steam depot configuration for Windows and macOS is drafted. | synapse_sea_worker | pending | Depot config sketch. | N/A for RC. |
| STEAM-003 | Steam Input defaults are documented if gamepad support is added later. | synapse_sea_worker | pending | Input mapping note. | N/A for RC. |
| STEAM-004 | Achievement list is drafted as a future feature. | synapse_sea_docs | pending | Feature backlog note. | N/A for RC. |
| STEAM-005 | Steam build upload workflow is sketched (SteamCMD or partner upload). | synapse_sea_worker | pending | Runbook note. | N/A for RC. |

---

## Cross-platform release notes

Release notes must be prepared before Gate 5 exit:

- Internal: `docs/game/release_notes/RC_v0.1.0.md` (see `docs/game/rc_task_list.md` § release notes format).
- Packaged: `CHANGELOG.txt` next to the executable.

The release notes must mention:

- Supported platforms and build channels.
- Save-file location per platform.
- Known issues and classified warnings.
- Credits and third-party license notices.

---

## Acceptance criteria

- [ ] Itch.io checklist exists with all requirements above.
- [ ] Every requirement has an owner and a status.
- [ ] Pricing, EULA/privacy, and save-data notices are covered.
- [ ] Butler upload workflow is documented.
- [ ] Steam stretch target is documented but explicitly excluded from Gate 5 blockers.
- [ ] This document is cited in `docs/game/08_milestone_gates.md` Gate 5 section.

## Non-goals

- Final marketing art, trailer production, or store-page A/B testing.
- Console or mobile certification.
- Multiplayer backend, cloud saves, or achievements for v0.1.0.
- Persistent meta-progression or DLC.

## Verification

1. Open `docs/game/store_requirements.md` and confirm the itch.io checklist is complete.
2. Confirm every row has an owner and a status column.
3. Confirm `docs/game/08_milestone_gates.md` Gate 5 section cites this document.
4. Confirm the Steam section is marked as a stretch target and does not block Gate 5.
