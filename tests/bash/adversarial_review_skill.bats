#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	SKILL="$REPO_ROOT/chezmoi/dot_agents/skills/adversarial-hypothesis-review/SKILL.md"
}

@test "adversarial review skill defines the evidence and review contract" {
	[ -f "$SKILL" ]
	grep -q '^name: adversarial-hypothesis-review$' "$SKILL"
	grep -q '^description: ' "$SKILL"
	grep -q "conditions that would falsify" "$SKILL"
	grep -q "Hypothesis" "$SKILL"
	grep -q "Empirical validation" "$SKILL"
	grep -q "Alternative comparison" "$SKILL"
	grep -q "Published prior art" "$SKILL"
	grep -q "Reviewer verification" "$SKILL"
	grep -q "reviewer identity or dispatch ID" "$SKILL"
	grep -q "## Adversarial review record" "$SKILL"
	grep -q -- "- Reviewer: <name or dispatch ID>" "$SKILL"
	grep -q -- "- Residual risk:" "$SKILL"
	grep -q -- "- Unresolved uncertainty:" "$SKILL"
	grep -q "repeat the independent review" "$SKILL"
}
