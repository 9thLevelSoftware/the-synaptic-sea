# Cross-System Balance Ledger

Source: Task 14 (`docs/game/build-plans/14-cross-system-integration-review-e2e.md`).

## Purpose

The balance ledger is a deterministic sanity envelope, not final tuning. It proves that the integrated loop can be scored with explicit thresholds instead of hand-waved as "probably balanced".

## Scenario: prepare -> derelict -> survive -> loot -> craft -> return -> upgrade

The Task 14 smoke feeds this representative metric set into `BalanceLedger`:

| Metric | Safe range | Reason |
|---|---:|---|
| oxygen_remaining_pct | 25-100 | The run should pressure oxygen without making the short loop unwinnable. |
| hunger_remaining_pct | 40-100 | Hunger should matter without starving in one short run. |
| thirst_remaining_pct | 35-100 | Thirst should be visible without becoming unrecoverable. |
| loot_value | 4-20 | The derelict should produce enough value to justify risk without trivializing scarcity. |
| crafts_completed | 1-4 | At least one craft should close the loot-to-usefulness loop. |
| meta_currency_delta | 50-150 | One successful short run can buy a first-tier upgrade, not a high-tier chain. |
| upgrade_cost | 50-75 | Task 14 targets `hub_storage_basic` as the first upgrade. |

## Scenario: combat -> loot -> craft

| Metric | Safe range | Reason |
|---|---:|---|
| threat_health_remaining | 1-23 | Combat should have impact without requiring a kill for the loop proof. |
| loot_roll_count | 1-6 | A derelict container should return a bounded reward. |
| craft_output_count | 1-2 | One power-cell craft proves salvage conversion without inventory inflation. |

## Follow-up

Task 14 created `t_4e47145d` for a stronger live main-scene/controller-path e2e probe; that card is now complete with `LIVE MAIN PREPARE UPGRADE PROBE PASS stages=7`. Future probes should either reuse these thresholds or deliberately patch this ledger with fresh evidence.
