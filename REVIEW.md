# Pull Request Review Guidance

Review every pull request in two passes: first for correctness, then with the mandatory Ponytail review. Always include the Ponytail pass, even when its only result is `Ponytail: Lean already. Ship.`

The objective is a correct, secure, maintainable codebase that stays as small as practical. Prefer the simplest solution that satisfies the actual requirement: fewer files, dependencies, abstractions, branches, and concepts.

## Review Order

1. **Understand the intent.** Read the title, description, linked issue, and changed files. Identify the behavior that should change before proposing simplification.
2. **Review correctness first.** Check for bugs, broken edge cases, security issues, data-loss risks, race conditions, missing validation, poor error handling, broken tests, and regressions.
3. **Perform the Ponytail pass.** Review the diff specifically for unnecessary complexity and removable code.

Ponytail must never remove necessary safety, validation, accessibility, observability, tests, or behavior explicitly requested by the pull request or linked issue.

## Correctness and Safety

Treat correctness, security, and data integrity as higher priorities than reducing code. Do not suggest removing:

- Required input validation or security checks.
- Error handling that prevents data loss or silent failure.
- Accessibility fundamentals.
- Tests protecting non-trivial behavior.
- Operationally necessary logging or metrics.
- Behavior required by the pull request or linked issue.

Do not prefer clever one-liners when a more readable form prevents mistakes. Do not block a pull request only because it could be shorter; request changes only for correctness, security, data-loss, or maintainability risks.

## Ponytail Review

Search for unnecessary complexity and prefer:

- Deletion over addition.
- Standard-library functionality over hand-written equivalents.
- Platform or framework-native features over custom code or dependencies.
- Existing repository patterns over new abstractions.
- A direct implementation over factories, registries, service layers, interfaces, adapters, or configuration with only one use.

Challenge speculative future-proofing and code added “just in case.” Flag:

- Abstractions with only one implementation.
- Wrappers around simple APIs.
- Dependencies used for trivial behavior.
- Helpers that duplicate language, framework, or repository functionality.
- Unnecessary branches, configuration, extension points, generated boilerplate, or broad scaffolding.
- Tests that mainly verify mocks, framework behavior, or implementation details rather than useful behavior.
- Documentation or comments that explain obvious code or defend unnecessary complexity.

Do not invent Ponytail findings. If the implementation is already simple, use the required no-finding statement.

### Ponytail Tags

Use one of these tags for every Ponytail finding:

- `delete`: dead code, unused flexibility, speculative features, unnecessary branches, unused configuration, or scaffolding.
- `stdlib`: hand-written logic already provided by the language standard library.
- `native`: a dependency or custom implementation duplicating platform or framework functionality.
- `yagni`: an abstraction, configuration option, or extension point with no current need.
- `shrink`: behavior that can be expressed with materially less code.
- `reuse`: a helper that duplicates an existing repository helper or pattern.
- `test-shrink`: a test that can be simplified while preserving meaningful coverage.

### Ponytail Finding Format

Make each finding concise and actionable:

```text
<file>:L<line>: <tag> <what to cut>. <what replaces it>.
```

Examples:

```text
src/cache.ts:L42: stdlib: custom LRU cache. Replace with Map plus size cap, or use the existing cache helper in src/lib/cache.ts.
app/services/UserService.ts:L18: yagni: IUserService has one implementation and one caller. Delete the interface and inject UserService directly.
src/validators/email.ts:L7: native: regex-based email parser. Use the platform/email validation already used in FormInput.
tests/user.test.ts:L88: test-shrink: five mocked repository tests cover the same branch. Keep one behavior test through the public API.
src/config.ts:L31: delete: FEATURE_X_STRATEGY has one value and no callers override it. Inline the value.
```

If there are no findings, write exactly:

```text
Ponytail: Lean already. Ship.
```

## Review Output

Use the following structure.

### Verdict

Choose one:

- Approve
- Request changes
- Comment only

Follow it with one short sentence explaining the decision.

### Correctness / Safety Findings

List only genuine correctness, safety, security, regression, or test issues in this format:

```text
<severity>: <file>:L<line>: <issue>. <required fix>.
```

Use these severities:

- `critical`: bug, security, or data-loss risk that must be fixed before merge.
- `important`: likely defect or maintainability hazard that should be fixed before merge.
- `minor`: small issue, typo, naming problem, or clarity concern.

If there are no findings, write:

```text
No correctness or safety findings.
```

### Ponytail Review

Always include this section. List findings in the required Ponytail format, or use the exact no-finding statement. End the section with:

```text
Ponytail net: -<estimated removable lines> lines.
```

If no lines are removable, write:

```text
Ponytail net: 0 lines.
```

### Suggested Minimal Patch

When findings are actionable, describe the smallest safe patch set. Prefer the fewest changed files and deleting code. Do not add dependencies unless absolutely necessary, and do not propose a broad refactor when a local fix is sufficient. Keep this section short.

If no patch is needed, write:

```text
No patch needed.
```

### Final Merge Guidance

State clearly whether the pull request can merge, for example:

- Can merge after the critical finding is fixed.
- Can merge; Ponytail suggestions are optional cleanup.
- Do not merge until tests cover the changed behavior.
- Can merge as-is.

## Reviewer Conduct

- Be direct, specific, and concise.
- Do not praise boilerplate or write long essays.
- Do not ask the author to “consider” vague changes.
- Every finding must state exactly what should change.
- Mark optional simplifications as optional.
- If complexity creates a real risk and simplification is required, explain that risk in one sentence.
- Do not treat tool, test, or CI self-reports as proof when the diff contradicts them.
- Prefer the smallest root-cause fix over patches scattered across callers.

## Mandatory Checklist

- Did I review correctness and security first?
- Did I run a separate Ponytail pass?
- Did I look for code to delete?
- Did I look for standard-library and native replacements?
- Did I look for one-implementation interfaces, factories, and adapters?
- Did I look for speculative configuration and extensibility?
- Did I avoid removing required validation, security, and tests?
- Did I include Ponytail findings or `Ponytail: Lean already. Ship.`?
