---
name: minimal-tests
description: Apply to every code creation or modification and every code review. Keep only the smallest necessary tests for current behavior; remove redundant, obsolete, legacy, and migration tests.
---

# Minimal tests

Apply this policy both while implementing a change and while reviewing its complete diff.

- Minimize test code, fixtures, mocks, scenarios, and execution cost. Do not add tests by default or to increase counts or coverage percentages.
- Add a test only when it protects a concrete, important failure in the current behavior that existing coverage does not catch. Prefer one representative test at the real execution boundary.
- Do not add migration, backward-compatibility, or legacy-behavior tests. Delete tests and fixtures as soon as the behavior they describe becomes obsolete.
- Do not test implementation spelling, private helpers, YAML/source structure, fixed command sequences, trivial argument validation, or every exception separately when observable behavior already covers the contract.
- Avoid checking the same behavior in unit, integration, and E2E tests. Keep it at the lowest-cost boundary that actually detects the failure; retain real E2E only for behavior that requires it.
- Remove obsolete tests in affected code even if they were not added by the current change. Do not preserve them merely because they previously existed.

Before adding or retaining a test, identify the specific failure it detects and why another test does not already detect it. If that justification is weak, omit or delete the test.

During review, inspect added and affected existing tests with the same criteria. Delete unnecessary scenarios and their fixtures; grouping them under fewer test names does not count as simplification. Report the meaningful coverage retained and any real limitation briefly, without adding a checklist artifact or tests for this policy itself.
