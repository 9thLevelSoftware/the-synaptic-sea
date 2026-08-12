# Shippable Art Gate

## Purpose

Define when an asset may enter the **live playable path**. Pipeline demos, LoRA training outputs, and contact-sheet tiles are not game content until they pass this gate.

**Linked milestone:** `docs/game/features/vertical_slice_v1.md`

## Non-runtime paths (evidence only until promoted)

These directories are **not** runtime content by default:

- `assets/tiles/synaptic_sea/`
- `data/training/lora_synaptic_sea/`
- ComfyUI workflow dumps and intermediate masks not referenced by a live loader
- `*.glb.bak_placeholder` and other backup/placeholder sidecars

Promotion means: copy/author into a versioned runtime path, wire a live consumer, pass this checklist, human sign-off in the PR.

## Runtime destination paths

Preferred:

- `assets/imported/<domain>/<kit_or_id>/...` (structural, props, threats)
- `assets/game/...` if introducing a cleaner top-level later
- Wrappers: `scenes/wrappers/...` only when paired with imported meshes and contracts

Forbidden as sole “done” proof:

- Assets that exist only under validation harness scenes
- Assets referenced only from smokes, not from playable loaders/placers/tools

## Checklist (all must pass)

1. **Scale / socket contract**  
   Matches `CELL_SIZE` / kit socket conventions used by `StructuralPlacer` / prop factory. Document expected footprint (e.g. 1x1 floor).

2. **Collision / nav friendly**  
   Floors walkable; no invisible snags; decorative collision avoided unless intentional blocking. Prefer existing placement contracts under `data/placement/contracts/` when structural.

3. **Locked-iso readability**  
   Silhouette and materials read at gameplay camera distance (not only beauty close-ups).

4. **Triangle / memory budget**  
   Documented in PR or kit note. Structural modules ~700 tris class is an accepted baseline; call out outliers.

5. **Named, versioned path**  
   Stable `res://` path under imported/game trees — not a ephemeral tile dump name.

6. **Live consumer**  
   Used by a production loader, placer, tool interactable, or threat renderer on the main playable path (title → main → playable ship), not only a harness.

7. **Human visual sign-off**  
   PR description includes a short note or screenshot path under `artifacts/` stating “shippable for slice” (or rejects with reason).

## Minimum bar by asset class (Vertical Slice v1)

| Class | Minimum shippable bar |
|---|---|
| Structural module | Real geometry (not pure BoxMesh), walkable floor, kit wrapper if required |
| Threat | Archetype-distinct silhouette + color/material; GLB preferred; identical grey capsules fail |
| Gameplay prop | Distinct prop mesh per interactable id; box-only fails for slice-critical list |
| UI icon | Readable at HUD scale; no empty placeholder path |
| Audio | Non-silent clip, licensed, path in catalog, coverage smoke |

## PR template snippet

```markdown
### Shippable art gate
- [ ] Scale/socket OK
- [ ] Collision/nav OK
- [ ] Iso readable
- [ ] Budget noted (tris/kb): 
- [ ] Runtime path: `res://...`
- [ ] Live consumer: `<script/scene>`
- [ ] Human sign-off: <name/date>
```

## Enforcement

- Reviewers and agents **reject** runtime wiring of ungated PoC tiles.
- Vertical Slice acceptance requires gate compliance for all newly promoted slice assets.
- When in doubt, keep the asset out of the live path and file it as pipeline evidence.
