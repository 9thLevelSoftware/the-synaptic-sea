# P17 catalog/checker independent review

Review date: 2026-09-05  
Reviewed HEAD: `5118737d592cec36f614352930c32f5b66080bef`  
Scope: `data/construction/structural_rebuild_catalog.json`,
`tools/check_structural_rebuild_catalog.py`, and
`tests/test_structural_rebuild_catalog.py` only, with read-only inspection of
their declared source authorities and ADR-0065.

## Verdict

**NEEDS WORK.** The checked-in catalog currently contains the intended 60 active
rows (4 layout identities by 15 module types), its BOM values match ADR-0065,
and all 120 contract/wrapper references exist. Independent parsing found every
current mapped socket in both the top-level contract socket list and the wrapper
anchor list. The checker does not preserve those guarantees under mutation,
however, and its P09 positive-evidence contract is inconsistent with the
required concrete `welder` compatibility.

The current full CLI is expected to block because `rebuild_structure` and the
P09 positive-report fields are not implemented yet. That dependency block is
correct and is not treated as a P17 catalog defect.

## Findings

### HIGH — Catalog validation accepts unauthorized and malformed extra data

Affected component: `tools/check_structural_rebuild_catalog.py:89-135` and
`tests/test_structural_rebuild_catalog.py`.

`validate_catalog()` filters to dictionary rows whose `active` value is exactly
`True` and validates only those rows. It therefore ignores unknown inactive
rows and non-object rows. It also does not enforce exact root or row key sets.
Python equality makes the type gap worse: `False == 0`, so a catalog row with
`"min_skill": false` compares equal to the expected integer zero and passes.

Independent mutants produced these false acceptances:

```text
extra_root_key: ok=True blockers=[]
extra_active_row_key: ok=True blockers=[]
unknown_inactive_row: ok=True blockers=[]
non_object_extra_row: ok=True blockers=[]
boolean_min_skill: ok=True blockers=[]
```

This matters because ADR-0065 makes this file the sole replacement policy and
requires unknown/custom rows to remain visibly unsupported. A permissive
checker can certify data that a later runtime parser may interpret, and it does
not enforce the design-review requirement that catalog validation reject
inactive or incomplete rows.

Remediation: validate an exact root envelope, require every `rows` element to be
a dictionary, require the exact row and nested requirement/socket key sets,
reject rows not present in the 60-row authority regardless of `active`, require
`active is True`, and use exact-type checks (`type(value) is int`) for
`min_skill`, quantities, and durations. Add mutants for every rejected type and
extra/inactive case.

### HIGH — Canonical resource validation does not verify the runtime socket contract or wrapper

Affected component: `tools/check_structural_rebuild_catalog.py:39-72`.

`canonical_rows()` checks only that the contract and wrapper files exist, that
a regex finds one footprint, and that the kit's socket-name IDs are a subset of
all `"id"` strings anywhere in the TRES text. Each TRES contains a top-level
runtime `sockets` field and a second nested legacy `asset.sockets` copy, so the
regex can find an ID in the nested copy after the live top-level socket has
drifted. The checker never validates socket kind, position, compatibility,
duplicate IDs, exact socket set, contract module/kit/self-path identity, or any
wrapper anchor/content.

Mutating only the top-level runtime socket kind and separately removing a mapped
wrapper socket anchor both remained accepted:

```text
mutated_runtime_socket_semantics: ACCEPTED rows=60
mutated_wrapper_socket_anchor: ACCEPTED rows=60
```

This matters because P17 authorization is defined by the exact captured socket
contract. A changed kind/position/compatibility can invalidate a bound neighbor,
and a missing wrapper anchor can make the authorized replacement impossible or
incorrect even though this gate reports success.

Remediation: parse the authoritative top-level contract fields structurally
(or introduce a versioned JSON manifest that can be parsed unambiguously).
Validate module ID, kit ID, contract path, wrapper self-reference, exact
footprint, unique socket records including kind/position/compatible kinds, and
the wrapper's exact mapped anchors. Bind these semantics to explicit source
versions or hashes so a contract/wrapper drift cannot be silently accepted.
Tests should mutate the top-level runtime record independently from the nested
copy and mutate wrapper anchors.

### HIGH — P09 positive compatibility is checked against a tool class instead of the concrete compatible item

Affected component: `tools/check_structural_rebuild_catalog.py:141-160` and
`tests/test_structural_rebuild_catalog.py:55-64`.

The checker reads P09 rows shaped as `{item_id, action_id}` but compares them to
`(requirements.tool_class, action_id)`, so it requires
`welding_lance/rebuild_structure`. The P17 plan explicitly requires adding
`rebuild_structure` to the concrete `welder.compatible_work_action_ids`, while
the runtime treats a direct class item and an authored compatible concrete item
as different positive routes. A report containing the required concrete pair
`welder/rebuild_structure` is rejected. Conversely, the fabricated
`welding_lance/rebuild_structure` fixture lets the test pass without proving the
required `welder` metadata.

The report row envelope is also permissive: a list containing one accepted pair
plus strings, non-string IDs, booleans, and extra keys still passes.

```text
concrete_welder_positive: ok=False blockers=['p09_tool_action_unverified']
malformed_p09_compatible_rows: ok=True blockers=[]
```

This matters because the gate can reject the correct future P09 contract while
accepting incomplete or malformed compatibility evidence. It also fails to
prove the allowed-file acceptance condition for `welder`.

Remediation: define the P09 field as strict positive concrete pairs with exact
string fields, emit `welder/rebuild_structure` from P09, and have P17 verify the
required reachable concrete compatible item(s) for each catalog tool
class/action. If direct class items are also supported, model that route
explicitly rather than conflating `item_id` with `tool_class`. Reject any
malformed/unknown compatibility row.

### HIGH — The named catalog-policy mutant test can pass solely because P09 is absent

Affected component: `tests/test_structural_rebuild_catalog.py:66-80`.

Every case in `test_canonical_mutants_block_exact_policy` supplies
`p09_report=None` and asserts only `report["ok"] is False`. That always adds
`p09_report_unverified`, so the test remains green even if duplicate, missing,
fractional, duration, or socket validation stops working. The five checked-in
tests passing does not provide the claimed mutation evidence.

The mapping-drift test also exercises only four of the six pinned paths and
mutates the expected-hash dictionary rather than a source copy. The underlying
implementation did reject independent byte mutations of all six paths, but the
checked-in regression suite would not protect every pin from later logic drift.

Remediation: provide a fully valid positive P09 report to every catalog-policy
mutant and assert the precise expected blocker. Parameterize actual temporary
source copies for all six pins. Add the strict-envelope, bool, concrete-tool,
top-level-contract, and wrapper-anchor mutants documented above.

### MEDIUM — Valid JSON with the wrong root type and source failures escape the stable gate report

Affected component: `tools/check_structural_rebuild_catalog.py:164-188`.

`main()` catches only JSON decoding around the catalog load. A valid JSON array
reaches `validate_catalog()` and raises `AttributeError` because the function
calls `.get()` without checking the root type. Missing/malformed item, tool,
action, kit, contract, or wrapper sources and `canonical_rows()` errors are also
outside a stable error boundary. The process exits nonzero, but it emits a
traceback instead of the declared `STRUCTURAL REBUILD CATALOG BLOCKED` report.

Remediation: validate the catalog root before calling `.get()`, convert source
and schema failures into typed errors, and catch those errors at the CLI
boundary to emit a stable blocked marker and actionable source path/reason.
Avoid the redundant `except (SourceError, Exception)` form, which is equivalent
to catching every exception and discards the P09 cause.

## Positive evidence

- Frozen SHA-256 hashes matched the supplied catalog, checker, and test hashes.
- `python -m pytest -q tests/test_structural_rebuild_catalog.py` returned
  `5 passed in 0.09s`.
- The current CLI returned exit 1 with the expected dependency blockers:
  `p09_acquisition_unverified`, `p09_report_unverified`,
  `p09_tool_action_unverified`, and `runtime_action_missing`.
- The catalog has exact root keys `schema, rows`, 60 active rows, 15 rows each
  for v0/hazard/industrial/biomatter, 15 unique contracts, and 15 unique
  wrappers. All catalog tuples match the current balance/source projection.
- All six declared mapping-source hashes match and independent byte mutations of
  each source were rejected, including hive, hazard, industrial, biomatter, and
  both generator sources.
- Independent current-state parsing found no missing mapped socket in the
  top-level TRES socket fields or wrapper anchors.

No production, catalog, checker, or checked-in test file was modified during
this review. Mutants ran from ignored `.superpowers/tmp` only.
