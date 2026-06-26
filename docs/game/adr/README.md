# ADR Index — Synaptic Sea Current Artifact Currency

Currency date: 2026-06-26
Validated by: Task 15 (`t_c7ac4d08`) / `REQUIREMENT TRACE PASS`

| ADR | Path | Artifact reference |
| --- | --- | --- |
| 0001 | docs/game/adr/0001-adopt-stage-gate-kanban-godot-validation.md | Stage-gate/Kanban/Godot validation operating model |
| 0005 | docs/game/adr/0005-multi-hazard-architecture.md | hazard contract smokes; oxygen/fire/electrical arc models |
| 0007 | docs/game/adr/0007-save-load-service-scope.md | RunSnapshot boundary, multi-slot additions, save/load smokes |
| 0029 | docs/game/adr/0029-audio-music-spatial-architecture.md | audio/music/spatial pure models and smokes |
| 0029 | docs/game/adr/0029-procedural-generation-expansion-architecture.md | procgen expansion models/templates/biomes/encounters |
| 0029 | docs/game/adr/0029-release-distribution-architecture.md | release metadata/demo/crash/readiness scaffold |
| 0030 | docs/game/adr/0030-achievement-catalog-and-triggers.md | achievement catalog/state smoke |
| 0031 | docs/game/adr/0031-localization-catalog-and-routing.md | localization catalog and language selector |
| 0031 | docs/game/adr/0031-multi-slot-save-architecture.md | save slot/index/autosave/manual/quicksave/world slot architecture |
| 0032 | docs/game/adr/0032-migration-permadeath-cloud-manifest.md | save migration, permadeath, cloud manifest |
| 0033 | docs/game/adr/0033-player-progression-meta-architecture.md | progression/meta/hub upgrade models and panels |
| 0033 | docs/game/adr/0033-ui-ux-accessibility-architecture.md | menu/settings/tutorial/minimap/glyph/tooltip UI shell |
| 0034 | docs/game/adr/0034-survival-vitals-architecture.md | survival vitals state and HUD persistence |
| 0034 | docs/game/adr/0034-food-cooking-spoilage-architecture.md | food/spoilage/cooking/hydroponics/synthesizer/water recycler |
| 0035 | docs/game/adr/0035-ship-systems-sustenance-expansion-architecture.md | power/life-support/hull/fire/propulsion/shield/sustenance models |
| 0036 | docs/game/adr/0036-consumable-effect-pipeline-architecture.md | effect dispatcher, medicine/stimulants/ammo/utility |
| 0037 | docs/game/adr/0037-combat-threat-architecture.md | damage, armor, status, detection, threats |
| 0037 | docs/game/adr/0037-loot-ecosystem-rarity-container-architecture.md | loot rarity/distribution/containers/unique/junk |
| 0038 | docs/game/adr/0038-crafting-materials-stations-architecture.md | materials/crafting/stations/quality/field crafting |
| 0039 | docs/game/adr/0039-cross-system-integration-audit-architecture.md | Task 14 integration audit models and e2e smokes |
| 0040 | docs/game/adr/0040-systems-map-task-graph-currency.md | Task 15 doc-currency validators and board manifest checks |

## Notes

- Number reuse exists in historical Task 12/13/10 ADRs (`0029`, `0031`, `0033`, `0034`, `0037`). The index keeps the file path as the identity because these ADRs were authored by separate package workers in a no-git/shared-workspace wave.
- ADR-0040 owns future currency checks for this index, requirements, systems map, validation plan, build plan, and Kanban manifests.
