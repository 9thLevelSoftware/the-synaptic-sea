# Progression / Skills / Meta Tuning Notes

Source: `docs/game/features/player_progression.md`, ADR-0033
Requirement range: REQ-PM-001..010

## XP curve

Per `PlayerProgressionState.xp_for_next_level(L)` = `(L + 1) * 100`.

| From L | To L | XP needed |
|---|---|---|
| 0 | 1 | 100 |
| 1 | 2 | 200 |
| 2 | 3 | 300 |
| ... | ... | ... |
| 9 | 10 (cap) | 1000 |

Total XP from 0 -> 10 = `100 + 200 + ... + 1000` = `5500`.

## Class XP multipliers

Engineer (1.5x technical), Medic (1.5x medical), Pilot (1.5x navigation),
Cook (1.5x survival), Communications (1.5x social), Scientist (1.2x
technical / 1.2x navigation), Security (1.2x survival / 1.1x social),
Mechanic (1.5x technical / 1.1x survival).

A class's off-category multiplier is 0.7x–0.9x. Cross-training events
land on a 0.5x penalty (REQ-PM-005) AND the class's category penalty,
compounding: an engineer's `first_aid` event grants 50 * 0.7 * 0.5 = 17.5
XP instead of 50. This is intentionally punishing so off-class skills
require either books (REQ-PM-004, no penalty) or sustained commitment.

## Skill book / schematic values

Books grant 200 XP by default, schematics grant 350-400. Books that are
also schematics unlock a prerequisite skill (e.g.
`advanced_welding_schematic` -> `welding_mastery`).

## Meta payout at run-end

Per `MetaProgressionState.apply_meta_payout`:

- `+10` per completed objective (max 4 per Gate-1 slice = 40).
- `+5` per skill at level >= 5.
- `+15` per skill at level >= 8.
- `+2` per discovery (future-proofing; not yet fired by any loop).

A Gate-1 completion (4 objectives, 0 high skills) pays 40. With all 22
skills at level 5 the bonus is 110; with all 22 at level 8 the bonus is
330. The combined payout for an "everything at 8" run is roughly 380
meta_currency.

## Hub upgrade costs (currency)

| Tier | Cost | Examples |
|---|---|---|
| T1 | 50-75 | hub_storage_basic, hub_workshop_basic, hub_medical_bay |
| T2 | 100 | hub_scanner_array, hub_armory |
| T3 | 150-200 | hub_reactor_booster, hub_xenobiology_lab, hub_astrogation_chamber, hub_morale_lounge, hub_survival_cache |
| T4 | 300-400 | hub_command_deck, hub_drydock |

A new run grants ~40 meta_currency (4-objective completion, no high
skills). To afford a T3 upgrade (200) takes ~5 runs. The drydock
(400) is a ~10-run commitment. This pacing keeps the meta loop
invested without runaway.

## Persistent XP multiplier bonuses

Hub upgrades grant +10% per category. Stacking all five category
multipliers (T3 upgrade tiers) compounds to 1.1^5 = ~1.61 across
every category. This is intentionally modest — the goal is to make
repeat runs feel smoother, not to trivialize progression.

## Death rules

Death applies the same payout as completion (per ADR-0033) then wipes
the current-run snapshot. Meta state survives. A death-on-objective-1
run still pays 10 + 0 + 0 = 10 meta_currency. This keeps failed runs
meaningful rather than zeroed.

## Known balance targets

- A new player completes their first run in ~30 minutes and earns ~40
  meta_currency.
- 5 runs unlocks one T3 hub upgrade.
- The `biomatter_diagnostics` skill (advanced) is reachable after
  signal_analysis >= 4 + reading the `biomatter_signal_analysis`
  schematic.
- The `welding_mastery` skill (advanced) is reachable after welding >= 5
  + reading the `advanced_welding_schematic`.

## Tuning safety rails

- All multipliers and costs are stored in `data/player/hub_upgrades.json`
  and `data/player/classes.json` — never in code.
- The XP curve is one place: `PlayerProgressionState.xp_for_next_level`.
  No magic numbers in grant_xp.
- The payout formula is one place: `MetaProgressionState.apply_meta_payout`.
  No magic numbers in the playable ship.
- The cross-training penalty (0.5x) is a constant on
  `PlayerProgressionState.CROSS_TRAINING_PENALTY`. Tune in one place.