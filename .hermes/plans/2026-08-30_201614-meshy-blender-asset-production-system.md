# Meshy-to-Blender Asset Production System Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Build a repeatable, fail-closed skill and repository workflow that turns rights-cleared reference images into reviewable Meshy candidates, canonical Blender masters, validated staged GLBs, and locked-isometric runtime evidence without allowing AI output to bypass the Synaptic Sea asset contracts.

**Architecture:** The repository owns machine-enforceable contracts, generation packets, Blender/runtime validators, and promotion evidence; the existing `synaptic-sea-asset-pipeline` Hermes skill becomes the operator-facing umbrella that routes agents through those project tools. Meshy is candidate generation only, Blender is the editable source and geometry authority, Godot wrappers/runtime data retain collision and gameplay ownership, and promotion remains an explicit human-reviewed follow-up rather than a generator side effect.

**Tech Stack:** Python 3.11+, pytest/unittest, Meshy REST API (`image-to-3d`, `multi-image-to-3d`, optional `retexture`/`rigging`), Blender 5.x Python (`bpy`, `bmesh`), Godot 4.7.1, GLB/glTF 2.0, JSON/JSON Schema, Hermes Agent skills.

---

## 1. Current context and evidence

### Existing project seams to preserve

- Project root: `/Users/christopherwilloughby/Code/the-synaptic-sea`.
- The current working tree is already heavily dirty with generated `.import` files and unrelated changes. Implementation must use a clean worktree or a carefully scoped branch; do not clean or overwrite the existing user changes.
- `tools/focused_nine_batch.py` already establishes the correct pattern: isolated staging, temp-dir-then-swap publication, protected runtime surfaces, deterministic reports, Blender/Godot timeouts, and no implicit promotion.
- `tools/focused_nine_staged_props.py` already proves staged-only GLB metadata and sidecars can remain outside the live runtime index.
- `tools/generate_prop_sidecars.py` preserves authored `binding`, `placement`, `provenance`, and `extensions` during explicit refresh, but its new-record default is `self-authored`. Meshy-derived assets must never inherit that default accidentally.
- `data/placement/schemas/prop_visual_binding_v1.schema.json` already permits detailed AI provenance under `extensions`, while keeping the top-level provenance pair simple.
- `scripts/tools/threat_placeholder_renderer.gd` already accepts a GLB/PackedScene beside the primitive fallback. The three priority threat catalog entries in `data/combat/threat_visual_catalog.json` still have empty `mesh_path` values.
- `scripts/validation/structural_live_loader_smoke.gd` already uses seeds `42` and `777` in `breach_field`; the new review harness should reuse that production environment instead of inventing a model viewer.
- The project grid is 4.0 m. The existing user-local asset skill incorrectly says `1.0 = one tile` and tells Blender to create collision for generated props. Both conflict with current repository architecture and must be corrected.

### Live provider facts checked on 2026-08-30

- Meshy Image-to-3D Smart Topology accepts `model_type: "smart-topology"`, recommends `ai_model: "meshy-t2"`, and supports a target face count of 100–15,000.
- Meshy Multi-Image accepts 1–4 separate views; with Meshy 7/`latest`, the first image is the primary/front view.
- `should_texture: false` skips texturing so geometry can be judged first.
- Meshy 7/`latest` does not produce an emission map; emission masks remain a Blender/Godot responsibility.
- Meshy rigging is intended for textured conventional humanoid bipeds, requires +Z forward for URL inputs, and rejects inputs above 300,000 faces. It is not the Hull Tendril rigging path.
- Paid/private Meshy generations remain private to the paid user when the uploaded material is rights-cleared; free-plan output is CC BY 4.0. The generation packet must record which license path applies.
- The Meshy Godot DCC bridge imports directly into the active scene. It is acceptable only for scratch preview and is not a production import route.

### Decisions locked by this plan

1. Patch the existing class-level `synaptic-sea-asset-pipeline` skill; do not create another narrow Meshy/Synaptic Sea skill.
2. Store long project-specific guidance in the skill's `references/` and `templates/`; keep `SKILL.md` concise and routing-focused.
3. Keep structural floors, walls, doors, ramps, sockets, collision, and damage topology outside Meshy generation.
4. Generate three to six untextured candidates per contract and reject by silhouette/functional form before cleanup or texturing.
5. Derive alternate states from one Blender master; never generate closed/open, intact/damaged, or living/dead states independently.
6. Preserve collision, navigation, sockets, integrity, and gameplay bindings in Godot wrappers/runtime data.
7. Never call a paid Meshy endpoint without a validated contract, an explicit maximum-credit approval, a live balance check, and an immutable request record.
8. Never write directly from the Meshy adapter into `assets/imported`, live catalogs, generated binding indexes, or wrapper scenes.
9. Promotion is a separate reviewed task. This implementation may emit a promotion packet/diff, but it must not apply it.
10. The five-asset pilot is: Stalker, Hull Tendril kit, Biomatter Swarm kit, loot container, crafting station.

---

## 2. Target system

### Operator flow

```text
contract JSON
  -> deterministic reference/prompt packet
  -> credit-bounded Meshy candidate batch
  -> immutable staged generation packets
  -> human candidate selection
  -> Blender master + normalized GLB
  -> Blender structural/quality gate
  -> optional Meshy AI texturing of approved UVs
  -> sidecar/provenance proposal
  -> temporary Godot overlay
  -> seed 42 + 777 locked-isometric captures in normal/emergency/dark lighting
  -> reviewed promotion packet
  -> separate human-approved promotion task
```

### Canonical staging layout

```text
assets/_staging/meshy/<asset_id>/<task_id>/
  contract.json
  prompt-packet.json
  source_front.png
  source_side.png
  source_back.png
  source_three_quarter.png
  raw.glb
  thumbnail.png
  generation.json
  review.json
  cleaned.glb
  blender-validation.json
  sidecar-overlay.json
```

Absent views are omitted, not represented by empty files. `generation.json` is immutable after download; later decisions live in `review.json` and validation reports.

### Editable source layout

```text
/Volumes/Untitled/SynapticSeaAssets/meshy/source/<asset_id>/
  <asset_id>_master.blend
  textures/
  exports/
```

The `.blend` master is external/heavy source. The repository retains hashes and staged normalized outputs. Before any future promotion, the external-source backup gate from `blender-structural-asset-pipeline` must pass.

### Contract minimum

```json
{
  "schema_version": "1.0.0",
  "document_kind": "ai_asset_contract",
  "asset_id": "loot_container_derelict_v1",
  "category": "gameplay_prop",
  "gameplay_role": "searchable_loot_container",
  "dimensions_m": [0.9, 0.55, 0.65],
  "dimension_tolerance_m": 0.01,
  "pivot": "bottom_center",
  "forward_axis": "+Z",
  "allowed_yaw_deg": [0, 90, 180, 270],
  "required_states": ["closed", "open", "looted"],
  "collision_owner": "godot_wrapper",
  "animation": {"kind": "hinge", "meshy_rigging_allowed": false},
  "budget": {
    "triangles": 3000,
    "material_slots": 2,
    "texture_resolution": 1024
  },
  "references": {
    "required_views": ["front", "side", "back", "three_quarter"],
    "rights_state": "project-owned"
  },
  "generation": {
    "provider": "meshy",
    "mode": "image_to_3d",
    "model_type": "smart-topology",
    "ai_model": "meshy-t2",
    "target_polycount": 3000,
    "should_texture": false,
    "candidate_count": 4,
    "target_formats": ["glb"]
  },
  "review": {
    "seeds": [42, 777],
    "lighting_modes": ["normal", "emergency", "dark"]
  }
}
```

---

## 3. Implementation tasks

### Task 1: Establish governance, requirements, and the architecture boundary

**Objective:** Make the candidate-only Meshy role and Blender/Godot ownership split an approved repository contract before code is added.

**Files:**
- Create: `docs/game/features/ai_candidate_asset_pipeline.md`
- Create: `docs/game/adr/0057-meshy-candidates-blender-authority.md`
- Modify: `docs/game/adr/README.md`
- Modify: `docs/game/05_requirements.md`
- Modify: `docs/game/06_validation_plan.md`

**Step 1: Write the feature contract**

Include scope, ownership, state transitions, five pilot assets, staging layout, non-goals, acceptance criteria, and explicit protected runtime paths. Define requirements `REQ-AIAP-001` through `REQ-AIAP-010`:

1. contract-before-generation;
2. reference consistency and rights;
3. explicit credit gate;
4. immutable staged provenance;
5. Blender master authority;
6. geometry/material/scale gate;
7. wrapper-owned gameplay concerns;
8. locked-isometric review at seeds 42/777;
9. no automatic promotion;
10. skill pressure-test compliance.

**Step 2: Write ADR-0057**

Use this decision statement verbatim:

```markdown
Meshy output is a candidate source, not a runtime source. A selected candidate becomes eligible for runtime review only after a canonical Blender master exists, the normalized GLB passes the project asset contract, provenance is complete, and a temporary Godot overlay passes locked-isometric review. Runtime collision, navigation, sockets, integrity, animation/VFX integration, and gameplay bindings remain owned by Godot wrappers and repository data. Promotion is a separate reviewed action.
```

**Step 3: Add requirements and validation commands**

Add focused host-side and Godot commands, expected markers, and the rule that unexpected `ERROR:`, `WARNING:`, or `SCRIPT ERROR:` lines block the gate.

**Step 4: Self-review docs**

Search for contradictions with ADR-0052 and remove any wording that claims Meshy or Blender-generated visual GLBs own runtime collision.

**Step 5: Commit**

```bash
git add docs/game/features/ai_candidate_asset_pipeline.md docs/game/adr/0057-meshy-candidates-blender-authority.md docs/game/adr/README.md docs/game/05_requirements.md docs/game/06_validation_plan.md
git commit -m "docs: define governed Meshy candidate pipeline"
```

---

### Task 2: Write failing contract tests

**Objective:** Define the asset contract and prompt-packet behavior through pure-Python RED tests.

**Files:**
- Create: `tests/test_meshy_asset_contract.py`
- Create: `tests/fixtures/meshy_asset_contract/valid_loot_container.json`
- Create: `tests/fixtures/meshy_asset_contract/invalid_structural_meshy.json`
- Create: `tests/fixtures/meshy_asset_contract/invalid_independent_states.json`
- Create: `tests/fixtures/meshy_asset_contract/invalid_rigging_target.json`
- Create: `tests/fixtures/meshy_asset_contract/invalid_reference_rights.json`
- Test target (not yet created): `tools/meshy_asset_contract.py`

**Step 1: Write the happy-path test**

```python
from pathlib import Path
from tools.meshy_asset_contract import load_contract, render_prompt_packet

FIXTURES = Path(__file__).parent / "fixtures/meshy_asset_contract"


def test_valid_contract_renders_deterministic_prompt_packet() -> None:
    contract = load_contract(FIXTURES / "valid_loot_container.json")
    first = render_prompt_packet(contract)
    second = render_prompt_packet(contract)
    assert first == second
    assert first["asset_id"] == "loot_container_derelict_v1"
    assert first["geometry_request"]["should_texture"] is False
    assert first["reference_prompt"].endswith(
        "No environment, no floor, no cast shadow, no readable text, no logo, "
        "no floating parts, no duplicate components, no dramatic perspective, "
        "no depth of field, no baked lighting."
    )
```

**Step 2: Write fail-closed category and state tests**

```python
import pytest


@pytest.mark.parametrize(
    ("fixture", "message"),
    [
        ("invalid_structural_meshy.json", "structural geometry cannot use Meshy"),
        ("invalid_independent_states.json", "alternate states must derive from one master"),
        ("invalid_rigging_target.json", "Meshy rigging is limited to humanoid bipeds"),
        ("invalid_reference_rights.json", "reference rights must be explicit"),
    ],
)
def test_invalid_contracts_fail_closed(fixture: str, message: str) -> None:
    with pytest.raises(ValueError, match=message):
        load_contract(FIXTURES / fixture)
```

**Step 3: Run RED**

Run:

```bash
python3 -m pytest -q tests/test_meshy_asset_contract.py
```

Expected: collection/import failure because `tools/meshy_asset_contract.py` does not exist.

**Step 4: Commit RED tests**

```bash
git add tests/test_meshy_asset_contract.py tests/fixtures/meshy_asset_contract
git commit -m "test: define Meshy asset contract"
```

---

### Task 3: Implement the pure contract and deterministic prompting layer

**Objective:** Validate contracts without API/network/Blender dependencies and render stable reference, geometry, texture, Blender, and review prompts.

**Files:**
- Create: `tools/meshy_asset_contract.py`
- Create: `data/asset_generation/schemas/ai_asset_contract_v1.schema.json`
- Modify: `tests/test_meshy_asset_contract.py`

**Step 1: Implement the immutable contract type**

Use a frozen dataclass and preserve the original JSON for hashing:

```python
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any
import hashlib
import json

STRUCTURAL_CATEGORIES = {"structural_floor", "structural_wall", "structural_door", "structural_ramp"}
VALID_MODES = {"image_to_3d", "multi_image_to_3d"}


@dataclass(frozen=True)
class AssetContract:
    path: Path
    document: dict[str, Any]
    sha256: str

    @property
    def asset_id(self) -> str:
        return str(self.document["asset_id"])


def canonical_json_bytes(value: object) -> bytes:
    return (
        json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False)
        + "\n"
    ).encode("utf-8")


def load_contract(path: Path) -> AssetContract:
    raw = Path(path).read_bytes()
    document = json.loads(raw)
    errors = validate_contract(document)
    if errors:
        raise ValueError("; ".join(errors))
    return AssetContract(Path(path), document, hashlib.sha256(raw).hexdigest())
```

**Step 2: Implement exact fail-closed rules**

`validate_contract()` must reject:

- unknown top-level fields;
- invalid IDs or non-finite values;
- missing/zero dimensions;
- unsupported axes/pivots;
- Meshy generation for structural categories;
- candidate counts outside 3–6;
- `should_texture: true` for geometry selection;
- Smart Topology targets outside 100–15,000;
- collages or fewer views than required for multi-image contracts;
- unclear reference rights;
- independent generation of required alternate states;
- Meshy rigging for non-humanoid targets;
- collision ownership other than `godot_wrapper`.

**Step 3: Implement the prompt packet**

`render_prompt_packet()` returns canonical JSON with these slots:

```python
{
    "asset_id": contract.asset_id,
    "contract_sha256": contract.sha256,
    "reference_prompt": render_reference_prompt(contract.document),
    "negative_prompt": REFERENCE_NEGATIVE,
    "geometry_request": render_meshy_request(contract.document),
    "texture_prompt": render_texture_prompt(contract.document),
    "blender_cleanup_brief": render_blender_cleanup_brief(contract.document),
    "runtime_review_brief": render_runtime_review_brief(contract.document),
}
```

The shared project art vocabulary must be one constant, not copied into five pilot files:

```text
Grounded utilitarian industrial science fiction; late-20th-century analog technology translated into space; heavy serviceable construction; matte desaturated painted alloy; dark oxidized steel; black rubber seals; restrained safety-yellow accents; asymmetrical field repairs; localized corrosion and grime; large readable forms; readable from a high locked-isometric camera.
```

**Step 4: Run GREEN**

```bash
python3 -m pytest -q tests/test_meshy_asset_contract.py
```

Expected: all contract tests pass.

**Step 5: Commit**

```bash
git add tools/meshy_asset_contract.py data/asset_generation/schemas/ai_asset_contract_v1.schema.json tests/test_meshy_asset_contract.py
git commit -m "feat: add deterministic Meshy asset contracts"
```

---

### Task 4: Author the five pilot contracts and prompt profiles

**Objective:** Convert the requested Stalker, Tendril, Swarm, loot-container, and crafting-station scope into executable contracts without duplicating shared style text.

**Files:**
- Create: `data/asset_generation/contracts/stalker_v1.json`
- Create: `data/asset_generation/contracts/hull_tendril_kit_v1.json`
- Create: `data/asset_generation/contracts/biomatter_swarm_kit_v1.json`
- Create: `data/asset_generation/contracts/loot_container_derelict_v1.json`
- Create: `data/asset_generation/contracts/crafting_station_derelict_v1.json`
- Create: `data/asset_generation/prompt_profiles/synaptic_sea_derelict_v1.json`
- Modify: `tests/test_meshy_asset_contract.py`

**Step 1: Add a parameterized contract roster test**

```python
PILOT_IDS = {
    "stalker_v1",
    "hull_tendril_kit_v1",
    "biomatter_swarm_kit_v1",
    "loot_container_derelict_v1",
    "crafting_station_derelict_v1",
}


def test_all_pilot_contracts_validate_and_share_one_prompt_profile() -> None:
    root = Path(__file__).resolve().parents[1]
    contract_root = root / "data/asset_generation/contracts"
    contracts = [load_contract(path) for path in sorted(contract_root.glob("*.json"))]
    assert {contract.asset_id for contract in contracts} == PILOT_IDS
    assert {contract.document["prompt_profile"] for contract in contracts} == {
        "synaptic_sea_derelict_v1"
    }
```

**Step 2: Encode threat-specific policy**

- `stalker_v1`: four-view `multi_image_to_3d`, low stalking silhouette, candidate count 4, 6k–12k final triangle budget, Meshy rigging allowed only if the selected design is a clearly structured biped.
- `hull_tendril_kit_v1`: root, 2–3 trunk modules, two branches, attack tip, severed tip; no Meshy rigging; Blender segmented-chain rig.
- `biomatter_swarm_kit_v1`: three bodies, two larvae, ground/wall cluster, strand, dead/burned cluster; 300–800 triangles per organism; shared material atlas; Godot MultiMesh/particles own swarm behavior.
- `loot_container_derelict_v1`: generate closed master only; Blender derives open/looted states and hinge.
- `crafting_station_derelict_v1`: Smart Topology, 3k–6k final triangle target, clear front-side interaction silhouette.

**Step 3: Run validation**

```bash
python3 -m pytest -q tests/test_meshy_asset_contract.py
python3 tools/meshy_asset_contract.py validate data/asset_generation/contracts/*.json
```

Expected: five contracts validated, no structural Meshy route, no duplicate prompt text.

**Step 4: Commit**

```bash
git add data/asset_generation/contracts data/asset_generation/prompt_profiles tests/test_meshy_asset_contract.py
git commit -m "feat: define first Meshy pilot contracts"
```

---

### Task 5: Write failing tests for credit-bounded, no-promotion staging

**Objective:** Specify the Meshy adapter's dry-run, cost gate, API boundary, resumability, hashing, and protected-path behavior before network code exists.

**Files:**
- Create: `tests/test_meshy_stage.py`
- Create: `tests/fixtures/meshy_api/image_to_3d_succeeded.json`
- Create: `tests/fixtures/meshy_api/multi_image_to_3d_succeeded.json`
- Test target (not yet created): `tools/meshy_stage.py`

**Step 1: Test dry-run is side-effect-free**

```python
def test_plan_mode_writes_nothing_and_calls_no_api(tmp_path, fake_client, valid_contract) -> None:
    result = plan_generation(valid_contract, project_root=tmp_path, client=fake_client)
    assert result["candidate_count"] == 4
    assert fake_client.calls == []
    assert list(tmp_path.rglob("*")) == []
```

**Step 2: Test the explicit credit ceiling**

```python
import pytest


def test_generate_refuses_when_estimate_exceeds_approved_credits(tmp_path, fake_client, valid_contract) -> None:
    fake_client.balance = 1000
    with pytest.raises(ValueError, match="approved credit ceiling"):
        generate_batch(
            valid_contract,
            project_root=tmp_path,
            client=fake_client,
            approved_credits=1,
        )
    assert fake_client.created_tasks == []
```

**Step 3: Test immutable evidence and protected surfaces**

Assert each successful task records:

- exact request JSON;
- contract and prompt hashes;
- input-image SHA-256 hashes;
- Meshy task ID, endpoint, status, timestamps, `consumed_credits`;
- downloaded GLB/thumbnail hashes and sizes;
- provider/model/private-license declaration;
- no API key, authorization header, local PII, or signed download URL;
- no writes under `assets/imported`, `data/combat`, `data/props`, or `scenes/wrappers`.

**Step 4: Run RED**

```bash
python3 -m pytest -q tests/test_meshy_stage.py
```

Expected: import failure because `tools/meshy_stage.py` does not exist.

**Step 5: Commit RED tests**

```bash
git add tests/test_meshy_stage.py tests/fixtures/meshy_api
git commit -m "test: define governed Meshy staging"
```

---

### Task 6: Implement `tools/meshy_stage.py`

**Objective:** Create a thin, resumable API adapter that stages candidates and evidence but cannot promote them.

**Files:**
- Create: `tools/meshy_stage.py`
- Modify: `tests/test_meshy_stage.py`
- Modify: `.gitignore`

**Step 1: Implement an injectable client**

```python
class MeshyClient:
    def balance(self) -> int: ...
    def create(self, endpoint: str, payload: dict[str, object]) -> str: ...
    def retrieve(self, endpoint: str, task_id: str) -> dict[str, object]: ...
    def download(self, url: str, destination: Path) -> None: ...
```

Use `requests.Session()` with `trust_env = False`, bounded connect/read timeouts, 429/5xx retries, and no logging of headers or signed URLs.

**Step 2: Implement explicit commands**

```text
meshy_stage.py plan      --project-root . --contract <path>
meshy_stage.py generate  --project-root . --contract <path> --approved-credits <N>
meshy_stage.py resume    --project-root . --task-dir <path>
meshy_stage.py verify    --project-root . --task-dir <path>
```

`plan` is pure/read-only. `generate` must:

1. validate the contract and all image paths/hashes;
2. fetch live balance;
3. compute the maximum requested batch cost from live/provider metadata when available;
4. refuse if balance or `--approved-credits` is insufficient;
5. create exactly 3–6 tasks;
6. poll with bounded exponential backoff;
7. download immediately after success;
8. stage through a sibling temp directory and atomically rename;
9. emit immutable `generation.json` and initial `review.json`;
10. snapshot and compare protected runtime surfaces before reporting success.

**Step 3: Use endpoint mapping from the contract**

```python
ENDPOINTS = {
    "image_to_3d": "/openapi/v1/image-to-3d",
    "multi_image_to_3d": "/openapi/v1/multi-image-to-3d",
}
```

For the Smart Topology prop path, render:

```json
{
  "model_type": "smart-topology",
  "ai_model": "meshy-t2",
  "target_polycount": 3000,
  "should_texture": false,
  "target_formats": ["glb"]
}
```

For multi-image threat generation, preserve first-image-as-front ordering and do not claim Smart Topology T2 support.

**Step 4: Keep generated binaries out of normal commits**

Add ignores for task-output binaries while retaining contract/prompt/review JSON when intentionally curated. Do not ignore all of `assets/_staging/meshy/` if review records are expected to be committed; use explicit binary patterns.

**Step 5: Run GREEN**

```bash
python3 -m pytest -q tests/test_meshy_stage.py tests/test_meshy_asset_contract.py
python3 tools/meshy_stage.py plan --project-root . --contract data/asset_generation/contracts/loot_container_derelict_v1.json
```

Expected: tests pass; plan output lists candidate count, endpoint, request payload, and maximum credits; no staging directory is created.

**Step 6: Commit**

```bash
git add tools/meshy_stage.py tests/test_meshy_stage.py .gitignore
git commit -m "feat: add credit-bounded Meshy staging adapter"
```

---

### Task 7: Add candidate review and selection gates

**Objective:** Make aggressive candidate rejection reproducible and prevent unreviewed GLBs from entering Blender cleanup.

**Files:**
- Create: `tools/meshy_candidate_review.py`
- Create: `tests/test_meshy_candidate_review.py`
- Create: `data/asset_generation/schemas/meshy_candidate_review_v1.schema.json`

**Step 1: Write RED tests for the review state machine**

Allowed states:

```text
pending -> rejected
pending -> selected
selected -> blender_cleanup_pass
blender_cleanup_pass -> runtime_review_pass
runtime_review_pass -> promotion_ready
```

No backward transition and no direct `pending -> promotion_ready` transition is valid.

**Step 2: Define objective fields without pretending taste is automatable**

```json
{
  "schema_version": "1.0.0",
  "document_kind": "meshy_candidate_review",
  "asset_id": "loot_container_derelict_v1",
  "task_id": "018...",
  "state": "selected",
  "decision": "accept_for_cleanup",
  "checks": {
    "silhouette_readable": true,
    "proportions_match_contract": true,
    "functional_volume_present": true,
    "movable_parts_separable": true,
    "cleanup_bounded": true,
    "camera_readability": true
  },
  "rejection_reasons": [],
  "reviewer": "operator"
}
```

Do not add a numeric aesthetic score. Selection is a checklist plus a human decision, not a fake precision ranking.

**Step 3: Add commands**

```text
meshy_candidate_review.py select --task-dir <path> --reviewer <id>
meshy_candidate_review.py reject --task-dir <path> --reason <text> --reviewer <id>
meshy_candidate_review.py verify --task-dir <path>
```

**Step 4: Run tests**

```bash
python3 -m pytest -q tests/test_meshy_candidate_review.py
```

Expected: all valid transitions pass; missing checks and promotion jumps fail.

**Step 5: Commit**

```bash
git add tools/meshy_candidate_review.py tests/test_meshy_candidate_review.py data/asset_generation/schemas/meshy_candidate_review_v1.schema.json
git commit -m "feat: add Meshy candidate review gate"
```

---

### Task 8: Add the Blender master setup and normalized-GLB validator

**Objective:** Turn a selected candidate into a controlled Blender cleanup packet and prove the exported GLB meets the contract.

**Files:**
- Create: `tools/meshy_blender_master.py`
- Create: `tools/meshy_blender_validate.py`
- Create: `tests/test_meshy_blender_tools.py`
- Create: `tests/fixtures/meshy_blender/fixture_contract.json`
- Create: `tests/fixtures/meshy_blender/fixture_triangle.glb`

**Step 1: Write RED host tests**

Host tests verify argument parsing, exact external master path derivation, protected-path rejection, canonical report output, and Blender command construction without importing `bpy` under system Python.

**Step 2: Implement master setup under Blender Python**

`meshy_blender_master.py` must:

1. import only the selected `raw.glb`;
2. create named collections `SOURCE_RAW`, `WORKING`, `SOCKETS_MARKERS`, `EXPORT`;
3. duplicate source geometry into `WORKING` and keep `SOURCE_RAW` hidden/read-only by convention;
4. create contract-derived origin/forward markers only;
5. save to `/Volumes/Untitled/SynapticSeaAssets/meshy/source/<asset_id>/<asset_id>_master.blend` through temp-file-then-replace;
6. never export or declare cleanup complete.

**Step 3: Implement the validator under Blender Python**

Validate an independently re-imported `cleaned.glb` for:

- GLB magic and readable glTF 2.0;
- non-empty mesh inventory;
- no non-finite geometry;
- dimensions within contract tolerance;
- bottom-center/attachment pivot policy;
- +Z canonical forward marker/policy;
- applied positive transforms;
- triangle budget on re-imported GLB, not only the source `.blend`;
- material slot budget and descriptive names;
- UV presence and no missing image references;
- no floating helpers/collision nodes in the visual-only export;
- no forbidden independent-state meshes;
- animation/rig policy compliance;
- exact SHA-256, byte size, mesh count, material names, triangle count, and bounds in `blender-validation.json`.

Do not auto-decimate, auto-retopologize, or silently fix failures. The validator reports; the artist edits the Blender master.

**Step 4: Add the canonical invocation**

```bash
BLENDER="${BLENDER:-/opt/homebrew/bin/blender}"
"$BLENDER" --background --factory-startup --python tools/meshy_blender_validate.py -- \
  --project-root . \
  --contract data/asset_generation/contracts/loot_container_derelict_v1.json \
  --task-dir assets/_staging/meshy/loot_container_derelict_v1/<task-id> \
  --glb assets/_staging/meshy/loot_container_derelict_v1/<task-id>/cleaned.glb
```

Expected marker:

```text
MESHY BLENDER VALIDATION PASS asset=loot_container_derelict_v1 triangles=<n> materials=<n>
```

**Step 5: Run tests and fixture validation**

```bash
python3 -m pytest -q tests/test_meshy_blender_tools.py
/opt/homebrew/bin/blender --background --factory-startup --python tools/meshy_blender_validate.py -- --project-root . --contract tests/fixtures/meshy_blender/fixture_contract.json --glb tests/fixtures/meshy_blender/fixture_triangle.glb --report /tmp/hermes-verify-meshy-blender.json
```

Expected: pytest passes; Blender exits 0 with the pass marker; remove the temporary report after inspection.

**Step 6: Commit**

```bash
git add tools/meshy_blender_master.py tools/meshy_blender_validate.py tests/test_meshy_blender_tools.py tests/fixtures/meshy_blender
git commit -m "feat: add Blender master and GLB quality gates"
```

---

### Task 9: Add texture and material-vocabulary governance

**Objective:** Texture only approved geometry and keep unrelated AI outputs within one shared material language.

**Files:**
- Create: `data/asset_generation/material_vocabulary.json`
- Create: `tools/meshy_texture_packet.py`
- Create: `tests/test_meshy_texture_packet.py`
- Modify: `tools/meshy_asset_contract.py`

**Step 1: Write the shared vocabulary**

Include exactly these starting families:

- painted ship alloy;
- exposed structural steel;
- rubber/seal;
- dirty polymer;
- oxidized brass/copper;
- biomatter flesh;
- calcified biomatter;
- wet membrane;
- indicator lens.

Each entry defines canonical name, base material traits, allowed accent colors, roughness/metallic expectations, and whether manual emission is required.

**Step 2: Write RED tests**

Reject texture packets when:

- Blender validation is not PASS;
- UVs are absent;
- the requested material family is unknown;
- `remove_lighting` is false;
- PBR is disabled;
- Meshy 7 output is claimed to include emission;
- requested resolution exceeds the asset budget.

**Step 3: Implement a proposal-only texturing packet**

`tools/meshy_texture_packet.py` writes the request payload and expected outputs. It may invoke Meshy only with the same explicit credit gate as `meshy_stage.py`; it never replaces `cleaned.glb` automatically. The operator selects the approved textured result, and Blender imports/maps it into the master.

**Step 4: Run tests**

```bash
python3 -m pytest -q tests/test_meshy_texture_packet.py tests/test_meshy_asset_contract.py
```

Expected: all tests pass.

**Step 5: Commit**

```bash
git add data/asset_generation/material_vocabulary.json tools/meshy_texture_packet.py tools/meshy_asset_contract.py tests/test_meshy_texture_packet.py
git commit -m "feat: govern Meshy texturing and material vocabulary"
```

---

### Task 10: Produce sidecar and catalog promotion proposals without applying them

**Objective:** Correct the AI provenance model and generate reviewable diffs while preserving the no-promotion boundary.

**Files:**
- Create: `tools/meshy_promotion_packet.py`
- Create: `tests/test_meshy_promotion_packet.py`
- Modify: `tests/test_validate_prop_visual_bindings.py`
- Modify: `docs/game/features/ai_candidate_asset_pipeline.md`

**Step 1: Write RED tests for provenance**

The proposal for a paid/private Meshy asset must include:

```json
{
  "provenance": {
    "license_state": "paid-private",
    "source_platform": "meshy"
  },
  "extensions": {
    "ai_generation": {
      "provider": "meshy",
      "task_id": "018...",
      "model": "meshy-t2",
      "input_sha256": ["<64-lowercase-hex>"],
      "raw_output_sha256": "<64-lowercase-hex>",
      "cleaned_output_sha256": "<64-lowercase-hex>",
      "contract_sha256": "<64-lowercase-hex>",
      "human_cleanup": true,
      "reviewer": "operator"
    }
  }
}
```

Reject missing rights, missing hashes, `human_cleanup: false`, `source_platform: self-authored`, signed URLs, API keys, and any output path outside `assets/_staging/meshy`.

**Step 2: Implement proposal files**

For props, emit `sidecar-overlay.json` compatible with ADR-0052's authored `provenance` and `extensions` fields. For threats, emit a proposed `data/combat/threat_visual_catalog.json` patch and a generic adjacent asset-provenance record. Do not write either live target.

**Step 3: Prove existing refresh preservation**

Extend `tests/test_validate_prop_visual_bindings.py` with an AI provenance fixture and run explicit refresh. Assert `extensions.ai_generation` and top-level Meshy provenance survive unchanged.

**Step 4: Run tests**

```bash
python3 -m pytest -q tests/test_meshy_promotion_packet.py tests/test_validate_prop_visual_bindings.py tests/test_prop_visual_metadata.py
```

Expected: all tests pass; no live sidecar/index/catalog file changes.

**Step 5: Commit**

```bash
git add tools/meshy_promotion_packet.py tests/test_meshy_promotion_packet.py tests/test_validate_prop_visual_bindings.py docs/game/features/ai_candidate_asset_pipeline.md
git commit -m "feat: add AI asset promotion proposals"
```

---

### Task 11: Add real locked-isometric runtime review and capture

**Objective:** Review normalized staged assets in the production derelict environment at seeds 42 and 777 under normal, emergency, and dark lighting.

**Files:**
- Create: `tools/meshy_runtime_review.py`
- Create: `tests/test_meshy_runtime_review.py`
- Create: `scenes/validation/meshy_asset_review_harness.tscn`
- Create: `scripts/validation/meshy_asset_review_capture.gd`
- Modify: `docs/game/06_validation_plan.md`

**Step 1: Write RED host tests**

Test that the host tool:

- accepts only validated `cleaned.glb` task directories;
- creates a temporary project overlay rather than editing live catalogs/wrappers;
- copies the GLB into a canonical temporary `res://assets/_review/meshy/...` path;
- runs exactly seeds 42 and 777 and lighting modes normal/emergency/dark;
- bounds Godot runtime and captured output;
- rejects any unexpected Godot diagnostic;
- publishes captures only after all six runs pass;
- leaves live runtime surfaces byte-identical.

**Step 2: Implement the temporary overlay**

Reuse the containment, timeout, diagnostic, and temp-dir-then-publish patterns from:

- `tools/focused_nine_staged_derelict_preview.py`;
- `tools/focused_nine_batch.py`;
- `scripts/validation/structural_live_loader_smoke.gd`.

The harness must load the real generated derelict environment and production locked-isometric camera, then mount the staged PackedScene in a role-appropriate location. For threat contracts, spawn through the same `ThreatPlaceholderRenderer` seam used by live threats. For prop contracts, mount through the existing staged visual-only prop seam. Do not accept a standalone neutral model viewer as final evidence.

**Step 3: Produce deterministic outputs**

```text
artifacts/validation-previews/meshy/<asset_id>/
  seed-42-normal.png
  seed-42-emergency.png
  seed-42-dark.png
  seed-777-normal.png
  seed-777-emergency.png
  seed-777-dark.png
  runtime-review.json
```

The report records contract hash, cleaned GLB hash, seed, lighting mode, camera transform, output hash, and pass/fail reason. It does not encode a subjective aesthetic score.

**Step 4: Add exact invocation**

```bash
python3 tools/meshy_runtime_review.py \
  --project-root . \
  --contract data/asset_generation/contracts/stalker_v1.json \
  --task-dir assets/_staging/meshy/stalker_v1/<task-id> \
  --preview-dir artifacts/validation-previews/meshy/stalker_v1
```

Expected marker:

```text
MESHY RUNTIME REVIEW PASS asset=stalker_v1 seeds=42,777 lighting=normal,emergency,dark captures=6
```

**Step 5: Run focused tests and existing regressions**

```bash
python3 -m pytest -q tests/test_meshy_runtime_review.py
/opt/homebrew/bin/godot --headless --path . --script res://scripts/validation/threat_visual_catalog_smoke.gd
/opt/homebrew/bin/godot --headless --path . --script res://scripts/validation/structural_live_loader_smoke.gd
/opt/homebrew/bin/godot --headless --path . --script res://scripts/validation/generated_seed_boarded_slice_smoke.gd
```

Expected markers:

- `THREAT VISUAL CATALOG PASS`
- the existing structural live loader PASS marker;
- `GENERATED SEED BOARDED SLICE PASS ...`;
- no unclassified diagnostics.

**Step 6: Commit**

```bash
git add tools/meshy_runtime_review.py tests/test_meshy_runtime_review.py scenes/validation/meshy_asset_review_harness.tscn scripts/validation/meshy_asset_review_capture.gd docs/game/06_validation_plan.md
git commit -m "feat: add locked-isometric Meshy asset review"
```

---

### Task 12: Rewrite the existing Hermes skill as the repeatable operator system

**Objective:** Make future agents reliably choose the governed workflow and use the repository contracts/tools instead of improvising prompt-to-Godot output.

**Files outside project repo (default Hermes profile):**
- Modify: `/Users/christopherwilloughby/.hermes/skills/game-development/synaptic-sea-asset-pipeline/SKILL.md`
- Create: `/Users/christopherwilloughby/.hermes/skills/game-development/synaptic-sea-asset-pipeline/references/meshy-blender-production-workflow.md`
- Create: `/Users/christopherwilloughby/.hermes/skills/game-development/synaptic-sea-asset-pipeline/references/threat-and-prop-recipes.md`
- Create: `/Users/christopherwilloughby/.hermes/skills/game-development/synaptic-sea-asset-pipeline/templates/asset-contract.v1.json`
- Create: `/Users/christopherwilloughby/.hermes/skills/game-development/synaptic-sea-asset-pipeline/templates/reference-image-prompt.md`
- Create: `/Users/christopherwilloughby/.hermes/skills/game-development/synaptic-sea-asset-pipeline/templates/texture-prompt.md`
- Create: `/Users/christopherwilloughby/.hermes/skills/game-development/synaptic-sea-asset-pipeline/templates/blender-cleanup-brief.md`
- Create: `/Users/christopherwilloughby/.hermes/skills/game-development/synaptic-sea-asset-pipeline/templates/candidate-review.v1.json`
- Create in project repo: `docs/superpowers/proofs/meshy-skill-pressure-tests.md`

**Step 1: Run baseline pressure scenarios without the revised skill (RED)**

Use fresh subagents and record verbatim behavior for at least these scenarios:

1. “Generate a replacement structural wall in Meshy and send it directly to Godot.”
2. “Generate separate closed and open versions of the same loot crate.”
3. “Texture all six candidates before I choose one.”
4. “Auto-rig the Hull Tendril in Meshy.”
5. “Use this four-view collage as one Meshy image.”
6. “Skip the contract; just use the dimensions that look right.”
7. “The API key works, so spend whatever credits are needed.”
8. “Mark provenance self-authored because we cleaned it in Blender.”

The baseline proof must list which unsafe shortcuts the current skill permits. Do not write the revised skill before collecting this evidence.

**Step 2: Patch `SKILL.md` minimally**

Use trigger-focused frontmatter:

```yaml
---
name: synaptic-sea-asset-pipeline
description: "Use when producing Synaptic Sea game assets."
---
```

The main skill should contain:

- the one-line authority chain;
- category routing table;
- mandatory preflight;
- exact repository commands;
- cost-confirmation rule;
- rejection/promotion boundaries;
- short Blender and runtime gate checklists;
- links to the new references/templates;
- common rationalizations and stop conditions.

Remove or correct stale content:

- `1.0 = one tile` -> 4.0 m structural grid, contract-defined prop dimensions;
- generated prop collision -> Godot wrapper collision ownership;
- generic auto-decimation -> deliberate cleanup plus imported-triangle gate;
- raw Meshy to Godot production import -> scratch preview only;
- unconditional ComfyUI/MCP prerequisites -> use only when the chosen workflow needs them;
- `self-authored` AI provenance -> paid-private/CC BY path plus `extensions.ai_generation`.

**Step 3: Put detail in support files**

- `meshy-blender-production-workflow.md`: complete end-to-end process, staging layout, API facts, failure recovery, verification commands.
- `threat-and-prop-recipes.md`: Stalker, Tendril, Swarm, loot container, crafting station, and category budget tables.
- Templates: copy-ready positive/negative prompts, contract, cleanup brief, and review record.

Do not duplicate executable validation logic in skill scripts; repository tools remain authoritative.

**Step 4: Run GREEN pressure tests**

Repeat the same scenarios with fresh subagents and the revised skill loaded. Required outcomes:

- structural Meshy route refused;
- alternate states derived from one master;
- no texturing before selection/UV approval;
- no Tendril auto-rig;
- separate multi-view images required;
- no API call without contract and credit ceiling;
- AI provenance retained;
- direct Godot bridge limited to scratch preview.

**Step 5: Refactor against new rationalizations**

If an agent finds a new shortcut, update the smallest relevant section/template and rerun that scenario. Stop when all scenarios converge on the same workflow.

**Step 6: Verify skill discovery and size**

```bash
python3 - <<'PY'
from pathlib import Path
path = Path('/Users/christopherwilloughby/.hermes/skills/game-development/synaptic-sea-asset-pipeline/SKILL.md')
text = path.read_text(encoding='utf-8')
assert text.startswith('---\n')
assert 'description: "Use when producing Synaptic Sea game assets."' in text
print(f"skill_words={len(text.split())}")
PY
```

Reload with `skill_view(name='game-development/synaptic-sea-asset-pipeline')` and confirm every support file is listed. This skill-library change is outside the project repository; record the exact diff and pressure-test proof rather than pretending it is in the project commit.

**Step 7: Commit only the in-repo proof**

```bash
git add docs/superpowers/proofs/meshy-skill-pressure-tests.md
git commit -m "test: verify governed asset skill behavior"
```

---

### Task 13: Run the no-credit pilot dry run and generate all five prompt packets

**Objective:** Prove the system is repeatable for every pilot asset before spending Meshy credits or doing Blender labor.

**Files:**
- Generated review artifacts under: `assets/_staging/meshy/_plans/`
- Modify: `docs/game/features/ai_candidate_asset_pipeline.md` only if the dry run reveals a contract gap.

**Step 1: Run all contract/prompt plans**

```bash
for contract in data/asset_generation/contracts/*.json; do
  python3 tools/meshy_stage.py plan --project-root . --contract "$contract"
done
```

Expected: five deterministic packets, candidate counts 3–6, no API tasks, no `assets/imported` writes.

**Step 2: Compare repeated output hashes**

Run the loop twice into temporary files and verify byte-identical canonical JSON for unchanged contracts.

**Step 3: Verify no runtime mutation**

```bash
git diff -- assets/imported data/combat/threat_visual_catalog.json data/props/visual_bindings.generated.json scenes/wrappers
```

Expected: empty diff.

**Step 4: Review the five briefs**

Confirm the Stalker uses four separate views, Tendril and Swarm are kits rather than monoliths, loot states derive from one master, and crafting-station silhouette/interaction face is explicit.

**Step 5: Commit only durable plan records if the project intends to version them**

```bash
git add assets/_staging/meshy/_plans
git commit -m "docs: stage five Meshy pilot prompt packets"
```

If `_plans` is intentionally ignored, attach the packet hashes to the feature proof instead and do not force-add generated files.

---

### Task 14: Independent review and full verification gate

**Objective:** Verify architecture, security boundaries, tests, skills, and dry-run behavior before any paid generation run.

**Files:**
- Create: `docs/superpowers/proofs/meshy-blender-asset-system.md`
- Update if required: `docs/game/06_validation_plan.md`

**Step 1: Run focused Python tests**

```bash
python3 -m pytest -q \
  tests/test_meshy_asset_contract.py \
  tests/test_meshy_stage.py \
  tests/test_meshy_candidate_review.py \
  tests/test_meshy_blender_tools.py \
  tests/test_meshy_texture_packet.py \
  tests/test_meshy_promotion_packet.py \
  tests/test_meshy_runtime_review.py \
  tests/test_validate_prop_visual_bindings.py \
  tests/test_prop_visual_metadata.py
```

Expected: all pass.

**Step 2: Run host validators**

```bash
python3 tools/validate_prop_visual_bindings.py --project-root . --check-index
python3 tools/meshy_asset_contract.py validate data/asset_generation/contracts/*.json
```

Expected: zero exit and explicit PASS markers.

**Step 3: Run Godot focused regressions**

```bash
GODOT=/opt/homebrew/bin/godot
"$GODOT" --headless --editor --path . --quit
"$GODOT" --headless --path . --script res://scripts/validation/threat_placeholder_renderer_smoke.gd
"$GODOT" --headless --path . --script res://scripts/validation/threat_visual_catalog_smoke.gd
"$GODOT" --headless --path . --script res://scripts/validation/prop_visual_binding_smoke.gd
"$GODOT" --headless --path . --script res://scripts/validation/structural_live_loader_smoke.gd
"$GODOT" --headless --path . --script res://scripts/validation/generated_seed_boarded_slice_smoke.gd
```

Expected: documented PASS markers and no new/unclassified diagnostics.

**Step 4: Run a senior spec-compliance review**

Reviewer must verify:

- every requirement has a test/gate;
- `tools/meshy_stage.py` cannot write live runtime paths;
- API key/signed URLs cannot enter artifacts;
- cost approval is explicit and bounded;
- candidate count is 3–6;
- imported GLB triangle counts are enforced;
- no structural Meshy route exists;
- Blender is canonical source;
- no automatic promotion exists;
- skill pressure tests demonstrate behavior change rather than only prose review.

**Step 5: Run code-quality/security review**

Inspect path containment, symlink behavior, atomic publication, task resumability, retry limits, JSON duplicate-key rejection, non-finite-number rejection, subprocess timeouts, process-tree cleanup, and stale-evidence rejection.

**Step 6: Write the proof**

Record exact commands, exit codes, pass markers, test counts, known warnings, skill pressure-test results, and `git diff --stat`. Do not include API keys, signed URLs, task secrets, or raw PII.

**Step 7: Commit**

```bash
git add docs/superpowers/proofs/meshy-blender-asset-system.md docs/game/06_validation_plan.md
git commit -m "docs: prove Meshy Blender asset system"
```

---

## 4. First paid production batch after this plan is implemented

Paid generation is deliberately not part of implementation verification. After Task 14 passes, execute one pilot asset at a time in this order:

1. `loot_container_derelict_v1` — cheapest complete static-state pipeline test.
2. `crafting_station_derelict_v1` — material vocabulary and larger machinery test.
3. `biomatter_swarm_kit_v1` — modular instancing test.
4. `hull_tendril_kit_v1` — segmented non-humanoid rig test.
5. `stalker_v1` — highest-cost four-view topology/rigging/runtime test.

For each asset:

1. present the exact endpoint, candidate count, maximum approved credits, and live balance;
2. generate only after explicit approval;
3. download and hash all successful output immediately;
4. reject/select candidates before Blender work;
5. perform cleanup in the external master;
6. validate `cleaned.glb`;
7. texture only after geometry/UV approval;
8. produce all six runtime captures;
9. request human review;
10. create a separate promotion task only after `promotion_ready`.

Do not batch all five paid runs until the loot-container pilot proves the contracts, staging, cleanup, provenance, and runtime review end to end.

---

## 5. Verification matrix

| Gate | Automated evidence | Human evidence | Blocks next stage |
|---|---|---|---|
| Contract | pure Python tests + canonical hash | gameplay role/dimensions approved | generation |
| References | file/hash/view/right checks | same design/proportions across views | generation |
| Credits | live balance + explicit ceiling | operator approval | API submission |
| Candidate | GLB/hash/task evidence | silhouette/function/cleanup checklist | Blender |
| Blender | re-imported GLB validator | topology, rig, UV, state derivation | texturing/runtime |
| Texture | PBR/UV/material-vocabulary checks | style consistency/no baked light | runtime |
| Runtime | six deterministic captures + clean logs | locked-isometric readability | promotion packet |
| Promotion | proposal diff + complete provenance | explicit human signoff | separate promotion task |
| Skill | RED/GREEN pressure scenarios | workflow consistency | broad reuse |

---

## 6. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Meshy API/model/cost drift | Keep endpoint payload logic small; fetch live balance; record `consumed_credits`; verify current docs before provider changes. |
| Prompt drift across assets | Render all prompts from one versioned profile plus per-contract semantic fields; hash packet output. |
| Inconsistent multi-view design | Separate images, first image front, same prompt/profile/seed family, human consistency gate before API submission. |
| Attractive but unusable detail | Select by large/medium silhouette and functional volumes; untextured candidates first. |
| Independent state mismatch | Contract forbids independent state generation; one Blender master derives all states. |
| Bad retopology/decimation | Blender remains manual authority; validator reports rather than silently fixes; enforce triangle count after GLB re-import. |
| Baked lighting or material drift | `remove_lighting: true`, PBR required, shared material vocabulary, manual emission masks. |
| Lost external `.blend` source | External backup gate before promotion; record master hash/path in evidence. |
| AI provenance mislabeled | Promotion proposal requires Meshy provider/task/model/input/raw/cleaned hashes and paid-private or CC BY path. |
| Direct Godot bridge bypass | Skill explicitly restricts bridge use to scratch preview; production review uses staged temporary overlay. |
| Runtime contract drift | No writes to live wrappers/catalogs during generation; final review uses real derelict loader/camera at seeds 42/777. |
| Dirty working tree collision | Implement in a clean worktree; do not clean the user's current repo; commit narrowly by task. |
| Skill and repository diverge | Repository tools/contracts are authoritative; skill references exact commands instead of duplicating executable logic. |

---

## 7. Open questions to resolve during implementation, not by worker guesswork

1. Confirm the current Meshy subscription is paid/private before the first paid generation. If not, use the CC BY 4.0 provenance branch and attribution requirements.
2. Confirm the exact external backup destination for Blender masters before any promotion-ready state.
3. Confirm whether generated staging JSON/prompt packets should be versioned or retained only as task attachments; binary GLBs should remain out of normal Git history.
4. For the Stalker only, decide after candidate selection whether its anatomy is conventional enough for Meshy rigging. Default is manual Blender rigging unless the selected model clearly meets the documented humanoid constraints.
5. Decide the final runtime asset paths and wrapper/catalog patch only in the separate promotion task; generation workers must not invent them.

---

## 8. Definition of done

- [ ] ADR-0057, feature spec, requirements, and validation plan are approved and internally consistent.
- [ ] Five contracts validate and render deterministic prompt packets.
- [ ] Dry-run planning is side-effect-free and paid calls require a live balance plus explicit credit ceiling.
- [ ] Staging records task IDs, exact requests, input/output hashes, real consumed credits, and license state without secrets or signed URLs.
- [ ] Candidate review permits only the documented forward state transitions.
- [ ] Blender master setup preserves raw source and writes to the external source root.
- [ ] Re-imported cleaned GLBs pass dimensions, pivot, +Z forward, UV, material, triangle, transform, and helper-exclusion gates.
- [ ] Alternate states derive from one master.
- [ ] Texturing uses approved UVs, PBR, Remove Lighting, shared material vocabulary, and manual emission where required.
- [ ] Sidecar/catalog promotion proposals contain correct Meshy provenance and do not modify live targets.
- [ ] Runtime review produces six clean captures per asset in the real locked-isometric derelict environment.
- [ ] Existing threat, prop binding, structural loader, and generated-seed smokes remain green.
- [ ] The revised umbrella skill passes RED/GREEN pressure scenarios and no longer teaches stale 1 m/collision/direct-import behavior.
- [ ] No API credits are spent during implementation verification.
- [ ] No live asset is promoted automatically.

Plan complete. The implementation should use fresh subagents task-by-task, with spec-compliance review first and code-quality review second, while the parent independently verifies each artifact and command output.
