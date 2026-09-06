# ADR-0060: Windows validation runtime for feature completion

- Status: Accepted for Windows feature-completion validation; baseline compatibility verified on 2026-09-05. Export qualification remains pending.
- Date: 2026-09-04
- Scope: Windows execution of the feature-completion program, P00 and P24.

## Context

The documented Godot 4.7.1 executable is a macOS path. The Windows workspace has
Godot 4.7.2 mono and 4.6.2 installed. The project declares Godot 4.7. Using 4.6.2
would downgrade the runtime. The existing Windows native extension initializes
under 4.7.2; initialization alone does not establish native generation coverage.

The isolated 4.7.2 import generated the missing damaged and breached doorway
compiled scenes. Five focused runtime smokes subsequently passed without
diagnostics: crafting state, module integrity consequences, repair loop, playable
station crafting, and pilot switching. Raw evidence is in the execution workspace
`.p00-scratch/logs/`; the P00 report records commands and environment. These local
logs must accompany gate evidence; this document is not a substitute for them.

## Decision and acceptance conditions

Use the installed Windows Godot `4.7.2.stable.mono.official.ed1daf0bf` for this
program if the full canonical regression and explicit native-generation probe
pass. Record the exact binary version and source revision in every gate run.
Do not declare general platform equivalence or modify the release engine contract
before that evidence is reviewed. Native export compatibility remains a separate
P24 gate and requires matching export templates and an offline launch.

The initial editor emitted two diagnostics: missing .NET SDK 8.0.30 from its C#
editor plugin, and an absent `GODOT_MCP_TOKEN` from optional local editor tooling.
The coordinator accepts these only as classified editor-setup diagnostics in that
specific import run. This does not permit suppressing either diagnostic during
runtime tests, any new diagnostic, or missing C# functionality if the source audit
finds runtime C# dependencies. No global SDK or credential setup is required by
this decision.

## Reviewed baseline evidence

The isolated baseline at `3b601e3900d96b3dfe9ba408e208c91a30196b3b`
passed all 652 canonical commands on the exact runtime above, with exit 0 and
`SYNAPTIC_SEA REGRESSION PASS commands=652 clean_output=true`.
A fresh native-generation probe also passed with native selection, deterministic
seed 1 output, and real scene markers. Raw evidence is retained in
[`P00-baseline-3b601e39`](../../../artifacts/feature-completion/P00-baseline-3b601e39/summary.json).
The summary SHA-256 is
`2B5245D94F9129FE06C6E5EF8096583A63A18711B35AC5381A2B91AD6C9A7631`;
the native probe log SHA-256 is
`162D0AA6D5E031B50150FCC5E6CF63B6C85E56AE17C105062A81E36AA669858F`.
Node 26.8.1 and npm 11.19.0 were prepended to the inherited process PATH,
preserving Git metadata collection. These results establish the runtime baseline,
not acceptance of subsequent feature changes or the other G0 accounting tasks.

## Consequences

The current runtime is accepted for this program's implementation validation.
Gate G0 still requires its separate P01/P02 accounting and runner acceptance. Failed
compatibility requires a documented runtime adjustment and fresh evidence rather
than silently changing expected markers or weakening diagnostic checks.

Generated import artifacts remain separate from authored gameplay changes. Review
tracked import manifest changes individually; never commit the editor cache or
local paid tooling as part of a gameplay feature.
