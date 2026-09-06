---
name: adversarial-hypothesis-review
description: Use when a diagnosis, design, or implementation plan contains a hypothesis or uncertain causal explanation that must be challenged before adoption or implementation.
---

# Adversarial Hypothesis Review

## Overview

Treat hypotheses as provisional until an independent sub-agent has challenged their assumptions, evidence, dependencies, counterexamples, and alternatives. If it is unclear whether a statement is a hypothesis, apply this skill.

## Required evidence contract

Before adopting a decision-relevant hypothesis, record these sections in the plan or final report:

- **Hypothesis**: proposed cause, design, or implementation approach; observed evidence and its source; constraints and assumptions; and conditions that would falsify the hypothesis.
- **Empirical validation**: target environment, versions, inputs, reproduction procedure, measurements, and evidence source. Documentation or one successful run is not proof of causality. Keep unverified claims explicitly unverified.
- **Alternative comparison**: compare the current baseline and plausible alternatives against correctness, safety, performance, maintainability, cost, compatibility, and supply-chain criteria relevant to the decision.
- **Published prior art**: independently search upstream documentation, standards, package registries, repositories, papers, and existing implementations. Record search scope, terms, date, sources, versions, results, applicability, maintenance, licensing, and supply-chain implications. “Not found” is scoped to the search, not proof of nonexistence.
- **Reviewer verification**: record reviewer identity or dispatch ID, verification methods, results for each dimension, objections, the reconciled decision, residual risk, and unresolved uncertainty.

Use this record shape so a review is auditable rather than a collection of unstructured claims:

```markdown
## Adversarial review record

- Reviewer: <name or dispatch ID>
- Date: <YYYY-MM-DD>
- Decision: <adopt, revise, defer, or reject>
- Residual risk: <known risk after reconciliation>
- Unresolved uncertainty: <what remains unverified>

### Hypothesis

<cause/design/approach, evidence sources, constraints, assumptions, and conditions that would falsify it>

### Empirical validation

<environment, versions, inputs, reproduction commands, measurements, and evidence>

### Alternative comparison

<baseline and alternatives compared against decision-relevant criteria>

### Published prior art

<search scope, terms, date, sources, versions, results, and applicability>

### Reviewer verification

<independent reruns/research/recomparisons, objections, and reconciliation>
```

## Workflow

1. State the hypothesis and its falsification conditions before implementation.
2. Start at least one independent sub-agent before proceeding. Give it the hypothesis, evidence, constraints, and falsification conditions without leading it toward agreement. It must be read-only or use an isolated worktree.
3. Ask the reviewer to challenge assumptions, boundary cases, hidden dependencies, regressions, alternative designs, and the smallest checks that distinguish competing hypotheses.
4. For decision-relevant technical claims, require separate empirical validation, alternative comparison, published prior-art research, and reviewer verification. A restatement of the proposal is not verification.
5. Reconcile material objections before implementation. If the cause, design, or implementation approach changes materially, repeat the independent review.
6. Scale the review to risk. For purely mechanical, low-risk changes, keep the evidence concise. If a required sub-agent or research tool is unavailable, mark that dimension unverifiable and do not present the hypothesis as confirmed.

## Review prompt

Use a neutral request such as:

> Review this hypothesis adversarially. Identify false assumptions, weak evidence, counterexamples, hidden dependencies or regressions, plausible alternatives, and the minimum checks needed to discriminate them. Do not optimize for agreement.

Do not skip the review because the change appears small; narrow the review to the change's actual risk.
