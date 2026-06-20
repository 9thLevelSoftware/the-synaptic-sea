# Bug Triage Process for Gate 3 Alpha

## Objective

Keep the Alpha build stable and shippable by classifying, routing, and tracking every bug through a single severity vocabulary and a fixed triage cadence. This process applies to all defects discovered during Gate 3 (internal validation, automated regression, playtests, or ad-hoc testing).

## Severity definitions

| Severity | Definition | Examples | Response time | Gate 3 disposition |
|---|---|---|---|---|
| **P0** | Core loop broken, crash, data loss, or any issue that prevents a clean run from start to finish. | Crash on slice load; player becomes permanently stuck; save corruption; regression bundle fails on an accepted smoke; extraction does not unlock when objectives are complete. | Same day; fix or downgrade with senior/coordinator sign-off. | Blocks Alpha exit until resolved or explicitly waived by a Gate 3 review card. |
| **P1** | Significant gameplay impact with a workaround, or a non-fatal regression that degrades the player experience. | HUD out of sync with runtime state; hazard cycle visible but not lethal; tool pickup requires two interactions; objective label wrong but progress still works. | Within 48 hours of triage. | Must be tracked; fix in Alpha if capacity allows, otherwise escalated to Beta backlog with accepted risk. |
| **P2** | Minor polish, cosmetic, nice-to-have, or low-impact inconsistency. | Typo in log text; particle effect offset; slight color mismatch on a disabled button. | Weekly batch review. | Deferred to Beta unless surplus capacity exists; never blocks Alpha exit. |

Severity is assigned at triage and can be changed only by the triage owner or a Gate 3 review card. A bug that is downgraded from P0 must record the rationale and the workaround or acceptance criteria.

## Triage cadence

- **Daily during active Gate 3 validation:** at the start of each work day, review all new issues reported in the last 24 hours.
- **Per regression run:** any regression bundle failure is triaged immediately after the run completes; see § Regression integration below.
- **End-of-week review:** reconcile the backlog, re-severity stale issues, and close duplicates or issues fixed incidentally.
- **Gate 3 exit review:** confirm no open P0/P1 bugs remain in the core loop before the Alpha gate decision.

## Triage owner

`sargassoreview` owns triage during Gate 3.

Responsibilities:
- Read incoming bug reports and assign severity.
- Create or request Kanban cards on `sargasso-stage-gate` for every P0 and P1 bug.
- Decide whether a P2 bug is accepted into Alpha or deferred to Beta.
- Update this document and `docs/game/08_milestone_gates.md` if the process itself changes.
- Chair the Gate 3 exit bug review and certify the blocker list.

Other agents may file bugs and may challenge a severity assignment via a comment on the relevant Kanban card; the triage owner resolves the challenge.

## Workflow: discovery to Kanban card

```
Discovery -> Report -> Triage -> Card -> Fix -> Verify -> Close
```

1. **Discovery.** Bug found via automated smoke, playtest, manual test, or code inspection.
2. **Report.** File a concise report with:
   - Repro steps or the exact smoke/script command that fails.
   - Expected vs. observed behavior.
   - Severity suggestion (optional).
   - Environment (Godot version, commit or workspace date, local vs. CI).
3. **Triage.** `sargassoreview` assigns P0/P1/P2 within one cadence window and updates the report with the assigned severity.
4. **Card.** For P0 and P1, create a Kanban card on board `sargasso-stage-gate` that:
   - Cites this document.
   - Cites the affected requirement or feature spec (`docs/game/05_requirements.md`, `docs/game/features/*.md`).
   - Lists allowed files and non-goals.
   - Includes the exact verification command.
5. **Fix.** `sargassoworker` implements the fix and runs the relevant smoke plus the regression bundle.
6. **Verify.** `sargassoreview` re-runs the verification command and confirms the regression bundle still passes.
7. **Close.** Card moved to done; report marked closed with the commit/workspace reference.

P2 bugs may be batched into a single "Alpha polish pass" card unless they are trivial one-line fixes.

## Regression integration

The regression bundle in `docs/game/06_validation_plan.md` is the primary automated discovery path for Gate 3.

Mapping from regression failure to severity:

| Failure mode | Default severity | Triage action |
|---|---|---|
| Smoke exits non-zero or missing pass marker on a previously passing smoke. | P0 | Create card immediately; block further Alpha validation work until the smoke passes again. |
| New unexpected `ERROR:` or `WARNING:` line not on the accepted baseline allowlist. | P0 | Classify the line in `06_validation_plan.md` before the smoke can be re-added to the bundle; if classification is delayed, treat as P0. |
| Smoke passes but prints degraded metrics compared to the previous run (e.g., lower completion count, longer frame time). | P1 | Create card and bisect the regression within 48 hours. |
| Accepted baseline teardown noise (GDAI capture, ObjectDB leak, REQ-012 save-rejection contract warning). | None | No card; monitor for changes in count or pattern. |

Regression failures discovered during a feature card's verification belong to that card until the card is complete. After completion, any remaining regression failure is routed through this triage process and owned by `sargassoreview`.

## Gate 3 Alpha exit criteria

- This document is current and cited in `docs/game/08_milestone_gates.md` Gate 3.
- All P0 bugs are closed or waived by a Gate 3 review card.
- All P1 core-loop bugs are closed or explicitly downgraded to P2 with a recorded rationale.
- The regression bundle passes cleanly on the build under review.
- A triage backlog snapshot is attached to the Gate 3 decision record.

## Related documents

- `docs/game/08_milestone_gates.md` — Gate 3 entry/exit criteria and decision record.
- `docs/game/06_validation_plan.md` — regression bundle commands and baseline noise allowlist.
- `docs/game/05_requirements.md` — requirements mapped to features and smokes.
- `docs/game/adr/` — architecture decisions that may override or clarify bug disposition.
