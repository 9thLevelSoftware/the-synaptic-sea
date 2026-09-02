# R8 Meshy production proof

## Verdict and evidence binding

- **READY FOR PR**: the source-backed branch gates required for review are complete.
- **LIVE PILOT PENDING**: provider execution and production promotion remain post-PR work.
- Evidence head: `35816acfef34b8eee14d11c0d0eca07592b9fa01`.
- Lineage: origin/main baseline `8a724c4503f23ecdcffa884edbd823e5622dfa21`; merge
  `4dc9e7d7f7aee2c5884bb72118949583737e8994`; phase-one evidence/docs
  `2fcd4e41fabc937f5f33187203a58806b54e4c44`; portability/texture correction
  `09b9fb6d83fae36dc3a17c34dfaab172fba57216`; final texture lower-bound correction
  `35816acfef34b8eee14d11c0d0eca07592b9fa01`.
- Meshy authority is ADR-0058. The R7 proof commit is
  `ad10204ca667fa30e02817971937d8b9ee2cff1a`.

## Authority, authorization, and boundaries

The project has standing subscription authorization for post-PR testing and removes spend bookkeeping as a
human blocker. It does not waive contract, rights, request-integrity, immutable-record,
reconciliation, Blender, runtime, provenance, or promotion gates.

For candidate `generate` and `resume`, a current read-only plan supplies `maximum_credits` as the
required `--approved-credits` request-integrity field; the value must equal the plan value. Each
planned candidate record permits one creation POST attempt per planned candidate record. Ambiguous
creation outcomes are reconciled from the immutable journal and are never automatically retried.

The texture packet is separate and proposal-only. Its `--approved-credits` value must be greater than or equal to the current fixed 10-credit estimate, and it creates no provider task. Candidates
must be selected before Blender cleanup or optional texturing. Godot retains collision,
navigation, wrappers, and gameplay authority; Blender supplies cleaned visual masters and derived
states; promotion remains a separate reviewed proposal.

## Deterministic plans and R7 pressure proof

Five read-only plans are deterministic and remain **unresolved planning envelopes** until
rights-cleared reference files exist:

| Asset | Candidates | Cost/candidate | Maximum credits | Plan SHA-256 |
|---|---:|---:|---:|---|
| `biomatter_swarm_kit_v1` | 3 | 5 | 15 | `112f99980a5c20b259e4e3ef496ee1be80d346c328d0ae6388f83bbd5fc97d95` |
| `crafting_station_derelict_v1` | 4 | 5 | 20 | `87a5a0587a976f07a6b2d51bfcb23317eb4537bc83d9ff5212b002b74824d7f8` |
| `hull_tendril_kit_v1` | 3 | 5 | 15 | `feb2b227820e0c1237b6a1a2789bacca8640311e878bf41c3bec17e03ed4d059` |
| `loot_container_derelict_v1` | 4 | 5 | 20 | `8cd0b5db47d24377aac75f1e219c2c0e16feb29390ccc660f6961a90ced4ff2f` |
| `stalker_v1` | 4 | 20 | 80 | `e44cd28c91ca73fec43b77e2002f8a5a50a9106e44a04da3b154cad009278cf9` |

The R7 pressure proof is `R7_V211_PROOF_PASS scenarios=8 unique=8 safe=8 corrected_scenario=2 pii_free=true cardinality=4x1`. The loot-container plan is one batch of
four candidate records, with one creation POST attempt per planned candidate record. No Meshy provider calls were made. No candidates, external Blender masters, live six-view runtime review,
or promotions were produced.

## Test gates and truthful baseline limits

The merged host-suite result was **340 passed** at the implementation snapshot. This is distinct
from the final focused gate, which recorded **375 passed** in 185.18 seconds. Native **Blender
5.2.0 LTS** recorded **three real Blender tests** passed. These are source-backed gate results,
not evidence of a live provider task or an external pilot master.

The complete feature full suite remains baseline-red: **103 failed, 721 passed, 7 errors**.
The origin/main full-suite baseline is **103 failed, 395 passed, 7 errors**. The exact failure and
error sets are equal; there were **zero new failing or error tests**. The feature's additional
passing tests do not convert the inherited baseline failures or errors into passes.

Godot recorded **9/11** required smokes. The two baseline failures are
`generated_seed_boarded_slice_smoke` and `builder_playable_runtime_fields_smoke`; they reproduce
on origin/main, and their failing call chain has zero feature-diff paths. They are not claimed as
passed. The merged Godot summary records the same root String-to-Dictionary diagnostic and has
summary SHA-256 `0b1cf89043f0cbe46499ca237e1d9bf8c05a5714c7a1ad4a26406a132e55fd03`; the origin/main
baseline summary SHA-256 is `08f1ed5a3eb91935777228ddff7d88484789cde4d291022747054986cc5abd1c`.

## Verification records

The complete verified evidence set is recorded by privacy-safe SHA-256 values:

| Record | SHA-256 |
|---|---|
| Documentation contract | `54c883a020b26f290dbf01a5de9844c8469af2e2cf4f304df650ebd149235bb9` |
| Requirement trace | `3d804aa56b5d7b9deb814ab6156a53b2b54915693e7bcfe51ecaa0aea794a40f` |
| Plan determinism | `b193473101ffcb8eea990b8df44b6dacf71629d8ac276fa7ca573c1c945eeb17` |
| R7 verification | `5cdaadc63eca75ea63f80c7f81bc5832fb6bca9fef69f5eb13d693c3c444e334` |
| Contract validation | `e7c605111b55bea0a95a920aff986314cba005ed745047606d4f3a8fe4fb4da5` |
| Final focused 375 | `b3569c5d16e42804b95438edb76c561ee36db1759d544fc196e29b2c6e367676` |
| Native Blender 5.2.0 LTS | `2938bbca7f20d03a4aa59490a09d818182690b49f35374b3116212b9a30b3e47` |
| Feature full-suite log | `3ce14655810e11df6776ff50ce0d8681d1b6343fff08234ec2afbd4f0d85b894` |
| Feature full-suite comparison | `bce893761f185692e2b3ca2d52631df62c5f51563a3c56745ccdd91ff8486d6a` |
| origin/main full-suite log | `eff969d18845e4e96cf365cc3259acac745de5639d1aa6e0231e138f082af5f5` |
| origin/main full-suite record | `bb1dcb7c711a235f3118ec1220cfd96e2a6a8f260c195943ad08365918064800` |
| Merged Godot summary | `0b1cf89043f0cbe46499ca237e1d9bf8c05a5714c7a1ad4a26406a132e55fd03` |
| origin/main Godot summary | `08f1ed5a3eb91935777228ddff7d88484789cde4d291022747054986cc5abd1c` |
| Gitleaks report | `37517e5f3dc66819f61f5a7bb8ace1921282415f10551d2defa5c3eb0985b570` |
| Scope record | `cd1e762b1a02b5eb2d349ab9c53d4885a0ad24b5c109a7c65d1ed5ebe88d5abb` |

## Security, scope, and corrective review

Scope evidence covers **56 paths**. **gitleaks 8.30.1** ran across **50 commits**; **no leaks found**. The protected implementation plan remained unchanged at SHA-256
`3e399f581aaca12e05adc8e3c163e188eb5da3b3b5661e228d12036bb50febf9`. No personal data, provider
credentials, authorization material, signed URLs, or machine-local paths are part of this proof.

Quality review found a machine-local path issue and a texture-lower-bound documentation issue.
Corrections `09b9fb6d83fae36dc3a17c34dfaab172fba57216` and
`35816acfef34b8eee14d11c0d0eca07592b9fa01` close them under the parent gates. No independent
corrective PASS is claimed.

## Post-PR live-pilot sequence

After PR readiness, supply separate rights-cleared reference files and their hashes, rerun each
read-only plan, create immutable request records, and execute only the gated candidate lifecycle.
For `loot_container_derelict_v1`, retain four candidate records and one creation POST attempt per
planned candidate record. Then select one candidate, produce or verify the external Blender master,
run Blender and UV gates, perform the locked-isometric six-view runtime review (seeds `42` and
`777`; normal, emergency, and dark lighting), and emit a reviewed proposal-only promotion packet.
Until those inputs and gates exist, the live pilot remains **LIVE PILOT PENDING**.
