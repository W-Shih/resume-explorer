# Project Instructions — resume-explorer

## 1. Project Scope

- This is a **Single Folder Project**.
- Project root: `E:\_projects\tools\scripts\resume-explorer`
- Unless explicitly requested, limit changes to this repository. Do not modify external projects or system configuration.

## 2. Core Engineering Principles

Prioritize **correctness, reliability, backward compatibility, maintainability, and testability**.

Follow these principles:

- **Backward Compatibility First**: Avoid breaking existing CLI interfaces, behavior, configuration, data formats, and workflows.
- **Minimal, Focused Changes**: Prefer the smallest change that correctly addresses the underlying problem. Avoid unrelated refactoring.
- **Maintainable Design**: Favor readable, cohesive, loosely coupled, and easily testable code.
- **Pragmatic Design Principles**: Apply SOLID, SRP, DRY, KISS, YAGNI, and Law of Demeter where appropriate. Do not introduce abstractions, design patterns, dependencies, or architectural layers without a clear benefit.
- **Extensibility Without Overengineering**: Consider foreseeable extension points, but avoid speculative functionality.

If a breaking change is genuinely necessary:

1. Explain why backward compatibility cannot reasonably be preserved.
2. Assess affected interfaces, consumers, and migration requirements.
3. Provide an appropriate compatibility or migration strategy.
4. Update relevant documentation, code comments, version numbers, and tests.

## 3. Review and Problem-Solving Workflow

**Evidence First, Root Cause Before Fix.**

When reviewing issues, designing solutions, or implementing fixes:

1. Inspect relevant source code, tests, documentation, and Git changes before making assumptions.
2. Distinguish verified facts, hypotheses, and unresolved questions.
3. Identify the underlying cause when feasible. Do not treat symptoms as proven root causes.
4. Evaluate reasonable alternatives, considering correctness, complexity, risks, maintainability, and testing cost.
5. Recommend a proportionate solution; avoid unnecessarily broad redesigns.
6. Define acceptance criteria and meaningful validation steps before implementation.

Treat `Backlog.md` and existing plans as **design intentions and historical context, not immutable implementation requirements**. Challenge and update them when code evidence or sound engineering reasoning supports a better approach.

For a review or planning request, do not implement production code unless explicitly requested.

## 4. Testing and Regression Prevention

**Tests are part of implementation, not optional follow-up work.**

When implementing new features or fixing defects:

- Add or update tests covering the intended behavior.
- Add regression tests for discovered bugs whenever practical.
- Cover important boundary cases, failure paths, and compatibility constraints.
- Prefer deterministic unit tests and mocks for logic that does not require Windows Explorer.
- Use integration or end-to-end tests when they provide meaningful additional confidence.
- Run relevant existing tests to detect regressions.
- Gradually improve missing test coverage as the project evolves, without unrelated large-scale test rewrites.

### Existing Test Integrity

**Never modify existing tests merely to make them pass.**

Treat existing tests as important behavioral contracts and regression safeguards. Before modifying any existing test code:

1. **Investigate the root cause**: Determine whether the failure originates from production code, an incorrect test, an outdated requirement, or an environmental issue.
2. **Challenge the necessity**: Carefully evaluate whether modifying the test is genuinely justified. Prefer fixing production code when the existing test correctly represents intended behavior.
3. **Preserve regression coverage**: Never weaken assertions, relax expectations, remove test cases, or skip failing tests simply to achieve a passing test suite.
4. **Justify legitimate changes**: Modify existing tests only when there is a verified reason, such as an incorrect test assumption, a confirmed test defect, or an intentional and approved behavior change.
5. **Document and validate**: Clearly explain why each existing test was modified, what behavioral expectation changed, and how regression protection is preserved. Add replacement or supplementary tests when necessary.

**A passing test suite is not sufficient evidence of correctness if the tests were modified to accommodate incorrect behavior.**

For Explorer-specific operations, prefer isolated or safely controlled testing. Do not disrupt active Explorer windows, terminate processes, or perform destructive environment changes without explicit authorization.

## 5. Implementation and Documentation

Keep implementation, tests, and documentation consistent.

- Preserve existing safety invariants, especially around Restore, Retry, identity verification, and checkpoint persistence.
- Avoid unnecessary changes to public parameters, report schemas, snapshot formats, or observable behavior.
- Document important design decisions, constraints, and non-obvious behavior.
- Update `README.md`, `Backlog.md`, relevant plans, and version information when warranted.
- Do not claim an issue is fixed or tests have passed without supporting verification.

## 6. Delivery Expectations

After completing a requested change, provide a concise summary covering:

- What changed and why.
- Files modified.
- Tests or validations performed and their results.
- Remaining risks, limitations, or unverified assumptions.

Keep changes focused and reviewable. Create a Git commit when explicitly requested; otherwise preserve the working tree for review.
