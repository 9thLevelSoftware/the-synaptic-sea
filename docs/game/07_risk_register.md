# 07 Risk Register

| ID | Risk | Likelihood | Impact | Area | Mitigation | Owner | Status |
|---|---|---:|---:|---|---|---|---|
| RISK-001 | Proof-artifact churn displaces real gameplay systems | Medium | High | Process | Enforce docs/game operating model, feature specs, and validation gates | Coordinator | Open |
| RISK-002 | Procedural interiors become spatially incoherent or jumbled | High | High | Design/Tech | Require corridor/socket/topology validation and locked-iso readability checks | Coordinator | Open |
| RISK-003 | Route/system state becomes a god-object | Medium | Medium | Tech | Keep pure state models separated; scene coordinator applies consequences | Coordinator | Mitigated for route control |
| RISK-004 | No-git workspace loses change provenance | Medium | High | Process | Maintain no-git ledgers and Kanban manifests until a repo boundary exists | Coordinator | Open |
| RISK-005 | Workers implement ad-hoc tasks without specs | Medium | High | Process | Require Kanban card contract with source requirements, scope, non-goals, verification | Coordinator | Open |
| RISK-006 | Godot MCP/editor automation changes scenes unsafely | Medium | Medium | Tooling | Prefer code review + headless smokes; keep destructive editor automation scoped | Coordinator | Open |
| RISK-007 | Missing hazard/survival loop leaves slice mechanically flat | Medium | High | Design | Hazard pressure-loop feature spec authored at `features/hazards.md`; oxygen pressure loop implemented and validated by model/main-scene smokes and regression bundle; broader hazard variety remains deferred beyond Gate 1 unless a gate decision recycles scope | Coordinator | Mitigated for Gate 1 |
| RISK-008 | Content production starts before vertical slice proves loop | Medium | High | Production | Gate 1 exit criteria blocks content-scale work | Coordinator | Open |
